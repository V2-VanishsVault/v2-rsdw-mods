-- Example material theme. Copy this file to materials.lua (same folder) to use it; Ctrl+F10 reloads in game.
--
-- Material effects are the animated/shader parts of the UI (bars, rings, highlights, vignettes). Theming
-- changes their parameters, so fills and animation keep working. Get the real effect and parameter names
-- from dumps/materials.txt (press Ctrl+F9 in game with the effect on screen); the names below are examples
-- taken from a dump and must match exactly.
--
--   vectors   colours: "#RRGGBB" / "#RRGGBBAA" (sRGB, as a colour picker shows) or { r, g, b, a } (linear)
--   scalars   numbers
--   textures  a PNG in this folder, by file name (".png" optional)
--   force     true = re-apply whenever the game sets these parameters itself (needed for animated values)
--
-- A key can be an effect name (MID_..., MI_...) or the material an effect is a copy of; the effect name wins.
return {
    -- MI_Item_Selected = {
    --     vectors = { Color = "#4FA3FF" },
    -- },

    -- MID_MI_CurvedProgressBar_WeaponEffect = {
    --     vectors = { FillColor = "#D04A2A", BackgroundColor = "#1A1410CC" },
    --     force = true,
    -- },
}
