-- Observer-only team status snapshots and client RPC synchronization.
local M = {}
local team_state = require("src/team/lobby_team_state")
local subscribers = {}

local RPC_NAMESPACE = "bird_mode_clientrpc"
local RPC_NAME = "bird_mode_clientrpc"

local function equipment_snapshot(player)
    local result = {}
    if player.components.inventory == nil then
        return result
    end

    for slot, item in pairs(player.components.inventory.equipslots) do
        if item ~= nil then
            local percent = nil
            if item.components.finiteuses ~= nil then
                percent = item.components.finiteuses:GetPercent()
            elseif item.components.fueled ~= nil then
                percent = item.components.fueled:GetPercent()
            elseif item.components.armor ~= nil then
                percent = item.components.armor:GetPercent()
            elseif item.components.perishable ~= nil then
                percent = item.components.perishable:GetPercent()
            end

            local image = item.replica.inventoryitem ~= nil
                and item.replica.inventoryitem:GetImage()
                or nil
            result[slot] = { image, percent }
        end
    end
    return result
end

local function build_snapshot()
    local teams = { {}, {} }
    for _, player in ipairs(AllPlayers) do
        local team_id, pending = team_state.get_player_team(player)
        if player:IsValid() and not pending and teams[team_id] ~= nil then
            local dead = IsEntityDeadOrGhost(player, true)
            table.insert(teams[team_id], {
                nm = player.name,
                pr = player.prefab,
                id = player.userid,
                sw = {
                    math.floor(player.components.hunger.current),
                    math.floor(player.components.sanity.current),
                    math.floor(dead and 0 or player.components.health.currenthealth),
                },
                dd = dead,
                eq = equipment_snapshot(player),
            })
        end
    end
    return teams
end

local function broadcast()
    local ok, payload = pcall(json.encode, build_snapshot())
    if not ok then
        return
    end

    for player in pairs(subscribers) do
        if player:IsValid() and player.userid ~= nil then
            SendModRPCToClient(CLIENT_MOD_RPC[RPC_NAMESPACE][RPC_NAME], player.userid, payload)
        end
    end
end

function M.set_subscribed(player, enabled)
    subscribers[player] = enabled and true or nil

    if next(subscribers) ~= nil then
        if TheWorld.chakan_task == nil then
            TheWorld.chakan_task = TheWorld:DoPeriodicTask(0.5, broadcast)
        end
    elseif TheWorld.chakan_task ~= nil then
        TheWorld.chakan_task:Cancel()
        TheWorld.chakan_task = nil
    end
end

function M.is_subscribed(player)
    return subscribers[player] == true
end

return M
