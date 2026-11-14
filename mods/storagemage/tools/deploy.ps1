# Installs Storage Mage into the game's UE4SS Mods folder.
#
#   powershell -ExecutionPolicy Bypass -File tools\deploy.ps1          copy (what players use)
#   powershell -ExecutionPolicy Bypass -File tools\deploy.ps1 -Link    development: junction Scripts\, Art\ and dev\
#                                                                       (the developer features) to this repo, so
#                                                                       edits are live on the next game start
#   add -GameDir "D:\...\RSDragonwilds" for a non-default install
#   add -ModsDir "\\server\share\...\ue4ss\Mods" to install straight into a UE4SS Mods folder anywhere, e.g. a
#       dedicated server on another machine (a network share). Use copy mode there: -Link can't cross machines.
#   powershell -ExecutionPolicy Bypass -File tools\deploy.ps1 -Package
#       builds dist\StorageMage.zip for a machine you copy to by hand (a dedicated server): unzip it into that
#       game's ue4ss\Mods folder and say yes to replacing files. It holds code and empty data folders only, so
#       the server's settings and saves are never replaced. Restart the server to load it.
#
# config\, dumps\ and saves\ are always real folders in the game directory (personal data; never overwritten).
param(
    [string]$GameDir = "C:\Program Files (x86)\Steam\steamapps\common\RSDragonwilds",
    [string]$ModsDir = "",
    [switch]$Link,
    [switch]$Package
)
$ErrorActionPreference = "Stop"
$src = (Resolve-Path (Join-Path $PSScriptRoot "..\StorageMage")).Path

if ($Package) {
    $dist = Join-Path $PSScriptRoot "..\dist"
    $stage = Join-Path $dist "stage"
    if (Test-Path $stage) { Remove-Item $stage -Recurse -Force }
    $mod = Join-Path $stage "StorageMage"
    New-Item -ItemType Directory -Force $mod | Out-Null
    foreach ($code in "Scripts", "Art") { Copy-Item (Join-Path $src $code) (Join-Path $mod $code) -Recurse }
    foreach ($dir in "config", "dumps", "saves") {
        New-Item -ItemType Directory -Force (Join-Path $mod $dir) | Out-Null
        Set-Content (Join-Path $mod "$dir\.keep") "" -Encoding ascii
    }
    Set-Content (Join-Path $mod "enabled.txt") "" -Encoding ascii
    $zip = Join-Path (Resolve-Path $dist).Path "StorageMage.zip"
    if (Test-Path $zip) { Remove-Item $zip -Force }
    Compress-Archive -Path $mod -DestinationPath $zip
    Remove-Item $stage -Recurse -Force
    Write-Host "Packaged $zip - unzip into the server's ue4ss\Mods folder, then restart the server."
    return
}
$mods = if ($ModsDir) { $ModsDir } else { Join-Path $GameDir "RSDragonwilds\Binaries\Win64\ue4ss\Mods" }
if (-not (Test-Path $mods)) { throw "UE4SS Mods folder not found: $mods" }
if ($Link -and $mods.StartsWith("\\")) { throw "-Link can't point a junction at another machine; deploy without -Link." }
if (Get-Process "RSDragonwilds*" -ErrorAction SilentlyContinue) {
    Write-Warning "The game is running; changes load on the next start."
}
$dst = Join-Path $mods "StorageMage"
New-Item -ItemType Directory -Force $dst | Out-Null

# True for a junction even when its target no longer exists (Test-Path reports a broken junction as missing).
function Test-Junction($path) {
    try { return [bool]([IO.File]::GetAttributes($path) -band [IO.FileAttributes]::ReparsePoint) } catch { return $false }
}

# Removes a folder. A junction is only unlinked: Remove-Item -Recurse on a junction in Windows PowerShell 5.1
# deletes the files in its TARGET (here, the repo).
function Remove-Folder($path) {
    if (Test-Junction $path) { [IO.Directory]::Delete($path, $false); return }
    if (Test-Path $path) { Remove-Item $path -Recurse -Force }
}

# Copy files from $from to $to that don't exist there yet (never overwrites).
function Add-Missing($from, $to) {
    if (-not (Test-Path $from)) { return 0 }
    $n = 0
    Get-ChildItem $from -Recurse -File -Force | ForEach-Object {
        $rel = $_.FullName.Substring($from.Length).TrimStart('\')
        $target = Join-Path $to $rel
        if (-not (Test-Path $target)) {
            New-Item -ItemType Directory -Force (Split-Path $target) | Out-Null
            Copy-Item $_.FullName $target
            $n++
        }
    }
    return $n
}

# Scripts\ and Art\ (the default-look art) are the mod's own files: linked or replaced, never merged.
foreach ($code in "Scripts", "Art") {
    $repoDir = Join-Path $src $code
    $gameDir = Join-Path $dst $code
    if ($Link) {
        if ((Test-Junction $gameDir) -and ((Get-Item $gameDir -Force).Target -contains $repoDir)) {
            Write-Host "$code already linked"
        } else {
            Remove-Folder $gameDir
            New-Item -ItemType Junction -Path $gameDir -Target $repoDir | Out-Null
            Write-Host "$code -> $repoDir (junction)"
        }
    } else {
        Remove-Folder $gameDir # always replaced
        Copy-Item $repoDir $gameDir -Recurse
    }
}

# Developer features (dumps, probes) live in ..\dev, never in releases. -Link links them in as Mods\StorageMage\dev;
# a copy install is what players get, so it has none (an old link is removed).
$devRepo = (Resolve-Path (Join-Path $PSScriptRoot "..\dev")).Path
$devGame = Join-Path $dst "dev"
if ($Link) {
    if ((Test-Junction $devGame) -and ((Get-Item $devGame -Force).Target -contains $devRepo)) {
        Write-Host "dev already linked"
    } else {
        Remove-Folder $devGame
        New-Item -ItemType Junction -Path $devGame -Target $devRepo | Out-Null
        Write-Host "dev -> $devRepo (junction: developer features)"
    }
} elseif ((Test-Path $devGame) -or (Test-Junction $devGame)) {
    Remove-Folder $devGame
    Write-Host "dev removed (a copy install has no developer features)"
}

foreach ($dir in "config", "dumps", "saves") {
    Add-Missing (Join-Path $src $dir) (Join-Path $dst $dir) | Out-Null
}

# Enabled via enabled.txt rather than mods.txt: Vortex manages mods.txt and may rewrite it.
Set-Content (Join-Path $dst "enabled.txt") "" -Encoding ascii
Write-Host ("Deployed to $dst" + $(if ($Link) { " (linked)" } else { " (copied)" }))
