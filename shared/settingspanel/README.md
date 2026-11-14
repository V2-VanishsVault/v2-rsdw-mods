# Shared Settings panel

The one Settings panel every mod in this repository draws its settings in (plan:
`mods/framemage/docs/settings-panel-plan.md`). It is never built, tagged or released on its own:

- **Releases:** `tools/build.sh` copies this folder into each mod's `Scripts/settingspanel/` inside the mod's zip.
- **Development:** each mod's `tools/deploy.ps1 -Link` links it into the game's copy of that mod.

Not written yet: the panel still lives in Frame Mage (`editor/settings.lua`).
