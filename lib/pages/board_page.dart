part of '../procode_app.dart';

class BoardPage extends StatefulWidget {
  final Map<String, dynamic> project;
  const BoardPage({super.key, required this.project});
  @override
  State<BoardPage> createState() => _ProjectBoardState();
}

class _ProjectBoardState extends State<BoardPage> {
  late final String projectId;
  late final String title;
  List<CardItem> cards = [];
  List<String> collaborators = [];
  bool loading = true;
  @override
  void initState() {
    super.initState();
    projectId = '${widget.project['idproject'] ?? widget.project['id']}';
    title =
        '${widget.project['nama_project'] ?? widget.project['name'] ?? 'Project'}';
    _load();
  }

  Future<void> _load() async {
    cards = await auth.cardCache(projectId);
    collaborators = await auth.membersCache(projectId);
    try {
      final users = await auth.projectUsers(projectId);
      final names = users
          .map((user) => '${user['name'] ?? user['email'] ?? ''}'.trim())
          .where((name) => name.isNotEmpty)
          .toList();
      if (names.isNotEmpty) {
        collaborators = names;
        await auth.saveMembers(projectId, collaborators);
      }
    } catch (_) {}
    if (mounted) setState(() => loading = false);
  }

  void _collaboratorDialog() {
    final email = TextEditingController();
    final form = GlobalKey<FormState>();
    showDialog(
      context: context,
      builder: (dialogContext) {
        var status = 'Masukkan email pengguna yang sudah terdaftar.';
        return StatefulBuilder(
          builder: (context, refresh) => AlertDialog(
            title: const Text('Undang Kolaborator'),
            content: Form(
              key: form,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ...collaborators.map(
                    (item) => ListTile(
                      leading: const Icon(Icons.person_outline),
                      title: Text(item),
                      subtitle: const Text('Anggota dari cache/API'),
                    ),
                  ),
                  TextFormField(
                    controller: email,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                      labelText: 'Alamat email',
                    ),
                    validator: (value) =>
                        value != null &&
                            RegExp(
                              r'^[^@\s]+@[^@\s]+\.[^@\s]+$',
                            ).hasMatch(value)
                        ? null
                        : 'Masukkan email yang valid',
                  ),
                  const SizedBox(height: 8),
                  Text(
                    status,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xff64748b),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Tutup'),
              ),
              FilledButton(
                onPressed: () async {
                  if (!form.currentState!.validate()) return;
                  try {
                    final result = await auth.checkProjectEmail(
                      projectId,
                      email.text.trim(),
                    );
                    if (result['available'] != true) {
                      refresh(
                        () => status =
                            '${result['message'] ?? 'Email tidak tersedia.'}',
                      );
                      return;
                    }
                    final invited = await auth.inviteProject(
                      projectId,
                      email.text.trim(),
                    );
                    refresh(
                      () => status =
                          '${invited['message'] ?? 'Kolaborator berhasil ditambahkan.'}',
                    );
                    final users = await auth.projectUsers(projectId);
                    final names = users
                        .map(
                          (user) =>
                              '${user['name'] ?? user['email'] ?? ''}'.trim(),
                        )
                        .where((name) => name.isNotEmpty)
                        .toList();
                    if (names.isNotEmpty) {
                      collaborators = names;
                      await auth.saveMembers(projectId, collaborators);
                      if (mounted) setState(() {});
                    }
                  } catch (error) {
                    refresh(
                      () => status = error.toString().replaceFirst(
                        'Exception: ',
                        '',
                      ),
                    );
                  }
                },
                child: const Text('Undang'),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _save() => auth.saveCardCache(projectId, cards);
  Future<void> _move(CardItem card, String status) async {
    final previous = card.status;
    if (previous == status) return;
    setState(() => card.status = status);
    try {
      if (!card.id.startsWith('local_')) await auth.updateTask(card, projectId);
      await _save();
    } catch (_) {
      setState(() => card.status = previous);
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Status gagal diperbarui. Perubahan dikembalikan.'),
          ),
        );
    }
  }

  Color _tone(String s) => s == '2'
      ? const Color(0xfffff6bf)
      : s == '3'
      ? const Color(0xffd8f5e1)
      : const Color(0xffdceaff);
  String _label(String s) => s == '2'
      ? 'In Progress'
      : s == '3'
      ? 'Done'
      : 'To Do';
  Future<void> _add(String status) async {
    final c = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Tambah ke ${_label(status)}'),
        content: TextField(controller: c, autofocus: true),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, c.text.trim().isNotEmpty),
            child: const Text('Tambah'),
          ),
        ],
      ),
    );
    if (ok == true) {
      setState(
        () => cards.add(
          CardItem(
            id: 'local_${DateTime.now().microsecondsSinceEpoch}',
            title: c.text.trim(),
            status: status,
          ),
        ),
      );
      await _save();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Tugas "${c.text.trim()}" berhasil ditambahkan.'),
          ),
        );
      }
    }
  }

  Future<void> _edit(CardItem item) async {
    final c = TextEditingController(text: item.title);
    String status = item.status;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (_, refresh) => AlertDialog(
          title: const Text('Edit tugas'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: c),
              DropdownButton<String>(
                value: status,
                isExpanded: true,
                items: const [
                  DropdownMenuItem(value: '1', child: Text('To Do')),
                  DropdownMenuItem(value: '2', child: Text('In Progress')),
                  DropdownMenuItem(value: '3', child: Text('Done')),
                ],
                onChanged: (v) => refresh(() => status = v!),
              ),
            ],
          ),
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
      ),
    );
    if (ok == true) {
      setState(() {
        item.title = c.text.trim();
        item.status = status;
      });
      await _save();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Tugas "${item.title}" berhasil diperbarui.')),
        );
      }
    }
  }

  Future<void> _delete(CardItem item) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Hapus tugas?'),
        content: Text('Yakin ingin menghapus "${item.title}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => cards.remove(item));
    await _save();
    if (mounted)
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Tugas dihapus.')));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(title),
      actions: [
        IconButton(
          onPressed: _collaboratorDialog,
          icon: const Icon(Icons.group_add_outlined),
        ),
      ],
    ),
    floatingActionButton: FloatingActionButton(
      backgroundColor: blue,
      foregroundColor: Colors.white,
      onPressed: () => _add('1'),
      child: const Icon(Icons.note_add_outlined),
    ),
    body: loading
        ? const Center(child: CircularProgressIndicator())
        : ListView(
            padding: const EdgeInsets.all(16),
            children: ['1', '2', '3'].map(_section).toList(),
          ),
  );
  Widget _section(String status) {
    final list = cards.where((c) => c.status == status).toList();
    return DragTarget<CardItem>(
      onWillAcceptWithDetails: (details) => details.data.status != status,
      onAcceptWithDetails: (details) => _move(details.data, status),
      builder: (context, candidates, _) => Container(
        margin: const EdgeInsets.only(bottom: 14),
        decoration: BoxDecoration(
          color: candidates.isNotEmpty ? const Color(0xffeff6ff) : null,
          border: Border.all(
            color: candidates.isNotEmpty ? blue : _tone(status),
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              color: _tone(status),
              child: Row(
                children: [
                  Text(
                    _label(status),
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const Spacer(),
                  CircleAvatar(
                    radius: 10,
                    backgroundColor: Colors.white,
                    child: Text(
                      '${list.length}',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
            if (list.isEmpty)
              const _EmptyState(label: 'Tidak ada task', compact: true)
            else
              ...list.map(
                (item) => LongPressDraggable<CardItem>(
                  data: item,
                  feedback: Material(
                    color: Colors.transparent,
                    child: SizedBox(
                      width: 260,
                      child: Card(child: ListTile(title: Text(item.title))),
                    ),
                  ),
                  childWhenDragging: Opacity(
                    opacity: .35,
                    child: Card(
                      margin: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      elevation: 0,
                      color: const Color(0xfff8fafc),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(6),
                        side: const BorderSide(color: Color(0xffe2e8f0)),
                      ),
                      child: ListTile(dense: true, title: Text(item.title)),
                    ),
                  ),
                  child: Card(
                    margin: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    elevation: 0,
                    color: const Color(0xfff8fafc),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(6),
                      side: const BorderSide(color: Color(0xffe2e8f0)),
                    ),
                    child: ListTile(
                      dense: true,
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => TaskDetailPage(
                            card: item,
                            onChanged: _save,
                            onDelete: () async {
                              setState(() => cards.remove(item));
                              await _save();
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      'Tugas "${item.title}" dihapus.',
                                    ),
                                  ),
                                );
                              }
                            },
                          ),
                        ),
                      ),
                      title: Text(item.title),
                      trailing: PopupMenuButton<String>(
                        onSelected: (v) {
                          if (v == 'edit') _edit(item);
                          if (v == 'delete') _delete(item);
                        },
                        itemBuilder: (_) => const [
                          PopupMenuItem(
                            value: 'edit',
                            child: Row(
                              children: [
                                Icon(
                                  Icons.edit_outlined,
                                  color: Colors.black87,
                                ),
                                SizedBox(width: 10),
                                Text(
                                  'Edit',
                                  style: TextStyle(color: Colors.black87),
                                ),
                              ],
                            ),
                          ),
                          PopupMenuItem(
                            value: 'delete',
                            child: Row(
                              children: [
                                Icon(Icons.delete_outline, color: Colors.red),
                                SizedBox(width: 10),
                                Text(
                                  'Hapus',
                                  style: TextStyle(color: Colors.red),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
