import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:procode_trello/main.dart';

void main() {
  testWidgets('menampilkan halaman login PROCODE', (tester) async {
    await tester.pumpWidget(const ProCodeApp());
    expect(find.byType(Image), findsOneWidget);
    expect(find.text('Masuk'), findsOneWidget);
    expect(find.text('Project management workspace'), findsOneWidget);
  });

  testWidgets('tombol daftar membuka form pendaftaran', (tester) async {
    await tester.pumpWidget(const ProCodeApp());
    await tester.tap(find.text('Belum punya akun? Daftar'));
    await tester.pumpAndSettle();
    expect(find.text('Daftar akun baru'), findsOneWidget);
    expect(find.text('Nama lengkap'), findsOneWidget);
  });
}
