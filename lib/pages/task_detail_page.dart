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
    final controller = TextEditingController(text: widget.card.title);
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Edit tugas'),
        content: TextField(controller: controller),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(context, controller.text.trim().isNotEmpty),
            child: const Text('Simpan'),
          ),
        ],
      ),
    );
    if (ok == true) {
      setState(() => widget.card.title = controller.text.trim());
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
        IconButton(onPressed: edit, icon: const Icon(Icons.edit_outlined)),
        IconButton(
          onPressed: () async {
            final confirmed = await showDialog<bool>(
              context: context,
              builder: (_) => AlertDialog(
                title: const Text('Hapus tugas?'),
                content: Text('Yakin ingin menghapus "${widget.card.title}"?'),
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
              const Text('Komentar', style: TextStyle(fontSize: 20)),
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
      _comment(comment, depth),
      ...comments
          .where((item) => item.parentId == comment.id)
          .map((reply) => _thread(reply, comments, depth + 1)),
    ],
  );

  Widget _comment(_CommentData comment, int depth) => Padding(
    padding: EdgeInsets.only(left: depth * 30.0, bottom: 14),
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
              Text(
                comment.author,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 3),
              Text(comment.body),
              TextButton(
                onPressed: () {
                  setState(() {
                    replyingToId = comment.id;
                    replyingToAuthor = comment.author;
                  });
                  inputFocus.requestFocus();
                },
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(0, 28),
                ),
                child: const Text('Balas'),
              ),
            ],
          ),
        ),
      ],
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
