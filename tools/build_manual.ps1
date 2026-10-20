$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

$root = 'E:\kuliah\Project'
$assets = Join-Path $root 'manual_assets'
$output = Join-Path $root 'ManualBookMobile.docx'
$pdfOutput = Join-Path $root 'manual_render_check.pdf'

$wdStyleNormal = -1
$wdStyleHeading1 = -2
$wdStyleHeading2 = -3
$wdStyleHeading3 = -4
$wdStyleCaption = -35
$wdAlignLeft = 0
$wdAlignCenter = 1
$wdPageBreak = 7
$wdCollapseEnd = 0
$wdFieldPage = 33
$wdFieldNumPages = 26
$wdExportFormatPDF = 17
$wdPaperA4 = 7
$wdOutlineNumberGallery = 3
$wdListApplyToWholeList = 0
$wdListBehaviorWord10 = 2
$wdColorBlue = 16081185
$wdColorGray = 7566195

function Set-RangeFont($range, [double]$size, [bool]$bold=$false, [bool]$italic=$false, [int]$color=0) {
    $range.Font.Name = 'Calibri'
    $range.Font.NameAscii = 'Calibri'
    try { $range.Font.NameFarEast = 'Calibri' } catch { }
    $range.Font.Size = $size
    $range.Font.Bold = if ($bold) { -1 } else { 0 }
    $range.Font.Italic = if ($italic) { -1 } else { 0 }
    if ($color -ne 0) { $range.Font.Color = $color }
}

function Add-RawParagraph($doc, [string]$text='') {
    $insert = $doc.Range($doc.Content.End - 1, $doc.Content.End - 1)
    $insert.InsertAfter($text + "`r")
    return $doc.Paragraphs.Item($doc.Paragraphs.Count - 1)
}

function Add-Paragraph($doc, [string]$text, [double]$size=11, [bool]$bold=$false, [bool]$italic=$false, [int]$align=0, [double]$after=6) {
    $p = Add-RawParagraph $doc $text
    Set-RangeFont $p.Range $size $bold $italic
    $p.Alignment = $align
    $p.LineSpacingRule = 5
    $p.LineSpacing = 13.8
    $p.SpaceAfter = $after
    $p.SpaceBefore = 0
    return $p
}

function Add-Heading($doc, [string]$text, [int]$level=1) {
    $p = Add-RawParagraph $doc $text
    if ($level -eq 1) { $p.Range.Style = $wdStyleHeading1 }
    elseif ($level -eq 2) { $p.Range.Style = $wdStyleHeading2 }
    else { $p.Range.Style = $wdStyleHeading3 }
    if ($level -le 2 -and $script:outlineTemplate) {
        $p.Range.ListFormat.ApplyListTemplateWithLevel($script:outlineTemplate, $true, $wdListApplyToWholeList, $wdListBehaviorWord10, $level)
    }
    $p.KeepWithNext = -1
    return $p
}

function Add-Steps($doc, [string[]]$steps) {
    $stepIndex = 0
    foreach ($step in $steps) {
        $p = Add-RawParagraph $doc $step
        $p.Range.Style = $wdStyleNormal
        Set-RangeFont $p.Range 11 $false $false
        $p.LineSpacingRule = 5
        $p.LineSpacing = 13.8
        $p.SpaceAfter = 6
        $p.OutlineLevel = 10
        $continueList = $stepIndex -gt 0
        $p.Range.ListFormat.ApplyListTemplateWithLevel($script:stepTemplate, $continueList, $wdListApplyToWholeList, $wdListBehaviorWord10, 1)
        $stepIndex++
    }
}

function Add-Bullets($doc, [string[]]$items) {
    foreach ($item in $items) {
        $p = Add-RawParagraph $doc $item
        $p.Range.Style = $wdStyleNormal
        Set-RangeFont $p.Range 11 $false $false
        $p.LineSpacingRule = 5
        $p.LineSpacing = 13.8
        $p.SpaceAfter = 6
        $p.Range.ListFormat.ApplyBulletDefault()
    }
}

function Add-Figure($doc, [string]$fileName, [string]$caption, [double]$widthCm=14.8) {
    $path = Join-Path $assets $fileName
    if (-not (Test-Path -LiteralPath $path)) { throw "Gambar tidak ditemukan: $path" }
    $bitmap = [System.Drawing.Image]::FromFile($path)
    try {
        if ($bitmap.Height -gt $bitmap.Width) { $widthCm = 7.2 }
    }
    finally { $bitmap.Dispose() }
    $p = Add-RawParagraph $doc ''
    $p.Alignment = $wdAlignCenter
    $p.KeepWithNext = -1
    $shape = $p.Range.InlineShapes.AddPicture($path, $false, $true)
    $shape.LockAspectRatio = -1
    $shape.Width = $word.CentimetersToPoints($widthCm)
    $cap = Add-RawParagraph $doc $caption
    $cap.Range.Style = $wdStyleCaption
    Set-RangeFont $cap.Range 10 $false $true $wdColorGray
    $cap.Alignment = $wdAlignCenter
    $cap.SpaceAfter = 10
    $cap.KeepWithNext = 0
}

function Add-Note($doc, [string]$text) {
    $p = Add-RawParagraph $doc "Catatan: $text"
    Set-RangeFont $p.Range 11 $false $true
    $p.LeftIndent = 12
    $p.RightIndent = 12
    $p.SpaceBefore = 4
    $p.SpaceAfter = 8
    $p.Range.Shading.BackgroundPatternColor = 15461355
}

function Add-PageBreak($doc) {
    $r = $doc.Range($doc.Content.End - 1, $doc.Content.End - 1)
    $r.InsertBreak($wdPageBreak)
}

$word = New-Object -ComObject Word.Application
$word.Visible = $false
$word.DisplayAlerts = 0
$word.Options.Pagination = $true
$doc = $null

try {
    Write-Host 'PROGRESS initializing-docx'
    if (Test-Path -LiteralPath $output) {
        $doc = $word.Documents.Open($output)
        $doc.Content.Delete() | Out-Null
    }
    else {
        $doc = $word.Documents.Add()
        $doc.SaveAs2($output)
    }
    $setup = $doc.PageSetup
    $setup.PaperSize = $wdPaperA4
    $setup.TopMargin = $word.CentimetersToPoints(2.5)
    $setup.BottomMargin = $word.CentimetersToPoints(2.5)
    $setup.LeftMargin = $word.CentimetersToPoints(2.5)
    $setup.RightMargin = $word.CentimetersToPoints(2.5)
    $setup.HeaderDistance = $word.CentimetersToPoints(1.25)
    $setup.FooterDistance = $word.CentimetersToPoints(1.25)
    $setup.DifferentFirstPageHeaderFooter = -1

    $normal = $doc.Styles.Item($wdStyleNormal)
    Set-RangeFont $normal 11 $false $false
    $normal.ParagraphFormat.Alignment = $wdAlignLeft
    $normal.ParagraphFormat.LineSpacingRule = 5
    $normal.ParagraphFormat.LineSpacing = 13.8
    $normal.ParagraphFormat.SpaceAfter = 6

    $h1 = $doc.Styles.Item($wdStyleHeading1)
    Set-RangeFont $h1 16 $true $false $wdColorBlue
    $h1.ParagraphFormat.SpaceBefore = 12
    $h1.ParagraphFormat.SpaceAfter = 8
    $h1.ParagraphFormat.KeepWithNext = -1
    $h1.ParagraphFormat.OutlineLevel = 1
    $h2 = $doc.Styles.Item($wdStyleHeading2)
    Set-RangeFont $h2 13 $true $false $wdColorBlue
    $h2.ParagraphFormat.SpaceBefore = 10
    $h2.ParagraphFormat.SpaceAfter = 6
    $h2.ParagraphFormat.KeepWithNext = -1
    $h2.ParagraphFormat.OutlineLevel = 2
    $h3 = $doc.Styles.Item($wdStyleHeading3)
    Set-RangeFont $h3 13 $true $false $wdColorBlue

    $outline = $doc.ListTemplates.Add($true, ('ManualOutline_' + [guid]::NewGuid().ToString('N')))
    $outline.ListLevels.Item(1).NumberFormat = '%1.'
    $outline.ListLevels.Item(1).NumberStyle = 0
    $outline.ListLevels.Item(1).StartAt = 1
    $outline.ListLevels.Item(1).TrailingCharacter = 0
    $outline.ListLevels.Item(1).NumberPosition = 0
    $outline.ListLevels.Item(1).TextPosition = $word.CentimetersToPoints(1.25)
    $outline.ListLevels.Item(1).TabPosition = $word.CentimetersToPoints(1.25)
    $outline.ListLevels.Item(2).NumberFormat = '%1.%2'
    $outline.ListLevels.Item(2).NumberStyle = 0
    $outline.ListLevels.Item(2).StartAt = 1
    $outline.ListLevels.Item(2).ResetOnHigher = 1
    $outline.ListLevels.Item(2).TrailingCharacter = 0
    $outline.ListLevels.Item(2).NumberPosition = $word.CentimetersToPoints(0.5)
    $outline.ListLevels.Item(2).TextPosition = $word.CentimetersToPoints(1.5)
    $outline.ListLevels.Item(2).TabPosition = $word.CentimetersToPoints(1.5)
    $h1.LinkToListTemplate($outline, 1)
    $h2.LinkToListTemplate($outline, 2)
    $script:outlineTemplate = $outline

    $script:stepTemplate = $doc.ListTemplates.Add($false, ('ManualSteps_' + [guid]::NewGuid().ToString('N')))
    $script:stepTemplate.ListLevels.Item(1).NumberFormat = '%1.'
    $script:stepTemplate.ListLevels.Item(1).NumberStyle = 0
    $script:stepTemplate.ListLevels.Item(1).StartAt = 1
    $script:stepTemplate.ListLevels.Item(1).TrailingCharacter = 0
    $script:stepTemplate.ListLevels.Item(1).NumberPosition = 0
    $script:stepTemplate.ListLevels.Item(1).TextPosition = $word.CentimetersToPoints(0.75)
    $script:stepTemplate.ListLevels.Item(1).TabPosition = $word.CentimetersToPoints(0.75)

    $header = $doc.Sections.Item(1).Headers.Item(1).Range
    $header.Text = 'USER MANUAL  |  PROCODE TRELLO'
    Set-RangeFont $header 9 $false $false $wdColorGray
    $header.ParagraphFormat.Alignment = $wdAlignLeft
    $footer = $doc.Sections.Item(1).Footers.Item(1).Range
    $footer.Text = 'PROCODE Trello  |  Halaman '
    Set-RangeFont $footer 9 $false $false $wdColorGray
    $footer.ParagraphFormat.Alignment = $wdAlignCenter
    $footer.Collapse($wdCollapseEnd)
    $doc.Fields.Add($footer, $wdFieldPage) | Out-Null

    # Cover
    Write-Host 'PROGRESS cover'
    $spacer = Add-Paragraph $doc '' 11 $false $false $wdAlignCenter 0
    $spacer.SpaceBefore = 90
    $logoP = Add-RawParagraph $doc ''
    $logoP.Alignment = $wdAlignCenter
    $logo = $logoP.Range.InlineShapes.AddPicture((Join-Path $root 'assets\procode_logo.png'), $false, $true)
    $logo.LockAspectRatio = -1
    $logo.Width = $word.CentimetersToPoints(7.5)
    $logoP.SpaceAfter = 30
    $title = Add-Paragraph $doc 'USER MANUAL' 28 $true $false $wdAlignCenter 8
    $subtitle = Add-Paragraph $doc 'APLIKASI PROCODE TRELLO' 20 $true $false $wdAlignCenter 18
    $tagline = Add-Paragraph $doc 'Panduan lengkap penggunaan aplikasi dari registrasi hingga logout' 13 $false $false $wdAlignCenter 60
    $meta = Add-Paragraph $doc "Versi Aplikasi 1.0.0`r15 Oktober 2026" 11 $false $false $wdAlignCenter 6
    Add-PageBreak $doc

    # TOC
    Write-Host 'PROGRESS toc'
    Add-Paragraph $doc 'Daftar Isi' 16 $true $false $wdAlignLeft 6 | Out-Null
    $tocRange = $doc.Range($doc.Content.End - 1, $doc.Content.End - 1)
    $toc = $doc.TablesOfContents.Add($tocRange, $true, 1, 2, $false, '', $true, $true, '', $true, $true, $false)
    Add-PageBreak $doc

    Add-Heading $doc 'Pendahuluan' 1 | Out-Null
    Write-Host 'PROGRESS content-start'
    Add-Heading $doc 'Tentang Aplikasi' 2 | Out-Null
    Add-Paragraph $doc 'PROCODE Trello adalah aplikasi pengelolaan proyek dan tugas berbasis Kanban. Pengguna dapat membuat tugas pribadi, membuat proyek, mengundang kolaborator, memindahkan tugas berdasarkan status pekerjaan, serta berdiskusi melalui komentar.' | Out-Null
    Add-Heading $doc 'Tujuan Manual' 2 | Out-Null
    Add-Paragraph $doc 'Manual ini memandu pengguna mengikuti alur aplikasi secara berurutan, mulai dari membuat akun, masuk, mengelola pekerjaan, berkolaborasi, sampai keluar dari aplikasi.' | Out-Null
    Add-Heading $doc 'Kebutuhan Penggunaan' 2 | Out-Null
    Add-Bullets $doc @('Perangkat komputer atau perangkat seluler yang mendukung aplikasi.', 'Koneksi internet aktif untuk autentikasi dan sinkronisasi data.', 'Alamat email yang unik untuk setiap akun pengguna.', 'Password minimal delapan karakter.')
    Add-Note $doc 'Seluruh tangkapan layar pada manual ini menggunakan layout mobile portrait 390 x 844 piksel. Nama tombol dan urutan fungsi tetap sama pada ukuran layar lain.'

    Add-Heading $doc 'Registrasi Akun' 1 | Out-Null
    Add-Paragraph $doc 'Registrasi dilakukan satu kali untuk memperoleh akun yang dapat digunakan masuk ke aplikasi.' | Out-Null
    Add-Heading $doc 'Membuka Halaman Registrasi' 2 | Out-Null
    Add-Steps $doc @('Buka aplikasi PROCODE Trello.', 'Pada halaman Masuk, pilih Belum punya akun? Daftar.', 'Pastikan halaman Daftar akun baru tampil.')
    Add-Figure $doc '02_register.png' 'Gambar 1. Halaman registrasi akun.'
    Add-Heading $doc 'Mengisi Data Registrasi' 2 | Out-Null
    Add-Steps $doc @('Isi Nama lengkap.', 'Masukkan alamat Email yang belum digunakan.', 'Masukkan Password minimal delapan karakter.', 'Ulangi password pada Konfirmasi password.', 'Pilih Daftar dan tunggu notifikasi bahwa akun berhasil dibuat.')
    Add-Figure $doc '03_register_filled.png' 'Gambar 2. Contoh pengisian formulir registrasi dengan data uji.'
    Add-Note $doc 'Gunakan alamat email dan password milik sendiri. Data pada gambar merupakan data uji.'

    Add-Heading $doc 'Login ke Aplikasi' 1 | Out-Null
    Add-Steps $doc @('Masukkan email akun yang telah didaftarkan.', 'Masukkan password.', 'Pilih Masuk.', 'Tunggu hingga halaman Dashboard ditampilkan.')
    Add-Figure $doc '06_login_filled.png' 'Gambar 3. Form login yang telah diisi.'
    Add-Heading $doc 'Penanganan Login Gagal' 2 | Out-Null
    Add-Bullets $doc @('Pastikan email dan password tidak kosong.', 'Periksa kembali ejaan email dan penggunaan huruf besar/kecil pada password.', 'Pastikan koneksi internet tersedia.', 'Hubungi pengelola aplikasi apabila akun tetap tidak dapat digunakan.')

    Add-Heading $doc 'Mengenal Dashboard' 1 | Out-Null
    Add-Paragraph $doc 'Dashboard menampilkan Task List, Project List, pencarian proyek, filter, identitas pengguna, dan tombol tambah di kanan bawah.' | Out-Null
    Add-Figure $doc '07_dashboard_empty.png' 'Gambar 4. Dashboard awal setelah login.'
    Add-Heading $doc 'Menu Tambah' 2 | Out-Null
    Add-Steps $doc @('Pilih tombol tambah (+) di kanan bawah.', 'Pilih Tugas untuk membuat tugas.', 'Pilih Project untuk membuat proyek.')
    Add-Figure $doc '08_add_menu.png' 'Gambar 5. Pilihan penambahan tugas atau proyek.'
    Add-Heading $doc 'Pencarian dan Filter Proyek' 2 | Out-Null
    Add-Paragraph $doc 'Gunakan kolom Cari project untuk menyaring proyek berdasarkan nama. Ikon filter di sisi kanan digunakan untuk memilih kelompok status yang ingin ditampilkan.' | Out-Null

    Add-Heading $doc 'Membuat Tugas Tanpa Proyek' 1 | Out-Null
    Add-Steps $doc @('Buka menu tambah dan pilih Tugas.', 'Isi Nama Tugas.', 'Isi Deskripsi apabila diperlukan.', 'Pilih Tenggat tanggal dan waktu untuk menentukan batas pekerjaan.', 'Biarkan Project pada Tanpa project (Task List).', 'Pilih Tambah.')
    Add-Figure $doc '09_create_task_dialog.png' 'Gambar 6. Form pembuatan tugas baru.'
    Add-Heading $doc 'Menentukan Tenggat' 2 | Out-Null
    Add-Paragraph $doc 'Pemilihan tenggat dilakukan dalam dua tahap, yaitu memilih tanggal kemudian waktu.' | Out-Null
    Add-Figure $doc '10_date_picker.png' 'Gambar 7. Pemilihan tanggal tenggat.' 12.5
    Add-Figure $doc '11_time_picker.png' 'Gambar 8. Pemilihan waktu tenggat.' 12.5
    Add-Heading $doc 'Melihat Task List' 2 | Out-Null
    Add-Paragraph $doc 'Tugas tanpa proyek muncul pada bagian Task List. Pilih nama tugas untuk membuka detail atau gunakan menu Aksi tugas untuk mengedit dan menghapus.' | Out-Null
    Add-Figure $doc '13_task_list.png' 'Gambar 9. Tugas berhasil ditambahkan ke Task List.'

    Add-Heading $doc 'Membuat dan Mengelola Proyek' 1 | Out-Null
    Write-Host 'PROGRESS project-section'
    Add-Heading $doc 'Membuat Proyek' 2 | Out-Null
    Add-Steps $doc @('Buka menu tambah dan pilih Project.', 'Masukkan Nama Project.', 'Pilih Buat Project.', 'Pastikan proyek baru muncul pada Project List.')
    Add-Figure $doc '15_project_filled.png' 'Gambar 10. Form pembuatan proyek.' 12.5
    Add-Figure $doc '16_dashboard_project.png' 'Gambar 11. Proyek berhasil ditambahkan pada dashboard.'
    Add-Heading $doc 'Aksi Proyek' 2 | Out-Null
    Add-Bullets $doc @('Buka halaman project: menampilkan papan Kanban.', 'Edit: mengubah nama proyek.', 'Bagikan: membagikan informasi proyek melalui fasilitas berbagi perangkat.', 'Hapus: menghapus proyek setelah konfirmasi.')

    Add-Heading $doc 'Menambahkan Kolaborator' 1 | Out-Null
    Add-Steps $doc @('Buka halaman proyek.', 'Pilih ikon anggota di kanan atas.', 'Masukkan email pengguna yang sudah terdaftar.', 'Pilih Undang.', 'Pastikan nama atau email anggota ditampilkan dan muncul pesan berhasil.')
    Add-Figure $doc '18_members_dialog.png' 'Gambar 12. Dialog undangan kolaborator.'
    Add-Figure $doc '20_invite_result.png' 'Gambar 13. Kolaborator berhasil ditambahkan.'
    Add-Note $doc 'Kolaborator harus memiliki akun terdaftar. Email yang tidak ditemukan tidak dapat diundang.'

    Add-Heading $doc 'Membuat Tugas dalam Proyek' 1 | Out-Null
    Add-Steps $doc @('Buka halaman proyek.', 'Pilih tombol tambah (+).', 'Isi Judul tugas dan Deskripsi.', 'Tentukan tenggat apabila diperlukan.', 'Pilih Tambah. Tugas baru ditempatkan pada kolom To Do.')
    Add-Figure $doc '22_project_task_filled.png' 'Gambar 14. Pengisian tugas di dalam proyek.'
    Add-Figure $doc '23_board_todo.png' 'Gambar 15. Tugas baru pada status To Do.'

    Add-Heading $doc 'Menggunakan Papan Kanban' 1 | Out-Null
    Write-Host 'PROGRESS kanban-section'
    Add-Paragraph $doc 'Papan Kanban terdiri dari tiga status: To Do untuk pekerjaan yang belum dimulai, In Progress untuk pekerjaan yang sedang dikerjakan, dan Done untuk pekerjaan yang telah selesai.' | Out-Null
    Add-Heading $doc 'Memindahkan Status Tugas' 2 | Out-Null
    Add-Steps $doc @('Tekan dan tahan kartu tugas.', 'Seret kartu menuju kolom status tujuan.', 'Lepaskan kartu pada area kolom.', 'Pastikan jumlah tugas dan posisi kartu telah berubah.')
    Add-Figure $doc '29_board_in_progress.png' 'Gambar 16. Tugas dipindahkan ke In Progress.'
    Add-Figure $doc '30_board_done.png' 'Gambar 17. Tugas dipindahkan ke Done.'
    Add-Note $doc 'Jika pemindahan gagal disimpan ke server, aplikasi mengembalikan tugas ke status sebelumnya dan menampilkan pesan kesalahan.'

    Add-Heading $doc 'Detail dan Pengeditan Tugas' 1 | Out-Null
    Add-Heading $doc 'Membuka Detail Tugas' 2 | Out-Null
    Add-Steps $doc @('Pilih kartu tugas pada papan Kanban.', 'Periksa judul, deskripsi, tenggat, serta komentar.', 'Gunakan ikon Edit tugas untuk mengubah informasi.', 'Gunakan ikon Hapus tugas untuk menghapus setelah konfirmasi.')
    Add-Figure $doc '24_task_detail.png' 'Gambar 18. Halaman detail tugas.'
    Add-Heading $doc 'Mengedit Tugas' 2 | Out-Null
    Add-Paragraph $doc 'Pada dialog Edit tugas, pengguna dapat mengubah judul, deskripsi, dan tenggat. Pilih Simpan untuk menerapkan perubahan atau Batal untuk kembali tanpa menyimpan.' | Out-Null
    Add-Figure $doc '28_edit_task_dialog.png' 'Gambar 19. Dialog pengeditan tugas.' 12.5
    Add-Heading $doc 'Menghapus Tugas' 2 | Out-Null
    Add-Steps $doc @('Buka detail tugas atau menu Aksi tugas.', 'Pilih Hapus.', 'Baca nama tugas pada dialog konfirmasi.', 'Pilih Hapus untuk melanjutkan atau Batal untuk mempertahankan tugas.')

    Add-Heading $doc 'Menggunakan Komentar' 1 | Out-Null
    Add-Heading $doc 'Menambahkan Komentar' 2 | Out-Null
    Add-Steps $doc @('Buka detail tugas.', 'Ketik pesan pada kolom Tulis komentar.', 'Pilih tombol kirim.', 'Komentar tampil bersama nama pengguna. Tautan yang valid dapat dibuka dari komentar.')
    Add-Figure $doc '25_comment.png' 'Gambar 20. Komentar dengan tautan pada detail tugas.'
    Add-Heading $doc 'Membalas Komentar' 2 | Out-Null
    Add-Steps $doc @('Pilih Balas pada komentar yang dituju.', 'Pastikan indikator Membalas menampilkan nama pengguna.', 'Ketik balasan dan pilih tombol kirim.', 'Balasan ditampilkan sebagai bagian dari percakapan.')
    Add-Figure $doc '26_reply_mode.png' 'Gambar 21. Mode membalas komentar.'
    Add-Figure $doc '27_reply_added.png' 'Gambar 22. Balasan berhasil ditambahkan.'

    Add-Heading $doc 'Melihat Profil Pengguna' 1 | Out-Null
    Add-Steps $doc @('Buka menu akun di kanan atas dashboard.', 'Pilih Profil.', 'Periksa inisial, nama, email, dan status akun.', 'Pilih tombol kembali untuk kembali ke dashboard.')
    Add-Figure $doc '31_account_menu.png' 'Gambar 23. Menu akun.'
    Add-Figure $doc '32_profile.png' 'Gambar 24. Informasi profil pengguna.'

    Add-Heading $doc 'Logout dari Aplikasi' 1 | Out-Null
    Add-Steps $doc @('Buka menu akun di kanan atas.', 'Pilih Log out.', 'Pada dialog konfirmasi, pilih Log out.', 'Pastikan aplikasi kembali ke halaman Masuk.')
    Add-Figure $doc '33_logout_confirm.png' 'Gambar 25. Konfirmasi logout.' 12.5
    Add-Figure $doc '34_logout_complete.png' 'Gambar 26. Halaman login setelah logout.'

    Add-Heading $doc 'Penanganan Masalah' 1 | Out-Null
    Add-Heading $doc 'Registrasi atau Login Gagal' 2 | Out-Null
    Add-Bullets $doc @('Lengkapi seluruh kolom wajib.', 'Gunakan password minimal delapan karakter dan konfirmasi yang sama.', 'Gunakan email yang belum pernah terdaftar.', 'Periksa koneksi internet lalu coba kembali.')
    Add-Heading $doc 'Proyek atau Tugas Gagal Dimuat' 2 | Out-Null
    Add-Bullets $doc @('Gunakan Muat ulang apabila tombol tersedia.', 'Keluar dan masuk kembali untuk memperbarui sesi.', 'Pastikan server aplikasi dapat diakses.', 'Jangan mengulangi penghapusan sebelum status data dipastikan.')
    Add-Heading $doc 'Undangan Anggota Gagal' 2 | Out-Null
    Add-Bullets $doc @('Pastikan email ditulis dengan benar.', 'Pastikan pengguna tujuan sudah melakukan registrasi.', 'Pastikan pengguna belum menjadi anggota proyek.', 'Coba kembali setelah koneksi stabil.')

    Add-Heading $doc 'Ringkasan Ikon dan Kontrol' 1 | Out-Null
    Write-Host 'PROGRESS tables'
    $table = $doc.Tables.Add($doc.Range($doc.Content.End - 1, $doc.Content.End - 1), 1, 3)
    $table.Borders.Enable = 1
    $table.AllowAutoFit = $false
    $table.Cell(1,1).Range.Text = 'Kontrol'
    $table.Cell(1,2).Range.Text = 'Lokasi'
    $table.Cell(1,3).Range.Text = 'Fungsi'
    $iconRows = @(
        @('Tombol +','Dashboard/Papan','Membuka pilihan pembuatan data.'),
        @('Kaca pembesar','Dashboard','Mencari proyek berdasarkan nama.'),
        @('Filter','Dashboard','Memilih status yang ditampilkan.'),
        @('Menu tiga titik','Tugas/Proyek','Membuka aksi edit, hapus, atau bagikan.'),
        @('Ikon anggota','Papan proyek','Melihat dan mengundang kolaborator.'),
        @('Ikon pensil','Detail tugas','Membuka pengeditan tugas.'),
        @('Ikon tempat sampah','Detail tugas','Menghapus tugas dengan konfirmasi.'),
        @('Panah kirim','Komentar','Mengirim komentar atau balasan.')
    )
    foreach ($row in $iconRows) {
        $cells = $table.Rows.Add().Cells
        for ($i=1; $i -le 3; $i++) { $cells.Item($i).Range.Text = $row[$i-1] }
    }
    $table.Columns.Item(1).Width = $word.CentimetersToPoints(3.2)
    $table.Columns.Item(2).Width = $word.CentimetersToPoints(4.0)
    $table.Columns.Item(3).Width = $word.CentimetersToPoints(8.8)
    foreach ($cell in $table.Range.Cells) {
        $cell.Range.Style = $wdStyleNormal
        $cell.Range.ListFormat.RemoveNumbers() | Out-Null
        Set-RangeFont $cell.Range 10.5 $false $false
        $cell.VerticalAlignment = 1
        $cell.Range.ParagraphFormat.SpaceAfter = 3
    }
    foreach ($cell in $table.Rows.Item(1).Cells) {
        $cell.Range.Font.Bold = -1
        $cell.Shading.BackgroundPatternColor = 15132390
    }

    Add-PageBreak $doc
    Add-Heading $doc 'Lampiran Hasil Pengujian' 1 | Out-Null
    Add-Paragraph $doc 'Pengujian dilakukan pada 15 Oktober 2026 menggunakan build web lokal aplikasi dengan layout mobile portrait yang terhubung ke API aplikasi. Data uji dibuat khusus untuk penyusunan manual.' | Out-Null
    Add-Heading $doc 'Matriks Fitur' 2 | Out-Null
    $testTable = $doc.Tables.Add($doc.Range($doc.Content.End - 1, $doc.Content.End - 1), 1, 3)
    $testTable.Borders.Enable = 1
    $testTable.AllowAutoFit = $false
    $testTable.Cell(1,1).Range.Text = 'No.'
    $testTable.Cell(1,2).Range.Text = 'Fitur yang Diuji'
    $testTable.Cell(1,3).Range.Text = 'Hasil'
    $tests = @('Registrasi akun','Login akun hasil registrasi','Pemulihan sesi','Pembuatan tugas tanpa proyek','Pemilihan tanggal dan waktu tenggat','Pembuatan proyek','Pencarian dan filter proyek','Undangan kolaborator terdaftar','Pembuatan tugas dalam proyek','Detail dan edit tugas','Komentar dan tautan','Balasan komentar','Perpindahan To Do ke In Progress','Perpindahan In Progress ke Done','Profil pengguna','Konfirmasi logout','Logout dan kembali ke login')
    for ($i=0; $i -lt $tests.Count; $i++) {
        $cells = $testTable.Rows.Add().Cells
        $cells.Item(1).Range.Text = [string]($i + 1)
        $cells.Item(2).Range.Text = $tests[$i]
        $cells.Item(3).Range.Text = 'Berhasil'
    }
    $testTable.Columns.Item(1).Width = $word.CentimetersToPoints(1.2)
    $testTable.Columns.Item(2).Width = $word.CentimetersToPoints(11.3)
    $testTable.Columns.Item(3).Width = $word.CentimetersToPoints(3.5)
    foreach ($cell in $testTable.Range.Cells) {
        $cell.Range.Style = $wdStyleNormal
        $cell.Range.ListFormat.RemoveNumbers() | Out-Null
        Set-RangeFont $cell.Range 10.5 $false $false
        $cell.VerticalAlignment = 1
        $cell.Range.ParagraphFormat.SpaceAfter = 3
    }
    foreach ($cell in $testTable.Rows.Item(1).Cells) {
        $cell.Range.Font.Bold = -1
        $cell.Shading.BackgroundPatternColor = 15132390
    }
    $testTable.Rows.Item(1).HeadingFormat = -1
    Add-Note $doc 'Fitur hapus proyek dan hapus tugas diverifikasi sampai dialog konfirmasi agar data pengujian utama tetap tersedia untuk pemeriksaan dokumen.'

    Write-Host 'PROGRESS updating-toc'
    $toc.Update()
    Write-Host 'PROGRESS saving-docx'
    $doc.Save()
    Write-Host 'PROGRESS closing'
    $doc.Close($false)
    $doc = $null
}
finally {
    if ($doc) { $doc.Close($false) }
    $word.Quit()
    [System.Runtime.InteropServices.Marshal]::ReleaseComObject($word) | Out-Null
    [GC]::Collect()
    [GC]::WaitForPendingFinalizers()
}

Write-Output $output
