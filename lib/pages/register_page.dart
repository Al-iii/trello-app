part of '../procode_app.dart';

class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});
  @override
  State<RegisterPage> createState() => _RegisterState();
}

class _RegisterState extends State<RegisterPage> {
  final name = TextEditingController(),
      email = TextEditingController(),
      pass = TextEditingController(),
      confirm = TextEditingController();
  Future<void> register() async {
    if (name.text.trim().isEmpty ||
        email.text.trim().isEmpty ||
        pass.text.length < 8 ||
        pass.text != confirm.text)
      return _msg(
        'Isi data lengkap. Password minimal 8 karakter dan harus sama.',
      );
    try {
      await auth.register(name.text.trim(), email.text.trim(), pass.text);
      if (mounted) {
        _msg('Akun berhasil dibuat. Silakan masuk.');
        Navigator.pop(context);
      }
    } catch (e) {
      _msg('$e');
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
  Widget build(BuildContext context) => _authScaffold('Daftar', [
    Image.asset(
      'assets/procode_logo_login.png',
      height: 190,
      width: 190,
      fit: BoxFit.contain,
    ),
    const SizedBox(height: 14),
    const Text(
      'Daftar akun baru',
      textAlign: TextAlign.center,
      style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
    ),
    const SizedBox(height: 28),
    _field(
      controller: name,
      label: 'Nama lengkap',
      hint: 'Masukkan nama lengkap',
    ),
    const SizedBox(height: 16),
    _field(controller: email, label: 'Email', hint: 'Masukkan email'),
    const SizedBox(height: 16),
    _field(
      controller: pass,
      label: 'Password',
      hint: 'Masukkan password',
      obscureText: true,
    ),
    const SizedBox(height: 16),
    _field(
      controller: confirm,
      label: 'Konfirmasi password',
      hint: 'Masukkan konfirmasi password',
      obscureText: true,
    ),
    const SizedBox(height: 20),
    FilledButton(onPressed: register, child: const Text('Daftar')),
    const SizedBox(height: 14),
    Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        const Text('Sudah mempunyai akun?'),
        TextButton(
          onPressed: () => Navigator.pop(context),
          style: TextButton.styleFrom(
            minimumSize: Size.zero,
            padding: const EdgeInsets.only(left: 5),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          child: const Text('Masuk'),
        ),
      ],
    ),
  ]);
}
