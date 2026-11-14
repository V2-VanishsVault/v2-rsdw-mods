-- Developer keys for Frame Mage's own features: reload the theme's art (Ctrl+F10) and play the level-up
-- celebration (Ctrl+F8). Not in releases: this file lives in dev/, which only a development install has
-- (tools\deploy.ps1 -Link). The keys are in defaults.lua (keys.reloadArt, keys.previewCelebration).
local M = {}

function M.init(c)
    local f = c.features
    c.keys.bind(c.settings.keys.reloadArt, "reloadArt", function()
        if f.art then f.art.reload() else c.log.warn("art reload: the art feature isn't running") end
    end)
    c.keys.bind(c.settings.keys.previewCelebration, "previewCelebration", function()
        if f.celebrate then f.celebrate.preview() else c.log.warn("preview: the celebrate feature isn't running") end
    end)
end

return M
