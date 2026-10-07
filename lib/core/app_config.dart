import 'package:flutter/material.dart';

const apiBase = 'https://trelloapp.id/api';

Uri apiUri(String path, [Map<String, String>? query]) {
  final uri = Uri.parse('${apiBase.replaceFirst(RegExp(r'/$'), '')}/$path');
  return query == null ? uri : uri.replace(queryParameters: query);
}

// Palet warna utama mengikuti desain web/mobile.
const blue = Color(0xff2161f5);
const darkBlue = Color(0xff1e5bb8);
const pageBackground = Color(0xfff4f7fb);
const borderLight = Color(0xffdbe3f0);
const textDark = Color(0xff111827);
