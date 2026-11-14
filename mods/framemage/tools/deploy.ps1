# Installs Frame Mage into the game's UE4SS Mods folder.
#
#   powershell -ExecutionPolicy Bypass -File tools\deploy.ps1          copy (what players use)
#   powershell -ExecutionPolicy Bypass -File tools\deploy.ps1 -Link    development: junction Scripts\, Art\ and
#                                                                       dev\ (the developer features) to this repo,
#                                                                       so edits are live
#   add -GameDir "D:\...\RSDragonwilds" for a non-default install
#
# config\, layouts\ and dumps\ are always real folders in the game directory (personal data; never overwritten).
param(
    [string]$GameDir = "C:\Program Files (x86)\Steam\steamapps\common\RSDragonwilds",
    [switch]$Link
)
$ErrorActionPreference = "Stop"
$src = (Resolve-Path (Join-Path $PSScriptRoot "..\FrameMage")).Path
$mods = Join-Path $GameDir "RSDragonwilds\Binaries\Win64\ue4ss\Mods"
if (-not (Test-Path $mods)) { throw "UE4SS Mods folder not found: $mods" }
if (Get-Process "RSDragonwilds*" -ErrorAction SilentlyContinue) {
    Write-Warning "The game is running; changes load on the next start."
}
$dst = Join-Path $mods "FrameMage"
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

# One-time migration from the mod's old name (Forgeframe): carry the player's data over, then retire the old
# folder without deleting it: its junctions are unlinked, enabled.txt removed (so it can't load), and it is renamed.
$legacy = Join-Path $mods "Forgeframe"
if (Test-Path $legacy) {
    foreach ($dir in "config", "layouts", "dumps", "share") {
        $n = Add-Missing (Join-Path $legacy $dir) (Join-Path $dst $dir)
        if ($n -gt 0) { Write-Host "Migrated $n file(s) from Forgeframe\$dir" }
    }
    foreach ($file in "modmenu-settings.txt") {
        $from = Join-Path $legacy $file
        if ((Test-Path $from) -and -not (Test-Path (Join-Path $dst $file))) { Copy-Item $from (Join-Path $dst $file) }
    }
    foreach ($dir in "Scripts", "Art") { if (Test-Junction (Join-Path $legacy $dir)) { Remove-Folder (Join-Path $legacy $dir) } }
    Remove-Item (Join-Path $legacy "enabled.txt") -Force -ErrorAction SilentlyContinue
    $retired = Join-Path $mods ("Forgeframe.migrated-" + (Get-Date -Format "yyyyMMdd-HHmmss"))
    Rename-Item $legacy $retired
    Write-Host "Old Forgeframe folder retired as $(Split-Path $retired -Leaf) (safe to delete)"
}

foreach ($dir in "Scripts", "Art") {
    $repoDir = Join-Path $src $dir
    $gameDir = Join-Path $dst $dir
    if ($Link) {
        if ((Test-Junction $gameDir) -and ((Get-Item $gameDir -Force).Target -contains $repoDir)) {
            Write-Host "$dir already linked"
            continue
        }
        if ($dir -eq "Art" -and (Test-Path $gameDir) -and -not (Test-Junction $gameDir)) {
            # keep art that only exists in the game folder: move it into the repo before linking
            $added = Add-Missing $gameDir $repoDir
            if ($added -gt 0) { Write-Host "Moved $added art file(s) from the game folder into the repo" }
        }
        Remove-Folder $gameDir
        New-Item -ItemType Junction -Path $gameDir -Target $repoDir | Out-Null
        Write-Host "$dir -> $repoDir (junction)"
    } else {
        if ($dir -eq "Scripts") {
            Remove-Folder $gameDir # code is always replaced
            Copy-Item $repoDir $gameDir -Recurse
        } else {
            if (Test-Junction $gameDir) { Remove-Folder $gameDir }
            $added = Add-Missing $repoDir $gameDir
            Write-Host "Art: $added new file(s)"
        }
    }
}

# Developer features (the API dump) live in ..\dev, never in releases. -Link links them in as Mods\FrameMage\dev;
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

foreach ($dir in "config", "layouts", "dumps", "share") {
    Add-Missing (Join-Path $src $dir) (Join-Path $dst $dir) | Out-Null
}

# Frame Mage no longer has a Mod Menu page (its own Settings panel replaced it): remove the old page so Mod Menu stops
# listing Frame Mage. (modmenu-settings.txt is left alone: it's only the old page's saved values.)
$oldPage = Join-Path $dst "modmenu.json"
if (Test-Path $oldPage) { Remove-Item $oldPage -Force; Write-Host "Removed the old Mod Menu page (modmenu.json)" }

# Enabled via enabled.txt rather than mods.txt: Vortex manages mods.txt and may rewrite it.
Set-Content (Join-Path $dst "enabled.txt") "" -Encoding ascii
Write-Host ("Deployed to $dst" + $(if ($Link) { " (linked)" } else { " (copied)" }))
