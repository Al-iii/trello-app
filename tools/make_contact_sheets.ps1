$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

$source = 'E:\kuliah\Project\manual_render_xps'
$output = 'E:\kuliah\Project\manual_contact_sheets'
New-Item -ItemType Directory -Force -Path $output | Out-Null
$files = Get-ChildItem -LiteralPath $source -Filter 'page-*.png' | Sort-Object Name
$thumbW = 720
$thumbH = 1018
$cols = 4
$rows = 2
$perSheet = $cols * $rows

for ($sheetIndex = 0; $sheetIndex -lt [Math]::Ceiling($files.Count / $perSheet); $sheetIndex++) {
    $canvas = New-Object System.Drawing.Bitmap($($thumbW * $cols), $($thumbH * $rows))
    $graphics = [System.Drawing.Graphics]::FromImage($canvas)
    try {
        $graphics.Clear([System.Drawing.Color]::FromArgb(230,230,230))
        for ($slot = 0; $slot -lt $perSheet; $slot++) {
            $fileIndex = $sheetIndex * $perSheet + $slot
            if ($fileIndex -ge $files.Count) { break }
            $image = [System.Drawing.Image]::FromFile($files[$fileIndex].FullName)
            try {
                $x = ($slot % $cols) * $thumbW
                $y = [Math]::Floor($slot / $cols) * $thumbH
                $graphics.DrawImage($image, $x, $y, $thumbW, $thumbH)
            }
            finally { $image.Dispose() }
        }
        $path = Join-Path $output ('sheet-{0:D2}.png' -f ($sheetIndex + 1))
        $canvas.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)
        Write-Output $path
    }
    finally {
        $graphics.Dispose()
        $canvas.Dispose()
    }
}
