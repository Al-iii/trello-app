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
  Widget build(BuildContext context) => SizedBox(
    width: double.infinity,
    child: Row(
      children: [
        Expanded(
          child: OutlinedButton(
            onPressed: onCancel,
            child: const Text('Batal'),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: FilledButton(onPressed: onSubmit, child: Text(submitLabel)),
        ),
      ],
    ),
  );
}
