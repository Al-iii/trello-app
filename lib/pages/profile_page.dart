part of '../procode_app.dart';

class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Profil saya')),
    body: ListView(
      padding: const EdgeInsets.all(24),
      children: [
        CircleAvatar(
          radius: 48,
          backgroundColor: blue,
          child: Text(
            initialsFor(displayNameFor(currentUser.value)),
            style: const TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
        ),
        const SizedBox(height: 20),
        ListTile(
          title: Text(displayNameFor(currentUser.value)),
          subtitle: Text(currentUser.value?.email ?? ''),
          leading: const Icon(Icons.person),
        ),
        const Card(
          child: ListTile(
            leading: Icon(Icons.check_circle, color: Colors.green),
            title: Text('Status akun'),
            trailing: Text('Aktif'),
          ),
        ),
      ],
    ),
  );
}
