# Saves a small JPEG beside each frame shot under -Path (<name>.view.jpg, 960 wide by default), so
# an agent or a reviewer can look at shots without opening 1080p PNGs. scripts\measure-run.ps1
# calls it for its own shots. The copies come from your game: keep them on your PC, never post them.
#
#   powershell -ExecutionPolicy Bypass -File scripts\make-view.ps1 -Path <run folder> [-Filter 'world-*.png']

param(
    [Parameter(Mandatory)] [string]$Path,
    [int]$Width = 960,
    [string]$Filter = 'frame-*.png'
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

foreach ($png in Get-ChildItem -LiteralPath $Path -Recurse -Filter $Filter) {
    $jpg = [IO.Path]::ChangeExtension($png.FullName, '.view.jpg')
    if ((Test-Path -LiteralPath $jpg) -and (Get-Item -LiteralPath $jpg).LastWriteTime -ge $png.LastWriteTime) { continue }
    $src = [System.Drawing.Bitmap]::FromFile($png.FullName)
    try {
        $h = [int]([double]$src.Height * $Width / $src.Width)
        $dst = New-Object System.Drawing.Bitmap $Width, $h
        $g = [System.Drawing.Graphics]::FromImage($dst)
        $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $g.DrawImage($src, 0, 0, $Width, $h)
        $g.Dispose()
        $dst.Save($jpg, [System.Drawing.Imaging.ImageFormat]::Jpeg)
        $dst.Dispose()
    } finally {
        $src.Dispose()
    }
    $jpg
}
