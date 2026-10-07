import 'package:http/http.dart' as http;

/// Satu client dipakai ulang agar konfigurasi dan koneksi seluruh request API
/// konsisten. Cookie lintas origin sengaja tidak diaktifkan karena API saat ini
/// mengembalikan `Access-Control-Allow-Origin: *` tanpa izin credentials.
http.Client createHttpClient() => http.Client();
