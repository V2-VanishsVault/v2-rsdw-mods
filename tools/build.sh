#!/usr/bin/env bash
# Builds one mod's release zip: dist/<ModFolder>-<version>.zip, ready to unzip into ue4ss/Mods.
#
#   tools/build.sh <mod> [version]     e.g. tools/build.sh framemage 1.2.0
#
# <mod> is a folder under mods/ (framemage, storagemage...). The mod's game folder is the one directory inside it
# that holds Scripts/main.lua (mods/framemage/FrameMage). The zip holds:
#   - that folder's Scripts/ and Art/ (never config/, dumps/, layouts/, saves/ or share/: those are the player's,
#     and never the mod's dev/ folder: developer features stay out of releases)
#   - empty config/ dumps/ layouts/ saves/ share/ folders the mod expects, and enabled.txt
#   - shared/settingspanel/ copied in as Scripts/settingspanel/ (when it has code)
#   - VERSION (the version given, else "dev")
# Runs in Git Bash on Windows, in WSL and on GitHub's Ubuntu runners.
set -euo pipefail

mod="${1:?usage: tools/build.sh <mod> [version]}"
version="${2:-dev}"
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
src="$root/mods/$mod"
[ -d "$src" ] || { echo "no such mod: mods/$mod" >&2; exit 1; }

game=""
for d in "$src"/*/; do
    if [ -f "$d/Scripts/main.lua" ]; then game="${d%/}"; break; fi
done
[ -n "$game" ] || { echo "mods/$mod has no folder with Scripts/main.lua" >&2; exit 1; }
name="$(basename "$game")"

stage="$root/dist/stage/$name"
rm -rf "$root/dist/stage"
mkdir -p "$stage"
cp -R "$game/Scripts" "$stage/Scripts"
[ -d "$game/Art" ] && cp -R "$game/Art" "$stage/Art"
for d in config dumps layouts saves share; do
    if [ -d "$game/$d" ]; then mkdir -p "$stage/$d" && touch "$stage/$d/.keep"; fi
done
: > "$stage/enabled.txt"

# the shared Settings panel, when there's code in it
if compgen -G "$root/shared/settingspanel/*.lua" > /dev/null; then
    mkdir -p "$stage/Scripts/settingspanel"
    cp "$root/shared/settingspanel/"*.lua "$stage/Scripts/settingspanel/"
fi

echo "$version" > "$stage/VERSION"
find "$stage" \( -name luac.out -o -name '*.tmp' -o -name '*.bad' -o -name __pycache__ \) -prune -exec rm -rf {} +

zip="$root/dist/$name-$version.zip"
rm -f "$zip"
if command -v zip > /dev/null; then
    (cd "$root/dist/stage" && zip -qr "$zip" "$name")
else
    # (Git Bash has no zip: Windows' own tar, not Git's, writes zip files)
    (cd "$root/dist/stage" && /c/Windows/System32/tar.exe -a -cf "../$name-$version.zip" "$name")
fi
rm -rf "$root/dist/stage"
echo "$zip"
