local function bird_get_mod_version()
    local value = version
    if value == nil and KnownModIndex ~= nil and modname ~= nil and KnownModIndex.GetModInfo ~= nil then
        local ok, info = pcall(KnownModIndex.GetModInfo, KnownModIndex, modname)
        if ok and info ~= nil then
            value = info.version
        end
    end
    return tostring(value or "")
end

GLOBAL.BIRD_PVP_VERSION = bird_get_mod_version()
GLOBAL.BIRD_PVP_DEBUG = string.find(string.lower(GLOBAL.BIRD_PVP_VERSION), "beta", 1, true) ~= nil
-- Root registration entry for the scripts/src layout.
-- modimport paths are relative to the mod root, so they include "scripts/".
modimport("scripts/src/pvp.lua")
