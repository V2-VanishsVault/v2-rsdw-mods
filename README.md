# V2 RuneScape: Dragonwilds mods

UE4SS Lua mods for RuneScape: Dragonwilds, from V2 - VanishsVault. Each mod is built and released on its own.

> Created using intellectual property belonging to Jagex Limited under the terms of Jagex's Fan Content Policy.
> This content is not endorsed by or affiliated with Jagex.

| Mod | Folder | What it does |
|---|---|---|
| Frame Mage | `mods/framemage` | UI: move, scale, fade or hide any widget; themes; restyled HUD and windows |
| Storage Mage | `mods/storagemage` | Bags and inventory pages |

Map Mage and Spell Mage will join under `mods/` when they start.

## Layout

```
mods/<mod>/        one mod: its game folder (FrameMage/, StorageMage/), tests, tools, docs
shared/            code built into several mods, never released alone (the shared Settings panel)
listings/<mod>/    the mod's pages on Nexus Mods and CurseForge: description, summary, images, screenshots
tools/build.sh     builds one mod's release zip
.github/workflows  CI (tests for the mods that changed) and releases (one mod per tag)
```

## Developing

- **Install into the game, linked to this repository** (edits are live on the next game start):
  `powershell -ExecutionPolicy Bypass -File mods\<mod>\tools\deploy.ps1 -Link`
- **Tests:** from a mod's folder, `lua tests/run_tests.lua` (Lua 5.4).
- **A release zip on your machine:** `bash tools/build.sh <mod> <version>` writes `dist/<Mod>-<version>.zip`.

## Releasing

Push a tag named `<mod>-v<version>`:

```
git tag framemage-v1.0.0
git push origin framemage-v1.0.0
```

The Release workflow runs that mod's tests, builds its zip (with `shared/` built in and a `VERSION` file) and
publishes a GitHub release. A version with a dash (`1.0.0-beta.1`) is published as a pre-release.
