part of '../procode_app.dart';

DateTime? taskDeadlineFrom(String raw) {
  if (raw.trim().isEmpty) return null;
  return DateTime.tryParse(raw)?.toLocal();
}

String taskDeadlineLabel(String raw) {
  final value = taskDeadlineFrom(raw);
  if (value == null) return raw;
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'Mei',
    'Jun',
    'Jul',
    'Agu',
    'Sep',
    'Okt',
    'Nov',
    'Des',
  ];
  final hour = value.hour.toString().padLeft(2, '0');
  final minute = value.minute.toString().padLeft(2, '0');
  return '${value.day} ${months[value.month - 1]} ${value.year}, $hour:$minute';
}

Future<DateTime?> pickTaskDeadline(
  BuildContext context,
  DateTime? current,
) async {
  final now = DateTime.now();
  final initial = current ?? now.add(const Duration(days: 1));
  final date = await showDatePicker(
    context: context,
    initialDate: initial,
    firstDate: DateTime(now.year - 1),
    lastDate: DateTime(now.year + 10),
  );
  if (date == null || !context.mounted) return current;
  final time = await showTimePicker(
    context: context,
    initialTime: TimeOfDay.fromDateTime(initial),
    // Layout landscape bawaan membutuhkan dialog yang lebih lebar daripada
    // batas modal aplikasi, sehingga tombol OK terpotong pada layar tertentu.
    orientation: Orientation.portrait,
  );
  if (time == null) return current;
  return DateTime(date.year, date.month, date.day, time.hour, time.minute);
}

class TaskLinkText extends StatelessWidget {
  final String text;
  final TextStyle? style;
  final int? maxLines;
  final TextOverflow overflow;

  const TaskLinkText(
    this.text, {
    super.key,
    this.style,
    this.maxLines,
    this.overflow = TextOverflow.clip,
  });

  @override
  Widget build(BuildContext context) => Linkify(
    text: text,
    style: style,
    linkStyle: (style ?? const TextStyle()).copyWith(color: blue),
    maxLines: maxLines,
    overflow: overflow,
    options: const LinkifyOptions(humanize: false),
    onOpen: (link) async {
      final rawUrl = link.url;
      final parsed = Uri.tryParse(rawUrl);
      final uri = parsed?.hasScheme == true
          ? parsed
          : Uri.tryParse('https://$rawUrl');
      if (uri == null ||
          !await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Tautan tidak dapat dibuka.')),
          );
        }
      }
    },
  );
}

class AppDialog extends StatelessWidget {
  final Widget title;
  final Widget? content;
  final List<Widget> actions;
  final bool showCloseButton;

  const AppDialog({
    super.key,
    required this.title,
    this.content,
    this.actions = const [],
    this.showCloseButton = true,
  });

  @override
  Widget build(BuildContext context) => Dialog(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 430),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 10, 8),
            child: Row(
              children: [
                Expanded(
                  child: DefaultTextStyle.merge(
                    style: const TextStyle(
                      color: textDark,
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                    ),
                    child: title,
                  ),
                ),
                if (showCloseButton)
                  IconButton(
                    tooltip: 'Tutup',
                    onPressed: () => Navigator.maybePop(context),
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(
                      Icons.close,
                      size: 19,
                      color: Color(0xff8792a2),
                    ),
                  ),
              ],
            ),
          ),
          if (content != null)
            Flexible(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
                child: content!,
              ),
            ),
          if (actions.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: actions,
              ),
            ),
        ],
      ),
    ),
  );
}

class DialogActionRow extends StatelessWidget {
  final VoidCallback onCancel;
  final VoidCallback onSubmit;
  final String cancelLabel;
  final String submitLabel;
  final bool destructive;

  const DialogActionRow({
    super.key,
    required this.onCancel,
    required this.onSubmit,
    this.cancelLabel = 'Batal',
    required this.submitLabel,
    this.destructive = false,
  });

  @override
  Widget build(BuildContext context) => Row(
    mainAxisAlignment: MainAxisAlignment.end,
    children: [
      OutlinedButton(
        onPressed: onCancel,
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 40),
          padding: const EdgeInsets.symmetric(horizontal: 16),
        ),
        child: Text(cancelLabel),
      ),
      const SizedBox(width: 10),
      FilledButton(
        onPressed: onSubmit,
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, 40),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          backgroundColor: destructive ? Colors.red : blue,
        ),
        child: Text(submitLabel),
      ),
    ],
  );
}

class TaskFormActions extends StatelessWidget {
  final VoidCallback onCancel;
  final VoidCallback onSubmit;
  final String submitLabel;

  const TaskFormActions({
    super.key,
    required this.onCancel,
    required this.onSubmit,
    required this.submitLabel,
  });

  @override
  Widget build(BuildContext context) => DialogActionRow(
    onCancel: onCancel,
    onSubmit: onSubmit,
    submitLabel: submitLabel,
  );
}
