-- Writes FrameMage/modmenu.json from the schema in features/modmenu.lua and the defaults in defaults.lua.
--   lua tools/gen_modmenu.lua        (from the repo root; tests/run_tests.lua checks the file is current)
package.path = "FrameMage/Scripts/?.lua;" .. package.path
local modmenu = require("framemage.features.modmenu")
local defaults = require("framemage.defaults")
local f = assert(io.open("FrameMage/modmenu.json", "wb"))
f:write(modmenu.toJson(defaults, "0.1.0"))
f:close()
print("wrote FrameMage/modmenu.json")
