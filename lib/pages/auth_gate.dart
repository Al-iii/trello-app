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
          currentUser.value = UserProfile(name: name, email: email);
        } else {
          await auth.logout();
        }
      } catch (_) {
        await auth.logout();
      }
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) =>
      currentUser.value == null ? const LoginPage() : const BoardsPage();
}
