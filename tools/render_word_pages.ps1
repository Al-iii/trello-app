$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$docx = 'E:\kuliah\Project\ManualBookMobile.docx'
$outDir = 'E:\kuliah\Project\manual_render_word'
New-Item -ItemType Directory -Force -Path $outDir | Out-Null

$wdGoToPage = 1
$wdGoToAbsolute = 1
$wdStatisticPages = 2

$word = New-Object -ComObject Word.Application
$word.Visible = $false
$word.DisplayAlerts = 0
$doc = $null

try {
    $doc = $word.Documents.Open($docx, $false, $true)
    $pageCount = $doc.ComputeStatistics($wdStatisticPages)
    for ($page = 1; $page -le $pageCount; $page++) {
        $start = $doc.GoTo($wdGoToPage, $wdGoToAbsolute, $page).Start
        if ($page -lt $pageCount) {
            $end = $doc.GoTo($wdGoToPage, $wdGoToAbsolute, $page + 1).Start - 1
        }
        else {
            $end = $doc.Content.End - 1
        }
        $range = $doc.Range($start, $end)
        [System.Windows.Forms.Clipboard]::Clear()
        $range.Select()
        $word.Selection.CopyAsPicture()
        Start-Sleep -Milliseconds 750
        $image = [System.Windows.Forms.Clipboard]::GetImage()
        if ($null -eq $image) {
            $formats = [System.Windows.Forms.Clipboard]::GetDataObject().GetFormats() -join ', '
            $emfData = [System.Windows.Forms.Clipboard]::GetData('EnhancedMetafile')
            $emfType = if ($null -eq $emfData) { 'null' } else { $emfData.GetType().FullName }
            throw "Clipboard image unavailable for page $page. EMF type: $emfType. Formats: $formats"
        }
        $path = Join-Path $outDir ('page-{0:D2}.png' -f $page)
        $image.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)
        $image.Dispose()
        Write-Output $path
    }
}
finally {
    if ($doc) { $doc.Close($false) }
    $word.Quit()
    [System.Runtime.InteropServices.Marshal]::ReleaseComObject($word) | Out-Null
}
