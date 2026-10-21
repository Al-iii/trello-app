part of '../procode_app.dart';

final apiClient = createHttpClient();

class AuthService {
  static const storage = FlutterSecureStorage();
  Future<String?> token() async {
    final p = await SharedPreferences.getInstance();
    // Flutter Web memakai SharedPreferences sebagai localStorage. Prioritaskan
    // token ini karena selalu ditulis ulang saat login terbaru.
    final webToken = p.getString('access_token');
    if (webToken != null && webToken.isNotEmpty) {
      final secureToken = await storage.read(key: 'access_token');
      if (secureToken != webToken) {
        await storage.write(key: 'access_token', value: webToken);
      }
      return webToken;
    }

    // Fallback untuk Android/iOS ketika SharedPreferences belum memiliki token.
    final secureToken = await storage.read(key: 'access_token');
    if (secureToken != null && secureToken.isNotEmpty) {
      await p.setString('access_token', secureToken);
    }
    return secureToken;
  }

  Future<Map<String, String>> headers() async {
    final t = await token();
    if (t == null) throw Exception('Sesi login tidak ditemukan');
    return {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      'Authorization': 'Bearer ${t.trim()}',
      'X-Requested-With': 'XMLHttpRequest',
    };
  }

  /// Header yang sama persis dengan request GET /api/projects di project.js
  /// milik web. Dipisahkan agar percobaan ini tidak memengaruhi endpoint lain.
  Future<Map<String, String>> projectHeaders() async {
    final t = await token();
    if (t == null || t.trim().isEmpty) {
      throw Exception('Sesi login tidak ditemukan');
    }
    return {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer ${t.trim()}',
    };
  }

  Future<UserProfile?> currentProfile() async {
    final r = await apiClient.get(apiUri('auth/me'), headers: await headers());
    if (r.statusCode == 401 || r.statusCode == 403) return null;
    if (r.statusCode < 200 || r.statusCode >= 300) {
      throw Exception('Profil gagal dimuat (${r.statusCode})');
    }
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
    final r = await apiClient.post(
      apiUri('auth/login'),
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
        final r = await apiClient.get(
          apiUri('users'),
          headers: await headers(),
        );
        if (r.statusCode >= 200 && r.statusCode < 300) {
          final decoded = r.body.isEmpty ? <dynamic>[] : jsonDecode(r.body);
          // Backend web /api/users mengembalikan profil sederhana:
          // {"name": "..."}. Dukungan array tetap dipertahankan untuk
          // response API versi lama.
          if (decoded is Map && decoded['name'] != null) {
            u = UserProfile.fromJson({
              ...Map<String, dynamic>.from(decoded),
              'email': decoded['email'] ?? email,
            });
          }
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
    await p.setString('profile_id', u.id);
    return UserProfile(
      id: u.id,
      name: u.name.isEmpty ? email.split('@').first : u.name,
      email: u.email.isEmpty ? email : u.email,
    );
  }

  Future<void> register(String name, String email, String password) async {
    final r = await apiClient.post(
      apiUri('auth/register'),
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
    late final http.Response r;
    try {
      r = await apiClient.get(
        apiUri('projects'),
        headers: await projectHeaders(),
      );
    } on http.ClientException catch (error) {
      throw Exception(
        'Request project diblokir browser setelah server mengalihkan ke '
        '/login. Detail: ${error.message}',
      );
    }
    if (r.statusCode < 200 || r.statusCode >= 300) {
      final detail = r.body.trim();
      throw Exception(
        'Board gagal dimuat (${r.statusCode})${detail.isEmpty ? '' : ': $detail'}',
      );
    }

    final contentType = r.headers['content-type'] ?? '';
    if (!contentType.toLowerCase().contains('application/json')) {
      throw Exception('Server mengembalikan halaman web, bukan data project.');
    }

    final decoded = r.body.isEmpty ? <dynamic>[] : jsonDecode(r.body);
    if (decoded is Map && decoded['success'] == false) {
      throw Exception('${decoded['message'] ?? 'Project gagal dimuat'}');
    }
    final dynamic raw = decoded is List
        ? decoded
        : decoded is Map
        ? (decoded['data'] ?? decoded['projects'] ?? <dynamic>[])
        : <dynamic>[];

    if (raw is! List) return [];
    return raw
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  Future<Map<String, dynamic>> createProject(String name) async {
    final r = await apiClient.post(
      apiUri('projects'),
      headers: await headers(),
      body: jsonEncode({'nama_project': name}),
    );
    final j = _json(r);
    if (r.statusCode < 200 || r.statusCode >= 300)
      throw Exception('Board gagal dibuat');
    return Map<String, dynamic>.from(j['project'] ?? j['data'] ?? j);
  }

  Future<Map<String, dynamic>> projectDetails(String projectId) async {
    final r = await apiClient.get(
      apiUri('projects/${Uri.encodeComponent(projectId)}'),
      headers: await headers(),
    );
    if (r.statusCode < 200 || r.statusCode >= 300) {
      throw Exception('Detail project gagal dimuat (${r.statusCode})');
    }
    final contentType = r.headers['content-type'] ?? '';
    if (!contentType.toLowerCase().contains('application/json')) {
      throw Exception(
        'Server mengembalikan halaman web, bukan detail project.',
      );
    }
    final decoded = r.body.isEmpty ? <String, dynamic>{} : jsonDecode(r.body);
    if (decoded is! Map) return {};
    final raw = decoded['project'] ?? decoded['data'] ?? decoded;
    return raw is Map ? Map<String, dynamic>.from(raw) : {};
  }

  Future<Map<String, dynamic>> userById(String userId) async {
    final r = await apiClient.get(
      apiUri('users/${Uri.encodeComponent(userId)}'),
      headers: await headers(),
    );
    if (r.statusCode < 200 || r.statusCode >= 300) return {};
    final contentType = r.headers['content-type'] ?? '';
    if (!contentType.toLowerCase().contains('application/json')) return {};

    final decoded = r.body.isEmpty ? <String, dynamic>{} : jsonDecode(r.body);
    if (decoded is! Map) return {};
    final raw = decoded['user'] ?? decoded['data'] ?? decoded;
    if (raw is! Map) return {};
    final user = Map<String, dynamic>.from(raw);
    final returnedId =
        '${user['id'] ?? user['iduser'] ?? user['user_id'] ?? ''}'.trim();

    // Jangan pernah memakai profil akun aktif sebagai pemilik bila endpoint
    // mengabaikan parameter ID seperti implementasi /users lama.
    return returnedId == userId ? user : {};
  }

  Map<String, dynamic> _userIdentity(Map<String, dynamic> raw) {
    final nested = raw['user'] is Map
        ? Map<String, dynamic>.from(raw['user'])
        : <String, dynamic>{};
    final id =
        '${nested['id'] ?? nested['iduser'] ?? raw['user_id'] ?? raw['iduser'] ?? raw['id'] ?? ''}'
            .trim();
    return {
      'id': id,
      'name':
          '${nested['name'] ?? nested['nama'] ?? nested['alias'] ?? raw['name'] ?? raw['nama'] ?? raw['alias'] ?? raw['username'] ?? ''}'
              .trim(),
      'email': '${nested['email'] ?? raw['email'] ?? ''}'.trim(),
    };
  }

  Future<void> rememberUsers(Iterable<Map<String, dynamic>> users) async {
    final p = await SharedPreferences.getInstance();
    final stored = p.getString('known_user_profiles');
    final directory = stored == null
        ? <String, dynamic>{}
        : Map<String, dynamic>.from(jsonDecode(stored));
    for (final raw in users) {
      final user = _userIdentity(raw);
      final id = '${user['id']}';
      if (id.isEmpty ||
          ('${user['name']}'.isEmpty && '${user['email']}'.isEmpty)) {
        continue;
      }
      directory[id] = user;
    }
    await p.setString('known_user_profiles', jsonEncode(directory));
  }

  Future<Map<String, dynamic>> resolveUserById(String userId) async {
    final p = await SharedPreferences.getInstance();
    final stored = p.getString('known_user_profiles');
    if (stored != null) {
      final directory = Map<String, dynamic>.from(jsonDecode(stored));
      if (directory[userId] is Map) {
        return Map<String, dynamic>.from(directory[userId]);
      }
    }

    final direct = await userById(userId);
    if (direct.isNotEmpty) {
      await rememberUsers([direct]);
      return _userIdentity(direct);
    }

    // API tidak menyediakan profil berdasarkan ID. Cari project lain tempat
    // user tersebut menjadi kolaborator, lalu gunakan daftar anggota resminya.
    for (final project in await boardCache()) {
      final collaborators = project['collaborators'];
      if (collaborators is! List ||
          !collaborators.whereType<Map>().any(
            (item) => '${item['user_id'] ?? ''}' == userId,
          )) {
        continue;
      }
      final id = '${project['idproject'] ?? project['id'] ?? ''}';
      if (id.isEmpty) continue;
      try {
        final users = await projectUsers(id);
        await rememberUsers(users);
        for (final raw in users) {
          final identity = _userIdentity(raw);
          if ('${identity['id']}' == userId) return identity;
        }
      } catch (_) {
        // Coba project kandidat berikutnya bila endpoint ini tidak tersedia.
      }
    }
    return {};
  }

  /// Daftar seluruh pengguna project. Backend memakai `project` (singular),
  /// sama seperti endpoint invite; route plural mengarah ke halaman web/HTML.
  Future<List<Map<String, dynamic>>> projectUsers(String projectId) async {
    final r = await apiClient.get(
      apiUri('project/${Uri.encodeComponent(projectId)}/users'),
      headers: await headers(),
    );
    if (r.statusCode < 200 || r.statusCode >= 300) {
      throw Exception('Anggota project gagal dimuat (${r.statusCode})');
    }
    final contentType = r.headers['content-type'] ?? '';
    if (!contentType.toLowerCase().contains('application/json')) {
      throw Exception('Server mengembalikan halaman web, bukan data anggota.');
    }
    final decoded = r.body.isEmpty ? <dynamic>[] : jsonDecode(r.body);
    dynamic list = decoded;
    if (decoded is Map) {
      list =
          decoded['data'] ??
          decoded['users'] ??
          decoded['members'] ??
          decoded['collaborators'] ??
          <dynamic>[];
      if (list is Map) {
        list =
            list['users'] ??
            list['members'] ??
            list['collaborators'] ??
            <dynamic>[];
      }
    }
    if (list is! List) return [];
    return List<Map<String, dynamic>>.from(
      list.whereType<Map>().map((item) => Map<String, dynamic>.from(item)),
    );
  }

  Future<Map<String, dynamic>> checkProjectEmail(
    String projectId,
    String email,
  ) async {
    final r = await apiClient.post(
      apiUri('check-email'),
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
    final r = await apiClient.post(
      apiUri('project/${Uri.encodeComponent(projectId)}/invite'),
      headers: await headers(),
      body: jsonEncode({'email': email}),
    );
    final json = _json(r);
    if (r.statusCode < 200 || r.statusCode >= 300) {
      if (r.statusCode == 405) {
        throw Exception(
          'Route invite belum menerima POST. Pastikan '
          'POST /api/projects/{project}/invite sudah aktif di server.',
        );
      }
      throw Exception(
        '${json['message'] ?? 'Undangan gagal dikirim'} (${r.statusCode})',
      );
    }
    return json;
  }

  Future<void> updateProject(String id, String name) async {
    final r = await apiClient.put(
      apiUri('projects/${Uri.encodeComponent(id)}'),
      headers: await headers(),
      body: jsonEncode({'nama_project': name}),
    );
    if (r.statusCode < 200 || r.statusCode >= 300)
      throw Exception('Board gagal diperbarui');
  }

  Future<void> deleteProject(String id) async {
    final r = await apiClient.delete(
      apiUri('projects/${Uri.encodeComponent(id)}'),
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
                'members': c.members,
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
            members: List<String>.from(e['members'] ?? []),
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
                'dueDate': c.dueDate,
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
            dueDate: '${e['dueDate'] ?? ''}',
            comments: List<String>.from(e['comments'] ?? []),
          ),
        )
        .toList();
  }

  Future<List<Map<String, dynamic>>> tasks(String projectId) async {
    final r = await apiClient.get(
      apiUri('tasks', {'idproject': projectId}),
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

  /// Menjadikan API sebagai sumber utama untuk task yang sudah tersimpan di
  /// server, sambil mempertahankan metadata yang saat ini masih lokal
  /// (komentar, label, member, deskripsi/tenggat bila backend belum mengirimnya).
  Future<List<CardItem>> syncedProjectCards(String projectId) async {
    final cached = await cardCache(projectId);
    final cachedById = {for (final card in cached) card.id: card};
    final remote = await tasks(projectId);

    String textFrom(
      Map<String, dynamic> row,
      List<String> keys,
      String fallback,
    ) {
      for (final key in keys) {
        final value = row[key];
        if (value != null) return '$value';
      }
      return fallback;
    }

    List<String> stringsFrom(
      Map<String, dynamic> row,
      String key,
      List<String> fallback,
    ) {
      final value = row[key];
      if (value is List && value.every((item) => item is String)) {
        return List<String>.from(value);
      }
      return List<String>.from(fallback);
    }

    final synced = <CardItem>[];
    for (final row in remote) {
      final taskId = textFrom(row, ['idtask', 'id'], '').trim();
      if (taskId.isEmpty) continue;
      final local = cachedById[taskId];
      synced.add(
        CardItem(
          id: taskId,
          title: textFrom(row, ['nama_task', 'title'], local?.title ?? 'Task'),
          description: textFrom(row, [
            'deskripsi',
            'description',
          ], local?.description ?? ''),
          status: textFrom(row, ['status'], local?.status ?? '1'),
          dueDate: textFrom(row, ['due_date', 'dueDate'], local?.dueDate ?? ''),
          labels: stringsFrom(row, 'labels', local?.labels ?? const []),
          members: stringsFrom(row, 'members', local?.members ?? const []),
          comments: stringsFrom(row, 'comments', local?.comments ?? const []),
        ),
      );
    }

    // Data lama ber-ID server yang tidak lagi dikirim API dianggap sudah
    // dihapus melalui web. Hanya task lokal yang belum tersinkron dipertahankan.
    synced.addAll(cached.where((card) => card.id.startsWith('local_')));
    await saveCardCache(projectId, synced);
    return synced;
  }

  Future<List<Map<String, dynamic>>> unassignedTasks() async {
    // Endpoint ini memang dipakai oleh web untuk memuat Task List/inbox.
    final r = await apiClient.get(
      apiUri('tasks', {'unassigned': '1'}),
      headers: await headers(),
    );
    if (r.statusCode < 200 || r.statusCode >= 300) {
      final detail = r.body.trim();
      throw Exception(
        'Task list gagal dimuat (${r.statusCode})${detail.isEmpty ? '' : ': $detail'}',
      );
    }

    final decoded = r.body.isEmpty ? <dynamic>[] : jsonDecode(r.body);
    final dynamic raw = decoded is List
        ? decoded
        : decoded is Map
        ? (decoded['data'] ?? decoded['tasks'] ?? <dynamic>[])
        : <dynamic>[];
    if (raw is! List) return [];
    return raw
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  Future<String> createTask(
    String name,
    String projectId, {
    String status = '1',
    String description = '',
    String dueDate = '',
  }) async {
    final r = await apiClient.post(
      apiUri('tasks'),
      headers: await headers(),
      body: jsonEncode({
        'nama_task': name,
        'status': status,
        'idproject': projectId,
        'deskripsi': description,
        'due_date': dueDate.isEmpty ? null : dueDate,
      }),
    );
    final j = _json(r);
    if (r.statusCode < 200 || r.statusCode >= 300) {
      throw Exception(
        '${j['message'] ?? j['error'] ?? 'Task gagal dibuat'} '
        '(${r.statusCode})',
      );
    }
    final rawTask = j['task'] ?? j['data'] ?? j;
    final task = rawTask is Map
        ? Map<String, dynamic>.from(rawTask)
        : <String, dynamic>{};
    final id = '${task['idtask'] ?? task['id'] ?? ''}'.trim();
    if (id.isEmpty) {
      throw Exception('Server tidak mengembalikan ID task yang dibuat');
    }
    return id;
  }

  Future<void> updateTask(CardItem c, String projectId) async {
    final uri = apiUri('tasks/${Uri.encodeComponent(c.id)}');
    final body = jsonEncode({
      'nama_task': c.title,
      'status': c.status,
      'idproject': projectId,
      'deskripsi': c.description,
      'due_date': c.dueDate.isEmpty ? null : c.dueDate,
    });
    final h = await headers();
    var r = await apiClient.put(uri, headers: h, body: body);
    if (r.statusCode < 200 || r.statusCode >= 300) {
      r = await apiClient.patch(uri, headers: h, body: body);
    }
    if (r.statusCode < 200 || r.statusCode >= 300) {
      final detail = r.body.trim();
      throw Exception(
        'Card gagal diperbarui (${r.statusCode})${detail.isEmpty ? '' : ': $detail'}',
      );
    }
  }

  Future<void> deleteTask(String id) async {
    final r = await apiClient.delete(
      apiUri('tasks/${Uri.encodeComponent(id)}'),
      headers: await headers(),
    );
    if (r.statusCode < 200 || r.statusCode >= 300) {
      throw Exception('Card gagal dihapus (${r.statusCode})');
    }
  }

  Future<void> logout() async {
    try {
      await apiClient.post(apiUri('auth/logout'), headers: await headers());
    } catch (_) {
      // Session lokal tetap dihapus walaupun server tidak dapat dihubungi.
    }
    await storage.delete(key: 'access_token');
    final p = await SharedPreferences.getInstance();
    // Cache workspace dipertahankan agar data lokal tetap tersedia setelah
    // pengguna masuk kembali. Hanya data yang mengidentifikasi sesi dihapus.
    await p.remove('profile_name');
    await p.remove('profile_email');
    await p.remove('profile_id');
    await p.remove('access_token');
  }

  Map<String, dynamic> _json(http.Response r) =>
      r.body.isEmpty ? {} : Map<String, dynamic>.from(jsonDecode(r.body));
}

final auth = AuthService();
final currentUser = ValueNotifier<UserProfile?>(null);
