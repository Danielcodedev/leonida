# Builds Leonida-Launcher.exe, a small window to pick a branch of this repository, switch to it and
# start run-gta6.ps1. Run it once from the repository's folder:
#
#   powershell -ExecutionPolicy Bypass -File .\scripts\build-launcher.ps1
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
Set-Location -LiteralPath (Split-Path -Parent $PSScriptRoot)
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
#  Leonida Launcher - pick a branch, then start the .ps1
# ==========================================================

Add-Type -AssemblyName System.Windows.Forms, System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

$Here = if ($PSScriptRoot) { $PSScriptRoot } else { [AppDomain]::CurrentDomain.BaseDirectory }

# ---------------------------------------------------------- Configuration
# Saved in %APPDATA%\LeonidaLauncher\config.json
$CfgDir  = Join-Path $env:APPDATA 'LeonidaLauncher'
$CfgPath = Join-Path $CfgDir 'config.json'

$script:Cfg = [pscustomobject]@{
    RepoUrl = 'https://github.com/ProjectLeonidaL/leonida.git'
    RepoDir = ''      # empty = the repository that holds the exe
    Ps1     = ''      # empty = run-gta6.ps1 at the root of the repository
    GtaDir  = ''
    Args    = '-GameDir {GTA}'   # {GTA} = game folder; left out if no folder is chosen
    Lang    = 'en'               # launcher language, picked in Settings: en or fr
}

# ---------------------------------------------------------- Texts
# One table per language. A key missing from a language falls back to English.
$LangCodes = @('en', 'fr')
$Texts = @{
    en = @{
        LangName      = 'English'
        CurrentBranch = 'Current branch: {0}'
        CurrentTag    = '(current)'
        BtnSettings   = '⚙  Settings'
        Settings      = 'Settings'
        Branches      = 'Available branches'
        Filter        = 'Filter:'
        Refresh       = 'Refresh'
        Clean         = 'Also delete untracked files (git clean -fd)'
        CloseAfter    = 'Close the launcher after starting'
        Go            = '▶   Load and start'
        RowRepoUrl    = 'GitHub repository URL'
        RowRepoDir    = 'Repository folder (local clone)'
        RowPs1        = '.ps1 script to start'
        RowGtaDir     = 'Game folder (optional)'
        RowArgs       = 'Script arguments  ({GTA} = game folder)'
        RowLang       = 'Language'
        Browse        = 'Browse...'
        Ps1Filter     = 'PowerShell scripts (*.ps1)|*.ps1|All files (*.*)|*.*'
        ConfigPath    = 'Config: {0}'
        Save          = 'Save'
        Cancel        = 'Cancel'
        SaveAnyway    = "Warning:`n- {0}`n`nSave anyway?"
        ErrRepoUrl    = 'Repository URL is empty'
        ErrRepoDir    = 'Repository folder is not valid (no .git)'
        ErrPs1        = '.ps1 script not found'
        ErrGtaDir     = 'Game folder not found'
        SetUpHint     = 'Set up the launcher in "Settings".'
        Fetching      = 'Fetching branches...'
        Failed        = 'Failed: {0}'
        BranchesFound = '{0} branch(es) found.'
        PickBranch    = 'Pick a branch.'
        LocalChanges  = "{0} locally modified file(s) will be overwritten.`n`nContinue?"
        LocalTitle    = 'Local changes'
        Cancelled     = 'Cancelled.'
        Downloading   = 'Downloading "{0}"...'
        FetchFailed   = 'Fetch failed: {0}'
        CheckoutFail  = 'Checkout failed: {0}'
        BranchLoaded  = 'Branch "{0}" loaded.'
        NoScript      = 'Script not found: {0}'
        Starting      = 'Starting {0}...'
        Saved         = 'Settings saved.'
        Welcome       = 'Welcome! Start by setting up the launcher.'
        GitMissing    = 'Git is not installed. The launcher needs it to list and load branches.'
        GitAsk        = "Git is not installed, and the launcher needs it.`n`nInstall it now with winget? Windows may ask for admin rights."
        GitInstalling = 'Installing Git with winget...'
        GitInstalled  = 'Git installed.'
        GitByHand     = 'Install Git from https://git-scm.com/download/win, then start the launcher again.'
        ToolsStop     = 'The build tools or Rust are still missing, so the game was not started. Close this window and press "Load and start" again once they are installed.'
    }
    fr = @{
        LangName      = 'Français'
        CurrentBranch = 'Branche actuelle : {0}'
        CurrentTag    = '(actuelle)'
        BtnSettings   = '⚙  Paramètres'
        Settings      = 'Paramètres'
        Branches      = 'Branches disponibles'
        Filter        = 'Filtrer :'
        Refresh       = 'Actualiser'
        Clean         = 'Supprimer aussi les fichiers non suivis (git clean -fd)'
        CloseAfter    = 'Fermer le lanceur après le lancement'
        Go            = '▶   Charger et lancer'
        RowRepoUrl    = 'URL du repo GitHub'
        RowRepoDir    = 'Dossier du repo (clone local)'
        RowPs1        = 'Script .ps1 à lancer'
        RowGtaDir     = 'Dossier du jeu (optionnel)'
        RowArgs       = 'Arguments du script  ({GTA} = dossier du jeu)'
        RowLang       = 'Langue'
        Browse        = 'Parcourir...'
        Ps1Filter     = 'Scripts PowerShell (*.ps1)|*.ps1|Tous les fichiers (*.*)|*.*'
        ConfigPath    = 'Config : {0}'
        Save          = 'Enregistrer'
        Cancel        = 'Annuler'
        SaveAnyway    = "Attention :`n- {0}`n`nEnregistrer quand même ?"
        ErrRepoUrl    = 'URL du repo vide'
        ErrRepoDir    = 'Dossier du repo invalide (pas de .git)'
        ErrPs1        = 'Script .ps1 introuvable'
        ErrGtaDir     = 'Dossier du jeu introuvable'
        SetUpHint     = 'Configure le lanceur via « Paramètres ».'
        Fetching      = 'Récupération des branches...'
        Failed        = 'Échec : {0}'
        BranchesFound = '{0} branche(s) trouvée(s).'
        PickBranch    = 'Sélectionne une branche.'
        LocalChanges  = "{0} fichier(s) modifié(s) localement seront écrasés.`n`nContinuer ?"
        LocalTitle    = 'Modifications locales'
        Cancelled     = 'Annulé.'
        Downloading   = 'Téléchargement de « {0} »...'
        FetchFailed   = 'Échec du fetch : {0}'
        CheckoutFail  = 'Échec du checkout : {0}'
        BranchLoaded  = 'Branche « {0} » chargée.'
        NoScript      = 'Script introuvable : {0}'
        Starting      = 'Lancement de {0}...'
        Saved         = 'Paramètres enregistrés.'
        Welcome       = 'Bienvenue ! Commence par configurer le lanceur.'
        GitMissing    = "Git n'est pas installé. Le lanceur en a besoin pour lister et charger les branches."
        GitAsk        = "Git n'est pas installé, et le lanceur en a besoin.`n`nL'installer maintenant avec winget ? Windows peut demander les droits d'administrateur."
        GitInstalling = 'Installation de Git avec winget...'
        GitInstalled  = 'Git installé.'
        GitByHand     = 'Installe Git depuis https://git-scm.com/download/win, puis relance le lanceur.'
        ToolsStop     = "Les outils de build ou Rust manquent encore, le jeu n'a pas été lancé. Ferme cette fenêtre et clique de nouveau sur « Charger et lancer » une fois qu'ils sont installés."
    }
}

function T([string]$Key) {
    $table = $Texts[[string]$script:Cfg.Lang]
    if ($table -and $table.ContainsKey($Key)) { $table[$Key] } else { $Texts['en'][$Key] }
}

function Import-Config {
    if (Test-Path $CfgPath) {
        try {
            $j = Get-Content $CfgPath -Raw -Encoding UTF8 | ConvertFrom-Json
            foreach ($k in 'RepoUrl', 'RepoDir', 'Ps1', 'GtaDir', 'Args', 'Lang') {
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
    if (-not $Cfg.RepoUrl)                                        { $errs += T 'ErrRepoUrl' }
    if (-not $Cfg.RepoDir -or -not (Test-Path (Join-Path $Cfg.RepoDir '.git'))) { $errs += T 'ErrRepoDir' }
    if (-not $Cfg.Ps1 -or -not (Test-Path $Cfg.Ps1))              { $errs += T 'ErrPs1' }
    if ($Cfg.GtaDir -and -not (Test-Path $Cfg.GtaDir))            { $errs += T 'ErrGtaDir' }
    $errs
}

Import-Config

# Defaults: the exe sits at the root of the repository (or in a subfolder) and starts run-gta6.ps1
if (-not $script:Cfg.RepoDir) {
    foreach ($d in @($Here, (Split-Path -Parent $Here))) {
        if ($d -and (Test-Path (Join-Path $d '.git'))) { $script:Cfg.RepoDir = $d; break }
    }
}
if (-not $script:Cfg.Ps1 -and $script:Cfg.RepoDir) {
    $def = Join-Path $script:Cfg.RepoDir 'run-gta6.ps1'
    if (Test-Path $def) { $script:Cfg.Ps1 = $def }
}

# --- Colors (taken from the logo) ---
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

# Same drawing as the fallback icon of build-launcher.ps1
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

# ---------------------------------------------------------- Window
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

# ---------------------------------------------------------- Header
$header = New-Object System.Windows.Forms.Panel
$header.SetBounds(0, 0, 580, 90)
$header.BackColor = $cPanel
$form.Controls.Add($header)

# Logo: the repository holds no images (docs/asset-policy.md). build-launcher.ps1 fills in the line
# below in a temporary copy of this script, with the logo downloaded at build time.
# Empty (script run as is, or download failed): the logo is drawn by the code.
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
$lblCurrent.ForeColor = $cMuted
$lblCurrent.AutoSize = $true
$lblCurrent.Location = New-Object System.Drawing.Point(95, 54)
$header.Controls.Add($lblCurrent)

$btnSettings = New-Object System.Windows.Forms.Button
$btnSettings.SetBounds(450, 30, 114, 30)
$btnSettings.FlatStyle = 'Flat'
$btnSettings.FlatAppearance.BorderColor = $cPurple
$btnSettings.FlatAppearance.MouseOverBackColor = $cPurple
$btnSettings.BackColor = $cPanel
$btnSettings.ForeColor = $cText
$btnSettings.Cursor = [System.Windows.Forms.Cursors]::Hand
$header.Controls.Add($btnSettings)
$lblCurrent.MaximumSize = New-Object System.Drawing.Size(350, 0)

# Gradient stripe under the header
$stripe = New-Object System.Windows.Forms.Panel
$stripe.SetBounds(0, 90, 580, 3)
$stripe.Add_Paint({
    param($s, $e)
    $r = $s.ClientRectangle
    $b = New-Object System.Drawing.Drawing2D.LinearGradientBrush($r, $cPurple, $cOrange, 0)
    $e.Graphics.FillRectangle($b, $r); $b.Dispose()
})
$form.Controls.Add($stripe)

# ---------------------------------------------------------- Branch list
$lblBranches = New-Object System.Windows.Forms.Label
$lblBranches.Font = $fontBold
$lblBranches.AutoSize = $true
$lblBranches.Location = New-Object System.Drawing.Point(14, 106)
$form.Controls.Add($lblBranches)

$lblFilter = New-Object System.Windows.Forms.Label
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
    if ($name -eq $script:Current) { $txt = "$name   $(T 'CurrentTag')" }
    $fg = if ($selected) { [System.Drawing.Color]::White } elseif ($name -eq $script:Current) { $cGreen } else { $cText }
    $tb = New-Object System.Drawing.SolidBrush($fg)
    $e.Graphics.DrawString($txt, $fontList, $tb, ($e.Bounds.X + 10), ($e.Bounds.Y + 4)); $tb.Dispose()
})
$form.Controls.Add($list)

# ---------------------------------------------------------- Options
$chkClean = New-Object System.Windows.Forms.CheckBox
$chkClean.AutoSize = $true
$chkClean.ForeColor = $cMuted
$chkClean.Location = New-Object System.Drawing.Point(16, 324)
$form.Controls.Add($chkClean)

$chkClose = New-Object System.Windows.Forms.CheckBox
$chkClose.AutoSize = $true
$chkClose.Checked = $true
$chkClose.ForeColor = $cMuted
$chkClose.Location = New-Object System.Drawing.Point(16, 350)
$form.Controls.Add($chkClose)

# ---------------------------------------------------------- Main button
$btnGo = New-Object System.Windows.Forms.Button
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

# ---------------------------------------------------------- Log
$log = New-Object System.Windows.Forms.RichTextBox
$log.SetBounds(16, 448, 548, 136)
$log.BackColor = $cField
$log.ForeColor = $cMuted
$log.Font = $fontLog
$log.BorderStyle = 'None'
$log.ReadOnly = $true
$form.Controls.Add($log)

# ==========================================================
#  Functions
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

# Every text of the main window, again after the language changes
$script:CurrentLine = '...'
function Update-Texts {
    $btnSettings.Text = T 'BtnSettings'
    $lblBranches.Text = T 'Branches'
    $lblFilter.Text = T 'Filter'
    $btnRefresh.Text = T 'Refresh'
    $chkClean.Text = T 'Clean'
    $chkClose.Text = T 'CloseAfter'
    $btnGo.Text = T 'Go'
    $lblCurrent.Text = (T 'CurrentBranch') -f $script:CurrentLine
    $list.Invalidate()
}

function Invoke-Git([string[]]$GitArgs) { Invoke-Hidden 'git' $GitArgs $script:Cfg.RepoDir }

# Runs a program without blocking the interface. The exe has no console, so a console program
# started with & would open a window of its own.
function Invoke-Hidden([string]$File, [string[]]$ArgList, [string]$Dir) {
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $File
    $psi.Arguments = ($ArgList | ForEach-Object { if ($_ -match '\s') { '"' + $_ + '"' } else { $_ } }) -join ' '
    if ($Dir) { $psi.WorkingDirectory = $Dir }
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true
    try { $p = [System.Diagnostics.Process]::Start($psi) }
    catch { return [pscustomobject]@{ Code = -1; Out = ''; Err = $_.Exception.Message } }
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
    $script:CurrentLine = "$($script:Current)   ·   $($s.Out.Trim())"
    $lblCurrent.Text = (T 'CurrentBranch') -f $script:CurrentLine
}

# Settings window - returns $true when saved
function Show-Settings {
    $dlg = New-Object System.Windows.Forms.Form
    $dlg.Text = T 'Settings'
    $dlg.ClientSize = New-Object System.Drawing.Size(560, 484)
    $dlg.StartPosition = 'CenterParent'
    $dlg.FormBorderStyle = 'FixedDialog'
    $dlg.MaximizeBox = $false; $dlg.MinimizeBox = $false
    $dlg.BackColor = $cBg; $dlg.ForeColor = $cText; $dlg.Font = $font
    if ($form.Icon) { $dlg.Icon = $form.Icon }

    $fields = @{}
    $y = 16
    $rows = @(
        @{ Key = 'RepoUrl'; Label = T 'RowRepoUrl'; Browse = $null },
        @{ Key = 'RepoDir'; Label = T 'RowRepoDir'; Browse = 'folder' },
        @{ Key = 'Ps1';     Label = T 'RowPs1';     Browse = 'ps1' },
        @{ Key = 'GtaDir';  Label = T 'RowGtaDir';  Browse = 'folder' },
        @{ Key = 'Args';    Label = T 'RowArgs';    Browse = $null }
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
            $b.Text = T 'Browse'
            $b.SetBounds(452, ($y + 22), 92, 28)
            $b.FlatStyle = 'Flat'; $b.FlatAppearance.BorderColor = $cPurple
            $b.BackColor = $cPanel; $b.ForeColor = $cText
            $b.Tag = @{ Box = $t; Kind = $row.Browse; Filter = T 'Ps1Filter' }
            $b.Add_Click({
                param($s, $e)
                $box = $s.Tag.Box
                if ($s.Tag.Kind -eq 'folder') {
                    $fb = New-Object System.Windows.Forms.FolderBrowserDialog
                    if ($box.Text -and (Test-Path $box.Text)) { $fb.SelectedPath = $box.Text }
                    if ($fb.ShowDialog() -eq 'OK') { $box.Text = $fb.SelectedPath }
                } else {
                    $of = New-Object System.Windows.Forms.OpenFileDialog
                    $of.Filter = $s.Tag.Filter
                    if ($box.Text -and (Test-Path $box.Text)) { $of.InitialDirectory = Split-Path -Parent $box.Text }
                    elseif ($fields['RepoDir'].Text -and (Test-Path $fields['RepoDir'].Text)) { $of.InitialDirectory = $fields['RepoDir'].Text }
                    if ($of.ShowDialog() -eq 'OK') { $box.Text = $of.FileName }
                }
            }.GetNewClosure())
            $dlg.Controls.Add($b)
        }
        $y += 64
    }

    $l = New-Object System.Windows.Forms.Label
    $l.Text = T 'RowLang'; $l.Font = $fontBold; $l.AutoSize = $true
    $l.Location = New-Object System.Drawing.Point(16, $y)
    $dlg.Controls.Add($l)

    $cmbLang = New-Object System.Windows.Forms.ComboBox
    $cmbLang.DropDownStyle = 'DropDownList'
    $cmbLang.FlatStyle = 'Flat'
    $cmbLang.BackColor = $cField; $cmbLang.ForeColor = $cText
    $cmbLang.SetBounds(16, ($y + 24), 200, 26)
    foreach ($code in $LangCodes) { [void]$cmbLang.Items.Add($Texts[$code]['LangName']) }
    $cmbLang.SelectedIndex = [Math]::Max(0, [array]::IndexOf($LangCodes, [string]$script:Cfg.Lang))
    $dlg.Controls.Add($cmbLang)
    $y += 64

    $hint = New-Object System.Windows.Forms.Label
    $hint.Text = (T 'ConfigPath') -f $CfgPath
    $hint.ForeColor = $cMuted; $hint.AutoSize = $true
    $hint.Location = New-Object System.Drawing.Point(16, ($y + 2))
    $dlg.Controls.Add($hint)

    $ok = New-Object System.Windows.Forms.Button
    $ok.Text = T 'Save'
    $ok.SetBounds(336, 438, 104, 32)
    $ok.FlatStyle = 'Flat'; $ok.FlatAppearance.BorderSize = 0
    $ok.BackColor = $cPink; $ok.ForeColor = [System.Drawing.Color]::White
    $dlg.Controls.Add($ok)

    $cancel = New-Object System.Windows.Forms.Button
    $cancel.Text = T 'Cancel'
    $cancel.SetBounds(448, 438, 96, 32)
    $cancel.FlatStyle = 'Flat'; $cancel.FlatAppearance.BorderColor = $cPurple
    $cancel.BackColor = $cPanel; $cancel.ForeColor = $cText
    $cancel.DialogResult = 'Cancel'
    $dlg.Controls.Add($cancel)
    $dlg.CancelButton = $cancel

    $ok.Add_Click({
        foreach ($k in $fields.Keys) { $script:Cfg.$k = $fields[$k].Text.Trim() }
        $script:Cfg.Lang = $LangCodes[[Math]::Max(0, $cmbLang.SelectedIndex)]
        $errs = @(Test-Config)
        if ($errs.Count -gt 0) {
            $msg = (T 'SaveAnyway') -f ($errs -join "`n- ")
            if ([System.Windows.Forms.MessageBox]::Show($msg, (T 'Settings'), 'YesNo', 'Warning') -ne 'Yes') { return }
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

# A PowerShell string literal for the command line of the window that starts the script
function ConvertTo-Literal([string]$Text) { "'" + $Text.Replace("'", "''") + "'" }

# Git lists and loads the branches. Offers to install it with winget when it is missing.
function Initialize-Git {
    if (Get-Command git -ErrorAction SilentlyContinue) { return $true }
    Write-Log (T 'GitMissing') $cOrange
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) { Write-Log (T 'GitByHand') $cOrange; return $false }
    $ans = [System.Windows.Forms.MessageBox]::Show((T 'GitAsk'), 'Git', 'YesNo', 'Question')
    if ($ans -ne 'Yes') { Write-Log (T 'GitByHand') $cOrange; return $false }
    Set-Busy $true
    Write-Log (T 'GitInstalling')
    [void](Invoke-Hidden 'winget' @('install', '--id', 'Git.Git', '--exact', '--silent',
        '--accept-package-agreements', '--accept-source-agreements') '')
    Set-Busy $false
    # The installer adds Git to PATH for new processes only
    $env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' +
        [Environment]::GetEnvironmentVariable('Path', 'User')
    if (Get-Command git -ErrorAction SilentlyContinue) { Write-Log (T 'GitInstalled') $cGreen; return $true }
    Write-Log (T 'GitByHand') $cRed
    $false
}

function Initialize-Launcher {
    $errs = @(Test-Config)
    if ($errs.Count -gt 0) {
        foreach ($e in $errs) { Write-Log $e $cOrange }
        Write-Log (T 'SetUpHint') $cOrange
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
    Write-Log (T 'Fetching')
    $r = Invoke-Git @('ls-remote', '--heads', $script:Cfg.RepoUrl)
    if ($r.Code -ne 0) {
        Write-Log ((T 'Failed') -f $r.Err) $cRed
    } else {
        $found = foreach ($line in ($r.Out -split "`n")) {
            if ($line -match 'refs/heads/(\S+)') { $Matches[1] }
        }
        $script:Branches = @($found | Sort-Object)
        Write-Log ((T 'BranchesFound') -f $script:Branches.Count) $cGreen
    }
    Update-Current
    Show-Branches
    Set-Busy $false
}

function Start-Selected {
    $br = [string]$list.SelectedItem
    if (-not $br) { Write-Log (T 'PickBranch') $cOrange; return }
    $errs = @(Test-Config)
    if ($errs.Count -gt 0) { foreach ($x in $errs) { Write-Log $x $cRed }; return }

    # Warn when local changes are about to be overwritten
    $st = Invoke-Git @('status', '--porcelain', '--untracked-files=no')
    $changed = @($st.Out -split "`n" | Where-Object { $_.Trim() })
    if ($changed.Count -gt 0) {
        $msg = (T 'LocalChanges') -f $changed.Count
        $ans = [System.Windows.Forms.MessageBox]::Show($msg, (T 'LocalTitle'), 'YesNo', 'Warning')
        if ($ans -ne 'Yes') { Write-Log (T 'Cancelled') $cOrange; return }
    }

    Set-Busy $true
    [void](Invoke-Git @('merge', '--abort'))
    [void](Invoke-Git @('rebase', '--abort'))

    Write-Log ((T 'Downloading') -f $br)
    $r = Invoke-Git @('fetch', $script:Cfg.RepoUrl, $br)
    if ($r.Code -ne 0) { Write-Log ((T 'FetchFailed') -f $r.Err) $cRed; Set-Busy $false; return }

    $r = Invoke-Git @('checkout', '-f', '-B', $br, 'FETCH_HEAD')
    if ($r.Code -ne 0) { Write-Log ((T 'CheckoutFail') -f $r.Err) $cRed; Set-Busy $false; return }

    if ($chkClean.Checked) {
        $r = Invoke-Git @('clean', '-fd')
        if ($r.Out.Trim()) { Write-Log $r.Out }
    }

    Update-Current
    $list.Invalidate()
    Write-Log ((T 'BranchLoaded') -f $br) $cGreen

    $ps1Path = $script:Cfg.Ps1
    if (-not $ps1Path -or -not (Test-Path $ps1Path)) {
        Write-Log ((T 'NoScript') -f $ps1Path) $cRed
        Set-Busy $false; return
    }
    $gta = $script:Cfg.GtaDir
    $env:LEONIDA_GTA_DIR  = $gta          # available to the script as $env:LEONIDA_GTA_DIR
    $env:LEONIDA_REPO_DIR = $script:Cfg.RepoDir
    $env:LEONIDA_BRANCH   = $br

    $extra = $script:Cfg.Args
    if ($extra -and $extra.Contains('{GTA}')) {
        # Without a chosen folder, run-gta6.ps1 asks for it itself, so the argument is left out
        $extra = if ($gta) { $extra.Replace('{GTA}', (ConvertTo-Literal $gta)) } else { '' }
    }

    # The build tools and Rust first: scripts\check-tools.ps1 offers to install what is missing,
    # in the same window, so its questions and progress show there. Branches without it skip this.
    $cmd = ''
    $check = Join-Path $script:Cfg.RepoDir 'scripts\check-tools.ps1'
    if (Test-Path -LiteralPath $check) {
        $cmd += "& $(ConvertTo-Literal $check)`n"
        $cmd += "if (-not `$?) { Write-Host $(ConvertTo-Literal (T 'ToolsStop')) -ForegroundColor Yellow; return }`n"
        # rustup installed a moment ago is not on this window's PATH yet
        $cmd += "`$env:Path = `$env:USERPROFILE + '\.cargo\bin;' + `$env:Path`n"
    }
    $cmd += "& $(ConvertTo-Literal $ps1Path) $extra"
    $enc = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($cmd))
    $argLine = "-NoProfile -ExecutionPolicy Bypass -NoExit -EncodedCommand $enc"

    Write-Log ((T 'Starting') -f (Split-Path -Leaf $ps1Path)) $cPink
    Start-Process powershell -WorkingDirectory $script:Cfg.RepoDir -ArgumentList $argLine
    Set-Busy $false
    if ($chkClose.Checked) { $form.Close() }
}

# ==========================================================
#  Events
# ==========================================================
$btnRefresh.Add_Click({ Get-Branches })
$btnGo.Add_Click({ Start-Selected })
$list.Add_DoubleClick({ Start-Selected })
$txtFilter.Add_TextChanged({ Show-Branches })
$form.AcceptButton = $btnGo
$btnSettings.Add_Click({
    if (Show-Settings) {
        Update-Texts
        Write-Log (T 'Saved') $cGreen
        Initialize-Launcher
    }
})
$form.Add_Shown({
    if (-not (Initialize-Git)) { $btnGo.Enabled = $false; $btnRefresh.Enabled = $false; return }
    if (@(Test-Config).Count -gt 0) {
        Write-Log (T 'Welcome') $cPink
        if (Show-Settings) { Update-Texts }
    }
    Initialize-Launcher
    $txtFilter.Focus()
})

Update-Texts
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

    $exe = Join-Path (Split-Path -Parent $PSScriptRoot) 'Leonida-Launcher.exe'
    Invoke-ps2exe -inputFile $script -outputFile $exe -iconFile $ico -noConsole -STA -title 'Leonida Launcher'
    if (-not (Test-Path -LiteralPath $exe)) { throw 'ps2exe did not produce Leonida-Launcher.exe' }
    Write-Host ''
    Write-Host "Built $exe"
} finally {
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}
