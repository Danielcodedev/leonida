# Like run-gta6.ps1, but with the diagnostics build: frame log and card meter
# (per pipeline) on, and everything the emulator prints saved to a log file.
# Logs go under %LOCALAPPDATA%\leonida\logs (game-derived output stays out of the repo).
# When the game closes it offers a short test report (scripts\test-report.ps1): figures
# only, shown in full, and shared only if you say so.
#
# The first time, it offers to look for your copy of the game (the folder with
# MicrosoftGame.config in it) or asks for that folder (scripts\game-dir.ps1), and offers to
# remember it in leonida.toml, which git ignores.
#
#   powershell -ExecutionPolicy Bypass -File .\measure-gta6.ps1
#   powershell -ExecutionPolicy Bypass -File .\measure-gta6.ps1 -GameDir 'D:\Games\GTA VI'   # this run only
#   powershell -ExecutionPolicy Bypass -File .\measure-gta6.ps1 -WarmUp yes   # warm up the shader cache without asking
#   powershell -ExecutionPolicy Bypass -File .\measure-gta6.ps1 -SpeedSwitches off   # the same run without the switches
#   powershell -ExecutionPolicy Bypass -File .\measure-gta6.ps1 -Report no   # no report afterwards

param(
    [string]$GameDir = '',
    # yes: warm up the shader cache before starting, no: skip it, ask: ask (default).
    [ValidateSet('ask', 'yes', 'no')]
    [string]$WarmUp = 'ask',
    # on: native profiles and graphics settings (default), off: baseline, ask: ask.
    [ValidateSet('on', 'off', 'ask')]
    [string]$SpeedSwitches = 'on',
    # ask: offer a test report when the game closes (default), no: don't.
    [ValidateSet('ask', 'no')]
    [string]$Report = 'ask'
)

$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'scripts\leonida-settings.ps1')
$environmentBefore = Save-LeonidaEnvironment

function Test-GameDir([string]$dir) {
    $dir -ne '' -and (Test-Path -LiteralPath (Join-Path $dir 'MicrosoftGame.config') -PathType Leaf)
}

# leonida.toml is read from the current folder.
Push-Location $PSScriptRoot
try {
    cargo build --profile diag -p leonida --features diagnostics
    if ($LASTEXITCODE -ne 0) { throw "cargo build failed (exit $LASTEXITCODE); is leonida.exe still running?" }
    $exe = Join-Path $PSScriptRoot 'target\diag\leonida.exe'

    if ($GameDir -ne '') {
        if (-not (Test-GameDir $GameDir)) { throw "no MicrosoftGame.config in $GameDir" }
        $dir = $GameDir
    } else {
        # What leonida.toml or LEONIDA_GAME_DIR already says.
        $out = & $exe config
        if ($LASTEXITCODE -ne 0) { throw "leonida config failed (exit $LASTEXITCODE); check leonida.toml" }
        $dir = ''
        $line = $out | Where-Object { $_ -match '^game_dir\s*:' } | Select-Object -First 1
        if ($line -match '^game_dir\s*:\s*(.+?)\s*$') { $dir = $Matches[1] -replace '\s+\(does not exist\)$', '' }

        if (-not (Test-GameDir $dir)) {
            if ($dir -ne '' -and $dir -ne '(not set)') { Write-Host "The saved game folder has no MicrosoftGame.config: $dir" }
            . (Join-Path $PSScriptRoot 'scripts\game-dir.ps1')
            $dir = Read-GameDir

            $answer = Read-Host 'Remember this folder for next time? [Y/n]'
            if ($answer.Trim() -match '^(y|yes)?$') {
                & $exe config --game-dir $dir | Out-Null
                if ($LASTEXITCODE -ne 0) { throw "saving the game folder failed (exit $LASTEXITCODE)" }
                Write-Host 'Saved to leonida.toml.'
            }
        }
    }
    $env:LEONIDA_GAME_DIR = $dir

    if ($SpeedSwitches -eq 'ask') {
        $graphics = Get-LeonidaGraphics $exe
        Show-LeonidaGraphics $graphics
        Write-Host ''
        Write-Host 'Use the graphics settings selected for this run?'
        Write-Host ((Get-LeonidaGraphicsSwitches $graphics -Short) -join ', ')
        Write-Host 'To help compare, play once with them and once without, in the same place in the game.'
        $answer = Read-Host 'Speed switches on? [Y/n]'
        $SpeedSwitches = if ($answer.Trim() -match '^(y|yes)?$') { 'on' } else { 'off' }
    }
    if ($SpeedSwitches -eq 'off') {
        Disable-LeonidaGraphics
        Write-Host 'speed switches: off'
    }
    # Capture the effective plan before adding diagnostic flags, including native-only settings.
    $graphics = Get-LeonidaGraphics $exe
    Show-LeonidaGraphics $graphics
    $switchList = @(Get-LeonidaGraphicsSwitches $graphics)

    $env:LEONIDA_FRAME_LOG = '1'
    $env:LEONIDA_CARD_METER = '1'
    $env:LEONIDA_CARD_METER_PIPELINES = '1'

    # Shaders not in the cache are translated the first time the game uses them, mid-play.
    if ($WarmUp -eq 'ask') {
        Write-Host ''
        Write-Host 'Warm up the shader cache first? It translates every shader before the game starts:'
        Write-Host 'about 1 to 2 minutes the first time (and after an update), about 30 s when the cache is full.'
        Write-Host 'WARNING: without it, the game translates shaders while you play, so it stutters and runs'
        Write-Host 'slower until the cache fills up.'
        $answer = Read-Host 'Warm up now? [Y/n]'
        $WarmUp = if ($answer.Trim() -match '^(y|yes)?$') { 'yes' } else { 'no' }
    }
    if ($WarmUp -eq 'yes') {
        & $exe translate --warm all
        if ($LASTEXITCODE -ne 0) { Write-Warning "the warm-up failed (exit $LASTEXITCODE); starting anyway" }
    } else {
        Write-Warning 'starting without a warm-up: expect stutter until the shader cache fills up'
    }

    $logDir = Join-Path $env:LOCALAPPDATA 'leonida\logs'
    New-Item -ItemType Directory -Force $logDir | Out-Null
    $log = Join-Path $logDir ("measure-{0:yyyyMMdd-HHmmss}.log" -f (Get-Date))
    Write-Host "logging to $log"

    # The emulator logs to stderr; PowerShell 5.1 wraps those lines as errors, so don't stop on them.
    $ErrorActionPreference = 'Continue'
    $started = Get-Date
    & $exe run --execute 2>&1 | ForEach-Object { "$_" } | Tee-Object -FilePath $log
    $exitCode = $LASTEXITCODE

    if ($Report -eq 'ask') {
        try {
            & (Join-Path $PSScriptRoot 'scripts\test-report.ps1') -Log $log -SpeedSwitches $switchList `
                -SwitchMode $SpeedSwitches -WarmUp $WarmUp -Started $started `
                -ExitCode "$exitCode" -Exe $exe -Graphics $graphics
        } catch {
            Write-Warning "the test report failed: $_"
        }
    }
} finally {
    Restore-LeonidaEnvironment $environmentBefore
    Pop-Location
}
