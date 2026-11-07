# Installs Forgeframe into the game's UE4SS Mods folder.
#
#   powershell -ExecutionPolicy Bypass -File tools\deploy.ps1          copy (what players use)
#   powershell -ExecutionPolicy Bypass -File tools\deploy.ps1 -Link    development: junction Scripts\ and Art\
#                                                                       to this repo, so edits are live
#   add -GameDir "D:\...\RSDragonwilds" for a non-default install
#
# config\, layouts\ and dumps\ are always real folders in the game directory (personal data; never overwritten).
param(
    [string]$GameDir = "C:\Program Files (x86)\Steam\steamapps\common\RSDragonwilds",
    [switch]$Link
)
$ErrorActionPreference = "Stop"
$src = (Resolve-Path (Join-Path $PSScriptRoot "..\Forgeframe")).Path
$mods = Join-Path $GameDir "RSDragonwilds\Binaries\Win64\ue4ss\Mods"
if (-not (Test-Path $mods)) { throw "UE4SS Mods folder not found: $mods" }
if (Get-Process "RSDragonwilds*" -ErrorAction SilentlyContinue) {
    Write-Warning "The game is running; changes load on the next start."
}
$dst = Join-Path $mods "Forgeframe"
New-Item -ItemType Directory -Force $dst | Out-Null

function Test-Junction($path) {
    (Test-Path $path) -and ((Get-Item $path -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)
}

# Removes a folder. A junction is only unlinked: Remove-Item -Recurse on a junction in Windows PowerShell 5.1
# deletes the files in its TARGET (here, the repo).
function Remove-Folder($path) {
    if (-not (Test-Path $path)) { return }
    if (Test-Junction $path) { [IO.Directory]::Delete($path, $false) }
    else { Remove-Item $path -Recurse -Force }
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

foreach ($dir in "config", "layouts", "dumps") {
    Add-Missing (Join-Path $src $dir) (Join-Path $dst $dir) | Out-Null
}

# Enabled via enabled.txt rather than mods.txt: Vortex manages mods.txt and may rewrite it.
Set-Content (Join-Path $dst "enabled.txt") "" -Encoding ascii
Write-Host ("Deployed to $dst" + $(if ($Link) { " (linked)" } else { " (copied)" }))
