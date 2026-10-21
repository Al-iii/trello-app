import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:procode_trello/main.dart';

void main() {
  testWidgets('menampilkan halaman login PROCODE', (tester) async {
    await tester.pumpWidget(const ProCodeApp());
    expect(find.byType(Image), findsOneWidget);
    expect(find.text('Masuk'), findsOneWidget);
    expect(find.text('Masuk akun'), findsOneWidget);
    expect(find.text('Belum punya akun?'), findsOneWidget);
  });

  testWidgets('tombol daftar membuka form pendaftaran', (tester) async {
    await tester.pumpWidget(const ProCodeApp());
    await tester.tap(find.text('Daftar'));
    await tester.pumpAndSettle();
    expect(find.text('Daftar akun baru'), findsOneWidget);
    expect(find.byType(Image), findsOneWidget);
    expect(find.text('Nama lengkap'), findsOneWidget);
    expect(
      find.widgetWithText(TextField, 'Masukkan nama lengkap'),
      findsOneWidget,
    );
    expect(find.text('Sudah mempunyai akun?'), findsOneWidget);
    expect(find.text('Masuk'), findsOneWidget);
  });

  testWidgets('aksi modal ringkas dan sejajar', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DialogActionRow(
            onCancel: () {},
            onSubmit: () {},
            submitLabel: 'Simpan',
          ),
        ),
      ),
    );

    final cancelRect = tester.getRect(
      find.widgetWithText(OutlinedButton, 'Batal'),
    );
    final submitRect = tester.getRect(
      find.widgetWithText(FilledButton, 'Simpan'),
    );
    expect(cancelRect.top, submitRect.top);
    expect(cancelRect.height, submitRect.height);
    expect(submitRect.left, greaterThan(cancelRect.right));
  });
}
