class UserProfile {
  String id, name, email;

  UserProfile({this.id = '', required this.name, required this.email});

  factory UserProfile.fromJson(Map<String, dynamic> json) => UserProfile(
    id: '${json['id'] ?? json['iduser'] ?? json['user']?['id'] ?? ''}',
    name: '${json['name'] ?? json['user']?['name'] ?? ''}',
    email: '${json['email'] ?? json['user']?['email'] ?? ''}',
  );
}

String displayNameFor(UserProfile? user) {
  final name = user?.name.trim() ?? '';
  if (name.isNotEmpty) return name;
  final email = user?.email.trim() ?? '';
  return email.isNotEmpty ? email : 'Profil';
}

String initialsFor(String value) {
  final words = value
      .trim()
      .split(RegExp(r'\s+'))
      .where((word) => word.isNotEmpty)
      .toList();
  if (words.isEmpty) return '?';
  if (words.length == 1) return words.first.substring(0, 1).toUpperCase();
  return '${words.first[0]}${words.last[0]}'.toUpperCase();
}
