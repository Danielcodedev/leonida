# Builds Leonida-Launcher.exe, a small window to pick a branch of this repository, switch to it and
# start run-gta6.ps1. Run it once from the repository's folder:
#
#   powershell -ExecutionPolicy Bypass -File .\build-launcher.ps1
#
# The launcher's code is below, in $LauncherSource. The repository holds no images
# (docs/asset-policy.md), so the logo is fetched at build time:
#   1. download the logo (PNG) from -LogoUrl;
#   2. write a temporary copy of the launcher's code with the logo embedded in it;
#   3. make the .exe icon from the same logo, in a temporary file;
#   4. build the .exe with ps2exe (installed for the current user the first time), then delete
#      the temporary files.
# Without network, or if the download fails, a logo drawn by the code is used instead.
# The only file written to the repository is Leonida-Launcher.exe, which git ignores (*.exe).

param(
    # The project's logo, the one shown at the top of README.md (same address, a fixed commit)
    [string]$LogoUrl = 'https://raw.githubusercontent.com/ShinniUwU/leonida/89b95f3e2215cc7b078618c2878ded1567a3be18/assets/logo.png'
)

$ErrorActionPreference = 'Stop'
Set-Location -LiteralPath $PSScriptRoot
Add-Type -AssemblyName System.Drawing

$work = Join-Path ([System.IO.Path]::GetTempPath()) ('leonida-launcher-' + [guid]::NewGuid().ToString('N'))
[void](New-Item -ItemType Directory -Path $work)

# The logo drawn by the code (same drawing as Draw-Logo in Leonida-Launcher.ps1)
function New-DrawnLogo([int]$S) {
    $bmp = New-Object System.Drawing.Bitmap($S, $S, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.Clear([System.Drawing.Color]::Transparent)
    $g.SmoothingMode = 'AntiAlias'
    $g.TextRenderingHint = 'AntiAliasGridFit'
    $purple = [System.Drawing.ColorTranslator]::FromHtml('#8b5cf6')
    $pink = [System.Drawing.ColorTranslator]::FromHtml('#ff3d9a')
    $orange = [System.Drawing.ColorTranslator]::FromHtml('#ff8a3d')
    $m = [Math]::Max(1, $S * 0.04); $r = $S * 0.24; $w = $S - 2 * $m
    $path = New-Object System.Drawing.Drawing2D.GraphicsPath
    $path.AddArc($m, $m, $r, $r, 180, 90)
    $path.AddArc($m + $w - $r, $m, $r, $r, 270, 90)
    $path.AddArc($m + $w - $r, $m + $w - $r, $r, $r, 0, 90)
    $path.AddArc($m, $m + $w - $r, $r, $r, 90, 90)
    $path.CloseFigure()
    $rect = New-Object System.Drawing.RectangleF($m, $m, $w, $w)
    $br = New-Object System.Drawing.Drawing2D.LinearGradientBrush($rect, $purple, $orange, [single]90)
    $blend = New-Object System.Drawing.Drawing2D.ColorBlend(3)
    $blend.Colors = [System.Drawing.Color[]]@($purple, $pink, $orange)
    $blend.Positions = [single[]]@(0, 0.55, 1)
    $br.InterpolationColors = $blend
    $g.FillPath($br, $path)
    $style = [System.Drawing.FontStyle]'Bold, Italic'
    $f = New-Object System.Drawing.Font('Segoe UI', [single]($S * 0.56), $style, [System.Drawing.GraphicsUnit]::Pixel)
    $sf = New-Object System.Drawing.StringFormat
    $sf.Alignment = 'Center'; $sf.LineAlignment = 'Center'
    $g.DrawString('L', $f, [System.Drawing.Brushes]::White, $rect, $sf)
    $br.Dispose(); $f.Dispose(); $path.Dispose(); $g.Dispose()
    $bmp
}

# The downloaded logo, centred in a transparent square of side S
function New-ScaledLogo($img, [int]$S) {
    $bmp = New-Object System.Drawing.Bitmap($S, $S, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.Clear([System.Drawing.Color]::Transparent)
    $g.InterpolationMode = 'HighQualityBicubic'
    $g.SmoothingMode = 'AntiAlias'
    $g.PixelOffsetMode = 'HighQuality'
    $k = [Math]::Min($S / $img.Width, $S / $img.Height)
    $w = $img.Width * $k; $h = $img.Height * $k
    $g.DrawImage($img, [single](($S - $w) / 2), [single](($S - $h) / 2), [single]$w, [single]$h)
    $g.Dispose()
    $bmp
}

function Get-PngBytes($bmp) {
    $ms = New-Object System.IO.MemoryStream
    $bmp.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png)
    , $ms.ToArray()
}

# One icon image as a BMP (DIB) entry: header, BGRA pixels bottom-up, then an empty AND mask.
function Get-DibBytes($bmp) {
    $s = $bmp.Width
    $ms = New-Object System.IO.MemoryStream
    $w = New-Object System.IO.BinaryWriter($ms)
    $w.Write([uint32]40); $w.Write([int32]$s); $w.Write([int32]($s * 2))
    $w.Write([uint16]1); $w.Write([uint16]32); $w.Write([uint32]0); $w.Write([uint32]0)
    $w.Write([int32]0); $w.Write([int32]0); $w.Write([uint32]0); $w.Write([uint32]0)
    $rect = New-Object System.Drawing.Rectangle(0, 0, $s, $s)
    $data = $bmp.LockBits($rect, 'ReadOnly', [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $buf = New-Object byte[] ($data.Stride * $s)
    [System.Runtime.InteropServices.Marshal]::Copy($data.Scan0, $buf, 0, $buf.Length)
    $bmp.UnlockBits($data)
    for ($y = $s - 1; $y -ge 0; $y--) { $w.Write($buf, $y * $data.Stride, $s * 4) }
    $maskRow = [int]([Math]::Ceiling($s / 32.0) * 4)
    $w.Write((New-Object byte[] ($maskRow * $s)))
    $w.Flush()
    , $ms.ToArray()
}

# Multi-size .ico: BMP entries up to 128 px, a PNG entry for 256 px
function Save-Icon([string]$Path, [scriptblock]$MakeBitmap) {
    $sizes = @(16, 24, 32, 48, 64, 128, 256)
    $images = @()
    foreach ($s in $sizes) {
        $bmp = & $MakeBitmap $s
        if ($s -eq 256) { $images += , (Get-PngBytes $bmp) } else { $images += , (Get-DibBytes $bmp) }
        $bmp.Dispose()
    }
    $fs = [System.IO.File]::Create($Path)
    $w = New-Object System.IO.BinaryWriter($fs)
    $w.Write([uint16]0); $w.Write([uint16]1); $w.Write([uint16]$sizes.Count)
    $offset = 6 + 16 * $sizes.Count
    for ($i = 0; $i -lt $sizes.Count; $i++) {
        $dim = [byte]($sizes[$i] % 256)   # 0 means 256
        $w.Write($dim); $w.Write($dim); $w.Write([byte]0); $w.Write([byte]0)
        $w.Write([uint16]1); $w.Write([uint16]32)
        $w.Write([uint32]$images[$i].Length); $w.Write([uint32]$offset)
        $offset += $images[$i].Length
    }
    foreach ($img in $images) { $w.Write([byte[]]$img) }
    $w.Close()
}

# ---------------------------------------------------------------- The launcher's code
$LauncherSource = @'
# ==========================================================
#  Leonida Launcher - choisir une branche puis lancer le .ps1
# ==========================================================

Add-Type -AssemblyName System.Windows.Forms, System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

$Here = if ($PSScriptRoot) { $PSScriptRoot } else { [AppDomain]::CurrentDomain.BaseDirectory }

# ---------------------------------------------------------- Configuration
# Enregistrée dans %APPDATA%\LeonidaLauncher\config.json
$CfgDir  = Join-Path $env:APPDATA 'LeonidaLauncher'
$CfgPath = Join-Path $CfgDir 'config.json'

$script:Cfg = [pscustomobject]@{
    RepoUrl = 'https://github.com/ProjectLeonidaL/leonida.git'
    RepoDir = ''      # vide = le dépôt qui contient l'exe
    Ps1     = ''      # vide = run-gta6.ps1 à la racine du dépôt
    GtaDir  = ''
    Args    = '-GameDir {GTA}'   # {GTA} = dossier du jeu ; ignoré si aucun dossier n'est choisi
}

function Import-Config {
    if (Test-Path $CfgPath) {
        try {
            $j = Get-Content $CfgPath -Raw -Encoding UTF8 | ConvertFrom-Json
            foreach ($k in 'RepoUrl', 'RepoDir', 'Ps1', 'GtaDir', 'Args') {
                if ($null -ne $j.$k) { $script:Cfg.$k = [string]$j.$k }
            }
        } catch { }
    }
}

function Export-Config {
    if (-not (Test-Path $CfgDir)) { [void](New-Item -ItemType Directory -Path $CfgDir) }
    $script:Cfg | ConvertTo-Json | Set-Content -Path $CfgPath -Encoding UTF8
}

function Test-Config {
    $Cfg = $script:Cfg
    $errs = @()
    if (-not $Cfg.RepoUrl)                                        { $errs += "URL du repo vide" }
    if (-not $Cfg.RepoDir -or -not (Test-Path (Join-Path $Cfg.RepoDir '.git'))) { $errs += "Dossier du repo invalide (pas de .git)" }
    if (-not $Cfg.Ps1 -or -not (Test-Path $Cfg.Ps1))              { $errs += "Script .ps1 introuvable" }
    if ($Cfg.GtaDir -and -not (Test-Path $Cfg.GtaDir))            { $errs += "Dossier du jeu introuvable" }
    $errs
}

Import-Config

# Valeurs par défaut : l'exe est à la racine du dépôt (ou dans un sous-dossier), et lance run-gta6.ps1
if (-not $script:Cfg.RepoDir) {
    foreach ($d in @($Here, (Split-Path -Parent $Here))) {
        if ($d -and (Test-Path (Join-Path $d '.git'))) { $script:Cfg.RepoDir = $d; break }
    }
}
if (-not $script:Cfg.Ps1 -and $script:Cfg.RepoDir) {
    $def = Join-Path $script:Cfg.RepoDir 'run-gta6.ps1'
    if (Test-Path $def) { $script:Cfg.Ps1 = $def }
}

# --- Couleurs (reprises du logo) ---
$cBg     = [System.Drawing.ColorTranslator]::FromHtml('#170d22')
$cPanel  = [System.Drawing.ColorTranslator]::FromHtml('#26163a')
$cField  = [System.Drawing.ColorTranslator]::FromHtml('#1f122f')
$cPink   = [System.Drawing.ColorTranslator]::FromHtml('#ff3d9a')
$cOrange = [System.Drawing.ColorTranslator]::FromHtml('#ff8a3d')
$cPurple = [System.Drawing.ColorTranslator]::FromHtml('#8b5cf6')
$cText   = [System.Drawing.Color]::White
$cMuted  = [System.Drawing.ColorTranslator]::FromHtml('#b9a8d4')
$cGreen  = [System.Drawing.ColorTranslator]::FromHtml('#4ade80')
$cRed    = [System.Drawing.ColorTranslator]::FromHtml('#f87171')

$font      = New-Object System.Drawing.Font('Segoe UI', 10)
$fontBold  = New-Object System.Drawing.Font('Segoe UI Semibold', 10)
$fontTitle = New-Object System.Drawing.Font('Segoe UI Semibold', 18)
$fontList  = New-Object System.Drawing.Font('Segoe UI', 11)
$fontLog   = New-Object System.Drawing.Font('Consolas', 9)

$script:Branches = @()
$script:Current  = ''

# Même dessin que l'icône de secours de build-launcher.ps1
function Draw-Logo($g, [int]$S) {
    $g.SmoothingMode = 'AntiAlias'
    $g.TextRenderingHint = 'AntiAliasGridFit'
    $m = [Math]::Max(1, $S * 0.04); $r = $S * 0.24; $w = $S - 2 * $m
    $path = New-Object System.Drawing.Drawing2D.GraphicsPath
    $path.AddArc($m, $m, $r, $r, 180, 90)
    $path.AddArc($m + $w - $r, $m, $r, $r, 270, 90)
    $path.AddArc($m + $w - $r, $m + $w - $r, $r, $r, 0, 90)
    $path.AddArc($m, $m + $w - $r, $r, $r, 90, 90)
    $path.CloseFigure()
    $rect = New-Object System.Drawing.RectangleF($m, $m, $w, $w)
    $br = New-Object System.Drawing.Drawing2D.LinearGradientBrush($rect, $cPurple, $cOrange, [single]90)
    $blend = New-Object System.Drawing.Drawing2D.ColorBlend(3)
    $blend.Colors = [System.Drawing.Color[]]@($cPurple, $cPink, $cOrange)
    $blend.Positions = [single[]]@(0, 0.55, 1)
    $br.InterpolationColors = $blend
    $g.FillPath($br, $path)
    $f = New-Object System.Drawing.Font('Segoe UI', [single]($S * 0.56), [System.Drawing.FontStyle]'Bold, Italic', [System.Drawing.GraphicsUnit]::Pixel)
    $sf = New-Object System.Drawing.StringFormat
    $sf.Alignment = 'Center'; $sf.LineAlignment = 'Center'
    $g.DrawString('L', $f, [System.Drawing.Brushes]::White, $rect, $sf)
    $br.Dispose(); $f.Dispose(); $path.Dispose()
}

# ---------------------------------------------------------- Fenetre
$form = New-Object System.Windows.Forms.Form
$form.Text = 'Leonida Launcher'
$form.ClientSize = New-Object System.Drawing.Size(580, 600)
$form.StartPosition = 'CenterScreen'
$form.FormBorderStyle = 'FixedSingle'
$form.MaximizeBox = $false
$form.BackColor = $cBg
$form.ForeColor = $cText
$form.Font = $font
try {
    $icoPath = Join-Path $Here 'logo.ico'
    if (Test-Path $icoPath) { $form.Icon = New-Object System.Drawing.Icon($icoPath) }
    else { $form.Icon = [System.Drawing.Icon]::ExtractAssociatedIcon([Diagnostics.Process]::GetCurrentProcess().MainModule.FileName) }
} catch { }

# ---------------------------------------------------------- En-tete
$header = New-Object System.Windows.Forms.Panel
$header.SetBounds(0, 0, 580, 90)
$header.BackColor = $cPanel
$form.Controls.Add($header)

# Logo : le dépôt ne contient aucune image (docs/asset-policy.md). build-launcher.ps1 remplit la ligne
# ci-dessous dans une copie temporaire de ce script, avec le logo téléchargé au moment du build.
# Vide (script lancé tel quel, ou téléchargement impossible) : le logo est dessiné par le code.
$LogoB64 = ''
$script:LogoImage = $null
if ($LogoB64) {
    try { $script:LogoImage = [System.Drawing.Image]::FromStream((New-Object System.IO.MemoryStream(, [Convert]::FromBase64String($LogoB64)))) } catch { }
}
$logo = New-Object System.Windows.Forms.Panel
$logo.SetBounds(16, 13, 64, 64)
$logo.Add_Paint({
    param($s, $e)
    if ($script:LogoImage) {
        $e.Graphics.InterpolationMode = 'HighQualityBicubic'
        $e.Graphics.DrawImage($script:LogoImage, 0, 0, $s.Width, $s.Height)
    } else {
        Draw-Logo $e.Graphics $s.Width
    }
})
$header.Controls.Add($logo)

$title = New-Object System.Windows.Forms.Label
$title.Text = 'Leonida Launcher'
$title.Font = $fontTitle
$title.ForeColor = $cPink
$title.AutoSize = $true
$title.Location = New-Object System.Drawing.Point(92, 14)
$header.Controls.Add($title)

$lblCurrent = New-Object System.Windows.Forms.Label
$lblCurrent.Text = 'Branche actuelle : ...'
$lblCurrent.ForeColor = $cMuted
$lblCurrent.AutoSize = $true
$lblCurrent.Location = New-Object System.Drawing.Point(95, 54)
$header.Controls.Add($lblCurrent)

$btnSettings = New-Object System.Windows.Forms.Button
$btnSettings.Text = '⚙  Paramètres'
$btnSettings.SetBounds(450, 30, 114, 30)
$btnSettings.FlatStyle = 'Flat'
$btnSettings.FlatAppearance.BorderColor = $cPurple
$btnSettings.FlatAppearance.MouseOverBackColor = $cPurple
$btnSettings.BackColor = $cPanel
$btnSettings.ForeColor = $cText
$btnSettings.Cursor = [System.Windows.Forms.Cursors]::Hand
$header.Controls.Add($btnSettings)
$lblCurrent.MaximumSize = New-Object System.Drawing.Size(350, 0)

# Liseré dégradé sous l'en-tête
$stripe = New-Object System.Windows.Forms.Panel
$stripe.SetBounds(0, 90, 580, 3)
$stripe.Add_Paint({
    param($s, $e)
    $r = $s.ClientRectangle
    $b = New-Object System.Drawing.Drawing2D.LinearGradientBrush($r, $cPurple, $cOrange, 0)
    $e.Graphics.FillRectangle($b, $r); $b.Dispose()
})
$form.Controls.Add($stripe)

# ---------------------------------------------------------- Liste des branches
$lblBranches = New-Object System.Windows.Forms.Label
$lblBranches.Text = 'Branches disponibles'
$lblBranches.Font = $fontBold
$lblBranches.AutoSize = $true
$lblBranches.Location = New-Object System.Drawing.Point(14, 106)
$form.Controls.Add($lblBranches)

$lblFilter = New-Object System.Windows.Forms.Label
$lblFilter.Text = 'Filtrer :'
$lblFilter.ForeColor = $cMuted
$lblFilter.AutoSize = $true
$lblFilter.Location = New-Object System.Drawing.Point(246, 106)
$form.Controls.Add($lblFilter)

$txtFilter = New-Object System.Windows.Forms.TextBox
$txtFilter.SetBounds(300, 103, 172, 24)
$txtFilter.BackColor = $cField
$txtFilter.ForeColor = $cText
$txtFilter.BorderStyle = 'FixedSingle'
$form.Controls.Add($txtFilter)

$btnRefresh = New-Object System.Windows.Forms.Button
$btnRefresh.Text = 'Actualiser'
$btnRefresh.SetBounds(480, 101, 84, 27)
$btnRefresh.FlatStyle = 'Flat'
$btnRefresh.FlatAppearance.BorderColor = $cPurple
$btnRefresh.BackColor = $cPanel
$btnRefresh.ForeColor = $cText
$btnRefresh.Cursor = [System.Windows.Forms.Cursors]::Hand
$form.Controls.Add($btnRefresh)

$list = New-Object System.Windows.Forms.ListBox
$list.SetBounds(16, 136, 548, 180)
$list.BackColor = $cField
$list.ForeColor = $cText
$list.Font = $fontList
$list.BorderStyle = 'FixedSingle'
$list.DrawMode = 'OwnerDrawFixed'
$list.ItemHeight = 28
$list.Add_DrawItem({
    param($s, $e)
    if ($e.Index -lt 0) { return }
    $name = [string]$s.Items[$e.Index]
    $selected = ($e.State -band [System.Windows.Forms.DrawItemState]::Selected) -ne 0
    $bg = if ($selected) { $cPink } else { $cField }
    $br = New-Object System.Drawing.SolidBrush($bg)
    $e.Graphics.FillRectangle($br, $e.Bounds); $br.Dispose()
    $txt = $name
    if ($name -eq $script:Current) { $txt = "$name   (actuelle)" }
    $fg = if ($selected) { [System.Drawing.Color]::White } elseif ($name -eq $script:Current) { $cGreen } else { $cText }
    $tb = New-Object System.Drawing.SolidBrush($fg)
    $e.Graphics.DrawString($txt, $fontList, $tb, ($e.Bounds.X + 10), ($e.Bounds.Y + 4)); $tb.Dispose()
})
$form.Controls.Add($list)

# ---------------------------------------------------------- Options
$chkClean = New-Object System.Windows.Forms.CheckBox
$chkClean.Text = 'Supprimer aussi les fichiers non suivis (git clean -fd)'
$chkClean.AutoSize = $true
$chkClean.ForeColor = $cMuted
$chkClean.Location = New-Object System.Drawing.Point(16, 324)
$form.Controls.Add($chkClean)

$chkClose = New-Object System.Windows.Forms.CheckBox
$chkClose.Text = 'Fermer le lanceur après le lancement'
$chkClose.AutoSize = $true
$chkClose.Checked = $true
$chkClose.ForeColor = $cMuted
$chkClose.Location = New-Object System.Drawing.Point(16, 350)
$form.Controls.Add($chkClose)

# ---------------------------------------------------------- Bouton principal
$btnGo = New-Object System.Windows.Forms.Button
$btnGo.Text = '▶   Charger et lancer'
$btnGo.SetBounds(16, 382, 548, 44)
$btnGo.FlatStyle = 'Flat'
$btnGo.FlatAppearance.BorderSize = 0
$btnGo.FlatAppearance.MouseOverBackColor = $cOrange
$btnGo.BackColor = $cPink
$btnGo.ForeColor = [System.Drawing.Color]::White
$btnGo.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 12)
$btnGo.Cursor = [System.Windows.Forms.Cursors]::Hand
$form.Controls.Add($btnGo)

$progress = New-Object System.Windows.Forms.ProgressBar
$progress.SetBounds(16, 434, 548, 6)
$progress.Style = 'Marquee'
$progress.MarqueeAnimationSpeed = 25
$progress.Visible = $false
$form.Controls.Add($progress)

# ---------------------------------------------------------- Journal
$log = New-Object System.Windows.Forms.RichTextBox
$log.SetBounds(16, 448, 548, 136)
$log.BackColor = $cField
$log.ForeColor = $cMuted
$log.Font = $fontLog
$log.BorderStyle = 'None'
$log.ReadOnly = $true
$form.Controls.Add($log)

# ==========================================================
#  Fonctions
# ==========================================================
function Write-Log([string]$Text, $Color = $cMuted) {
    $log.SelectionStart = $log.TextLength
    $log.SelectionColor = $Color
    $log.AppendText(("[{0:HH:mm:ss}] {1}`r`n" -f (Get-Date), $Text.TrimEnd()))
    $log.ScrollToCaret()
}

function Set-Busy([bool]$Busy) {
    $progress.Visible = $Busy
    $btnGo.Enabled = -not $Busy
    $btnRefresh.Enabled = -not $Busy
    $list.Enabled = -not $Busy
    $form.Cursor = if ($Busy) { [System.Windows.Forms.Cursors]::WaitCursor } else { [System.Windows.Forms.Cursors]::Default }
}

# Lance git sans bloquer l'interface
function Invoke-Git([string[]]$GitArgs) {
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = 'git'
    $psi.Arguments = ($GitArgs | ForEach-Object { if ($_ -match '\s') { '"' + $_ + '"' } else { $_ } }) -join ' '
    $psi.WorkingDirectory = $script:Cfg.RepoDir
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true
    $p = [System.Diagnostics.Process]::Start($psi)
    $out = $p.StandardOutput.ReadToEndAsync()
    $err = $p.StandardError.ReadToEndAsync()
    while (-not $p.HasExited) {
        [System.Windows.Forms.Application]::DoEvents()
        Start-Sleep -Milliseconds 30
    }
    $p.WaitForExit()
    [pscustomobject]@{ Code = $p.ExitCode; Out = $out.Result; Err = $err.Result }
}

function Update-Current {
    $r = Invoke-Git @('rev-parse', '--abbrev-ref', 'HEAD')
    $s = Invoke-Git @('log', '-1', '--format=%h  %s')
    $script:Current = $r.Out.Trim()
    $lblCurrent.Text = "Branche actuelle : $($script:Current)   ·   $($s.Out.Trim())"
}

# Fenêtre de paramètres - renvoie $true si enregistré
function Show-Settings {
    $dlg = New-Object System.Windows.Forms.Form
    $dlg.Text = 'Paramètres'
    $dlg.ClientSize = New-Object System.Drawing.Size(560, 420)
    $dlg.StartPosition = 'CenterParent'
    $dlg.FormBorderStyle = 'FixedDialog'
    $dlg.MaximizeBox = $false; $dlg.MinimizeBox = $false
    $dlg.BackColor = $cBg; $dlg.ForeColor = $cText; $dlg.Font = $font
    if ($form.Icon) { $dlg.Icon = $form.Icon }

    $fields = @{}
    $y = 16
    $rows = @(
        @{ Key = 'RepoUrl'; Label = 'URL du repo GitHub';                 Browse = $null },
        @{ Key = 'RepoDir'; Label = 'Dossier du repo (clone local)';      Browse = 'folder' },
        @{ Key = 'Ps1';     Label = 'Script .ps1 à lancer';               Browse = 'ps1' },
        @{ Key = 'GtaDir';  Label = 'Dossier du jeu (optionnel)';                     Browse = 'folder' },
        @{ Key = 'Args';    Label = 'Arguments du script  ({GTA} = dossier du jeu)'; Browse = $null }
    )
    foreach ($row in $rows) {
        $l = New-Object System.Windows.Forms.Label
        $l.Text = $row.Label; $l.Font = $fontBold; $l.AutoSize = $true
        $l.Location = New-Object System.Drawing.Point(16, $y)
        $dlg.Controls.Add($l)

        $t = New-Object System.Windows.Forms.TextBox
        $t.Text = $script:Cfg.($row.Key)
        $t.BackColor = $cField; $t.ForeColor = $cText; $t.BorderStyle = 'FixedSingle'
        $w = if ($row.Browse) { 430 } else { 528 }
        $t.SetBounds(16, ($y + 24), $w, 26)
        $dlg.Controls.Add($t)
        $fields[$row.Key] = $t

        if ($row.Browse) {
            $b = New-Object System.Windows.Forms.Button
            $b.Text = 'Parcourir...'
            $b.SetBounds(452, ($y + 22), 92, 28)
            $b.FlatStyle = 'Flat'; $b.FlatAppearance.BorderColor = $cPurple
            $b.BackColor = $cPanel; $b.ForeColor = $cText
            $b.Tag = @{ Box = $t; Kind = $row.Browse }
            $b.Add_Click({
                param($s, $e)
                $box = $s.Tag.Box
                if ($s.Tag.Kind -eq 'folder') {
                    $fb = New-Object System.Windows.Forms.FolderBrowserDialog
                    if ($box.Text -and (Test-Path $box.Text)) { $fb.SelectedPath = $box.Text }
                    if ($fb.ShowDialog() -eq 'OK') { $box.Text = $fb.SelectedPath }
                } else {
                    $of = New-Object System.Windows.Forms.OpenFileDialog
                    $of.Filter = 'Scripts PowerShell (*.ps1)|*.ps1|Tous les fichiers (*.*)|*.*'
                    if ($box.Text -and (Test-Path $box.Text)) { $of.InitialDirectory = Split-Path -Parent $box.Text }
                    elseif ($fields['RepoDir'].Text -and (Test-Path $fields['RepoDir'].Text)) { $of.InitialDirectory = $fields['RepoDir'].Text }
                    if ($of.ShowDialog() -eq 'OK') { $box.Text = $of.FileName }
                }
            }.GetNewClosure())
            $dlg.Controls.Add($b)
        }
        $y += 64
    }

    $hint = New-Object System.Windows.Forms.Label
    $hint.Text = "Config : $CfgPath"
    $hint.ForeColor = $cMuted; $hint.AutoSize = $true
    $hint.Location = New-Object System.Drawing.Point(16, ($y + 2))
    $dlg.Controls.Add($hint)

    $ok = New-Object System.Windows.Forms.Button
    $ok.Text = 'Enregistrer'
    $ok.SetBounds(336, 374, 104, 32)
    $ok.FlatStyle = 'Flat'; $ok.FlatAppearance.BorderSize = 0
    $ok.BackColor = $cPink; $ok.ForeColor = [System.Drawing.Color]::White
    $dlg.Controls.Add($ok)

    $cancel = New-Object System.Windows.Forms.Button
    $cancel.Text = 'Annuler'
    $cancel.SetBounds(448, 374, 96, 32)
    $cancel.FlatStyle = 'Flat'; $cancel.FlatAppearance.BorderColor = $cPurple
    $cancel.BackColor = $cPanel; $cancel.ForeColor = $cText
    $cancel.DialogResult = 'Cancel'
    $dlg.Controls.Add($cancel)
    $dlg.CancelButton = $cancel

    $ok.Add_Click({
        foreach ($k in $fields.Keys) { $script:Cfg.$k = $fields[$k].Text.Trim() }
        $errs = @(Test-Config)
        if ($errs.Count -gt 0) {
            $msg = "Attention :`n- " + ($errs -join "`n- ") + "`n`nEnregistrer quand même ?"
            if ([System.Windows.Forms.MessageBox]::Show($msg, 'Paramètres', 'YesNo', 'Warning') -ne 'Yes') { return }
        }
        Export-Config
        $dlg.DialogResult = 'OK'
        $dlg.Close()
    })

    $before = $script:Cfg | ConvertTo-Json
    $res = $dlg.ShowDialog($form)
    if ($res -ne 'OK') { $script:Cfg = $before | ConvertFrom-Json }   # annuler = restaurer
    return ($res -eq 'OK')
}

function Initialize-Launcher {
    $errs = @(Test-Config)
    if ($errs.Count -gt 0) {
        foreach ($e in $errs) { Write-Log $e $cOrange }
        Write-Log 'Configure le lanceur via « Paramètres ».' $cOrange
        $btnGo.Enabled = $false
        if (-not $script:Cfg.RepoDir -or -not (Test-Path (Join-Path $script:Cfg.RepoDir '.git'))) {
            $script:Branches = @(); Show-Branches
            return
        }
    }
    Get-Branches
    if ($errs.Count -gt 0) { $btnGo.Enabled = $false }
}

function Show-Branches {
    $list.BeginUpdate()
    $list.Items.Clear()
    $f = $txtFilter.Text.Trim()
    foreach ($b in $script:Branches) {
        if (-not $f -or $b -like "*$f*") { [void]$list.Items.Add($b) }
    }
    $list.EndUpdate()
    $i = $list.Items.IndexOf($script:Current)
    if ($i -ge 0) { $list.SelectedIndex = $i } elseif ($list.Items.Count) { $list.SelectedIndex = 0 }
}

function Get-Branches {
    Set-Busy $true
    Write-Log 'Récupération des branches...'
    $r = Invoke-Git @('ls-remote', '--heads', $script:Cfg.RepoUrl)
    if ($r.Code -ne 0) {
        Write-Log "Échec : $($r.Err)" $cRed
    } else {
        $found = foreach ($line in ($r.Out -split "`n")) {
            if ($line -match 'refs/heads/(\S+)') { $Matches[1] }
        }
        $script:Branches = @($found | Sort-Object)
        Write-Log "$($script:Branches.Count) branche(s) trouvée(s)." $cGreen
    }
    Update-Current
    Show-Branches
    Set-Busy $false
}

function Start-Selected {
    $br = [string]$list.SelectedItem
    if (-not $br) { Write-Log 'Sélectionne une branche.' $cOrange; return }
    $errs = @(Test-Config)
    if ($errs.Count -gt 0) { foreach ($x in $errs) { Write-Log $x $cRed }; return }

    # Avertir si des modifications locales vont être écrasées
    $st = Invoke-Git @('status', '--porcelain', '--untracked-files=no')
    $changed = @($st.Out -split "`n" | Where-Object { $_.Trim() })
    if ($changed.Count -gt 0) {
        $msg = "$($changed.Count) fichier(s) modifié(s) localement seront écrasés.`n`nContinuer ?"
        $ans = [System.Windows.Forms.MessageBox]::Show($msg, 'Modifications locales', 'YesNo', 'Warning')
        if ($ans -ne 'Yes') { Write-Log 'Annulé.' $cOrange; return }
    }

    Set-Busy $true
    [void](Invoke-Git @('merge', '--abort'))
    [void](Invoke-Git @('rebase', '--abort'))

    Write-Log "Téléchargement de « $br »..."
    $r = Invoke-Git @('fetch', $script:Cfg.RepoUrl, $br)
    if ($r.Code -ne 0) { Write-Log "Échec du fetch : $($r.Err)" $cRed; Set-Busy $false; return }

    $r = Invoke-Git @('checkout', '-f', '-B', $br, 'FETCH_HEAD')
    if ($r.Code -ne 0) { Write-Log "Échec du checkout : $($r.Err)" $cRed; Set-Busy $false; return }

    if ($chkClean.Checked) {
        $r = Invoke-Git @('clean', '-fd')
        if ($r.Out.Trim()) { Write-Log $r.Out }
    }

    Update-Current
    $list.Invalidate()
    Write-Log "Branche « $br » chargée." $cGreen

    $ps1Path = $script:Cfg.Ps1
    if (-not $ps1Path -or -not (Test-Path $ps1Path)) {
        Write-Log "Script introuvable : $ps1Path" $cRed
        Set-Busy $false; return
    }
    $gta = $script:Cfg.GtaDir
    $env:LEONIDA_GTA_DIR  = $gta          # dispo dans le script via $env:LEONIDA_GTA_DIR
    $env:LEONIDA_REPO_DIR = $script:Cfg.RepoDir
    $env:LEONIDA_BRANCH   = $br

    $argLine = "-NoProfile -ExecutionPolicy Bypass -NoExit -File `"$ps1Path`""
    $extra = $script:Cfg.Args
    if ($extra -and $extra.Contains('{GTA}')) {
        # Sans dossier choisi, run-gta6.ps1 le demande lui-même : on n'envoie pas l'argument
        $extra = if ($gta) { $extra.Replace('{GTA}', "`"$gta`"") } else { '' }
    }
    if ($extra) { $argLine += ' ' + $extra }

    Write-Log "Lancement de $(Split-Path -Leaf $ps1Path)..." $cPink
    Start-Process powershell -WorkingDirectory $script:Cfg.RepoDir -ArgumentList $argLine
    Set-Busy $false
    if ($chkClose.Checked) { $form.Close() }
}

# ==========================================================
#  Événements
# ==========================================================
$btnRefresh.Add_Click({ Get-Branches })
$btnGo.Add_Click({ Start-Selected })
$list.Add_DoubleClick({ Start-Selected })
$txtFilter.Add_TextChanged({ Show-Branches })
$form.AcceptButton = $btnGo
$btnSettings.Add_Click({
    if (Show-Settings) {
        Write-Log 'Paramètres enregistrés.' $cGreen
        Initialize-Launcher
    }
})
$form.Add_Shown({
    if (@(Test-Config).Count -gt 0) {
        Write-Log 'Bienvenue ! Commence par configurer le lanceur.' $cPink
        [void](Show-Settings)
    }
    Initialize-Launcher
    $txtFilter.Focus()
})

[void]$form.ShowDialog()
'@

# ---------------------------------------------------------------- Build
try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

    # 1. Logo
    $logo = $null
    if ($LogoUrl) {
        $png = Join-Path $work 'logo.png'
        try {
            Write-Host "Downloading the logo from $LogoUrl ..."
            Invoke-WebRequest -Uri $LogoUrl -OutFile $png -UseBasicParsing -TimeoutSec 30
            $logo = [System.Drawing.Image]::FromFile($png)
        } catch {
            Write-Warning "No logo downloaded ($($_.Exception.Message)). Using the drawn logo."
            $logo = $null
        }
    }

    # 2. Temporary copy of the launcher, with the logo embedded
    $source = $LauncherSource
    if ($logo) {
        $small = New-ScaledLogo $logo 128
        $b64 = [Convert]::ToBase64String((Get-PngBytes $small))
        $small.Dispose()
        $marker = "`$LogoB64 = ''"
        if (-not $source.Contains($marker)) { throw "The launcher code has no line $marker" }
        $source = $source.Replace($marker, "`$LogoB64 = '$b64'")
    }
    $script = Join-Path $work 'Leonida-Launcher.ps1'
    [System.IO.File]::WriteAllText($script, $source, (New-Object System.Text.UTF8Encoding($true)))

    # 3. Icon
    $ico = Join-Path $work 'leonida-launcher.ico'
    if ($logo) { Save-Icon $ico { param($s) New-ScaledLogo $logo $s } }
    else { Save-Icon $ico { param($s) New-DrawnLogo $s } }
    if ($logo) { $logo.Dispose() }

    # 4. ps2exe, for the current user only, the first time
    if (-not (Get-Module -ListAvailable ps2exe)) {
        Write-Host 'Installing ps2exe for this user (first build only)...'
        if (-not (Get-PackageProvider -ListAvailable -Name NuGet -ErrorAction SilentlyContinue)) {
            Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Scope CurrentUser -Force | Out-Null
        }
        Install-Module ps2exe -Scope CurrentUser -Force
    }
    Import-Module ps2exe

    $exe = Join-Path $PSScriptRoot 'Leonida-Launcher.exe'
    Invoke-ps2exe -inputFile $script -outputFile $exe -iconFile $ico -noConsole -STA -title 'Leonida Launcher'
    if (-not (Test-Path -LiteralPath $exe)) { throw 'ps2exe did not produce Leonida-Launcher.exe' }
    Write-Host ''
    Write-Host "Built $exe"
} finally {
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}
