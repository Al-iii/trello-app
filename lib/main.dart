import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:kanban_board/kanban_board.dart';
import 'package:share_plus/share_plus.dart';

const apiBase = 'https://trelloapp.id/api';
// Palet warna utama mengikuti desain web/mobile.
const blue = Color(0xff2161f5);
const darkBlue = Color(0xff1e5bb8);
const pageBackground = Color(0xfff4f7fb);
const borderLight = Color(0xffdbe3f0);
const textDark = Color(0xff111827);

class UserProfile {
  String name, email;
  UserProfile({required this.name, required this.email});
  factory UserProfile.fromJson(Map<String, dynamic> j) => UserProfile(
    name: '${j['name'] ?? j['user']?['name'] ?? ''}',
    email: '${j['email'] ?? j['user']?['email'] ?? ''}',
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

class AuthService {
  static const storage = FlutterSecureStorage();
  Future<String?> token() async {
    final t = await storage.read(key: 'access_token');
    if (t != null && t.isNotEmpty) return t;
    final p = await SharedPreferences.getInstance();
    final old = p.getString('access_token');
    if (old != null) await storage.write(key: 'access_token', value: old);
    return old;
  }

  Future<Map<String, String>> headers() async {
    final t = await token();
    if (t == null) throw Exception('Sesi login tidak ditemukan');
    return {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      'Authorization': 'Bearer $t',
    };
  }

  Future<UserProfile?> currentProfile() async {
    final r = await http.post(
      Uri.parse('$apiBase/auth/me'),
      headers: await headers(),
    );
    if (r.statusCode < 200 || r.statusCode >= 300) return null;
    final profile = UserProfile.fromJson(_json(r));
    if (profile.name.trim().isEmpty && profile.email.trim().isEmpty) {
      return null;
    }
    return profile;
  }

  Future<String> _cacheScope() async {
    final p = await SharedPreferences.getInstance();
    final email = p.getString('profile_email') ?? 'anonymous';
    return email.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_');
  }

  Future<UserProfile> login(String email, String password) async {
    final r = await http.post(
      Uri.parse('$apiBase/auth/login'),
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
      body: jsonEncode({'email': email, 'password': password}),
    );
    final j = _json(r);
    if (r.statusCode < 200 || r.statusCode >= 300)
      throw Exception('${j['error'] ?? j['message'] ?? 'Login gagal'}');
    final t = '${j['access_token'] ?? ''}';
    if (t.isEmpty) throw Exception('Token login tidak ditemukan');
    await storage.write(key: 'access_token', value: t);
    final sessionPrefs = await SharedPreferences.getInstance();
    // Browser builds may not persist secure storage consistently. Keep the
    // same token in the existing per-device preferences fallback as well.
    await sessionPrefs.setString('access_token', t);
    var u = UserProfile.fromJson(
      j['user'] is Map ? Map<String, dynamic>.from(j['user']) : j,
    );
    // The verified login response contains only access_token/token_type/
    // expires_in. Resolve the human-readable profile from /users when the
    // endpoint is available, while keeping the login usable if it is not.
    if (u.name.trim().isEmpty || u.email.trim().isEmpty) {
      try {
        final r = await http.get(
          Uri.parse('$apiBase/users'),
          headers: await headers(),
        );
        if (r.statusCode >= 200 && r.statusCode < 300) {
          final decoded = r.body.isEmpty ? <dynamic>[] : jsonDecode(r.body);
          final raw = decoded is List
              ? decoded
              : (decoded is Map
                    ? (decoded['data'] ?? decoded['users'] ?? <dynamic>[])
                    : <dynamic>[]);
          final users = (raw as List).whereType<Map>().map(
            (item) => Map<String, dynamic>.from(item),
          );
          final match = users.cast<Map<String, dynamic>?>().firstWhere(
            (item) =>
                '${item?['email'] ?? ''}'.toLowerCase() == email.toLowerCase(),
            orElse: () => null,
          );
          if (match != null) u = UserProfile.fromJson(match);
        }
      } catch (_) {
        // Profile lookup is supplementary; token login remains valid.
      }
    }
    final p = sessionPrefs;
    await p.setString(
      'profile_name',
      u.name.isEmpty ? email.split('@').first : u.name,
    );
    await p.setString('profile_email', u.email.isEmpty ? email : u.email);
    return UserProfile(
      name: u.name.isEmpty ? email.split('@').first : u.name,
      email: u.email.isEmpty ? email : u.email,
    );
  }

  Future<void> register(String name, String email, String password) async {
    final r = await http.post(
      Uri.parse('$apiBase/auth/register'),
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
      body: jsonEncode({
        'name': name,
        'email': email,
        'password': password,
        'password_confirmation': password,
      }),
    );
    final j = _json(r);
    if (r.statusCode < 200 || r.statusCode >= 300)
      throw Exception('${j['error'] ?? j['message'] ?? 'Pendaftaran gagal'}');
  }

  Future<List<Map<String, dynamic>>> projects() async {
    final r = await http.get(
      Uri.parse('$apiBase/projects'),
      headers: await headers(),
    );
    if (r.statusCode < 200 || r.statusCode >= 300)
      throw Exception('Board gagal dimuat (${r.statusCode})');
    final j = jsonDecode(r.body);
    final list = j is List ? j : (j['data'] ?? j['projects'] ?? []);
    return List<Map<String, dynamic>>.from(
      list.map((e) => Map<String, dynamic>.from(e)),
    );
  }

  Future<Map<String, dynamic>> createProject(String name) async {
    final r = await http.post(
      Uri.parse('$apiBase/projects'),
      headers: await headers(),
      body: jsonEncode({'nama_project': name}),
    );
    final j = _json(r);
    if (r.statusCode < 200 || r.statusCode >= 300)
      throw Exception('Board gagal dibuat');
    return Map<String, dynamic>.from(j['project'] ?? j['data'] ?? j);
  }

  /// Verified in the web application's Network panel.
  Future<List<Map<String, dynamic>>> projectUsers(String projectId) async {
    final r = await http.get(
      Uri.parse('$apiBase/projects/${Uri.encodeComponent(projectId)}/users'),
      headers: await headers(),
    );
    if (r.statusCode < 200 || r.statusCode >= 300) {
      throw Exception('Anggota project gagal dimuat (${r.statusCode})');
    }
    final decoded = r.body.isEmpty ? <dynamic>[] : jsonDecode(r.body);
    final list = decoded is List
        ? decoded
        : (decoded is Map
              ? (decoded['data'] ?? decoded['users'] ?? <dynamic>[])
              : <dynamic>[]);
    return List<Map<String, dynamic>>.from(
      (list as List).whereType<Map>().map(
        (item) => Map<String, dynamic>.from(item),
      ),
    );
  }

  Future<Map<String, dynamic>> checkProjectEmail(
    String projectId,
    String email,
  ) async {
    final r = await http.post(
      Uri.parse('$apiBase/check-email'),
      headers: await headers(),
      body: jsonEncode({'email': email, 'project_id': projectId}),
    );
    final json = _json(r);
    if (r.statusCode < 200 || r.statusCode >= 300) {
      throw Exception('${json['message'] ?? 'Email gagal diperiksa'}');
    }
    return json;
  }

  Future<Map<String, dynamic>> inviteProject(
    String projectId,
    String email,
  ) async {
    final r = await http.post(
      Uri.parse('$apiBase/projects/${Uri.encodeComponent(projectId)}/invite'),
      headers: await headers(),
      body: jsonEncode({'email': email}),
    );
    final json = _json(r);
    if (r.statusCode < 200 || r.statusCode >= 300) {
      throw Exception('${json['message'] ?? 'Undangan gagal dikirim'}');
    }
    return json;
  }

  Future<void> updateProject(String id, String name) async {
    final r = await http.put(
      Uri.parse('$apiBase/projects/$id'),
      headers: await headers(),
      body: jsonEncode({'nama_project': name}),
    );
    if (r.statusCode < 200 || r.statusCode >= 300)
      throw Exception('Board gagal diperbarui');
  }

  Future<void> deleteProject(String id) async {
    final r = await http.delete(
      Uri.parse('$apiBase/projects/$id'),
      headers: await headers(),
    );
    if (r.statusCode < 200 || r.statusCode >= 300)
      throw Exception('Board gagal dihapus');
  }

  Future<void> saveBoardCache(List<Map<String, dynamic>> boards) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(
      'boards_cache_${await _cacheScope()}',
      jsonEncode(boards),
    );
  }

  Future<List<Map<String, dynamic>>> boardCache() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString('boards_cache_${await _cacheScope()}');
    if (raw == null) return [];
    return List<Map<String, dynamic>>.from(
      (jsonDecode(raw) as List).map((e) => Map<String, dynamic>.from(e)),
    );
  }

  Future<void> saveMembers(String boardId, List<String> members) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(
      'members_${await _cacheScope()}_$boardId',
      jsonEncode(members),
    );
  }

  Future<List<String>> membersCache(String boardId) async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString('members_${await _cacheScope()}_$boardId');
    return raw == null ? [] : List<String>.from(jsonDecode(raw));
  }

  Future<void> saveCardCache(String boardId, List<CardItem> cards) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(
      'cards_${await _cacheScope()}_$boardId',
      jsonEncode(
        cards
            .map(
              (c) => {
                'id': c.id,
                'title': c.title,
                'description': c.description,
                'status': c.status,
                'dueDate': c.dueDate,
                'labels': c.labels,
                'comments': c.comments,
              },
            )
            .toList(),
      ),
    );
  }

  Future<List<CardItem>> cardCache(String boardId) async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString('cards_${await _cacheScope()}_$boardId');
    if (raw == null) return [];
    return (jsonDecode(raw) as List)
        .map(
          (e) => CardItem(
            id: '${e['id']}',
            title: '${e['title']}',
            description: '${e['description'] ?? ''}',
            status: '${e['status'] ?? '1'}',
            dueDate: '${e['dueDate'] ?? ''}',
            labels: List<String>.from(e['labels'] ?? []),
            comments: List<String>.from(e['comments'] ?? []),
          ),
        )
        .toList();
  }

  /// Tugas yang belum diberi proyek disimpan lokal sampai backend menyediakan
  /// endpoint inbox/backlog khusus.
  Future<void> saveInbox(List<CardItem> cards) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(
      'inbox_tasks_${await _cacheScope()}',
      jsonEncode(
        cards
            .map(
              (c) => {
                'id': c.id,
                'title': c.title,
                'description': c.description,
                'status': c.status,
                'comments': c.comments,
              },
            )
            .toList(),
      ),
    );
  }

  Future<List<CardItem>> inbox() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString('inbox_tasks_${await _cacheScope()}');
    if (raw == null) return [];
    return (jsonDecode(raw) as List)
        .map(
          (e) => CardItem(
            id: '${e['id']}',
            title: '${e['title']}',
            description: '${e['description'] ?? ''}',
            status: '${e['status'] ?? '1'}',
            comments: List<String>.from(e['comments'] ?? []),
          ),
        )
        .toList();
  }

  Future<List<Map<String, dynamic>>> tasks(String projectId) async {
    final r = await http.get(
      Uri.parse('$apiBase/tasks?idproject=$projectId'),
      headers: await headers(),
    );
    if (r.statusCode < 200 || r.statusCode >= 300)
      throw Exception('Card gagal dimuat');
    final j = jsonDecode(r.body);
    return List<Map<String, dynamic>>.from(
      (j is List ? j : j['data'] ?? []).map(
        (e) => Map<String, dynamic>.from(e),
      ),
    );
  }

  Future<List<Map<String, dynamic>>> unassignedTasks() async {
    final r = await http.get(
      Uri.parse('$apiBase/tasks?unassigned=1'),
      headers: await headers(),
    );
    if (r.statusCode < 200 || r.statusCode >= 300) {
      throw Exception('Task tanpa project gagal dimuat (${r.statusCode})');
    }
    final decoded = jsonDecode(r.body);
    final list = decoded is List
        ? decoded
        : (decoded is Map
              ? (decoded['data'] ?? decoded['tasks'] ?? <dynamic>[])
              : <dynamic>[]);
    return List<Map<String, dynamic>>.from(
      (list as List).whereType<Map>().map(
        (item) => Map<String, dynamic>.from(item),
      ),
    );
  }

  Future<String> createTask(String name, String projectId) async {
    final r = await http.post(
      Uri.parse('$apiBase/tasks'),
      headers: await headers(),
      body: jsonEncode({
        'nama_task': name,
        'status': '1',
        'idproject': projectId,
      }),
    );
    if (r.statusCode < 200 || r.statusCode >= 300)
      throw Exception('Card gagal dibuat');
    final j = _json(r);
    final task = j['task'] is Map ? Map<String, dynamic>.from(j['task']) : j;
    return '${task['idtask'] ?? task['id'] ?? DateTime.now().microsecondsSinceEpoch}';
  }

  Future<void> updateTask(CardItem c, String projectId) async {
    final uri = Uri.parse('$apiBase/tasks/${Uri.encodeComponent(c.id)}');
    final body = jsonEncode({
      'nama_task': c.title,
      'status': c.status,
      'idproject': projectId,
    });
    final h = await headers();
    var r = await http.put(uri, headers: h, body: body);
    if (r.statusCode < 200 || r.statusCode >= 300) {
      r = await http.patch(uri, headers: h, body: body);
    }
    if (r.statusCode < 200 || r.statusCode >= 300) {
      final detail = r.body.trim();
      throw Exception(
        'Card gagal diperbarui (${r.statusCode})${detail.isEmpty ? '' : ': $detail'}',
      );
    }
  }

  Future<void> deleteTask(String id) async {
    await http.delete(
      Uri.parse('$apiBase/tasks/$id'),
      headers: await headers(),
    );
  }

  Future<void> logout() async {
    await storage.delete(key: 'access_token');
    final p = await SharedPreferences.getInstance();
    // Cache workspace dipertahankan agar data lokal tetap tersedia setelah
    // pengguna masuk kembali. Hanya data yang mengidentifikasi sesi dihapus.
    await p.remove('profile_name');
    await p.remove('profile_email');
    await p.remove('access_token');
  }

  Map<String, dynamic> _json(http.Response r) =>
      r.body.isEmpty ? {} : Map<String, dynamic>.from(jsonDecode(r.body));
}

final auth = AuthService();
final currentUser = ValueNotifier<UserProfile?>(null);
void main() => runApp(const ProCodeApp());

class ProCodeApp extends StatelessWidget {
  const ProCodeApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'PROCODE Trello',
    theme: ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: blue),
      scaffoldBackgroundColor: pageBackground,
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.white,
        foregroundColor: textDark,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      cardTheme: CardThemeData(
        color: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(7)),
          side: BorderSide(color: borderLight),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(6)),
          borderSide: BorderSide(color: Color(0xffcbd5e1)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(6)),
          borderSide: BorderSide(color: Color(0xffcbd5e1)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(6)),
          borderSide: BorderSide(color: blue, width: 1.5),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: blue,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(6)),
          ),
          minimumSize: const Size.fromHeight(44),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: blue,
          side: const BorderSide(color: blue),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(6)),
          ),
        ),
      ),
    ),
    home: const AuthGate(),
  );
}

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
      style: TextStyle(fontSize: 24, fontWeight: FontWeight.w600),
    ),
    const SizedBox(height: 28),
    TextField(
      controller: email,
      decoration: const InputDecoration(
        labelText: 'Email',
        hintText: 'Masukkan email',
        border: OutlineInputBorder(),
      ),
    ),
    const SizedBox(height: 14),
    TextField(
      controller: password,
      obscureText: true,
      decoration: const InputDecoration(
        labelText: 'Password',
        hintText: 'Masukkan password',
        border: OutlineInputBorder(),
      ),
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
    TextButton(
      onPressed: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const RegisterPage()),
      ),
      child: const Text('Belum mempunyai akun?  Daftar akun'),
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

class BoardsPage extends StatefulWidget {
  const BoardsPage({super.key});
  @override
  State<BoardsPage> createState() => _BoardsState();
}

class _LegacyBoardsState extends State<BoardsPage> {
  List<Map<String, dynamic>> boards = [];
  List<CardItem> inboxTasks = [];
  String? expandedBoardId;
  bool loading = true;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    boards = await auth.boardCache();
    inboxTasks = await auth.inbox();
    try {
      boards = await auth.projects();
      await auth.saveBoardCache(boards);
    } catch (_) {}
    if (mounted) setState(() => loading = false);
  }

  String boardId(Map<String, dynamic> b) =>
      '${b['idproject'] ?? b['id'] ?? ''}';
  String boardName(Map<String, dynamic> b) =>
      '${b['nama_project'] ?? b['name'] ?? b['title'] ?? 'Board'}';

  Future<void> editBoard(int index) async {
    final c = TextEditingController(text: boardName(boards[index]));
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Edit board'),
        content: TextField(controller: c),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, c.text.trim().isNotEmpty),
            child: const Text('Simpan'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await auth.updateProject(boardId(boards[index]), c.text.trim());
      setState(() => boards[index]['nama_project'] = c.text.trim());
      await auth.saveBoardCache(boards);
    } catch (e) {
      _msg('$e');
    }
  }

  Future<void> deleteBoard(int index) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Hapus board?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await auth.deleteProject(boardId(boards[index]));
      setState(() => boards.removeAt(index));
      await auth.saveBoardCache(boards);
    } catch (e) {
      _msg('$e');
    }
  }

  Future<void> shareBoard(Map<String, dynamic> board) =>
      SharePlus.instance.share(
        ShareParams(text: 'Board ${boardName(board)}\nID: ${boardId(board)}'),
      );

  Future<void> addBoard() async {
    final c = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Buat board'),
        content: TextField(
          controller: c,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Nama board'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, c.text.trim().isNotEmpty),
            child: const Text('Buat'),
          ),
        ],
      ),
    );
    if (ok == true) {
      try {
        final b = await auth.createProject(c.text.trim());
        setState(() => boards.add(b));
        await auth.saveBoardCache(boards);
      } catch (e) {
        _msg('$e');
      }
    }
  }

  Future<void> addInboxTask() async {
    final input = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Tambah tugas'),
        content: TextField(
          controller: input,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Nama tugas'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(context, input.text.trim().isNotEmpty),
            child: const Text('Tambah'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(
      () => inboxTasks.add(
        CardItem(
          id: 'local_${DateTime.now().microsecondsSinceEpoch}',
          title: input.text.trim(),
        ),
      ),
    );
    await auth.saveInbox(inboxTasks);
  }

  Future<void> assignToProject(
    CardItem card,
    Map<String, dynamic> board,
  ) async {
    final id = boardId(board);
    final projectCards = await auth.cardCache(id);
    projectCards.add(card);
    await auth.saveCardCache(id, projectCards);
    if (!card.id.startsWith('local_')) {
      try {
        await auth.updateTask(card, id);
      } catch (_) {}
    }
    setState(() => inboxTasks.removeWhere((task) => task.id == card.id));
    await auth.saveInbox(inboxTasks);
    if (mounted) _msg('Tugas dipindahkan ke ${boardName(board)}');
  }

  Future<void> logout() async {
    await auth.logout();
    currentUser.value = null;
    if (mounted)
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const LoginPage()),
      );
  }

  void _msg(String s) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(s.replaceFirst('Exception: ', ''))));
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Image.asset('assets/procode_logo.png', height: 30),
      actions: [
        IconButton(
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const ProfilePage()),
          ),
          icon: const Icon(Icons.account_circle_outlined),
        ),
        PopupMenuButton<String>(
          onSelected: (v) {
            if (v == 'logout') logout();
            if (v == 'profile')
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ProfilePage()),
              );
          },
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'profile', child: Text('Profil')),
            PopupMenuItem(value: 'logout', child: Text('Keluar')),
          ],
        ),
      ],
    ),
    body: RefreshIndicator(
      onRefresh: load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Dashboard',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                ),
              ),
              SizedBox(
                width: 154,
                child: TextField(
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: 'Cari project...',
                    prefixIcon: const Icon(Icons.search, size: 18),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          const Text(
            'Task List',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(
            'Drag tugas ke project yang dibuka untuk menugaskan.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const Divider(),
          if (inboxTasks.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 22),
              child: Center(
                child: Column(
                  children: [
                    Icon(Icons.assignment_outlined, color: Color(0xff94a3b8)),
                    SizedBox(height: 4),
                    Text(
                      'Belum ada task',
                      style: TextStyle(color: Color(0xff94a3b8)),
                    ),
                  ],
                ),
              ),
            )
          else
            ...inboxTasks.map(
              (task) => LongPressDraggable<CardItem>(
                data: task,
                feedback: Material(
                  color: Colors.transparent,
                  child: _taskTile(task, elevated: true),
                ),
                childWhenDragging: Opacity(
                  opacity: .35,
                  child: _taskTile(task),
                ),
                child: InkWell(
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => TaskDetailPage(
                        card: task,
                        onChanged: () async {
                          await auth.saveInbox(inboxTasks);
                          if (mounted) setState(() {});
                        },
                      ),
                    ),
                  ),
                  child: _taskTile(task),
                ),
              ),
            ),
          const SizedBox(height: 18),
          const Text(
            'Project List',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          const Divider(),
          if (loading) const Center(child: CircularProgressIndicator()),
          ...boards.asMap().entries.map((e) => _projectCard(e.key, e.value)),
        ],
      ),
    ),
    bottomNavigationBar: SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: addInboxTask,
                icon: const Icon(Icons.add),
                label: const Text('Tambah Tugas'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: FilledButton.icon(
                onPressed: addBoard,
                icon: const Icon(Icons.add),
                label: const Text('Tambah Project'),
              ),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _taskTile(CardItem task, {bool elevated = false}) => Card(
    elevation: elevated ? 6 : 0,
    margin: const EdgeInsets.only(bottom: 8),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(7),
      side: const BorderSide(color: Color(0xffdbe3f0)),
    ),
    child: ListTile(
      dense: true,
      leading: const Icon(Icons.assignment_outlined, color: blue),
      title: Text(
        task.title,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      trailing: const Icon(Icons.drag_indicator, color: Color(0xff94a3b8)),
    ),
  );

  Widget _projectCard(int index, Map<String, dynamic> board) {
    final id = boardId(board);
    final isOpen = expandedBoardId == id;
    return DragTarget<CardItem>(
      onWillAcceptWithDetails: (_) => isOpen,
      onAcceptWithDetails: (detail) => assignToProject(detail.data, board),
      builder: (context, candidates, _) => Card(
        color: candidates.isNotEmpty ? const Color(0xffeff6ff) : Colors.white,
        margin: const EdgeInsets.only(bottom: 9),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(6),
          side: BorderSide(color: isOpen ? blue : const Color(0xffdbe3f0)),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: () => setState(() => expandedBoardId = isOpen ? null : id),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        boardName(board),
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => BoardPage(project: board),
                        ),
                      ),
                      icon: const Icon(
                        Icons.arrow_circle_right,
                        color: darkBlue,
                      ),
                    ),
                    PopupMenuButton<String>(
                      onSelected: (v) {
                        if (v == 'edit') editBoard(index);
                        if (v == 'delete') deleteBoard(index);
                        if (v == 'share') shareBoard(board);
                      },
                      itemBuilder: (_) => const [
                        PopupMenuItem(
                          value: 'edit',
                          child: Text('Edit project'),
                        ),
                        PopupMenuItem(
                          value: 'delete',
                          child: Text('Hapus project'),
                        ),
                        PopupMenuItem(value: 'share', child: Text('Bagikan')),
                      ],
                    ),
                  ],
                ),
                const Text(
                  'Dibuat: 23 September 2026',
                  style: TextStyle(fontSize: 12, color: Color(0xff64748b)),
                ),
                if (isOpen)
                  const Padding(
                    padding: EdgeInsets.only(top: 10),
                    child: Row(
                      children: [
                        Icon(Icons.file_download_outlined, color: blue),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Lepaskan task di sini untuk memasukkannya ke project.',
                            style: TextStyle(color: blue),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

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

class BoardItem extends KanbanBoardGroupItem {
  final CardItem card;
  BoardItem(this.card);
  @override
  String get id => card.id;
}

class LegacyBoardPage extends StatefulWidget {
  final Map<String, dynamic> project;
  const LegacyBoardPage({super.key, required this.project});
  @override
  State<LegacyBoardPage> createState() => _LegacyBoardState();
}

class _LegacyBoardState extends State<LegacyBoardPage> {
  final controller = KanbanBoardController();
  final columns = <String, List<CardItem>>{
    'To Do': [],
    'In Progress': [],
    'Done': [],
  };
  late final String projectId;
  late final String title;
  bool loading = true;
  final invitedMembers = <String>[];

  @override
  void initState() {
    super.initState();
    projectId = '${widget.project['idproject'] ?? widget.project['id'] ?? ''}';
    title =
        '${widget.project['nama_project'] ?? widget.project['name'] ?? 'Board'}';
    _load();
    _loadMembers();
  }

  Future<void> _loadMembers() async {
    invitedMembers.addAll(await auth.membersCache(projectId));
    if (mounted) setState(() {});
  }

  Future<void> _load() async {
    final cached = await auth.cardCache(projectId);
    for (final card in cached) columns[_listFor(card.status)]!.add(card);
    try {
      final remote = await auth.tasks(projectId);
      if (remote.isNotEmpty) {
        for (final list in columns.values) list.clear();
        for (final t in remote) {
          final card = CardItem(
            id: '${t['idtask']}',
            title: '${t['nama_task']}',
            status: '${t['status'] ?? '1'}',
          );
          columns[_listFor(card.status)]!.add(card);
        }
        await _saveCards();
      }
    } catch (_) {}
    if (mounted) setState(() => loading = false);
  }

  Future<void> _saveCards() async =>
      auth.saveCardCache(projectId, columns.values.expand((x) => x).toList());

  CardItem? _findCard(String id) => columns.values
      .expand((x) => x)
      .cast<CardItem?>()
      .firstWhere((c) => c?.id == id, orElse: () => null);

  Future<void> _editCard(CardItem card) async {
    if (card.id.isEmpty || card.id == 'null') {
      _show('ID card tidak valid. Muat ulang board.');
      return;
    }
    final c = TextEditingController(text: card.title);
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Edit card'),
        content: TextField(controller: c),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, c.text.trim().isNotEmpty),
            child: const Text('Simpan'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    card.title = c.text.trim();
    try {
      await auth.updateTask(card, projectId);
      await _saveCards();
      if (mounted) setState(() {});
    } catch (e) {
      _show('$e');
    }
  }

  Future<void> _deleteCard(CardItem card) async {
    try {
      await auth.deleteTask(card.id);
      for (final list in columns.values) list.remove(card);
      await _saveCards();
      if (mounted) setState(() {});
    } catch (e) {
      _show('$e');
    }
  }

  String _listFor(String status) => status == '2'
      ? 'In Progress'
      : status == '3'
      ? 'Done'
      : 'To Do';
  String _statusFor(String list) => list == 'Done'
      ? '3'
      : list == 'In Progress'
      ? '2'
      : '1';

  List<KanbanBoardGroup<BoardGroupData, BoardItem>> _groups() => columns.entries
      .map(
        (entry) => KanbanBoardGroup<BoardGroupData, BoardItem>(
          id: entry.key,
          name: entry.key,
          customData: BoardGroupData(entry.key),
          items: entry.value.map(BoardItem.new).toList(),
        ),
      )
      .toList();

  Future<void> _add(String list) async {
    final input = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Tambah card ke $list'),
        content: TextField(controller: input, autofocus: true),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(context, input.text.trim().isNotEmpty),
            child: const Text('Tambah'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final id = await auth.createTask(input.text.trim(), projectId);
      setState(
        () => columns[list]!.add(
          CardItem(id: id, title: input.text.trim(), status: _statusFor(list)),
        ),
      );
      await _saveCards();
    } catch (e) {
      _show('$e');
    }
  }

  void _onMove(int? oldCard, int? newCard, int? oldGroup, int? newGroup) {
    if (oldCard == null ||
        oldGroup == null ||
        newGroup == null ||
        oldGroup == newGroup)
      return;
    final from = columns.keys.elementAt(oldGroup);
    final to = columns.keys.elementAt(newGroup);
    final card = columns[from]![oldCard];
    setState(() {
      columns[from]!.removeAt(oldCard);
      card.status = _statusFor(to);
      columns[to]!.insert(
        (newCard ?? columns[to]!.length).clamp(0, columns[to]!.length),
        card,
      );
    });
    auth.updateTask(card, projectId);
    _saveCards();
  }

  void _show(String text) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(text.replaceFirst('Exception: ', ''))));

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(title),
      actions: [
        IconButton(
          onPressed: () => _add('To Do'),
          icon: const Icon(Icons.add_card),
        ),
        IconButton(onPressed: _members, icon: const Icon(Icons.group)),
      ],
    ),
    body: loading
        ? const Center(child: CircularProgressIndicator())
        : KanbanBoard(
            controller: controller,
            groups: _groups(),
            groupConstraints: const BoxConstraints(
              maxWidth: 300,
              minWidth: 280,
            ),
            onGroupItemMove: _onMove,
            groupItemBuilder: (context, groupId, index) {
              final card = columns[groupId]![index];
              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  title: Text(card.title),
                  subtitle: card.dueDate.isEmpty
                      ? null
                      : Text('Due: ${card.dueDate}'),
                  trailing: PopupMenuButton<String>(
                    onSelected: (v) {
                      if (v == 'edit') _editCard(card);
                      if (v == 'delete') _deleteCard(card);
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'edit', child: Text('Edit card')),
                      PopupMenuItem(value: 'delete', child: Text('Hapus card')),
                    ],
                  ),
                  onTap: () => _detail(card),
                ),
              );
            },
          ),
  );

  void _members() {
    final email = TextEditingController();
    showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, refresh) => AlertDialog(
          title: const Text('Member board'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (invitedMembers.isNotEmpty)
                ...invitedMembers.map(
                  (e) => ListTile(
                    leading: const Icon(Icons.email_outlined),
                    title: Text(e),
                    trailing: IconButton(
                      onPressed: () {
                        refresh(() => invitedMembers.remove(e));
                      },
                      icon: const Icon(Icons.remove_circle_outline),
                    ),
                  ),
                ),
              TextField(
                controller: email,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(labelText: 'Email member'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Tutup'),
            ),
            FilledButton(
              onPressed: () async {
                final value = email.text.trim();
                if (value.isNotEmpty && !invitedMembers.contains(value)) {
                  refresh(() => invitedMembers.add(value));
                  await auth.saveMembers(projectId, invitedMembers);
                }
                email.clear();
              },
              child: const Text('Invite'),
            ),
          ],
        ),
      ),
    );
  }

  void _detail(CardItem card) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => TaskDetailPage(
          card: card,
          onChanged: () async {
            await _saveCards();
            if (mounted) setState(() {});
          },
        ),
      ),
    );
  }
}

class BoardGroupData {
  final String title;
  BoardGroupData(this.title);
}

class LegacyTaskDetailPage extends StatefulWidget {
  final CardItem card;
  final Future<void> Function() onChanged;
  const LegacyTaskDetailPage({
    super.key,
    required this.card,
    required this.onChanged,
  });

  @override
  State<LegacyTaskDetailPage> createState() => _LegacyTaskDetailPageState();
}

class _LegacyTaskDetailPageState extends State<LegacyTaskDetailPage> {
  final comment = TextEditingController();

  @override
  void dispose() {
    comment.dispose();
    super.dispose();
  }

  Future<void> _addComment() async {
    final text = comment.text.trim();
    if (text.isEmpty) return;
    setState(() => widget.card.comments.add(text));
    comment.clear();
    await widget.onChanged();
  }

  Future<void> _edit() async {
    final input = TextEditingController(text: widget.card.title);
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Edit tugas'),
        content: TextField(controller: input, autofocus: true),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(context, input.text.trim().isNotEmpty),
            child: const Text('Simpan'),
          ),
        ],
      ),
    );
    if (ok == true) {
      setState(() => widget.card.title = input.text.trim());
      await widget.onChanged();
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      leading: const BackButton(),
      title: Text(
        widget.card.title,
        style: const TextStyle(fontWeight: FontWeight.bold),
      ),
      centerTitle: true,
      actions: [
        IconButton(onPressed: _edit, icon: const Icon(Icons.edit_outlined)),
        IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.delete_outline, color: Colors.red),
        ),
      ],
    ),
    body: Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(18),
            children: [
              const Text('Komentar', style: TextStyle(fontSize: 20)),
              const SizedBox(height: 14),
              if (widget.card.comments.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 34),
                  child: Center(
                    child: Text(
                      'Belum ada komentar',
                      style: TextStyle(color: Color(0xff94a3b8)),
                    ),
                  ),
                )
              else
                ...widget.card.comments.asMap().entries.map(
                  (entry) => _commentItem(entry.key, entry.value),
                ),
            ],
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: TextField(
              controller: comment,
              onSubmitted: (_) => _addComment(),
              decoration: InputDecoration(
                hintText: 'Typing...',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                suffixIcon: IconButton(
                  onPressed: _addComment,
                  icon: const Icon(Icons.send_outlined),
                ),
              ),
            ),
          ),
        ),
      ],
    ),
  );

  Widget _commentItem(int index, String text) => Padding(
    padding: const EdgeInsets.only(bottom: 18),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CircleAvatar(
          radius: 16,
          backgroundColor: index.isEven ? blue : Colors.deepPurple,
          child: Text(
            'T${index + 1}',
            style: const TextStyle(fontSize: 10, color: Colors.white),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Team ${index + 1}',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 3),
              Text(text),
              TextButton(
                onPressed: () {},
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(0, 26),
                ),
                child: const Text('Balas'),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

// Mobile workspace redesign. This state is deliberately local-first so every
// interaction remains available when the project API is offline.
class _BoardsState extends State<BoardsPage> {
  final Map<String, List<CardItem>> tasks = {};
  final Set<String> openProjects = {};
  final search = TextEditingController();
  String semester = 'Semua Semester';
  bool loading = true, addOpen = false;
  String? loadError;
  List<Map<String, dynamic>> boards = [];
  List<CardItem> inboxTasks = [];

  static const semesters = [
    'Semua Semester',
    '2027/2028 - Genap',
    '2027/2028 - Ganjil',
    '2026/2027 - Genap',
    '2026/2027 - Ganjil',
    '2025/2026 - Genap',
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  String id(Map<String, dynamic> board) =>
      '${board['idproject'] ?? board['id'] ?? ''}';
  String name(Map<String, dynamic> board) =>
      '${board['nama_project'] ?? board['name'] ?? 'Project'}';

  Future<void> _load() async {
    if (mounted)
      setState(() {
        loading = true;
        loadError = null;
      });
    boards = await auth.boardCache();
    inboxTasks = await auth.inbox();
    try {
      final remoteInbox = await auth.unassignedTasks();
      if (remoteInbox.isNotEmpty) {
        inboxTasks = remoteInbox
            .map(
              (row) => CardItem(
                id: '${row['idtask'] ?? row['id']}',
                title: '${row['nama_task'] ?? row['title'] ?? 'Task'}',
                description: '${row['deskripsi'] ?? row['description'] ?? ''}',
                status: '${row['status'] ?? '1'}',
                dueDate: '${row['due_date'] ?? row['dueDate'] ?? ''}',
              ),
            )
            .toList();
        await auth.saveInbox(inboxTasks);
      }
    } catch (_) {}
    try {
      boards = await auth.projects();
      await auth.saveBoardCache(boards);
    } catch (error) {
      loadError = error.toString().replaceFirst('Exception: ', '');
    }
    for (final board in boards) {
      final projectId = id(board);
      var cards = await auth.cardCache(projectId);
      try {
        final remote = await auth.tasks(projectId);
        if (cards.isEmpty && remote.isNotEmpty)
          cards = remote
              .map(
                (row) => CardItem(
                  id: '${row['idtask'] ?? row['id']}',
                  title: '${row['nama_task'] ?? row['title']}',
                  status: '${row['status'] ?? '1'}',
                  description: '${row['deskripsi'] ?? ''}',
                ),
              )
              .toList();
      } catch (_) {}
      tasks[projectId] = cards;
      await auth.saveCardCache(projectId, cards);
      try {
        board['_serverMembers'] = await auth.projectUsers(projectId);
      } catch (_) {
        // Keep any member information that was previously cached with board.
      }
    }
    await auth.saveBoardCache(boards);
    if (mounted) setState(() => loading = false);
  }

  List<Map<String, dynamic>> get filtered => boards.where((b) {
    final matchesName = name(
      b,
    ).toLowerCase().contains(search.text.toLowerCase());
    final matchesSemester =
        semester == semesters.first ||
        '${b['semester'] ?? semesters[4]}' == semester;
    return matchesName && matchesSemester;
  }).toList();

  int _statusCount(String projectId, String status) =>
      tasks[projectId]?.where((t) => t.status == status).length ?? 0;
  String _label(String status) => status == '2'
      ? 'In Progress'
      : status == '3'
      ? 'Done'
      : 'To Do';
  Color _tone(String status) => status == '2'
      ? const Color(0xfffff6bf)
      : status == '3'
      ? const Color(0xffd8f5e1)
      : const Color(0xffdceaff);
  Color _ink(String status) => status == '2'
      ? const Color(0xff8a6415)
      : status == '3'
      ? const Color(0xff16805b)
      : const Color(0xff315d9c);

  Future<void> _saveProjectTasks(String projectId) =>
      auth.saveCardCache(projectId, tasks[projectId] ?? []);

  Future<void> _newProject() async {
    final input = TextEditingController();
    final form = GlobalKey<FormState>();
    final created = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            const Expanded(child: Text('Buat Project Baru')),
            IconButton(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.close, size: 18),
            ),
          ],
        ),
        content: Form(
          key: form,
          child: TextFormField(
            controller: input,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Nama Project',
              hintText: 'Masukkan nama project',
              border: OutlineInputBorder(),
            ),
            validator: (value) => value == null || value.trim().isEmpty
                ? 'Nama project wajib diisi'
                : null,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () {
              if (form.currentState!.validate()) Navigator.pop(context, true);
            },
            child: const Text('Buat Project'),
          ),
        ],
      ),
    );
    if (created != true) return;
    Map<String, dynamic> project;
    try {
      project = await auth.createProject(input.text.trim());
    } catch (_) {
      project = {
        'id': 'local_${DateTime.now().microsecondsSinceEpoch}',
        'nama_project': input.text.trim(),
      };
    }
    project['semester'] = semesters[4];
    setState(() {
      boards.add(project);
      tasks[id(project)] = [];
    });
    await auth.saveBoardCache(boards);
  }

  Future<void> _newTask({String? defaultProject}) async {
    final title = TextEditingController(),
        description = TextEditingController();
    final form = GlobalKey<FormState>();
    String? project = defaultProject;
    String status = '1';
    final created = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialog) => AlertDialog(
          title: Row(
            children: [
              const Expanded(child: Text('Buat Tugas Baru')),
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close, size: 18),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Form(
              key: form,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: title,
                    autofocus: true,
                    decoration: const InputDecoration(
                      labelText: 'Nama Tugas',
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) => v == null || v.trim().isEmpty
                        ? 'Nama tugas wajib diisi'
                        : null,
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String?>(
                    value: project,
                    decoration: const InputDecoration(
                      labelText: 'Project',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Text('Tanpa project (Task List)'),
                      ),
                      ...boards.map(
                        (b) => DropdownMenuItem(
                          value: id(b),
                          child: Text(name(b), overflow: TextOverflow.ellipsis),
                        ),
                      ),
                    ],
                    onChanged: (v) => setDialog(() => project = v),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: description,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'Deskripsi',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Batal'),
            ),
            FilledButton(
              onPressed: () {
                if (form.currentState!.validate()) Navigator.pop(context, true);
              },
              child: const Text('Buat Tugas'),
            ),
          ],
        ),
      ),
    );
    if (created != true) return;
    var taskId = 'local_${DateTime.now().microsecondsSinceEpoch}';
    if (project != null) {
      try {
        taskId = await auth.createTask(title.text.trim(), project!);
      } catch (_) {}
    }
    final task = CardItem(
      id: taskId,
      title: title.text.trim(),
      status: status,
      description: description.text.trim(),
      dueDate: '',
    );
    if (project == null) {
      setState(() => inboxTasks.add(task));
      await auth.saveInbox(inboxTasks);
    } else {
      setState(() => tasks.putIfAbsent(project!, () => []).add(task));
      await _saveProjectTasks(project!);
    }
  }

  Future<void> _editTask(String projectId, CardItem task) async {
    final input = TextEditingController(text: task.title);
    String status = task.status;
    final changed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialog) => AlertDialog(
          title: const Text('Edit tugas'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: input,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Nama tugas'),
              ),
              DropdownButton<String>(
                value: status,
                isExpanded: true,
                items: const [
                  DropdownMenuItem(value: '1', child: Text('To Do')),
                  DropdownMenuItem(value: '2', child: Text('In Progress')),
                  DropdownMenuItem(value: '3', child: Text('Done')),
                ],
                onChanged: (v) => setDialog(() => status = v!),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Batal'),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.pop(context, input.text.trim().isNotEmpty),
              child: const Text('Simpan'),
            ),
          ],
        ),
      ),
    );
    if (changed != true) return;
    setState(() {
      task.title = input.text.trim();
      task.status = status;
    });
    if (!task.id.startsWith('local_')) {
      try {
        await auth.updateTask(task, projectId);
      } catch (_) {}
    }
    await _saveProjectTasks(projectId);
  }

  String? _ownerOf(CardItem task) {
    if (inboxTasks.any((item) => item.id == task.id)) return null;
    for (final entry in tasks.entries) {
      if (entry.value.any((item) => item.id == task.id)) return entry.key;
    }
    return null;
  }

  Future<void> _moveTask(
    CardItem task,
    String? targetProjectId,
    String status,
  ) async {
    final sourceProjectId = _ownerOf(task);
    final oldInbox = List<CardItem>.from(inboxTasks);
    final oldSource = sourceProjectId == null
        ? null
        : List<CardItem>.from(tasks[sourceProjectId] ?? []);
    final oldTarget = targetProjectId == null
        ? null
        : List<CardItem>.from(tasks[targetProjectId] ?? []);
    final oldStatus = task.status;
    setState(() {
      inboxTasks.removeWhere((item) => item.id == task.id);
      for (final list in tasks.values) {
        list.removeWhere((item) => item.id == task.id);
      }
      task.status = status;
      if (targetProjectId == null)
        inboxTasks.add(task);
      else
        tasks.putIfAbsent(targetProjectId, () => []).add(task);
    });
    try {
      if (!task.id.startsWith('local_') && targetProjectId != null)
        await auth.updateTask(task, targetProjectId);
      await auth.saveInbox(inboxTasks);
      if (sourceProjectId != null) await _saveProjectTasks(sourceProjectId);
      if (targetProjectId != null && targetProjectId != sourceProjectId)
        await _saveProjectTasks(targetProjectId);
    } catch (_) {
      setState(() {
        inboxTasks = oldInbox;
        task.status = oldStatus;
        if (sourceProjectId != null && oldSource != null)
          tasks[sourceProjectId] = oldSource;
        if (targetProjectId != null && oldTarget != null)
          tasks[targetProjectId] = oldTarget;
      });
      _message('Tugas gagal dipindahkan. Perubahan dikembalikan.');
    }
  }

  Future<void> _deleteTask(String projectId, CardItem task) async {
    final confirmed = await _confirmDelete('tugas', task.title);
    if (!confirmed) return;
    setState(() => tasks[projectId]?.remove(task));
    if (!task.id.startsWith('local_')) {
      try {
        await auth.deleteTask(task.id);
      } catch (_) {}
    }
    await _saveProjectTasks(projectId);
    _message('Tugas "${task.title}" dihapus.');
  }

  Future<bool> _confirmDelete(String type, String name) async =>
      await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: Text('Hapus $type?'),
          content: Text('Yakin ingin menghapus "$name"?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Batal'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Hapus'),
            ),
          ],
        ),
      ) ??
      false;

  Future<void> _deleteProject(Map<String, dynamic> board) async {
    if (!await _confirmDelete('project', name(board))) return;
    final projectId = id(board);
    try {
      if (!projectId.startsWith('local_')) await auth.deleteProject(projectId);
      setState(() {
        boards.remove(board);
        tasks.remove(projectId);
        openProjects.remove(projectId);
      });
      await auth.saveBoardCache(boards);
      _message('Project "${name(board)}" dihapus.');
    } catch (_) {
      _message('Project gagal dihapus.');
    }
  }

  Future<void> _logout() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Log out?'),
        content: const Text('Anda akan keluar dari sesi ini.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Log out'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await auth.logout();
    currentUser.value = null;
    if (mounted)
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const LoginPage()),
        (_) => false,
      );
  }

  void _message(String message) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(message)));
  String get _displayName {
    final user = currentUser.value;
    final name = user?.name.trim() ?? '';
    return name.isNotEmpty
        ? name
        : (user?.email.trim().isNotEmpty == true ? user!.email : 'Profil');
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Image.asset('assets/procode_logo.png', height: 29),
      actions: [
        PopupMenuButton<String>(
          onSelected: (value) {
            if (value == 'profile')
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ProfilePage()),
              );
            if (value == 'logout') _logout();
          },
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'profile', child: Text('Profil')),
            PopupMenuItem(value: 'logout', child: Text('Log out')),
          ],
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircleAvatar(
                  radius: 13,
                  backgroundColor: blue,
                  child: Text(
                    initialsFor(_displayName),
                    style: const TextStyle(fontSize: 10, color: Colors.white),
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  _displayName,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: Color(0xff111827),
                  ),
                ),
                Icon(Icons.keyboard_arrow_down, color: Color(0xff111827)),
              ],
            ),
          ),
        ),
      ],
    ),
    floatingActionButton: _addMenu(),
    body: RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 96),
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Dashboard',
                  style: TextStyle(fontSize: 21, fontWeight: FontWeight.bold),
                ),
              ),
              SizedBox(
                width: 142,
                child: TextField(
                  controller: search,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: 'Cari project...',
                    prefixIcon: const Icon(Icons.search, size: 17),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(5),
                    ),
                  ),
                ),
              ),
              PopupMenuButton<String>(
                icon: const Icon(Icons.filter_alt_outlined, color: blue),
                onSelected: (value) => setState(() => semester = value),
                itemBuilder: (_) => semesters
                    .map(
                      (item) => CheckedPopupMenuItem(
                        value: item,
                        checked: item == semester,
                        child: Text(item, style: const TextStyle(fontSize: 12)),
                      ),
                    )
                    .toList(),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Text(
            'Task List',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const Divider(height: 10),
          _inboxDropArea(),
          const SizedBox(height: 20),
          const Text(
            'Project List',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const Divider(height: 10),
          if (loading)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: CircularProgressIndicator(),
              ),
            )
          else if (loadError != null && filtered.isEmpty)
            _LoadError(message: loadError!, onRetry: _load)
          else if (filtered.isEmpty)
            const _EmptyState(label: 'Project tidak ditemukan')
          else
            ...filtered.map(_projectCard),
        ],
      ),
    ),
  );

  Widget _inboxDropArea() => DragTarget<CardItem>(
    onWillAcceptWithDetails: (details) => _ownerOf(details.data) != null,
    onAcceptWithDetails: (details) => _moveTask(details.data, null, '1'),
    builder: (context, candidates, _) => Container(
      decoration: BoxDecoration(
        color: candidates.isNotEmpty ? const Color(0xffeff6ff) : null,
        borderRadius: BorderRadius.circular(7),
        border: candidates.isNotEmpty ? Border.all(color: blue) : null,
      ),
      child: inboxTasks.isEmpty
          ? const _EmptyState(label: 'Belum ada task')
          : Column(children: inboxTasks.map(_inboxTaskCard).toList()),
    ),
  );

  Widget _inboxTaskCard(CardItem task) => LongPressDraggable<CardItem>(
    data: task,
    feedback: Material(
      color: Colors.transparent,
      child: SizedBox(width: 280, child: _taskVisual(task, elevated: true)),
    ),
    childWhenDragging: Opacity(opacity: .35, child: _taskVisual(task)),
    child: _taskVisual(
      task,
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => TaskDetailPage(
            card: task,
            onChanged: () => auth.saveInbox(inboxTasks),
            onDelete: () async {
              setState(() => inboxTasks.remove(task));
              await auth.saveInbox(inboxTasks);
            },
          ),
        ),
      ),
      trailing: _taskMenu(
        onEdit: () => _editInboxTask(task),
        onDelete: () => _deleteInboxTask(task),
      ),
    ),
  );

  Widget _taskVisual(
    CardItem task, {
    bool elevated = false,
    VoidCallback? onTap,
    Widget? trailing,
  }) => Card(
    margin: const EdgeInsets.only(bottom: 7),
    elevation: elevated ? 7 : 0,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(6),
      side: const BorderSide(color: Color(0xffe2e8f0)),
    ),
    child: ListTile(
      dense: true,
      leading: const Icon(Icons.assignment_outlined, color: blue),
      title: Text(task.title),
      subtitle: const Text(
        'Tahan untuk memindahkan',
        style: TextStyle(fontSize: 10),
      ),
      onTap: onTap,
      trailing:
          trailing ??
          const Icon(Icons.drag_indicator, color: Color(0xff94a3b8)),
    ),
  );

  Widget _taskMenu({
    required VoidCallback onEdit,
    required VoidCallback onDelete,
  }) => PopupMenuButton<String>(
    tooltip: 'Aksi tugas',
    onSelected: (value) {
      if (value == 'edit') onEdit();
      if (value == 'delete') onDelete();
    },
    itemBuilder: (_) => const [
      PopupMenuItem(value: 'edit', child: Text('Edit')),
      PopupMenuItem(value: 'delete', child: Text('Hapus')),
    ],
  );

  Future<void> _editInboxTask(CardItem task) async {
    final input = TextEditingController(text: task.title);
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Edit tugas'),
        content: TextField(controller: input, autofocus: true),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(context, input.text.trim().isNotEmpty),
            child: const Text('Simpan'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => task.title = input.text.trim());
    await auth.saveInbox(inboxTasks);
  }

  Future<void> _deleteInboxTask(CardItem task) async {
    if (!await _confirmDelete('tugas', task.title)) return;
    setState(() => inboxTasks.remove(task));
    await auth.saveInbox(inboxTasks);
    _message('Tugas "${task.title}" dihapus.');
  }

  Widget _addMenu() => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.end,
    children: [
      if (addOpen) ...[
        FloatingActionButton.extended(
          heroTag: 'task',
          backgroundColor: darkBlue,
          foregroundColor: Colors.white,
          onPressed: () {
            setState(() => addOpen = false);
            _newTask();
          },
          icon: const Icon(Icons.note_add_outlined),
          label: const Text('Tugas'),
        ),
        const SizedBox(height: 8),
        FloatingActionButton.extended(
          heroTag: 'project',
          backgroundColor: darkBlue,
          foregroundColor: Colors.white,
          onPressed: () {
            setState(() => addOpen = false);
            _newProject();
          },
          icon: const Icon(Icons.create_new_folder_outlined),
          label: const Text('Project'),
        ),
        const SizedBox(height: 10),
      ],
      FloatingActionButton(
        heroTag: 'main',
        backgroundColor: darkBlue,
        foregroundColor: Colors.white,
        onPressed: () => setState(() => addOpen = !addOpen),
        child: Icon(addOpen ? Icons.close : Icons.add),
      ),
    ],
  );

  Widget _projectCard(Map<String, dynamic> board) {
    final projectId = id(board), open = openProjects.contains(projectId);
    final rawCreated =
        board['created_at'] ?? board['createdAt'] ?? board['tanggal_dibuat'];
    final parsedCreated = rawCreated == null
        ? null
        : DateTime.tryParse('$rawCreated');
    final createdLabel = rawCreated == null || '$rawCreated'.trim().isEmpty
        ? 'Tanggal pembuatan tidak tersedia'
        : parsedCreated == null
        ? '$rawCreated'
        : '${parsedCreated.day.toString().padLeft(2, '0')}/${parsedCreated.month.toString().padLeft(2, '0')}/${parsedCreated.year}';
    final people = <String>[];
    void addPerson(dynamic value) {
      if (value is String && value.trim().isNotEmpty) people.add(value.trim());
      if (value is Map) {
        final label = '${value['name'] ?? value['email'] ?? ''}'.trim();
        if (label.isNotEmpty) people.add(label);
      }
      if (value is List)
        for (final item in value) {
          addPerson(item);
        }
    }

    addPerson(board['owner']);
    addPerson(board['creator']);
    addPerson(board['members']);
    addPerson(board['collaborators']);
    addPerson(board['_serverMembers']);
    addPerson(board['users']);
    return DragTarget<CardItem>(
      onWillAcceptWithDetails: (_) => false,
      onAcceptWithDetails: (details) => _moveTask(details.data, projectId, '1'),
      builder: (context, candidates, _) => Card(
        color: candidates.isNotEmpty ? const Color(0xffeff6ff) : null,
        margin: const EdgeInsets.only(bottom: 10),
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(5),
          side: BorderSide(
            color: candidates.isNotEmpty ? blue : const Color(0xffdbe3f0),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: InkWell(
                      onTap: () => setState(() {
                        if (open)
                          openProjects.remove(projectId);
                        else
                          openProjects.add(projectId);
                      }),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name(board),
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            'Dibuat: $createdLabel',
                            style: TextStyle(
                              fontSize: 12,
                              color: Color(0xff64748b),
                            ),
                          ),
                          const SizedBox(height: 5),
                          if (people.isNotEmpty)
                            Wrap(
                              spacing: 3,
                              children: people
                                  .toSet()
                                  .take(4)
                                  .map(
                                    (person) => CircleAvatar(
                                      radius: 9,
                                      backgroundColor: const Color(0xffc997ed),
                                      child: Text(
                                        initialsFor(person),
                                        style: const TextStyle(
                                          fontSize: 8,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ),
                                  )
                                  .toList(),
                            ),
                        ],
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Buka halaman project',
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => BoardPage(project: board),
                      ),
                    ).then((_) => _load()),
                    icon: const Icon(
                      Icons.arrow_circle_right,
                      color: darkBlue,
                      size: 29,
                    ),
                  ),
                  PopupMenuButton<String>(
                    onSelected: (value) {
                      if (value == 'delete') _deleteProject(board);
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(
                        value: 'delete',
                        child: Text('Hapus project'),
                      ),
                    ],
                  ),
                ],
              ),
              if (open) ...[const SizedBox(height: 10), _board(projectId)],
            ],
          ),
        ),
      ),
    );
  }

  Widget _board(String projectId) => Column(
    children: [
      '1',
      '2',
      '3',
    ].map((status) => _statusSection(projectId, status)).toList(),
  );
  Widget _statusSection(String projectId, String status) {
    final list =
        tasks[projectId]?.where((task) => task.status == status).toList() ?? [];
    return DragTarget<CardItem>(
      onWillAcceptWithDetails: (details) =>
          _ownerOf(details.data) != projectId || details.data.status != status,
      onAcceptWithDetails: (details) =>
          _moveTask(details.data, projectId, status),
      builder: (context, candidates, _) => Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: candidates.isNotEmpty ? const Color(0xffeff6ff) : null,
          border: Border.all(
            color: candidates.isNotEmpty ? blue : _tone(status),
          ),
          borderRadius: BorderRadius.circular(7),
        ),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                color: _tone(status),
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(6),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    status == '1'
                        ? Icons.view_list
                        : status == '2'
                        ? Icons.schedule
                        : Icons.check_circle,
                    color: _ink(status),
                    size: 19,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    _label(status),
                    style: TextStyle(
                      color: _ink(status),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  CircleAvatar(
                    radius: 10,
                    backgroundColor: Colors.white,
                    child: Text(
                      '${list.length}',
                      style: TextStyle(
                        color: _ink(status),
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(10),
              child: list.isEmpty
                  ? const _EmptyState(label: 'Tidak ada task', compact: true)
                  : Column(
                      children: list
                          .map(
                            (task) => _taskCard(projectId, task, inBoard: true),
                          )
                          .toList(),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _taskCard(String projectId, CardItem task, {bool inBoard = false}) =>
      LongPressDraggable<CardItem>(
        data: task,
        feedback: Material(
          color: Colors.transparent,
          child: SizedBox(
            width: 280,
            child: _taskSurface(task, elevated: true),
          ),
        ),
        childWhenDragging: Opacity(opacity: .35, child: _taskSurface(task)),
        child: Card(
          margin: const EdgeInsets.only(bottom: 7),
          elevation: 0,
          color: const Color(0xfff8fafc),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(6),
            side: const BorderSide(color: Color(0xffe2e8f0)),
          ),
          child: ListTile(
            dense: true,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => TaskDetailPage(
                  card: task,
                  onChanged: () => _saveProjectTasks(projectId),
                  onDelete: () => _deleteTask(projectId, task),
                ),
              ),
            ),
            title: Text(task.title),
            subtitle: task.dueDate.isEmpty
                ? null
                : Text(
                    'Tenggat ${task.dueDate}',
                    style: const TextStyle(fontSize: 11),
                  ),
            trailing: _taskMenu(
              onEdit: () => _editTask(projectId, task),
              onDelete: () => _deleteTask(projectId, task),
            ),
          ),
        ),
      );

  Widget _taskSurface(CardItem task, {bool elevated = false}) => Card(
    margin: const EdgeInsets.only(bottom: 7),
    elevation: elevated ? 7 : 0,
    color: const Color(0xfff8fafc),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(6),
      side: const BorderSide(color: Color(0xffe2e8f0)),
    ),
    child: ListTile(
      dense: true,
      title: Text(task.title),
      subtitle: task.dueDate.isEmpty
          ? null
          : Text(
              'Tenggat ${task.dueDate}',
              style: const TextStyle(fontSize: 11),
            ),
    ),
  );
}

class _EmptyState extends StatelessWidget {
  final String label;
  final bool compact;
  const _EmptyState({required this.label, this.compact = false});
  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.symmetric(vertical: compact ? 14 : 26),
    child: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.assignment_outlined, color: Color(0xff94a3b8)),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(fontSize: 11, color: Color(0xff94a3b8)),
          ),
        ],
      ),
    ),
  );
}

class _LoadError extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _LoadError({required this.message, required this.onRetry});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 28),
    child: Center(
      child: Column(
        children: [
          const Icon(Icons.cloud_off_outlined, color: Colors.redAccent),
          const SizedBox(height: 8),
          const Text('Project gagal dimuat'),
          const SizedBox(height: 4),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12, color: Color(0xff64748b)),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('Muat ulang'),
          ),
        ],
      ),
    ),
  );
}

class BoardPage extends StatefulWidget {
  final Map<String, dynamic> project;
  const BoardPage({super.key, required this.project});
  @override
  State<BoardPage> createState() => _ProjectBoardState();
}

class _ProjectBoardState extends State<BoardPage> {
  late final String projectId;
  late final String title;
  List<CardItem> cards = [];
  List<String> collaborators = [];
  bool loading = true;
  @override
  void initState() {
    super.initState();
    projectId = '${widget.project['idproject'] ?? widget.project['id']}';
    title =
        '${widget.project['nama_project'] ?? widget.project['name'] ?? 'Project'}';
    _load();
  }

  Future<void> _load() async {
    cards = await auth.cardCache(projectId);
    collaborators = await auth.membersCache(projectId);
    try {
      final users = await auth.projectUsers(projectId);
      final names = users
          .map((user) => '${user['name'] ?? user['email'] ?? ''}'.trim())
          .where((name) => name.isNotEmpty)
          .toList();
      if (names.isNotEmpty) {
        collaborators = names;
        await auth.saveMembers(projectId, collaborators);
      }
    } catch (_) {}
    if (mounted) setState(() => loading = false);
  }

  void _collaboratorDialog() {
    final email = TextEditingController();
    final form = GlobalKey<FormState>();
    showDialog(
      context: context,
      builder: (dialogContext) {
        var status = 'Masukkan email pengguna yang sudah terdaftar.';
        return StatefulBuilder(
          builder: (context, refresh) => AlertDialog(
            title: const Text('Undang Kolaborator'),
            content: Form(
              key: form,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ...collaborators.map(
                    (item) => ListTile(
                      leading: const Icon(Icons.person_outline),
                      title: Text(item),
                      subtitle: const Text('Anggota dari cache/API'),
                    ),
                  ),
                  TextFormField(
                    controller: email,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                      labelText: 'Alamat email',
                    ),
                    validator: (value) =>
                        value != null &&
                            RegExp(
                              r'^[^@\s]+@[^@\s]+\.[^@\s]+$',
                            ).hasMatch(value)
                        ? null
                        : 'Masukkan email yang valid',
                  ),
                  const SizedBox(height: 8),
                  Text(
                    status,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xff64748b),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Tutup'),
              ),
              FilledButton(
                onPressed: () async {
                  if (!form.currentState!.validate()) return;
                  try {
                    final result = await auth.checkProjectEmail(
                      projectId,
                      email.text.trim(),
                    );
                    if (result['available'] != true) {
                      refresh(
                        () => status =
                            '${result['message'] ?? 'Email tidak tersedia.'}',
                      );
                      return;
                    }
                    final invited = await auth.inviteProject(
                      projectId,
                      email.text.trim(),
                    );
                    refresh(
                      () => status =
                          '${invited['message'] ?? 'Kolaborator berhasil ditambahkan.'}',
                    );
                    final users = await auth.projectUsers(projectId);
                    final names = users
                        .map(
                          (user) =>
                              '${user['name'] ?? user['email'] ?? ''}'.trim(),
                        )
                        .where((name) => name.isNotEmpty)
                        .toList();
                    if (names.isNotEmpty) {
                      collaborators = names;
                      await auth.saveMembers(projectId, collaborators);
                      if (mounted) setState(() {});
                    }
                  } catch (error) {
                    refresh(
                      () => status = error.toString().replaceFirst(
                        'Exception: ',
                        '',
                      ),
                    );
                  }
                },
                child: const Text('Undang'),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _save() => auth.saveCardCache(projectId, cards);
  Future<void> _move(CardItem card, String status) async {
    final previous = card.status;
    if (previous == status) return;
    setState(() => card.status = status);
    try {
      if (!card.id.startsWith('local_')) await auth.updateTask(card, projectId);
      await _save();
    } catch (_) {
      setState(() => card.status = previous);
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Status gagal diperbarui. Perubahan dikembalikan.'),
          ),
        );
    }
  }

  Color _tone(String s) => s == '2'
      ? const Color(0xfffff6bf)
      : s == '3'
      ? const Color(0xffd8f5e1)
      : const Color(0xffdceaff);
  String _label(String s) => s == '2'
      ? 'In Progress'
      : s == '3'
      ? 'Done'
      : 'To Do';
  Future<void> _add(String status) async {
    final c = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Tambah ke ${_label(status)}'),
        content: TextField(controller: c, autofocus: true),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, c.text.trim().isNotEmpty),
            child: const Text('Tambah'),
          ),
        ],
      ),
    );
    if (ok == true) {
      setState(
        () => cards.add(
          CardItem(
            id: 'local_${DateTime.now().microsecondsSinceEpoch}',
            title: c.text.trim(),
            status: status,
          ),
        ),
      );
      await _save();
    }
  }

  Future<void> _edit(CardItem item) async {
    final c = TextEditingController(text: item.title);
    String status = item.status;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (_, refresh) => AlertDialog(
          title: const Text('Edit tugas'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: c),
              DropdownButton<String>(
                value: status,
                isExpanded: true,
                items: const [
                  DropdownMenuItem(value: '1', child: Text('To Do')),
                  DropdownMenuItem(value: '2', child: Text('In Progress')),
                  DropdownMenuItem(value: '3', child: Text('Done')),
                ],
                onChanged: (v) => refresh(() => status = v!),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Batal'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, c.text.trim().isNotEmpty),
              child: const Text('Simpan'),
            ),
          ],
        ),
      ),
    );
    if (ok == true) {
      setState(() {
        item.title = c.text.trim();
        item.status = status;
      });
      await _save();
    }
  }

  Future<void> _delete(CardItem item) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Hapus tugas?'),
        content: Text('Yakin ingin menghapus "${item.title}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => cards.remove(item));
    await _save();
    if (mounted)
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Tugas dihapus.')));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(title),
      actions: [
        IconButton(
          onPressed: _collaboratorDialog,
          icon: const Icon(Icons.group_add_outlined),
        ),
      ],
    ),
    floatingActionButton: FloatingActionButton(
      backgroundColor: blue,
      foregroundColor: Colors.white,
      onPressed: () => _add('1'),
      child: const Icon(Icons.note_add_outlined),
    ),
    body: loading
        ? const Center(child: CircularProgressIndicator())
        : ListView(
            padding: const EdgeInsets.all(16),
            children: ['1', '2', '3'].map(_section).toList(),
          ),
  );
  Widget _section(String status) {
    final list = cards.where((c) => c.status == status).toList();
    return DragTarget<CardItem>(
      onWillAcceptWithDetails: (details) => details.data.status != status,
      onAcceptWithDetails: (details) => _move(details.data, status),
      builder: (context, candidates, _) => Container(
        margin: const EdgeInsets.only(bottom: 14),
        decoration: BoxDecoration(
          color: candidates.isNotEmpty ? const Color(0xffeff6ff) : null,
          border: Border.all(
            color: candidates.isNotEmpty ? blue : _tone(status),
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              color: _tone(status),
              child: Row(
                children: [
                  Text(
                    _label(status),
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const Spacer(),
                  CircleAvatar(
                    radius: 10,
                    backgroundColor: Colors.white,
                    child: Text(
                      '${list.length}',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
            if (list.isEmpty)
              const _EmptyState(label: 'Tidak ada task', compact: true)
            else
              ...list.map(
                (item) => LongPressDraggable<CardItem>(
                  data: item,
                  feedback: Material(
                    color: Colors.transparent,
                    child: SizedBox(
                      width: 260,
                      child: Card(child: ListTile(title: Text(item.title))),
                    ),
                  ),
                  childWhenDragging: Opacity(
                    opacity: .35,
                    child: Card(
                      margin: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      elevation: 0,
                      color: const Color(0xfff8fafc),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(6),
                        side: const BorderSide(color: Color(0xffe2e8f0)),
                      ),
                      child: ListTile(dense: true, title: Text(item.title)),
                    ),
                  ),
                  child: Card(
                    margin: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    elevation: 0,
                    color: const Color(0xfff8fafc),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(6),
                      side: const BorderSide(color: Color(0xffe2e8f0)),
                    ),
                    child: ListTile(
                      dense: true,
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => TaskDetailPage(
                            card: item,
                            onChanged: _save,
                            onDelete: () async {
                              setState(() => cards.remove(item));
                              await _save();
                            },
                          ),
                        ),
                      ),
                      title: Text(item.title),
                      trailing: PopupMenuButton<String>(
                        onSelected: (v) {
                          if (v == 'edit') _edit(item);
                          if (v == 'delete') _delete(item);
                        },
                        itemBuilder: (_) => const [
                          PopupMenuItem(value: 'edit', child: Text('Edit')),
                          PopupMenuItem(value: 'delete', child: Text('Hapus')),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class TaskDetailPage extends StatefulWidget {
  final CardItem card;
  final Future<void> Function() onChanged;
  final Future<void> Function()? onDelete;
  const TaskDetailPage({
    super.key,
    required this.card,
    required this.onChanged,
    this.onDelete,
  });
  @override
  State<TaskDetailPage> createState() => _TaskDetailPageState();
}

class _TaskDetailPageState extends State<TaskDetailPage> {
  final input = TextEditingController();
  @override
  void dispose() {
    input.dispose();
    super.dispose();
  }

  Future<void> send({String? replyTo}) async {
    final text = input.text.trim();
    if (text.isEmpty) return;
    final author = currentUser.value?.name.trim() ?? '';
    setState(
      () => widget.card.comments.add(
        '$author\u001f${replyTo == null ? text : 'Balasan: $text'}',
      ),
    );
    input.clear();
    await widget.onChanged();
  }

  Future<void> edit() async {
    final controller = TextEditingController(text: widget.card.title);
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Edit tugas'),
        content: TextField(controller: controller),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(context, controller.text.trim().isNotEmpty),
            child: const Text('Simpan'),
          ),
        ],
      ),
    );
    if (ok == true) {
      setState(() => widget.card.title = controller.text.trim());
      await widget.onChanged();
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      leading: const BackButton(),
      title: Text(
        widget.card.title,
        style: const TextStyle(fontWeight: FontWeight.bold),
      ),
      centerTitle: true,
      actions: [
        IconButton(onPressed: edit, icon: const Icon(Icons.edit_outlined)),
        IconButton(
          onPressed: () async {
            final confirmed = await showDialog<bool>(
              context: context,
              builder: (_) => AlertDialog(
                title: const Text('Hapus tugas?'),
                content: Text('Yakin ingin menghapus "${widget.card.title}"?'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Batal'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('Hapus'),
                  ),
                ],
              ),
            );
            if (confirmed != true) return;
            if (widget.onDelete != null) await widget.onDelete!();
            if (mounted) Navigator.pop(context);
          },
          icon: const Icon(Icons.delete_outline, color: Colors.red),
        ),
      ],
    ),
    body: Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(18),
            children: [
              const Text('Komentar', style: TextStyle(fontSize: 20)),
              const SizedBox(height: 16),
              if (widget.card.comments.isEmpty)
                const _EmptyState(label: 'Belum ada komentar')
              else
                ...widget.card.comments.asMap().entries.map(
                  (entry) => _comment(entry.key, entry.value),
                ),
            ],
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: TextField(
              controller: input,
              onSubmitted: (_) => send(),
              decoration: InputDecoration(
                hintText: 'Typing...',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                suffixIcon: IconButton(
                  onPressed: send,
                  icon: const Icon(Icons.send_outlined),
                ),
              ),
            ),
          ),
        ),
      ],
    ),
  );
  Widget _comment(int index, String text) => Padding(
    padding: const EdgeInsets.only(bottom: 18),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CircleAvatar(
          radius: 16,
          backgroundColor: index.isEven ? blue : Colors.deepPurple,
          child: Text(
            _authorFor(text).isEmpty ? '?' : _authorFor(text)[0].toUpperCase(),
            style: const TextStyle(fontSize: 10, color: Colors.white),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_authorFor(text).isNotEmpty)
                Text(
                  _authorFor(text),
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              const SizedBox(height: 3),
              Text(_bodyFor(text)),
              TextButton(
                onPressed: () {
                  final author = _authorFor(text);
                  input.text = author.isEmpty ? '' : '@$author ';
                },
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(0, 28),
                ),
                child: const Text('Balas'),
              ),
            ],
          ),
        ),
      ],
    ),
  );
  String _authorFor(String text) =>
      text.contains('\u001f') ? text.split('\u001f').first : '';
  String _bodyFor(String text) => text.contains('\u001f')
      ? text.substring(text.indexOf('\u001f') + 1)
      : text;
}
