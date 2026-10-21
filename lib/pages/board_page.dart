part of '../procode_app.dart';

class _ProjectMember {
  const _ProjectMember({
    required this.id,
    required this.name,
    required this.email,
    required this.isOwner,
  });

  final String id;
  final String name;
  final String email;
  final bool isOwner;

  String get label => name.isNotEmpty ? name : email;

  _ProjectMember copyWith({bool? isOwner}) => _ProjectMember(
    id: id,
    name: name,
    email: email,
    isOwner: isOwner ?? this.isOwner,
  );
}

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
  List<_ProjectMember> collaborators = [];
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
    try {
      cards = await auth.syncedProjectCards(projectId);
    } catch (_) {
      // Cache tetap digunakan ketika API tidak dapat dijangkau.
    }
    collaborators = (await auth.membersCache(projectId))
        .map(
          (label) =>
              _ProjectMember(id: '', name: label, email: '', isOwner: false),
        )
        .toList();

    // Daftar ringkas project tidak selalu menyertakan identitas pemilik.
    try {
      final details = await auth.projectDetails(projectId);
      if (details.isNotEmpty) widget.project.addAll(details);
    } catch (_) {
      // Data daftar ringkas tetap dipakai bila detail tidak tersedia.
    }

    // Ambil alias/nama asli pemilik dari endpoint berbasis ID. Respons baru
    // dipakai setelah AuthService memastikan ID profil sama dengan iduser.
    if (_projectOwnerId.isNotEmpty && !_currentUserOwnsProject()) {
      try {
        final owner = await auth.resolveUserById(_projectOwnerId);
        if (owner.isNotEmpty) {
          widget.project['owner'] = {...owner, 'is_owner': true};
        }
      } catch (_) {
        // Fallback "Pemilik project" tetap digunakan bila profil tidak tersedia.
      }
    }

    // Daftar project sudah membawa relasi `users`. Gunakan data tersebut agar
    // anggota dapat langsung ditampilkan sambil menunggu refresh dari API.
    final embeddedUsers = widget.project['users'];
    if (embeddedUsers is List) {
      _replaceMembers(_withProjectOwner(embeddedUsers));
    }

    // Endpoint ini dipakai versi web dan memastikan anggota yang baru
    // ditambahkan ikut muncul saat halaman project dibuka.
    try {
      final remoteUsers = await auth.projectUsers(projectId);
      if (remoteUsers.isNotEmpty) {
        await auth.rememberUsers(remoteUsers);
        _replaceMembers(_withProjectOwner(remoteUsers));
      }
    } catch (_) {
      // Data embedded/cache tetap dapat digunakan saat endpoint tidak tersedia.
    }
    await _cacheMemberLabels();
    if (mounted) setState(() => loading = false);
  }

  bool _truthy(dynamic value) =>
      value == true || value == 1 || '$value'.toLowerCase() == 'true';

  String _value(Map<dynamic, dynamic> source, List<String> keys) {
    for (final key in keys) {
      final raw = source[key];
      if (raw is Map || raw is Iterable) continue;
      final value = '${raw ?? ''}'.trim();
      if (value.isNotEmpty && value != 'null') return value;
    }
    return '';
  }

  String get _projectOwnerId => _value(widget.project, const [
    'owner_id',
    'ownerId',
    'created_by',
    'createdBy',
    'user_id',
    'iduser',
  ]);

  bool _currentUserOwnsProject() {
    final profile = currentUser.value;
    if (profile == null) return false;
    final ownerId = _projectOwnerId;
    if (ownerId.isNotEmpty && profile.id.isNotEmpty) {
      return ownerId == profile.id;
    }

    final pivot = widget.project['pivot'] is Map
        ? Map<String, dynamic>.from(widget.project['pivot'])
        : <String, dynamic>{};
    final role = _value(widget.project, const [
      'role',
      'peran',
      'type',
    ]).toLowerCase();
    final pivotRole = _value(pivot, const [
      'role',
      'peran',
      'type',
    ]).toLowerCase();
    if (role.contains('owner') ||
        role.contains('pemilik') ||
        pivotRole.contains('owner') ||
        pivotRole.contains('pemilik')) {
      return true;
    }
    if (_truthy(widget.project['is_owner']) ||
        _truthy(widget.project['isOwner']) ||
        _truthy(widget.project['owned_by_me'])) {
      return true;
    }
    final profileMap = {
      'id': profile.id,
      'name': profile.name,
      'email': profile.email,
    };
    for (final key in const [
      'owner',
      'creator',
      'created_by',
      'created_by_user',
      'user',
    ]) {
      final candidate = widget.project[key];
      if (candidate is Map &&
          _sameIdentity(Map<String, dynamic>.from(candidate), profileMap)) {
        return true;
      }
    }
    return false;
  }

  bool _isEmbeddedOwner(dynamic candidate) {
    if (candidate is! Map) return false;
    final map = Map<String, dynamic>.from(candidate);
    if (_projectOwnerId.isEmpty) return true;
    final candidateId = _value(map, const ['id', 'iduser', 'user_id']);
    return candidateId.isNotEmpty && candidateId == _projectOwnerId;
  }

  List<dynamic> _withProjectOwner(Iterable<dynamic> users) => [
    ...users,
    for (final key in const ['owner', 'creator', 'created_by_user', 'user'])
      if (_isEmbeddedOwner(widget.project[key])) widget.project[key],
    if (_currentUserOwnsProject() && currentUser.value != null)
      {
        'id': currentUser.value!.id,
        'name': currentUser.value!.name,
        'email': currentUser.value!.email,
        'is_owner': true,
      },
    if (!_currentUserOwnsProject() &&
        _projectOwnerId.isNotEmpty &&
        !const [
          'owner',
          'creator',
          'created_by_user',
          'user',
        ].any((key) => _isEmbeddedOwner(widget.project[key])))
      {'id': _projectOwnerId, 'name': 'Pemilik project', 'is_owner': true},
  ];

  bool _sameIdentity(Map<String, dynamic> user, dynamic candidate) {
    final userId = _value(user, const ['id', 'iduser', 'user_id']);
    final userEmail = _value(user, const ['email']).toLowerCase();
    final userName = _value(user, const ['name', 'nama']).toLowerCase();
    if (candidate is Map) {
      final map = Map<String, dynamic>.from(candidate);
      final candidateId = _value(map, const ['id', 'iduser', 'user_id']);
      final candidateEmail = _value(map, const ['email']).toLowerCase();
      final candidateName = _value(map, const ['name', 'nama']).toLowerCase();
      if (userId.isNotEmpty && candidateId.isNotEmpty) {
        return userId == candidateId;
      }
      if (userEmail.isNotEmpty && candidateEmail.isNotEmpty) {
        return userEmail == candidateEmail;
      }
      return userName.isNotEmpty && userName == candidateName;
    }
    final value = '$candidate'.trim().toLowerCase();
    return value.isNotEmpty &&
        (value == userId.toLowerCase() ||
            value == userEmail ||
            value == userName);
  }

  bool _isOwner(Map<String, dynamic> user) {
    final ownerId = _projectOwnerId;
    final userId = _value(user, const ['id', 'iduser', 'user_id']);
    if (ownerId.isNotEmpty && userId.isNotEmpty) {
      return ownerId == userId;
    }

    final pivot = user['pivot'] is Map
        ? Map<String, dynamic>.from(user['pivot'])
        : <String, dynamic>{};
    final role = _value(user, const ['role', 'peran', 'type']).isNotEmpty
        ? _value(user, const ['role', 'peran', 'type'])
        : _value(pivot, const ['role', 'peran', 'type']);
    if (role.toLowerCase().contains('owner') ||
        role.toLowerCase().contains('pemilik')) {
      return true;
    }
    if (_truthy(user['is_owner']) ||
        _truthy(user['isOwner']) ||
        _truthy(pivot['is_owner']) ||
        _truthy(pivot['isOwner'])) {
      return true;
    }

    for (final key in const [
      'owner',
      'creator',
      'created_by',
      'created_by_user',
      'user',
    ]) {
      if (_sameIdentity(user, widget.project[key])) return true;
    }
    if (ownerId.isNotEmpty && _sameIdentity(user, ownerId)) return true;

    final profile = currentUser.value;
    final ownedByCurrentUser =
        _truthy(widget.project['is_owner']) ||
        _truthy(widget.project['isOwner']) ||
        _truthy(widget.project['owned_by_me']);
    return ownedByCurrentUser &&
        profile != null &&
        _sameIdentity(user, {
          'id': profile.id,
          'name': profile.name,
          'email': profile.email,
        });
  }

  _ProjectMember _memberFrom(Map<String, dynamic> user) {
    final nested = user['user'] is Map
        ? Map<String, dynamic>.from(user['user'])
        : <String, dynamic>{};
    final identity = {...nested, ...user};
    final nestedId = _value(nested, const ['id', 'iduser', 'user_id']);
    return _ProjectMember(
      id: nestedId.isNotEmpty
          ? nestedId
          : _value(user, const ['user_id', 'iduser', 'id']),
      name: _value(identity, const ['name', 'nama', 'alias', 'username']),
      email: _value(identity, const ['email']),
      isOwner: _isOwner(identity),
    );
  }

  void _replaceMembers(Iterable<dynamic> users) {
    final merged = <String, _ProjectMember>{};
    for (final item in users) {
      final member = item is Map
          ? _memberFrom(Map<String, dynamic>.from(item))
          : _ProjectMember(
              id: '',
              name: '$item'.trim(),
              email: '',
              isOwner: false,
            );
      if (member.label.isEmpty) continue;
      final key = member.id.isNotEmpty
          ? 'id:${member.id}'
          : (member.email.isNotEmpty ? member.email : member.label)
                .toLowerCase();
      final existing = merged[key];
      merged[key] = existing == null
          ? member
          : member.copyWith(isOwner: existing.isOwner || member.isOwner);
    }
    if (merged.isNotEmpty) {
      collaborators = merged.values.toList()
        ..sort((a, b) {
          if (a.isOwner == b.isOwner) return 0;
          return a.isOwner ? -1 : 1;
        });
    }
  }

  Future<void> _cacheMemberLabels() => auth.saveMembers(
    projectId,
    collaborators.map((member) => member.label).toList(),
  );

  Color _memberColor(String value) {
    const colors = [
      Color(0xffec6f91),
      Color(0xff9b7be8),
      Color(0xffeeaa62),
      Color(0xff34a6c8),
      Color(0xff43a879),
    ];
    return colors[value.codeUnits.fold<int>(0, (sum, unit) => sum + unit) %
        colors.length];
  }

  Widget _memberAvatar(_ProjectMember member, {double radius = 14}) => Tooltip(
    message: member.isOwner ? '${member.label} (Pemilik)' : member.label,
    child: Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: radius * 2,
          height: radius * 2,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: _memberColor(member.label),
            shape: BoxShape.circle,
            border: Border.all(
              color: member.isOwner ? const Color(0xffffb020) : Colors.white,
              width: member.isOwner ? 2 : 1.5,
            ),
          ),
          child: Text(
            initialsFor(member.label),
            style: TextStyle(
              color: Colors.white,
              fontSize: radius * .65,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        if (member.isOwner)
          const Positioned(
            right: -3,
            bottom: -3,
            child: CircleAvatar(
              radius: 6,
              backgroundColor: Color(0xffffb020),
              child: Icon(Icons.star, size: 8, color: Colors.white),
            ),
          ),
      ],
    ),
  );

  Widget _memberStrip() {
    final visible = collaborators.take(4).toList();
    return Semantics(
      button: true,
      label: '${collaborators.length} anggota project',
      child: InkWell(
        onTap: _collaboratorDialog,
        borderRadius: BorderRadius.circular(18),
        child: SizedBox(
          width: 28 + (visible.length - 1) * 20,
          height: 34,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              for (var index = 0; index < visible.length; index++)
                Positioned(
                  left: index * 20,
                  top: 3,
                  child: _memberAvatar(visible[index]),
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _collaboratorDialog() {
    final email = TextEditingController();
    final form = GlobalKey<FormState>();
    showDialog(
      context: context,
      builder: (dialogContext) {
        var status = 'Masukkan email pengguna yang sudah terdaftar.';
        return StatefulBuilder(
          builder: (context, refresh) => AppDialog(
            title: const Text('Kolaborator'),
            content: Form(
              key: form,
              child: SizedBox(
                width: 380,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (collaborators.isEmpty)
                      const Padding(
                        padding: EdgeInsets.only(bottom: 16),
                        child: Text('Belum ada anggota project.'),
                      )
                    else
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 220),
                        child: ListView.separated(
                          shrinkWrap: true,
                          itemCount: collaborators.length,
                          separatorBuilder: (_, _) => const Divider(height: 1),
                          itemBuilder: (_, index) {
                            final member = collaborators[index];
                            return ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: _memberAvatar(member, radius: 18),
                              title: Text(member.label),
                              subtitle: Text(
                                member.isOwner
                                    ? 'Pemilik project'
                                    : member.email.isNotEmpty
                                    ? member.email
                                    : 'Kolaborator',
                              ),
                              trailing: member.isOwner
                                  ? const Chip(
                                      avatar: Icon(Icons.star, size: 15),
                                      label: Text('Pemilik'),
                                      visualDensity: VisualDensity.compact,
                                    )
                                  : null,
                            );
                          },
                        ),
                      ),
                    if (collaborators.isNotEmpty) const SizedBox(height: 16),
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
            ),
            actions: [
              DialogActionRow(
                cancelLabel: 'Tutup',
                onCancel: () => Navigator.pop(context),
                onSubmit: () async {
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

                    // Respons invite sudah membawa user yang baru ditambahkan.
                    // Tidak perlu memanggil ulang /projects/{id}/users.
                    final invitedUser = invited['user'];
                    final member = invitedUser is Map
                        ? _memberFrom(Map<String, dynamic>.from(invitedUser))
                        : _ProjectMember(
                            id: '',
                            name: '',
                            email: email.text.trim(),
                            isOwner: false,
                          );
                    final alreadyExists = collaborators.any(
                      (item) =>
                          item.email.toLowerCase() ==
                              member.email.toLowerCase() ||
                          item.label.toLowerCase() ==
                              member.label.toLowerCase(),
                    );
                    if (member.label.isNotEmpty && !alreadyExists) {
                      collaborators.add(member);
                      await _cacheMemberLabels();
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
                submitLabel: 'Undang',
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
  Color _ink(String status) => status == '2'
      ? const Color(0xff8a6415)
      : status == '3'
      ? const Color(0xff16805b)
      : const Color(0xff315d9c);
  String _label(String s) => s == '2'
      ? 'In Progress'
      : s == '3'
      ? 'Done'
      : 'To Do';
  Future<void> _add(String status) async {
    final title = TextEditingController();
    final description = TextEditingController();
    DateTime? deadline;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialog) => AppDialog(
          title: Text('Tambah ke ${_label(status)}'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: title,
                  autofocus: true,
                  decoration: const InputDecoration(labelText: 'Judul tugas'),
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
                  Navigator.pop(context, title.text.trim().isNotEmpty),
              submitLabel: 'Tambah',
            ),
          ],
        ),
      ),
    );
    if (ok == true) {
      try {
        final taskId = await auth.createTask(
          title.text.trim(),
          projectId,
          status: status,
          description: description.text.trim(),
          dueDate: deadline?.toIso8601String() ?? '',
        );
        if (!mounted) return;
        setState(
          () => cards.add(
            CardItem(
              id: taskId,
              title: title.text.trim(),
              description: description.text.trim(),
              status: status,
              dueDate: deadline?.toIso8601String() ?? '',
            ),
          ),
        );
        await _save();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Tugas "${title.text.trim()}" berhasil ditambahkan.',
              ),
            ),
          );
        }
      } catch (error) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(error.toString().replaceFirst('Exception: ', '')),
            ),
          );
        }
      }
    }
  }

  Future<void> _edit(CardItem item) async {
    final title = TextEditingController(text: item.title);
    final description = TextEditingController(text: item.description);
    String status = item.status;
    DateTime? deadline = taskDeadlineFrom(item.dueDate);
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (_, refresh) => AppDialog(
          title: const Text('Edit tugas'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: title,
                  decoration: const InputDecoration(labelText: 'Judul tugas'),
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
                          onPressed: () => refresh(() => deadline = null),
                          icon: const Icon(Icons.close),
                        ),
                  onTap: () async {
                    final selected = await pickTaskDeadline(context, deadline);
                    if (context.mounted) refresh(() => deadline = selected);
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
                  onChanged: (v) => refresh(() => status = v!),
                ),
              ],
            ),
          ),
          actions: [
            TaskFormActions(
              onCancel: () => Navigator.pop(context),
              onSubmit: () =>
                  Navigator.pop(context, title.text.trim().isNotEmpty),
              submitLabel: 'Simpan',
            ),
          ],
        ),
      ),
    );
    if (ok == true) {
      setState(() {
        item.title = title.text.trim();
        item.description = description.text.trim();
        item.status = status;
        item.dueDate = deadline?.toIso8601String() ?? '';
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
      builder: (_) => AppDialog(
        title: const Text('Hapus tugas?'),
        content: Text('Yakin ingin menghapus "${item.title}"?'),
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
        if (collaborators.isNotEmpty) ...[
          _memberStrip(),
          const SizedBox(width: 4),
        ],
        IconButton(
          tooltip: 'Lihat dan undang kolaborator',
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
                  : Column(children: list.map(_projectTaskCard).toList()),
            ),
          ],
        ),
      ),
    );
  }

  Widget _projectTaskCard(CardItem item) => LongPressDraggable<CardItem>(
    data: item,
    feedback: Material(
      color: Colors.transparent,
      child: SizedBox(
        width: 280,
        child: _projectTaskSurface(item, elevated: true),
      ),
    ),
    childWhenDragging: Opacity(opacity: .35, child: _projectTaskSurface(item)),
    child: _projectTaskSurface(
      item,
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => TaskDetailPage(
            card: item,
            onChanged: _save,
            onDelete: () async {
              setState(() => cards.remove(item));
              await _save();
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Tugas "${item.title}" dihapus.')),
                );
              }
            },
          ),
        ),
      ),
      trailing: PopupMenuButton<String>(
        tooltip: 'Aksi tugas',
        onSelected: (value) {
          if (value == 'edit') _edit(item);
          if (value == 'delete') _delete(item);
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
      ),
    ),
  );

  Widget _projectTaskSurface(
    CardItem item, {
    bool elevated = false,
    VoidCallback? onTap,
    Widget? trailing,
  }) => Card(
    margin: const EdgeInsets.only(bottom: 7),
    elevation: elevated ? 7 : 0,
    color: const Color(0xfff8fafc),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(6),
      side: const BorderSide(color: Color(0xffe2e8f0)),
    ),
    child: ListTile(
      dense: true,
      onTap: onTap,
      title: Text(item.title),
      subtitle: _taskDetails(item),
      trailing: trailing,
    ),
  );

  Widget? _taskDetails(CardItem item) {
    if (item.dueDate.isEmpty) return null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (item.dueDate.isNotEmpty) ...[
          const SizedBox(height: 3),
          Row(
            children: [
              const Icon(Icons.schedule, size: 13, color: Color(0xff64748b)),
              const SizedBox(width: 4),
              Text(
                taskDeadlineLabel(item.dueDate),
                style: const TextStyle(fontSize: 11),
              ),
            ],
          ),
        ],
      ],
    );
  }
}
