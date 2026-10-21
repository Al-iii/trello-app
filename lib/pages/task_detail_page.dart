part of '../procode_app.dart';

class TaskDetailPage extends StatefulWidget {
  final CardItem card;
  final Future<void> Function() onChanged;
  final Future<void> Function()? onDelete;
  const TaskDetailPage({
    super.key,
    required this.card,
    required this.onChanged,
    this.onDelete,
  });
  @override
  State<TaskDetailPage> createState() => _TaskDetailPageState();
}

class _TaskDetailPageState extends State<TaskDetailPage> {
  final input = TextEditingController();
  final inputFocus = FocusNode();
  String? replyingToId;
  String? replyingToAuthor;

  @override
  void dispose() {
    input.dispose();
    inputFocus.dispose();
    super.dispose();
  }

  Future<void> send() async {
    final text = input.text.trim();
    if (text.isEmpty) return;
    final author = displayNameFor(currentUser.value);
    final id = '${DateTime.now().microsecondsSinceEpoch}';
    final parentId = replyingToId ?? '';
    setState(() {
      widget.card.comments.add(
        'v2\u001f$id\u001f$parentId\u001f$author\u001f$text',
      );
      replyingToId = null;
      replyingToAuthor = null;
    });
    input.clear();
    await widget.onChanged();
  }

  Future<void> edit() async {
    final title = TextEditingController(text: widget.card.title);
    final description = TextEditingController(text: widget.card.description);
    DateTime? deadline = taskDeadlineFrom(widget.card.dueDate);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialog) => AppDialog(
          title: const Text('Edit tugas'),
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
                  minLines: 4,
                  maxLines: 7,
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
              submitLabel: 'Simpan',
            ),
          ],
        ),
      ),
    );
    if (ok == true) {
      setState(() {
        widget.card.title = title.text.trim();
        widget.card.description = description.text.trim();
        widget.card.dueDate = deadline?.toIso8601String() ?? '';
      });
      await widget.onChanged();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Tugas berhasil diperbarui.')),
        );
      }
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
        IconButton(
          tooltip: 'Edit tugas',
          onPressed: edit,
          icon: const Icon(Icons.edit_outlined, color: Colors.black87),
        ),
        IconButton(
          tooltip: 'Hapus tugas',
          onPressed: () async {
            final confirmed = await showDialog<bool>(
              context: context,
              builder: (_) => AppDialog(
                title: const Text('Hapus tugas?'),
                content: Text('Yakin ingin menghapus "${widget.card.title}"?'),
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
            if (confirmed != true) return;
            if (widget.onDelete != null) await widget.onDelete!();
            if (context.mounted) Navigator.pop(context);
          },
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
              const Text(
                'Deskripsi',
                style: TextStyle(fontSize: 21, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              InkWell(
                onTap: edit,
                borderRadius: BorderRadius.circular(18),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border.all(color: borderLight),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (widget.card.description.isEmpty)
                        const Text(
                          'Belum ada deskripsi.',
                          style: TextStyle(color: Color(0xff64748b)),
                        )
                      else
                        TaskLinkText(widget.card.description),
                      if (widget.card.dueDate.isNotEmpty) ...[
                        const SizedBox(height: 14),
                        const Divider(height: 1),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            const Icon(
                              Icons.schedule_outlined,
                              size: 18,
                              color: Color(0xff64748b),
                            ),
                            const SizedBox(width: 7),
                            Text(
                              'Tenggat: ${taskDeadlineLabel(widget.card.dueDate)}',
                              style: const TextStyle(
                                fontSize: 13,
                                color: Color(0xff475569),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'Komentar',
                style: TextStyle(fontSize: 21, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Divider(),
              const SizedBox(height: 16),
              if (widget.card.comments.isEmpty)
                const _EmptyState(label: 'Belum ada komentar')
              else
                ..._threadWidgets(),
            ],
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (replyingToId != null)
                  Container(
                    margin: const EdgeInsets.only(bottom: 6),
                    padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
                    decoration: BoxDecoration(
                      color: const Color(0xffeff6ff),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Membalas ${replyingToAuthor ?? 'komentar'}',
                            style: const TextStyle(fontSize: 12, color: blue),
                          ),
                        ),
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          onPressed: () => setState(() {
                            replyingToId = null;
                            replyingToAuthor = null;
                          }),
                          icon: const Icon(Icons.close, size: 17),
                        ),
                      ],
                    ),
                  ),
                TextField(
                  controller: input,
                  focusNode: inputFocus,
                  onSubmitted: (_) => send(),
                  decoration: InputDecoration(
                    hintText: replyingToId == null
                        ? 'Tulis komentar...'
                        : 'Tulis balasan...',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    suffixIcon: IconButton(
                      onPressed: send,
                      icon: const Icon(Icons.send_outlined),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );

  List<Widget> _threadWidgets() {
    final comments = widget.card.comments
        .asMap()
        .entries
        .map((entry) => _CommentData.parse(entry.value, entry.key))
        .toList();
    final ids = comments.map((comment) => comment.id).toSet();
    final roots = comments.where(
      (comment) => comment.parentId == null || !ids.contains(comment.parentId),
    );
    return roots.map((comment) => _thread(comment, comments, 0)).toList();
  }

  Widget _thread(
    _CommentData comment,
    List<_CommentData> comments,
    int depth,
  ) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _comment(comment, depth, _parentAuthor(comment, comments)),
      ...comments
          .where((item) => item.parentId == comment.id)
          .map((reply) => _thread(reply, comments, depth + 1)),
    ],
  );

  String? _parentAuthor(_CommentData comment, List<_CommentData> comments) {
    if (comment.parentId == null) return null;
    for (final candidate in comments) {
      if (candidate.id == comment.parentId) return candidate.author;
    }
    return null;
  }

  Widget _comment(_CommentData comment, int depth, String? parentAuthor) =>
      Padding(
        padding: EdgeInsets.only(left: depth * 30.0, bottom: 14),
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 12, 8, 4),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 16,
                backgroundColor: _avatarColor(comment.author),
                child: Text(
                  initialsFor(comment.author),
                  style: const TextStyle(fontSize: 10, color: Colors.white),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          comment.author,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        if (parentAuthor != null)
                          Text(
                            '  Membalas $parentAuthor',
                            style: const TextStyle(
                              fontSize: 11,
                              color: Color(0xff64748b),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    TaskLinkText(comment.body),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: () {
                          setState(() {
                            replyingToId = comment.id;
                            replyingToAuthor = comment.author;
                          });
                          inputFocus.requestFocus();
                        },
                        style: TextButton.styleFrom(
                          foregroundColor: textDark,
                          padding: EdgeInsets.zero,
                          minimumSize: const Size(0, 28),
                        ),
                        child: const Text('Balas'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );

  Color _avatarColor(String author) {
    const palette = [
      blue,
      Colors.deepPurple,
      Colors.teal,
      Colors.orange,
      Colors.pink,
      Colors.indigo,
    ];
    var hash = 0;
    for (final codeUnit in author.toLowerCase().codeUnits) {
      hash = (hash * 31 + codeUnit) & 0x7fffffff;
    }
    return palette[hash % palette.length];
  }
}

class _CommentData {
  final String id;
  final String? parentId;
  final String author;
  final String body;

  const _CommentData({
    required this.id,
    required this.parentId,
    required this.author,
    required this.body,
  });

  factory _CommentData.parse(String raw, int index) {
    const separator = '\u001f';
    final parts = raw.split(separator);
    if (parts.length >= 5 && parts.first == 'v2') {
      return _CommentData(
        id: parts[1],
        parentId: parts[2].isEmpty ? null : parts[2],
        author: parts[3].trim().isEmpty ? 'Pengguna' : parts[3],
        body: parts.sublist(4).join(separator),
      );
    }
    if (parts.length >= 2) {
      return _CommentData(
        id: 'legacy_$index',
        parentId: null,
        author: parts.first.trim().isEmpty ? 'Pengguna' : parts.first,
        body: parts.sublist(1).join(separator),
      );
    }
    return _CommentData(
      id: 'legacy_$index',
      parentId: null,
      author: 'Pengguna',
      body: raw,
    );
  }
}
