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
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Daftar akun baru')),
    body: _authScaffold('Daftar', [
      const Icon(Icons.person_add_alt_1, size: 56, color: blue),
      TextField(
        controller: name,
        decoration: const InputDecoration(labelText: 'Nama lengkap'),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: email,
        decoration: const InputDecoration(labelText: 'Email'),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: pass,
        obscureText: true,
        decoration: const InputDecoration(labelText: 'Password'),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: confirm,
        obscureText: true,
        decoration: const InputDecoration(labelText: 'Konfirmasi password'),
      ),
      const SizedBox(height: 20),
      FilledButton(onPressed: register, child: const Text('Daftar')),
    ]),
  );
}
