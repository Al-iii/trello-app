part of '../procode_app.dart';

class BoardsPage extends StatefulWidget {
  const BoardsPage({super.key});
  @override
  State<BoardsPage> createState() => _BoardsState();
}

class _LegacyBoardsState extends State<BoardsPage> {
  List<Map<String, dynamic>> boards = [];
  List<CardItem> inboxTasks = [];
  String? expandedBoardId;
  bool loading = true;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    boards = await auth.boardCache();
    inboxTasks = await auth.inbox();
    try {
      boards = await auth.projects();
      await auth.saveBoardCache(boards);
    } catch (_) {}
    if (mounted) setState(() => loading = false);
  }

  String boardId(Map<String, dynamic> b) =>
      '${b['idproject'] ?? b['id'] ?? ''}';
  String boardName(Map<String, dynamic> b) =>
      '${b['nama_project'] ?? b['name'] ?? b['title'] ?? 'Board'}';

  Future<void> editBoard(int index) async {
    final c = TextEditingController(text: boardName(boards[index]));
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AppDialog(
        title: const Text('Edit board'),
        content: TextField(controller: c),
        actions: [
          DialogActionRow(
            onCancel: () => Navigator.pop(context),
            onSubmit: () => Navigator.pop(context, c.text.trim().isNotEmpty),
            submitLabel: 'Simpan',
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await auth.updateProject(boardId(boards[index]), c.text.trim());
      setState(() => boards[index]['nama_project'] = c.text.trim());
      await auth.saveBoardCache(boards);
    } catch (e) {
      _msg('$e');
    }
  }

  Future<void> deleteBoard(int index) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AppDialog(
        title: const Text('Hapus board?'),
        actions: [
          DialogActionRow(
            onCancel: () => Navigator.pop(context, false),
            onSubmit: () => Navigator.pop(context, true),
            submitLabel: 'Hapus',
            destructive: true,
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await auth.deleteProject(boardId(boards[index]));
      setState(() => boards.removeAt(index));
      await auth.saveBoardCache(boards);
    } catch (e) {
      _msg('$e');
    }
  }

  Future<void> shareBoard(Map<String, dynamic> board) =>
      SharePlus.instance.share(
        ShareParams(text: 'Board ${boardName(board)}\nID: ${boardId(board)}'),
      );

  Future<void> addBoard() async {
    final c = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AppDialog(
        title: const Text('Buat board'),
        content: TextField(
          controller: c,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Nama board'),
        ),
        actions: [
          DialogActionRow(
            onCancel: () => Navigator.pop(context),
            onSubmit: () => Navigator.pop(context, c.text.trim().isNotEmpty),
            submitLabel: 'Buat',
          ),
        ],
      ),
    );
    if (ok == true) {
      try {
        final b = await auth.createProject(c.text.trim());
        setState(() => boards.add(b));
        await auth.saveBoardCache(boards);
      } catch (e) {
        _msg('$e');
      }
    }
  }

  Future<void> addInboxTask() async {
    final input = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AppDialog(
        title: const Text('Tambah tugas'),
        content: TextField(
          controller: input,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Nama tugas'),
        ),
        actions: [
          DialogActionRow(
            onCancel: () => Navigator.pop(context),
            onSubmit: () =>
                Navigator.pop(context, input.text.trim().isNotEmpty),
            submitLabel: 'Tambah',
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(
      () => inboxTasks.add(
        CardItem(
          id: 'local_${DateTime.now().microsecondsSinceEpoch}',
          title: input.text.trim(),
        ),
      ),
    );
    await auth.saveInbox(inboxTasks);
  }

  Future<void> assignToProject(
    CardItem card,
    Map<String, dynamic> board,
  ) async {
    final id = boardId(board);
    final projectCards = await auth.cardCache(id);
    projectCards.add(card);
    await auth.saveCardCache(id, projectCards);
    if (!card.id.startsWith('local_')) {
      try {
        await auth.updateTask(card, id);
      } catch (_) {}
    }
    setState(() => inboxTasks.removeWhere((task) => task.id == card.id));
    await auth.saveInbox(inboxTasks);
    if (mounted) _msg('Tugas dipindahkan ke ${boardName(board)}');
  }

  Future<void> logout() async {
    await auth.logout();
    currentUser.value = null;
    if (mounted)
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const LoginPage()),
      );
  }

  void _msg(String s) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(s.replaceFirst('Exception: ', ''))));
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Image.asset('assets/procode_logo.png', height: 30),
      actions: [
        IconButton(
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const ProfilePage()),
          ),
          icon: const Icon(Icons.account_circle_outlined),
        ),
        PopupMenuButton<String>(
          onSelected: (v) {
            if (v == 'logout') logout();
            if (v == 'profile')
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ProfilePage()),
              );
          },
          itemBuilder: (_) => const [
            PopupMenuItem(
              value: 'profile',
              child: Row(
                children: [
                  Icon(Icons.person_outline, size: 20),
                  SizedBox(width: 10),
                  Text('Profil'),
                ],
              ),
            ),
            PopupMenuItem(
              value: 'logout',
              child: Row(
                children: [
                  Icon(Icons.logout, size: 20, color: Colors.red),
                  SizedBox(width: 10),
                  Text('Keluar', style: TextStyle(color: Colors.red)),
                ],
              ),
            ),
          ],
        ),
      ],
    ),
    body: RefreshIndicator(
      onRefresh: load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Dashboard',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                ),
              ),
              SizedBox(
                width: 154,
                child: TextField(
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: 'Cari project...',
                    prefixIcon: const Icon(Icons.search, size: 18),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          const Text(
            'Task List',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(
            'Drag tugas ke project yang dibuka untuk menugaskan.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const Divider(),
          if (inboxTasks.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 22),
              child: Center(
                child: Column(
                  children: [
                    Icon(Icons.assignment_outlined, color: Color(0xff94a3b8)),
                    SizedBox(height: 4),
                    Text(
                      'Belum ada task',
                      style: TextStyle(color: Color(0xff94a3b8)),
                    ),
                  ],
                ),
              ),
            )
          else
            ...inboxTasks.map(
              (task) => LongPressDraggable<CardItem>(
                data: task,
                feedback: Material(
                  color: Colors.transparent,
                  child: _taskTile(task, elevated: true),
                ),
                childWhenDragging: Opacity(
                  opacity: .35,
                  child: _taskTile(task),
                ),
                child: InkWell(
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => TaskDetailPage(
                        card: task,
                        onChanged: () async {
                          await auth.saveInbox(inboxTasks);
                          if (mounted) setState(() {});
                        },
                      ),
                    ),
                  ),
                  child: _taskTile(task),
                ),
              ),
            ),
          const SizedBox(height: 18),
          const Text(
            'Project List',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          const Divider(),
          if (loading) const Center(child: CircularProgressIndicator()),
          ...boards.asMap().entries.map((e) => _projectCard(e.key, e.value)),
        ],
      ),
    ),
    bottomNavigationBar: SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: addInboxTask,
                icon: const Icon(Icons.add),
                label: const Text('Tambah Tugas'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: FilledButton.icon(
                onPressed: addBoard,
                icon: const Icon(Icons.add),
                label: const Text('Tambah Project'),
              ),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _taskTile(CardItem task, {bool elevated = false}) => Card(
    elevation: elevated ? 6 : 0,
    margin: const EdgeInsets.only(bottom: 8),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(7),
      side: const BorderSide(color: Color(0xffdbe3f0)),
    ),
    child: ListTile(
      dense: true,
      leading: const Icon(Icons.assignment_outlined, color: blue),
      title: Text(
        task.title,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      trailing: const Icon(Icons.drag_indicator, color: Color(0xff94a3b8)),
    ),
  );

  Widget _projectCard(int index, Map<String, dynamic> board) {
    final id = boardId(board);
    final isOpen = expandedBoardId == id;
    return DragTarget<CardItem>(
      onWillAcceptWithDetails: (_) => isOpen,
      onAcceptWithDetails: (detail) => assignToProject(detail.data, board),
      builder: (context, candidates, _) => Card(
        color: candidates.isNotEmpty ? const Color(0xffeff6ff) : Colors.white,
        margin: const EdgeInsets.only(bottom: 9),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(6),
          side: BorderSide(color: isOpen ? blue : const Color(0xffdbe3f0)),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: () => setState(() => expandedBoardId = isOpen ? null : id),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        boardName(board),
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => BoardPage(project: board),
                        ),
                      ),
                      icon: const Icon(Icons.arrow_circle_right, color: blue),
                    ),
                    PopupMenuButton<String>(
                      onSelected: (v) {
                        if (v == 'edit') editBoard(index);
                        if (v == 'delete') deleteBoard(index);
                        if (v == 'share') shareBoard(board);
                      },
                      itemBuilder: (_) => const [
                        PopupMenuItem(
                          value: 'edit',
                          child: Text('Edit project'),
                        ),
                        PopupMenuItem(
                          value: 'delete',
                          child: Text('Hapus project'),
                        ),
                        PopupMenuItem(value: 'share', child: Text('Bagikan')),
                      ],
                    ),
                  ],
                ),
                const Text(
                  'Dibuat: 23 September 2026',
                  style: TextStyle(fontSize: 12, color: Color(0xff64748b)),
                ),
                if (isOpen)
                  const Padding(
                    padding: EdgeInsets.only(top: 10),
                    child: Row(
                      children: [
                        Icon(Icons.file_download_outlined, color: blue),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Lepaskan task di sini untuk memasukkannya ke project.',
                            style: TextStyle(color: blue),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _BoardsState extends State<BoardsPage> {
  final Map<String, List<CardItem>> tasks = {};
  final Set<String> openProjects = {};
  final search = TextEditingController();
  String semester = 'Semua Semester';
  bool loading = true, addOpen = false;
  String? loadError;
  List<Map<String, dynamic>> boards = [];
  List<CardItem> inboxTasks = [];

  static const semesters = [
    'Semua Semester',
    '2027/2028 - Genap',
    '2027/2028 - Ganjil',
    '2026/2027 - Genap',
    '2026/2027 - Ganjil',
    '2025/2026 - Genap',
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  String id(Map<String, dynamic> board) =>
      '${board['idproject'] ?? board['id'] ?? ''}';
  String name(Map<String, dynamic> board) =>
      '${board['nama_project'] ?? board['name'] ?? 'Project'}';

  Future<void> _load() async {
    if (mounted)
      setState(() {
        loading = true;
        loadError = null;
      });
    boards = await auth.boardCache();
    inboxTasks = await auth.inbox();
    try {
      final remoteInbox = await auth.unassignedTasks();
      if (remoteInbox.isNotEmpty) {
        inboxTasks = remoteInbox
            .map(
              (row) => CardItem(
                id: '${row['idtask'] ?? row['id']}',
                title: '${row['nama_task'] ?? row['title'] ?? 'Task'}',
                description: '${row['deskripsi'] ?? row['description'] ?? ''}',
                status: '${row['status'] ?? '1'}',
                dueDate: '${row['due_date'] ?? row['dueDate'] ?? ''}',
              ),
            )
            .toList();
        await auth.saveInbox(inboxTasks);
      }
    } catch (_) {}
    try {
      boards = await auth.projects();
      await auth.saveBoardCache(boards);
    } catch (error) {
      loadError = error.toString().replaceFirst('Exception: ', '');
    }
    for (final board in boards) {
      final projectId = id(board);
      List<CardItem> cards;
      try {
        cards = await auth.syncedProjectCards(projectId);
      } catch (_) {
        cards = await auth.cardCache(projectId);
      }
      tasks[projectId] = cards;
      // GET /projects sudah menyertakan `users`. Hindari satu request anggota
      // tambahan per project; endpoint khusus dipakai saat daftar perlu di-refresh.
      if (board['users'] is List) {
        board['_serverMembers'] = board['users'];
      }
    }
    await auth.saveBoardCache(boards);
    if (mounted) setState(() => loading = false);
  }

  List<Map<String, dynamic>> get filtered => boards.where((b) {
    final matchesName = name(
      b,
    ).toLowerCase().contains(search.text.toLowerCase());
    final matchesSemester =
        semester == semesters.first ||
        '${b['semester'] ?? semesters[4]}' == semester;
    return matchesName && matchesSemester;
  }).toList();

  int _statusCount(String projectId, String status) =>
      tasks[projectId]?.where((t) => t.status == status).length ?? 0;
  String _label(String status) => status == '2'
      ? 'In Progress'
      : status == '3'
      ? 'Done'
      : 'To Do';
  Color _tone(String status) => status == '2'
      ? const Color(0xfffff6bf)
      : status == '3'
      ? const Color(0xffd8f5e1)
      : const Color(0xffdceaff);
  Color _ink(String status) => status == '2'
      ? const Color(0xff8a6415)
      : status == '3'
      ? const Color(0xff16805b)
      : const Color(0xff315d9c);

  Future<void> _saveProjectTasks(String projectId) =>
      auth.saveCardCache(projectId, tasks[projectId] ?? []);

  Future<void> _newProject() async {
    final input = TextEditingController();
    final form = GlobalKey<FormState>();
    final created = await showDialog<bool>(
      context: context,
      builder: (context) => AppDialog(
        title: const Text('Buat Project Baru'),
        content: Form(
          key: form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Nama Project',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 7),
              TextFormField(
                controller: input,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'Masukkan nama project',
                ),
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'Nama project wajib diisi'
                    : null,
              ),
            ],
          ),
        ),
        actions: [
          DialogActionRow(
            onCancel: () => Navigator.pop(context),
            onSubmit: () {
              if (form.currentState!.validate()) {
                Navigator.pop(context, true);
              }
            },
            submitLabel: 'Buat Project',
          ),
        ],
      ),
    );
    if (created != true) return;
    Map<String, dynamic> project;
    try {
      project = await auth.createProject(input.text.trim());
    } catch (_) {
      project = {
        'id': 'local_${DateTime.now().microsecondsSinceEpoch}',
        'nama_project': input.text.trim(),
      };
    }
    project['semester'] = semesters[4];
    setState(() {
      boards.add(project);
      tasks[id(project)] = [];
    });
    await auth.saveBoardCache(boards);
    _message('Project "${name(project)}" berhasil ditambahkan.');
  }

  Future<void> _newTask({String? defaultProject}) async {
    final title = TextEditingController();
    final description = TextEditingController();
    final form = GlobalKey<FormState>();
    String? project = defaultProject;
    String status = '1';
    DateTime? deadline;
    final created = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialog) => AppDialog(
          title: const Text('Buat Tugas Baru'),
          content: SingleChildScrollView(
            child: Form(
              key: form,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: title,
                    autofocus: true,
                    decoration: const InputDecoration(
                      labelText: 'Nama Tugas',
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) => v == null || v.trim().isEmpty
                        ? 'Nama tugas wajib diisi'
                        : null,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: description,
                    minLines: 3,
                    maxLines: 5,
                    decoration: const InputDecoration(
                      labelText: 'Deskripsi',
                      alignLabelWithHint: true,
                    ),
                  ),
                  const SizedBox(height: 12),
                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(6),
                      side: const BorderSide(color: Color(0xffcbd5e1)),
                    ),
                    leading: const Icon(Icons.event_outlined),
                    title: const Text('Tenggat tanggal dan waktu'),
                    subtitle: Text(
                      deadline == null
                          ? 'Belum ditentukan'
                          : taskDeadlineLabel(deadline!.toIso8601String()),
                    ),
                    trailing: deadline == null
                        ? const Icon(Icons.chevron_right)
                        : IconButton(
                            tooltip: 'Hapus tenggat',
                            onPressed: () => setDialog(() => deadline = null),
                            icon: const Icon(Icons.close),
                          ),
                    onTap: () async {
                      final selected = await pickTaskDeadline(
                        context,
                        deadline,
                      );
                      if (context.mounted) {
                        setDialog(() => deadline = selected);
                      }
                    },
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String?>(
                    value: project,
                    decoration: const InputDecoration(
                      labelText: 'Project',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Text('Tanpa project (Task List)'),
                      ),
                      ...boards.map(
                        (b) => DropdownMenuItem(
                          value: id(b),
                          child: Text(name(b), overflow: TextOverflow.ellipsis),
                        ),
                      ),
                    ],
                    onChanged: (v) => setDialog(() => project = v),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TaskFormActions(
              onCancel: () => Navigator.pop(context),
              onSubmit: () {
                if (form.currentState!.validate()) Navigator.pop(context, true);
              },
              submitLabel: 'Tambah',
            ),
          ],
        ),
      ),
    );
    if (created != true) return;
    var taskId = 'local_${DateTime.now().microsecondsSinceEpoch}';
    if (project != null) {
      try {
        taskId = await auth.createTask(
          title.text.trim(),
          project!,
          status: status,
          description: description.text.trim(),
          dueDate: deadline?.toIso8601String() ?? '',
        );
      } catch (error) {
        _message(error.toString().replaceFirst('Exception: ', ''));
        return;
      }
    }
    final task = CardItem(
      id: taskId,
      title: title.text.trim(),
      description: description.text.trim(),
      status: status,
      dueDate: deadline?.toIso8601String() ?? '',
    );
    if (project == null) {
      setState(() => inboxTasks.add(task));
      await auth.saveInbox(inboxTasks);
    } else {
      setState(() => tasks.putIfAbsent(project!, () => []).add(task));
      await _saveProjectTasks(project!);
    }
    _message('Tugas "${task.title}" berhasil ditambahkan.');
  }

  Future<void> _editTask(String projectId, CardItem task) async {
    final input = TextEditingController(text: task.title);
    final description = TextEditingController(text: task.description);
    String status = task.status;
    DateTime? deadline = taskDeadlineFrom(task.dueDate);
    final changed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialog) => AppDialog(
          title: const Text('Edit tugas'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: input,
                  autofocus: true,
                  decoration: const InputDecoration(labelText: 'Nama tugas'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: description,
                  minLines: 3,
                  maxLines: 5,
                  decoration: const InputDecoration(
                    labelText: 'Deskripsi',
                    alignLabelWithHint: true,
                  ),
                ),
                const SizedBox(height: 12),
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(6),
                    side: const BorderSide(color: Color(0xffcbd5e1)),
                  ),
                  leading: const Icon(Icons.event_outlined),
                  title: const Text('Tenggat'),
                  subtitle: Text(
                    deadline == null
                        ? 'Belum ditentukan'
                        : taskDeadlineLabel(deadline!.toIso8601String()),
                  ),
                  trailing: deadline == null
                      ? const Icon(Icons.chevron_right)
                      : IconButton(
                          onPressed: () => setDialog(() => deadline = null),
                          icon: const Icon(Icons.close),
                        ),
                  onTap: () async {
                    final selected = await pickTaskDeadline(context, deadline);
                    if (context.mounted) {
                      setDialog(() => deadline = selected);
                    }
                  },
                ),
                DropdownButton<String>(
                  value: status,
                  isExpanded: true,
                  items: const [
                    DropdownMenuItem(value: '1', child: Text('To Do')),
                    DropdownMenuItem(value: '2', child: Text('In Progress')),
                    DropdownMenuItem(value: '3', child: Text('Done')),
                  ],
                  onChanged: (v) => setDialog(() => status = v!),
                ),
              ],
            ),
          ),
          actions: [
            TaskFormActions(
              onCancel: () => Navigator.pop(context),
              onSubmit: () =>
                  Navigator.pop(context, input.text.trim().isNotEmpty),
              submitLabel: 'Simpan',
            ),
          ],
        ),
      ),
    );
    if (changed != true) return;
    setState(() {
      task.title = input.text.trim();
      task.description = description.text.trim();
      task.status = status;
      task.dueDate = deadline?.toIso8601String() ?? '';
    });
    if (!task.id.startsWith('local_')) {
      try {
        await auth.updateTask(task, projectId);
      } catch (_) {}
    }
    await _saveProjectTasks(projectId);
    _message('Tugas "${task.title}" berhasil diperbarui.');
  }

  Future<void> _editProject(Map<String, dynamic> board) async {
    final input = TextEditingController(text: name(board));
    final form = GlobalKey<FormState>();
    final changed = await showDialog<bool>(
      context: context,
      builder: (context) => AppDialog(
        title: const Text('Edit project'),
        content: Form(
          key: form,
          child: TextFormField(
            controller: input,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Nama project'),
            validator: (value) => value == null || value.trim().isEmpty
                ? 'Nama project wajib diisi'
                : null,
          ),
        ),
        actions: [
          DialogActionRow(
            onCancel: () => Navigator.pop(context, false),
            onSubmit: () {
              if (form.currentState!.validate()) Navigator.pop(context, true);
            },
            submitLabel: 'Simpan',
          ),
        ],
      ),
    );
    if (changed != true) return;

    final projectId = id(board);
    final newName = input.text.trim();
    try {
      if (!projectId.startsWith('local_')) {
        await auth.updateProject(projectId, newName);
      }
      setState(() {
        if (board.containsKey('nama_project')) {
          board['nama_project'] = newName;
        } else {
          board['name'] = newName;
        }
      });
      await auth.saveBoardCache(boards);
      _message('Project "$newName" berhasil diperbarui.');
    } catch (_) {
      _message('Project gagal diperbarui.');
    }
  }

  String? _ownerOf(CardItem task) {
    if (inboxTasks.any((item) => item.id == task.id)) return null;
    for (final entry in tasks.entries) {
      if (entry.value.any((item) => item.id == task.id)) return entry.key;
    }
    return null;
  }

  Future<void> _moveTask(
    CardItem task,
    String? targetProjectId,
    String status,
  ) async {
    final sourceProjectId = _ownerOf(task);
    final oldInbox = List<CardItem>.from(inboxTasks);
    final oldSource = sourceProjectId == null
        ? null
        : List<CardItem>.from(tasks[sourceProjectId] ?? []);
    final oldTarget = targetProjectId == null
        ? null
        : List<CardItem>.from(tasks[targetProjectId] ?? []);
    final oldStatus = task.status;
    setState(() {
      inboxTasks.removeWhere((item) => item.id == task.id);
      for (final list in tasks.values) {
        list.removeWhere((item) => item.id == task.id);
      }
      task.status = status;
      if (targetProjectId == null)
        inboxTasks.add(task);
      else
        tasks.putIfAbsent(targetProjectId, () => []).add(task);
    });
    try {
      if (!task.id.startsWith('local_') && targetProjectId != null)
        await auth.updateTask(task, targetProjectId);
      await auth.saveInbox(inboxTasks);
      if (sourceProjectId != null) await _saveProjectTasks(sourceProjectId);
      if (targetProjectId != null && targetProjectId != sourceProjectId)
        await _saveProjectTasks(targetProjectId);
    } catch (_) {
      setState(() {
        inboxTasks = oldInbox;
        task.status = oldStatus;
        if (sourceProjectId != null && oldSource != null)
          tasks[sourceProjectId] = oldSource;
        if (targetProjectId != null && oldTarget != null)
          tasks[targetProjectId] = oldTarget;
      });
      _message('Tugas gagal dipindahkan. Perubahan dikembalikan.');
    }
  }

  Future<void> _deleteTask(
    String projectId,
    CardItem task, {
    bool askConfirmation = true,
  }) async {
    if (askConfirmation && !await _confirmDelete('tugas', task.title)) return;
    setState(() => tasks[projectId]?.remove(task));
    if (!task.id.startsWith('local_')) {
      try {
        await auth.deleteTask(task.id);
      } catch (_) {}
    }
    await _saveProjectTasks(projectId);
    _message('Tugas "${task.title}" dihapus.');
  }

  Future<bool> _confirmDelete(String type, String name) async =>
      await showDialog<bool>(
        context: context,
        builder: (_) => AppDialog(
          title: Text('Hapus $type?'),
          content: Text('Yakin ingin menghapus "$name"?'),
          actions: [
            DialogActionRow(
              onCancel: () => Navigator.pop(context, false),
              onSubmit: () => Navigator.pop(context, true),
              submitLabel: 'Hapus',
              destructive: true,
            ),
          ],
        ),
      ) ??
      false;

  Future<void> _deleteProject(Map<String, dynamic> board) async {
    if (!await _confirmDelete('project', name(board))) return;
    final projectId = id(board);
    try {
      if (!projectId.startsWith('local_')) await auth.deleteProject(projectId);
      setState(() {
        boards.remove(board);
        tasks.remove(projectId);
        openProjects.remove(projectId);
      });
      await auth.saveBoardCache(boards);
      _message('Project "${name(board)}" dihapus.');
    } catch (_) {
      _message('Project gagal dihapus.');
    }
  }

  Future<void> _logout() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AppDialog(
        title: const Text('Log out?'),
        content: const Text('Anda akan keluar dari sesi ini.'),
        actions: [
          DialogActionRow(
            onCancel: () => Navigator.pop(context, false),
            onSubmit: () => Navigator.pop(context, true),
            submitLabel: 'Log out',
          ),
        ],
      ),
    );
    if (ok != true) return;
    await auth.logout();
    currentUser.value = null;
    if (mounted)
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const LoginPage()),
        (_) => false,
      );
  }

  void _message(String message) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(message)));
  String get _displayName {
    final user = currentUser.value;
    final name = user?.name.trim() ?? '';
    return name.isNotEmpty
        ? name
        : (user?.email.trim().isNotEmpty == true ? user!.email : 'Profil');
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Image.asset('assets/procode_logo.png', height: 29),
      actions: [
        PopupMenuButton<String>(
          onSelected: (value) {
            if (value == 'profile')
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ProfilePage()),
              );
            if (value == 'logout') _logout();
          },
          itemBuilder: (_) => const [
            PopupMenuItem(
              value: 'profile',
              child: Row(
                children: [
                  Icon(Icons.person_outline, size: 20),
                  SizedBox(width: 10),
                  Text('Profil'),
                ],
              ),
            ),
            PopupMenuItem(
              value: 'logout',
              child: Row(
                children: [
                  Icon(Icons.logout, size: 20, color: Colors.red),
                  SizedBox(width: 10),
                  Text('Log out', style: TextStyle(color: Colors.red)),
                ],
              ),
            ),
          ],
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircleAvatar(
                  radius: 13,
                  backgroundColor: blue,
                  child: Text(
                    initialsFor(_displayName),
                    style: const TextStyle(fontSize: 10, color: Colors.white),
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  _displayName,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: Color(0xff111827),
                  ),
                ),
                Icon(Icons.keyboard_arrow_down, color: Color(0xff111827)),
              ],
            ),
          ),
        ),
      ],
    ),
    floatingActionButton: _addMenu(),
    body: RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 96),
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Dashboard',
                  style: TextStyle(fontSize: 21, fontWeight: FontWeight.bold),
                ),
              ),
              SizedBox(
                width: 142,
                child: TextField(
                  controller: search,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: 'Cari project...',
                    prefixIcon: const Icon(Icons.search, size: 17),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(5),
                    ),
                  ),
                ),
              ),
              PopupMenuButton<String>(
                tooltip: 'Filter semester: $semester',
                icon: const Icon(Icons.filter_alt_outlined, color: blue),
                offset: const Offset(0, 8),
                color: Colors.white,
                surfaceTintColor: Colors.transparent,
                elevation: 8,
                constraints: const BoxConstraints(
                  minWidth: 190,
                  maxWidth: 210,
                  maxHeight: 248,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                  side: const BorderSide(color: Color(0xffe5e7eb)),
                ),
                onSelected: (value) => setState(() => semester = value),
                itemBuilder: (_) => semesters.map((item) {
                  final selected = item == semester;
                  return PopupMenuItem<String>(
                    value: item,
                    height: 40,
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: Container(
                      height: 34,
                      padding: const EdgeInsets.symmetric(horizontal: 9),
                      decoration: BoxDecoration(
                        color: selected
                            ? const Color(0xffeef4ff)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            item == semesters.first
                                ? Icons.format_list_bulleted_rounded
                                : Icons.school_outlined,
                            size: 16,
                            color: selected ? blue : const Color(0xff9ca3af),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              item,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: selected
                                    ? FontWeight.w600
                                    : FontWeight.w400,
                                color: selected
                                    ? blue
                                    : const Color(0xff24324a),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Text(
            'Task List',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const Divider(height: 10),
          _inboxDropArea(),
          const SizedBox(height: 20),
          const Text(
            'Project List',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const Divider(height: 10),
          if (loading)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: CircularProgressIndicator(),
              ),
            )
          else if (loadError != null && filtered.isEmpty)
            _LoadError(message: loadError!, onRetry: _load)
          else if (filtered.isEmpty)
            const _EmptyState(label: 'Project tidak ditemukan')
          else
            ...filtered.map(_projectCard),
        ],
      ),
    ),
  );

  Widget _inboxDropArea() => DragTarget<CardItem>(
    onWillAcceptWithDetails: (details) => _ownerOf(details.data) != null,
    onAcceptWithDetails: (details) => _moveTask(details.data, null, '1'),
    builder: (context, candidates, _) => Container(
      decoration: BoxDecoration(
        color: candidates.isNotEmpty ? const Color(0xffeff6ff) : null,
        borderRadius: BorderRadius.circular(7),
        border: candidates.isNotEmpty ? Border.all(color: blue) : null,
      ),
      child: inboxTasks.isEmpty
          ? const _EmptyState(label: 'Belum ada task')
          : Column(children: inboxTasks.map(_inboxTaskCard).toList()),
    ),
  );

  Widget _inboxTaskCard(CardItem task) => LongPressDraggable<CardItem>(
    data: task,
    feedback: Material(
      color: Colors.transparent,
      child: SizedBox(width: 280, child: _taskVisual(task, elevated: true)),
    ),
    childWhenDragging: Opacity(opacity: .35, child: _taskVisual(task)),
    child: _taskVisual(
      task,
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => TaskDetailPage(
            card: task,
            onChanged: () => auth.saveInbox(inboxTasks),
            onDelete: () async {
              setState(() => inboxTasks.remove(task));
              await auth.saveInbox(inboxTasks);
              _message('Tugas "${task.title}" dihapus.');
            },
          ),
        ),
      ),
      trailing: _taskMenu(
        onEdit: () => _editInboxTask(task),
        onDelete: () => _deleteInboxTask(task),
      ),
    ),
  );

  Widget _taskVisual(
    CardItem task, {
    bool elevated = false,
    VoidCallback? onTap,
    Widget? trailing,
  }) => Card(
    margin: const EdgeInsets.only(bottom: 7),
    elevation: elevated ? 7 : 0,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(6),
      side: const BorderSide(color: Color(0xffe2e8f0)),
    ),
    child: ListTile(
      dense: true,
      leading: const Icon(Icons.assignment_outlined, color: blue),
      title: Text(task.title),
      subtitle: _taskSubtitle(task, includeDragHint: true),
      onTap: onTap,
      trailing:
          trailing ??
          const Icon(Icons.drag_indicator, color: Color(0xff94a3b8)),
    ),
  );

  Widget _taskMenu({
    required VoidCallback onEdit,
    required VoidCallback onDelete,
  }) => PopupMenuButton<String>(
    tooltip: 'Aksi tugas',
    onSelected: (value) {
      if (value == 'edit') onEdit();
      if (value == 'delete') onDelete();
    },
    itemBuilder: (_) => const [
      PopupMenuItem(
        value: 'edit',
        child: Row(
          children: [
            Icon(Icons.edit_outlined, color: Colors.black87),
            SizedBox(width: 10),
            Text('Edit', style: TextStyle(color: Colors.black87)),
          ],
        ),
      ),
      PopupMenuItem(
        value: 'delete',
        child: Row(
          children: [
            Icon(Icons.delete_outline, color: Colors.red),
            SizedBox(width: 10),
            Text('Hapus', style: TextStyle(color: Colors.red)),
          ],
        ),
      ),
    ],
  );

  Future<void> _editInboxTask(CardItem task) async {
    final input = TextEditingController(text: task.title);
    final description = TextEditingController(text: task.description);
    DateTime? deadline = taskDeadlineFrom(task.dueDate);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialog) => AppDialog(
          title: const Text('Edit tugas'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: input, autofocus: true),
                const SizedBox(height: 12),
                TextField(
                  controller: description,
                  minLines: 3,
                  maxLines: 5,
                  decoration: const InputDecoration(
                    labelText: 'Deskripsi',
                    alignLabelWithHint: true,
                  ),
                ),
                const SizedBox(height: 12),
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(6),
                    side: const BorderSide(color: Color(0xffcbd5e1)),
                  ),
                  leading: const Icon(Icons.event_outlined),
                  title: const Text('Tenggat'),
                  subtitle: Text(
                    deadline == null
                        ? 'Belum ditentukan'
                        : taskDeadlineLabel(deadline!.toIso8601String()),
                  ),
                  trailing: deadline == null
                      ? const Icon(Icons.chevron_right)
                      : IconButton(
                          onPressed: () => setDialog(() => deadline = null),
                          icon: const Icon(Icons.close),
                        ),
                  onTap: () async {
                    final selected = await pickTaskDeadline(context, deadline);
                    if (context.mounted) {
                      setDialog(() => deadline = selected);
                    }
                  },
                ),
              ],
            ),
          ),
          actions: [
            TaskFormActions(
              onCancel: () => Navigator.pop(context),
              onSubmit: () =>
                  Navigator.pop(context, input.text.trim().isNotEmpty),
              submitLabel: 'Simpan',
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    setState(() {
      task.title = input.text.trim();
      task.description = description.text.trim();
      task.dueDate = deadline?.toIso8601String() ?? '';
    });
    await auth.saveInbox(inboxTasks);
    _message('Tugas "${task.title}" berhasil diperbarui.');
  }

  Future<void> _deleteInboxTask(CardItem task) async {
    if (!await _confirmDelete('tugas', task.title)) return;
    setState(() => inboxTasks.remove(task));
    await auth.saveInbox(inboxTasks);
    _message('Tugas "${task.title}" dihapus.');
  }

  Widget _addMenu() => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.end,
    children: [
      if (addOpen) ...[
        FloatingActionButton.extended(
          heroTag: 'task',
          backgroundColor: blue,
          foregroundColor: Colors.white,
          onPressed: () {
            setState(() => addOpen = false);
            _newTask();
          },
          icon: const Icon(Icons.note_add_outlined),
          label: const Text('Tugas'),
        ),
        const SizedBox(height: 8),
        FloatingActionButton.extended(
          heroTag: 'project',
          backgroundColor: blue,
          foregroundColor: Colors.white,
          onPressed: () {
            setState(() => addOpen = false);
            _newProject();
          },
          icon: const Icon(Icons.create_new_folder_outlined),
          label: const Text('Project'),
        ),
        const SizedBox(height: 10),
      ],
      FloatingActionButton(
        heroTag: 'main',
        backgroundColor: blue,
        foregroundColor: Colors.white,
        onPressed: () => setState(() => addOpen = !addOpen),
        child: Icon(addOpen ? Icons.close : Icons.add),
      ),
    ],
  );

  Widget _projectCard(Map<String, dynamic> board) {
    final projectId = id(board), open = openProjects.contains(projectId);
    final rawCreated =
        board['created_at'] ?? board['createdAt'] ?? board['tanggal_dibuat'];
    final parsedCreated = rawCreated == null
        ? null
        : DateTime.tryParse('$rawCreated');
    final createdLabel = rawCreated == null || '$rawCreated'.trim().isEmpty
        ? 'Tanggal pembuatan tidak tersedia'
        : parsedCreated == null
        ? '$rawCreated'
        : '${parsedCreated.day.toString().padLeft(2, '0')}/${parsedCreated.month.toString().padLeft(2, '0')}/${parsedCreated.year}';
    final people = <String>[];
    void addPerson(dynamic value) {
      if (value is String && value.trim().isNotEmpty) people.add(value.trim());
      if (value is Map) {
        final label = '${value['name'] ?? value['email'] ?? ''}'.trim();
        if (label.isNotEmpty) people.add(label);
      }
      if (value is List)
        for (final item in value) {
          addPerson(item);
        }
    }

    addPerson(board['owner']);
    addPerson(board['creator']);
    addPerson(board['members']);
    addPerson(board['collaborators']);
    addPerson(board['_serverMembers']);
    addPerson(board['users']);
    return DragTarget<CardItem>(
      onWillAcceptWithDetails: (_) => false,
      onAcceptWithDetails: (details) => _moveTask(details.data, projectId, '1'),
      builder: (context, candidates, _) => Card(
        color: candidates.isNotEmpty ? const Color(0xffeff6ff) : null,
        margin: const EdgeInsets.only(bottom: 10),
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(5),
          side: BorderSide(
            color: candidates.isNotEmpty ? blue : const Color(0xffdbe3f0),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: InkWell(
                      onTap: () => setState(() {
                        if (open)
                          openProjects.remove(projectId);
                        else
                          openProjects.add(projectId);
                      }),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name(board),
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            'Dibuat: $createdLabel',
                            style: TextStyle(
                              fontSize: 12,
                              color: Color(0xff64748b),
                            ),
                          ),
                          const SizedBox(height: 5),
                          if (people.isNotEmpty)
                            Wrap(
                              spacing: 3,
                              children: people
                                  .toSet()
                                  .take(4)
                                  .map(
                                    (person) => CircleAvatar(
                                      radius: 9,
                                      backgroundColor: const Color(0xffc997ed),
                                      child: Text(
                                        initialsFor(person),
                                        style: const TextStyle(
                                          fontSize: 8,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ),
                                  )
                                  .toList(),
                            ),
                        ],
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Buka halaman project',
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => BoardPage(project: board),
                      ),
                    ).then((_) => _load()),
                    icon: const Icon(
                      Icons.arrow_circle_right,
                      color: blue,
                      size: 29,
                    ),
                  ),
                  PopupMenuButton<String>(
                    onSelected: (value) {
                      if (value == 'edit') _editProject(board);
                      if (value == 'delete') _deleteProject(board);
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(
                        value: 'edit',
                        child: Row(
                          children: [
                            Icon(Icons.edit_outlined, color: Colors.black87),
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
                            Text('Hapus', style: TextStyle(color: Colors.red)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              if (open) ...[const SizedBox(height: 10), _board(projectId)],
            ],
          ),
        ),
      ),
    );
  }

  Widget _board(String projectId) => Column(
    children: [
      '1',
      '2',
      '3',
    ].map((status) => _statusSection(projectId, status)).toList(),
  );
  Widget _statusSection(String projectId, String status) {
    final list =
        tasks[projectId]?.where((task) => task.status == status).toList() ?? [];
    return DragTarget<CardItem>(
      onWillAcceptWithDetails: (details) =>
          _ownerOf(details.data) != projectId || details.data.status != status,
      onAcceptWithDetails: (details) =>
          _moveTask(details.data, projectId, status),
      builder: (context, candidates, _) => Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: candidates.isNotEmpty ? const Color(0xffeff6ff) : null,
          border: Border.all(
            color: candidates.isNotEmpty ? blue : _tone(status),
          ),
          borderRadius: BorderRadius.circular(7),
        ),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                color: _tone(status),
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(6),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    status == '1'
                        ? Icons.view_list
                        : status == '2'
                        ? Icons.schedule
                        : Icons.check_circle,
                    color: _ink(status),
                    size: 19,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    _label(status),
                    style: TextStyle(
                      color: _ink(status),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  CircleAvatar(
                    radius: 10,
                    backgroundColor: Colors.white,
                    child: Text(
                      '${list.length}',
                      style: TextStyle(
                        color: _ink(status),
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(10),
              child: list.isEmpty
                  ? const _EmptyState(label: 'Tidak ada task', compact: true)
                  : Column(
                      children: list
                          .map(
                            (task) => _taskCard(projectId, task, inBoard: true),
                          )
                          .toList(),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _taskCard(String projectId, CardItem task, {bool inBoard = false}) =>
      LongPressDraggable<CardItem>(
        data: task,
        feedback: Material(
          color: Colors.transparent,
          child: SizedBox(
            width: 280,
            child: _taskSurface(task, elevated: true),
          ),
        ),
        childWhenDragging: Opacity(opacity: .35, child: _taskSurface(task)),
        child: Card(
          margin: const EdgeInsets.only(bottom: 7),
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
                  card: task,
                  onChanged: () => _saveProjectTasks(projectId),
                  onDelete: () =>
                      _deleteTask(projectId, task, askConfirmation: false),
                ),
              ),
            ),
            title: Text(task.title),
            subtitle: _taskSubtitle(task),
            trailing: _taskMenu(
              onEdit: () => _editTask(projectId, task),
              onDelete: () => _deleteTask(projectId, task),
            ),
          ),
        ),
      );

  Widget _taskSurface(CardItem task, {bool elevated = false}) => Card(
    margin: const EdgeInsets.only(bottom: 7),
    elevation: elevated ? 7 : 0,
    color: const Color(0xfff8fafc),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(6),
      side: const BorderSide(color: Color(0xffe2e8f0)),
    ),
    child: ListTile(
      dense: true,
      title: Text(task.title),
      subtitle: _taskSubtitle(task),
    ),
  );

  Widget? _taskSubtitle(CardItem task, {bool includeDragHint = false}) {
    if (task.dueDate.isEmpty && !includeDragHint) {
      return null;
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (task.dueDate.isNotEmpty) ...[
          const SizedBox(height: 3),
          Row(
            children: [
              const Icon(Icons.schedule, size: 13, color: Color(0xff64748b)),
              const SizedBox(width: 4),
              Text(
                taskDeadlineLabel(task.dueDate),
                style: const TextStyle(fontSize: 11),
              ),
            ],
          ),
        ],
        if (includeDragHint)
          const Text('Tahan untuk memindahkan', style: TextStyle(fontSize: 10)),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  final String label;
  final bool compact;
  const _EmptyState({required this.label, this.compact = false});
  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.symmetric(vertical: compact ? 14 : 26),
    child: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.assignment_outlined, color: Color(0xff94a3b8)),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(fontSize: 11, color: Color(0xff94a3b8)),
          ),
        ],
      ),
    ),
  );
}

class _LoadError extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _LoadError({required this.message, required this.onRetry});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 28),
    child: Center(
      child: Column(
        children: [
          const Icon(Icons.cloud_off_outlined, color: Colors.redAccent),
          const SizedBox(height: 8),
          const Text('Project gagal dimuat'),
          const SizedBox(height: 4),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12, color: Color(0xff64748b)),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('Muat ulang'),
          ),
        ],
      ),
    ),
  );
}
