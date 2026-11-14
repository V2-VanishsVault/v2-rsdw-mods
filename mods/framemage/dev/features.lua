-- Frame Mage's developer features: loaded only when this folder is installed (tools\deploy.ps1 -Link links it into
-- the game as Mods\FrameMage\dev). Release zips never contain it. Each name is a module under framemage/features/
-- in this folder, started after the mod's own features, in this order.
--   inspector  Ctrl+F9 / Ctrl+Shift+F9: what's on screen -> dumps/widgets.txt, textures.txt, materials.txt
--   devkeys    Ctrl+F10 reloads the theme's art; Ctrl+F8 plays the level-up celebration
--   apidump    Numpad +: the game's functions for the classes a feature drives -> dumps/api.txt
return { "inspector", "devkeys", "apidump" }
