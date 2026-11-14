# Shared Settings panel

The one Settings panel every mod in this repository draws its settings in (plan:
`mods/framemage/docs/settings-panel-plan.md`). It is never built, tagged or released on its own:

- **Releases:** `tools/build.sh` copies this folder's `*.lua` files into each mod's `Scripts/settingspanel/` inside
  the mod's zip (top level only).
- **Development:** each mod's `tools/deploy.ps1 -Link` is to link it into that mod's `Scripts/settingspanel/`.
  Not added yet (plan, step 5).

Not written yet: the panel still lives in Frame Mage (`editor/settings.lua`). The Frame Mage session owns this
folder.
