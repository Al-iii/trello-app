class CardItem {
  String id, title, description, status, dueDate;
  List<String> labels, members, comments;

  CardItem({
    required this.id,
    required this.title,
    this.description = '',
    this.status = '1',
    this.dueDate = '',
    List<String>? labels,
    List<String>? members,
    List<String>? comments,
  }) : labels = labels ?? [],
       members = members ?? [],
       comments = comments ?? [];
}
