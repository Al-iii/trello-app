part of '../procode_app.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});
  @override
  State<LoginPage> createState() => _LoginState();
}

class _LoginState extends State<LoginPage> {
  final email = TextEditingController(), password = TextEditingController();
  bool busy = false;
  Future<void> login() async {
    if (email.text.trim().isEmpty || password.text.isEmpty)
      return _msg('Email dan password wajib diisi');
    setState(() => busy = true);
    try {
      currentUser.value = await auth.login(email.text.trim(), password.text);
      if (mounted)
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const BoardsPage()),
        );
    } catch (e) {
      _msg('$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  void _msg(String s) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(s.replaceFirst('Exception: ', ''))));

  Widget _field({
    required TextEditingController controller,
    required String label,
    required String hint,
    bool obscureText = false,
  }) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        label,
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
      ),
      const SizedBox(height: 7),
      TextField(
        controller: controller,
        obscureText: obscureText,
        decoration: InputDecoration(hintText: hint),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) => _authScaffold('Masuk', [
    Image.asset(
      'assets/procode_logo_login.png',
      height: 190,
      width: 190,
      fit: BoxFit.contain,
    ),
    const SizedBox(height: 14),
    const Text(
      'Masuk akun',
      textAlign: TextAlign.center,
      style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
    ),
    const SizedBox(height: 28),
    _field(controller: email, label: 'Email', hint: 'Masukkan email'),
    const SizedBox(height: 16),
    _field(
      controller: password,
      label: 'Password',
      hint: 'Masukkan password',
      obscureText: true,
    ),
    const SizedBox(height: 20),
    FilledButton(
      onPressed: busy ? null : login,
      child: busy
          ? const SizedBox(
              height: 20,
              width: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Text('Masuk'),
    ),
    const SizedBox(height: 14),
    Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        const Text('Belum punya akun?'),
        TextButton(
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const RegisterPage()),
          ),
          style: TextButton.styleFrom(
            minimumSize: Size.zero,
            padding: const EdgeInsets.only(left: 5),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          child: const Text('Daftar'),
        ),
      ],
    ),
  ]);
}

Widget _authScaffold(String title, List<Widget> children) => Scaffold(
  body: Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(28),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 430),
        child: Card(
          margin: EdgeInsets.zero,
          elevation: 3,
          shadowColor: Colors.black12,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
            side: BorderSide.none,
          ),
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: children,
            ),
          ),
        ),
      ),
    ),
  ),
);
