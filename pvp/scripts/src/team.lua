-- Team system loader: component, RPC action support, chat, markers, research, and lobby team sync.
-- Only registration scripts are loaded with modimport. Shared data/action modules remain require modules.

local function add_prefab_once(name)
    PrefabFiles = PrefabFiles or {}
    for _, prefab in ipairs(PrefabFiles) do
        if prefab == name then
            return
        end
    end
    table.insert(PrefabFiles, name)
end

add_prefab_once("bird_duiwufx")

modimport("scripts/src/team/lobby_team_sync.lua")
modimport("scripts/src/team/marker_hooks.lua")
modimport("scripts/src/team/component.lua")
modimport("scripts/src/team/chat.lua")
modimport("scripts/src/team/research.lua")
