part of '../procode_app.dart';

class BoardItem extends KanbanBoardGroupItem {
  final CardItem card;
  BoardItem(this.card);
  @override
  String get id => card.id;
}

class LegacyBoardPage extends StatefulWidget {
  final Map<String, dynamic> project;
  const LegacyBoardPage({super.key, required this.project});
  @override
  State<LegacyBoardPage> createState() => _LegacyBoardState();
}

class _LegacyBoardState extends State<LegacyBoardPage> {
  final controller = KanbanBoardController();
  final columns = <String, List<CardItem>>{
    'To Do': [],
    'In Progress': [],
    'Done': [],
  };
  late final String projectId;
  late final String title;
  bool loading = true;
  final invitedMembers = <String>[];

  @override
  void initState() {
    super.initState();
    projectId = '${widget.project['idproject'] ?? widget.project['id'] ?? ''}';
    title =
        '${widget.project['nama_project'] ?? widget.project['name'] ?? 'Board'}';
    _load();
    _loadMembers();
  }

  Future<void> _loadMembers() async {
    invitedMembers.addAll(await auth.membersCache(projectId));
    if (mounted) setState(() {});
  }

  Future<void> _load() async {
    final cached = await auth.cardCache(projectId);
    for (final card in cached) columns[_listFor(card.status)]!.add(card);
    try {
      final remote = await auth.tasks(projectId);
      if (remote.isNotEmpty) {
        for (final list in columns.values) list.clear();
        for (final t in remote) {
          final card = CardItem(
            id: '${t['idtask']}',
            title: '${t['nama_task']}',
            status: '${t['status'] ?? '1'}',
          );
          columns[_listFor(card.status)]!.add(card);
        }
        await _saveCards();
      }
    } catch (_) {}
    if (mounted) setState(() => loading = false);
  }

  Future<void> _saveCards() async =>
      auth.saveCardCache(projectId, columns.values.expand((x) => x).toList());

  CardItem? _findCard(String id) => columns.values
      .expand((x) => x)
      .cast<CardItem?>()
      .firstWhere((c) => c?.id == id, orElse: () => null);

  Future<void> _editCard(CardItem card) async {
    if (card.id.isEmpty || card.id == 'null') {
      _show('ID card tidak valid. Muat ulang board.');
      return;
    }
    final c = TextEditingController(text: card.title);
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Edit card'),
        content: TextField(controller: c),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, c.text.trim().isNotEmpty),
            child: const Text('Simpan'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    card.title = c.text.trim();
    try {
      await auth.updateTask(card, projectId);
      await _saveCards();
      if (mounted) setState(() {});
    } catch (e) {
      _show('$e');
    }
  }

  Future<void> _deleteCard(CardItem card) async {
    try {
      await auth.deleteTask(card.id);
      for (final list in columns.values) list.remove(card);
      await _saveCards();
      if (mounted) setState(() {});
    } catch (e) {
      _show('$e');
    }
  }

  String _listFor(String status) => status == '2'
      ? 'In Progress'
      : status == '3'
      ? 'Done'
      : 'To Do';
  String _statusFor(String list) => list == 'Done'
      ? '3'
      : list == 'In Progress'
      ? '2'
      : '1';

  List<KanbanBoardGroup<BoardGroupData, BoardItem>> _groups() => columns.entries
      .map(
        (entry) => KanbanBoardGroup<BoardGroupData, BoardItem>(
          id: entry.key,
          name: entry.key,
          customData: BoardGroupData(entry.key),
          items: entry.value.map(BoardItem.new).toList(),
        ),
      )
      .toList();

  Future<void> _add(String list) async {
    final input = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Tambah card ke $list'),
        content: TextField(controller: input, autofocus: true),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(context, input.text.trim().isNotEmpty),
            child: const Text('Tambah'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final id = await auth.createTask(input.text.trim(), projectId);
      setState(
        () => columns[list]!.add(
          CardItem(id: id, title: input.text.trim(), status: _statusFor(list)),
        ),
      );
      await _saveCards();
    } catch (e) {
      _show('$e');
    }
  }

  void _onMove(int? oldCard, int? newCard, int? oldGroup, int? newGroup) {
    if (oldCard == null ||
        oldGroup == null ||
        newGroup == null ||
        oldGroup == newGroup)
      return;
    final from = columns.keys.elementAt(oldGroup);
    final to = columns.keys.elementAt(newGroup);
    final card = columns[from]![oldCard];
    setState(() {
      columns[from]!.removeAt(oldCard);
      card.status = _statusFor(to);
      columns[to]!.insert(
        (newCard ?? columns[to]!.length).clamp(0, columns[to]!.length),
        card,
      );
    });
    auth.updateTask(card, projectId);
    _saveCards();
  }

  void _show(String text) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(text.replaceFirst('Exception: ', ''))));

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(title),
      actions: [
        IconButton(
          onPressed: () => _add('To Do'),
          icon: const Icon(Icons.add_card),
        ),
        IconButton(onPressed: _members, icon: const Icon(Icons.group)),
      ],
    ),
    body: loading
        ? const Center(child: CircularProgressIndicator())
        : KanbanBoard(
            controller: controller,
            groups: _groups(),
            groupConstraints: const BoxConstraints(
              maxWidth: 300,
              minWidth: 280,
            ),
            onGroupItemMove: _onMove,
            groupItemBuilder: (context, groupId, index) {
              final card = columns[groupId]![index];
              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  title: Text(card.title),
                  subtitle: card.dueDate.isEmpty
                      ? null
                      : Text('Due: ${card.dueDate}'),
                  trailing: PopupMenuButton<String>(
                    onSelected: (v) {
                      if (v == 'edit') _editCard(card);
                      if (v == 'delete') _deleteCard(card);
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'edit', child: Text('Edit card')),
                      PopupMenuItem(value: 'delete', child: Text('Hapus card')),
                    ],
                  ),
                  onTap: () => _detail(card),
                ),
              );
            },
          ),
  );

  void _members() {
    final email = TextEditingController();
    showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, refresh) => AlertDialog(
          title: const Text('Member board'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (invitedMembers.isNotEmpty)
                ...invitedMembers.map(
                  (e) => ListTile(
                    leading: const Icon(Icons.email_outlined),
                    title: Text(e),
                    trailing: IconButton(
                      onPressed: () {
                        refresh(() => invitedMembers.remove(e));
                      },
                      icon: const Icon(Icons.remove_circle_outline),
                    ),
                  ),
                ),
              TextField(
                controller: email,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(labelText: 'Email member'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Tutup'),
            ),
            FilledButton(
              onPressed: () async {
                final value = email.text.trim();
                if (value.isNotEmpty && !invitedMembers.contains(value)) {
                  refresh(() => invitedMembers.add(value));
                  await auth.saveMembers(projectId, invitedMembers);
                }
                email.clear();
              },
              child: const Text('Invite'),
            ),
          ],
        ),
      ),
    );
  }

  void _detail(CardItem card) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => TaskDetailPage(
          card: card,
          onChanged: () async {
            await _saveCards();
            if (mounted) setState(() {});
          },
        ),
      ),
    );
  }
}

class BoardGroupData {
  final String title;
  BoardGroupData(this.title);
}

class LegacyTaskDetailPage extends StatefulWidget {
  final CardItem card;
  final Future<void> Function() onChanged;
  const LegacyTaskDetailPage({
    super.key,
    required this.card,
    required this.onChanged,
  });

  @override
  State<LegacyTaskDetailPage> createState() => _LegacyTaskDetailPageState();
}

class _LegacyTaskDetailPageState extends State<LegacyTaskDetailPage> {
  final comment = TextEditingController();

  @override
  void dispose() {
    comment.dispose();
    super.dispose();
  }

  Future<void> _addComment() async {
    final text = comment.text.trim();
    if (text.isEmpty) return;
    setState(() => widget.card.comments.add(text));
    comment.clear();
    await widget.onChanged();
  }

  Future<void> _edit() async {
    final input = TextEditingController(text: widget.card.title);
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Edit tugas'),
        content: TextField(controller: input, autofocus: true),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(context, input.text.trim().isNotEmpty),
            child: const Text('Simpan'),
          ),
        ],
      ),
    );
    if (ok == true) {
      setState(() => widget.card.title = input.text.trim());
      await widget.onChanged();
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      leading: const BackButton(),
      title: Text(
        widget.card.title,
        style: const TextStyle(fontWeight: FontWeight.bold),
      ),
      centerTitle: true,
      actions: [
        IconButton(onPressed: _edit, icon: const Icon(Icons.edit_outlined)),
        IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.delete_outline, color: Colors.red),
        ),
      ],
    ),
    body: Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(18),
            children: [
              const Text('Komentar', style: TextStyle(fontSize: 20)),
              const SizedBox(height: 14),
              if (widget.card.comments.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 34),
                  child: Center(
                    child: Text(
                      'Belum ada komentar',
                      style: TextStyle(color: Color(0xff94a3b8)),
                    ),
                  ),
                )
              else
                ...widget.card.comments.asMap().entries.map(
                  (entry) => _commentItem(entry.key, entry.value),
                ),
            ],
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: TextField(
              controller: comment,
              onSubmitted: (_) => _addComment(),
              decoration: InputDecoration(
                hintText: 'Typing...',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                suffixIcon: IconButton(
                  onPressed: _addComment,
                  icon: const Icon(Icons.send_outlined),
                ),
              ),
            ),
          ),
        ),
      ],
    ),
  );

  Widget _commentItem(int index, String text) => Padding(
    padding: const EdgeInsets.only(bottom: 18),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CircleAvatar(
          radius: 16,
          backgroundColor: index.isEven ? blue : Colors.deepPurple,
          child: Text(
            'T${index + 1}',
            style: const TextStyle(fontSize: 10, color: Colors.white),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Team ${index + 1}',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 3),
              Text(text),
              TextButton(
                onPressed: () {},
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(0, 26),
                ),
                child: const Text('Balas'),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}
