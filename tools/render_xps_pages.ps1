$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName ReachFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName WindowsBase

$xpsPath = 'E:\kuliah\Project\manual_render_check.xps'
$outDir = 'E:\kuliah\Project\manual_render_xps'
New-Item -ItemType Directory -Force -Path $outDir | Out-Null

$xps = New-Object System.Windows.Xps.Packaging.XpsDocument($xpsPath, [System.IO.FileAccess]::Read)
try {
    $sequence = $xps.GetFixedDocumentSequence()
    $paginator = $sequence.DocumentPaginator
    $count = $paginator.PageCount
    for ($index = 0; $index -lt $count; $index++) {
        $page = $paginator.GetPage($index)
        $width = [int][Math]::Ceiling($page.Size.Width)
        $height = [int][Math]::Ceiling($page.Size.Height)
        $bitmap = New-Object System.Windows.Media.Imaging.RenderTargetBitmap($width, $height, 96, 96, [System.Windows.Media.PixelFormats]::Pbgra32)
        $bitmap.Render($page.Visual)
        $encoder = New-Object System.Windows.Media.Imaging.PngBitmapEncoder
        $encoder.Frames.Add([System.Windows.Media.Imaging.BitmapFrame]::Create($bitmap))
        $path = Join-Path $outDir ('page-{0:D2}.png' -f ($index + 1))
        $stream = [System.IO.File]::Open($path, [System.IO.FileMode]::Create)
        try { $encoder.Save($stream) }
        finally { $stream.Dispose() }
        Write-Output $path
    }
}
finally {
    $xps.Close()
}
