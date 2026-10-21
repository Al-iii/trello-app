part of '../procode_app.dart';

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});
  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  @override
  void initState() {
    super.initState();
    _restore();
  }

  Future<void> _restore() async {
    final p = await SharedPreferences.getInstance();
    if (await auth.token() != null && p.getString('profile_email') != null) {
      // Pulihkan sesi lokal lebih dulu agar hot restart tidak mengembalikan
      // pengguna ke halaman login hanya karena API sedang lambat/tidak tersedia.
      currentUser.value = UserProfile(
        id: p.getString('profile_id') ?? '',
        name: p.getString('profile_name') ?? p.getString('profile_email')!,
        email: p.getString('profile_email')!,
      );
      try {
        final profile = await auth.currentProfile();
        if (profile != null) {
          final name = profile.name.trim().isEmpty
              ? (p.getString('profile_name') ?? profile.email)
              : profile.name;
          final email = profile.email.trim().isEmpty
              ? p.getString('profile_email')!
              : profile.email;
          await p.setString('profile_name', name);
          await p.setString('profile_email', email);
          await p.setString('profile_id', profile.id);
          currentUser.value = UserProfile(
            id: profile.id,
            name: name,
            email: email,
          );
        } else {
          await auth.logout();
          currentUser.value = null;
        }
      } catch (_) {
        // Token dan profil cache tetap dipakai pada gangguan jaringan/server.
      }
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) =>
      currentUser.value == null ? const LoginPage() : const BoardsPage();
}
