-- [PATCH] 新增：比赛结束检测、胜利烟花、世界重置倒计时与结算面板调用。
-- 当一方队伍全部阵亡或离线时自动判定另一方获胜；管理员可用控制台命令
-- c_bird_endmatch 强制结束。胜利后等待 1 分钟再启动 30 秒重置倒计时，
-- 管理员可用 c_bird_cancelreset 取消。

local team_state = require("src/team/lobby_team_state")

local TEAM_RED = team_state.TEAM_RED
local TEAM_BLUE = team_state.TEAM_BLUE

local _match_ended = false
local _reset_task = nil
local _reset_seconds_left = 0
local _pending_victory_task = nil  -- [PATCH] 自动胜负判定的 1 分钟延迟任务

local function IsAuthorityShard()
    if TheWorld == nil then
        return false
    end
    if TheWorld.HasTag ~= nil and TheWorld:HasTag("cave") then
        return false
    end
    return TheWorld.worldprefab ~= "cave" and TheWorld.prefab ~= "cave"
end

local function IsGameStarted()
    local lobby = TheWorld ~= nil
        and TheWorld.net ~= nil
        and TheWorld.net.components ~= nil
        and TheWorld.net.components.worldcharacterselectlobby
        or nil
    if lobby ~= nil and lobby.HasGameStarted ~= nil then
        return lobby:HasGameStarted()
    end
    return false
end

local function GetLivingPlayersByTeam()
    local red = {}
    local blue = {}
    for _, player in ipairs(AllPlayers or {}) do
        if player.userid ~= nil and player.userid ~= "" then
            local team, pending = team_state.get_player_team(player, nil)
            if not pending then
                if team == TEAM_RED and player.components.health ~= nil and not player.components.health:IsDead() then
                    table.insert(red, player)
                elseif team == TEAM_BLUE and player.components.health ~= nil and not player.components.health:IsDead() then
                    table.insert(blue, player)
                end
            end
        end
    end
    return red, blue
end

local function TryStartFX(prefab_name, x, y, z)
    local fx = SpawnPrefab(prefab_name)
    if fx == nil then
        return false
    end
    fx.Transform:SetPosition(x, y, z)

    -- Fireworks prefabs expose different activation methods across DST versions.
    local function try_call(method_name)
        if fx[method_name] ~= nil then
            local ok = pcall(function() fx[method_name](fx) end)
            return ok
        end
        return false
    end

    try_call("DoFireworks")
    try_call("Light")
    try_call("Ignite")

    if fx.components ~= nil and fx.components.burnable ~= nil and fx.components.burnable.Ignite ~= nil then
        pcall(function() fx.components.burnable:Ignite() end)
    end

    return true
end

local function SpawnFireworkBurst(x, y, z)
    -- Primary: the seasonal fireworks prefab.
    if TryStartFX("fireworks", x, y, z) then
        TryStartFX("fireworks", x, y + 2, z)
        return
    end

    -- Fallback 1: small explosion + sparkles.
    TryStartFX("explode_small", x, y, z)
    TryStartFX("sparklefx", x, y + 1, z)

    -- Fallback 2: lightning-like flash.
    TryStartFX("lightning", x, y, z)
end

local function SpawnFireworksForTeam(players)
    for _, player in ipairs(players) do
        if player:IsValid() then
            local x, y, z = player.Transform:GetWorldPosition()
            SpawnFireworkBurst(x, y, z)
        end
    end
end

local function BroadcastSettlement(winner_team)
    local round = BirdFinalizeRoundStats()
    local payload = json.encode({
        winner = winner_team,
        red = round.teams.red,
        blue = round.teams.blue,
    })

    for _, player in ipairs(AllPlayers or {}) do
        if player.userid ~= nil and player.userid ~= "" then
            SendModRPCToClient(GetClientModRPC("bird_pvp_settlement", "show"), player.userid, payload)
        end
    end

    -- Also send to clients still in lobby/migration if possible.
    for _, client in ipairs(TheNet:GetClientTable() or {}) do
        if client.userid ~= nil and client.userid ~= "" then
            local found = false
            for _, player in ipairs(AllPlayers or {}) do
                if player.userid == client.userid then
                    found = true
                    break
                end
            end
            if not found then
                SendModRPCToClient(GetClientModRPC("bird_pvp_settlement", "show"), client.userid, payload)
            end
        end
    end
end

local function CancelWorldReset(reason)
    if _pending_victory_task ~= nil then
        _pending_victory_task:Cancel()
        _pending_victory_task = nil
    end
    if _reset_task ~= nil then
        _reset_task:Cancel()
        _reset_task = nil
    end
    _reset_seconds_left = 0
    if TheNet ~= nil and TheNet.Announce ~= nil then
        TheNet:Announce(reason or "世界重置已取消。")
    end
end

local VICTORY_DELAY_SECONDS = 60  -- [PATCH] 自动胜负判定的延迟时间：对方全灭后等待 1 分钟再判胜。
local RESET_COUNTDOWN_SECONDS = 30

local function RequestWorldReset()
    if _reset_task ~= nil then
        _reset_task:Cancel()
        _reset_task = nil
    end
    _reset_seconds_left = RESET_COUNTDOWN_SECONDS

    local function Tick()
        if TheWorld == nil or not TheWorld.ismastersim then
            _reset_task = nil
            return
        end

        if _reset_seconds_left > 0 then
            if TheNet ~= nil and TheNet.Announce ~= nil then
                if _reset_seconds_left == RESET_COUNTDOWN_SECONDS or _reset_seconds_left == 20 or _reset_seconds_left == 10 or _reset_seconds_left <= 5 then
                    TheNet:Announce(_reset_seconds_left .. " 秒后重新生成世界，管理员可输入 /cancelreset 取消。")
                end
            end
            _reset_seconds_left = _reset_seconds_left - 1
            _reset_task = TheWorld:DoTaskInTime(1, Tick)
        else
            _reset_task = nil
            if TheNet ~= nil and TheNet.Announce ~= nil then
                TheNet:Announce("正在重新生成世界...")
            end
            -- Try the standard console regenerate command first (works for hosted games).
            if GLOBAL.c_regenerateworld ~= nil then
                pcall(GLOBAL.c_regenerateworld)
            elseif GLOBAL.c_reset ~= nil then
                pcall(GLOBAL.c_reset)
            elseif TheWorld ~= nil then
                TheWorld:PushEvent("ms_saveandshutdown", { reset = true })
            end
        end
    end

    Tick()
end

-- [PATCH] 核心结束逻辑：广播获胜方、燃放烟花、推送结算面板并立即启动 30 秒重置倒计时。
function GLOBAL.BirdEndMatch(winner_team, reason)
    if not TheWorld.ismastersim then
        return
    end
    if _match_ended then
        return
    end
    -- 取消任何待定的自动胜负判定，避免重复触发。
    if _pending_victory_task ~= nil then
        _pending_victory_task:Cancel()
        _pending_victory_task = nil
    end
    -- 自动检测只在游戏已开始时生效；管理员/控制台命令可在任意分片执行（包括地下）。
    if reason == "auto" and not IsGameStarted() then
        return
    end

    _match_ended = true
    reason = reason or "auto"

    if winner_team ~= TEAM_RED and winner_team ~= TEAM_BLUE then
        local red, blue = GetLivingPlayersByTeam()
        if #red > 0 and #blue == 0 then
            winner_team = TEAM_RED
        elseif #blue > 0 and #red == 0 then
            winner_team = TEAM_BLUE
        else
            -- Draw / undecided; default to red for fireworks placement.
            winner_team = TEAM_RED
        end
    end

    if TheNet ~= nil and TheNet.Announce ~= nil then
        TheNet:Announce("本局结束！" .. (winner_team == TEAM_RED and "红队" or "蓝队") .. " 获胜！")
    end

    local winning_players = {}
    for _, player in ipairs(AllPlayers or {}) do
        local team, pending = team_state.get_player_team(player, nil)
        if not pending and team == winner_team then
            table.insert(winning_players, player)
        end
    end

    SpawnFireworksForTeam(winning_players)
    BroadcastSettlement(winner_team)

    -- Schedule repeated fireworks for a few seconds.
    local bursts = 0
    local function DoRepeatedFireworks()
        if bursts >= 3 then
            return
        end
        bursts = bursts + 1
        SpawnFireworksForTeam(winning_players)
        TheWorld:DoTaskInTime(1.5, DoRepeatedFireworks)
    end
    TheWorld:DoTaskInTime(1.5, DoRepeatedFireworks)

    -- [PATCH] 胜利判定后不再等待额外缓冲，直接启动 30 秒世界重置倒计时。
    -- 管理员可在倒计时期间使用 c_bird_cancelreset 取消。
    RequestWorldReset()
end

-- [PATCH] 自动胜负判定：当一方队伍没有存活玩家时，延迟 1 分钟再判定另一方获胜。
-- 若期间该队伍有玩家复活或加入，则取消待定的胜利判定。
local function CheckMatchEnd()
    if not TheWorld.ismastersim then
        return
    end
    if not IsAuthorityShard() then
        return
    end
    if not IsGameStarted() then
        return
    end
    if _match_ended then
        return
    end

    local red, blue = GetLivingPlayersByTeam()
    if #red == 0 and #blue == 0 then
        -- 双方同时全灭，按平局处理，不触发结束流程。
        return
    end

    local pending_winner = nil
    if #red == 0 then
        pending_winner = TEAM_BLUE
    elseif #blue == 0 then
        pending_winner = TEAM_RED
    end

    if pending_winner == nil then
        -- 两队都还有存活玩家，取消任何待定的胜利判定。
        if _pending_victory_task ~= nil then
            _pending_victory_task:Cancel()
            _pending_victory_task = nil
        end
        return
    end

    if _pending_victory_task ~= nil then
        -- 已有待定的胜利判定，不再重复创建。
        return
    end

    if TheNet ~= nil and TheNet.Announce ~= nil then
        TheNet:Announce("对方队伍已全部阵亡，1 分钟后判定本局结果。")
    end

    _pending_victory_task = TheWorld:DoTaskInTime(VICTORY_DELAY_SECONDS, function()
        _pending_victory_task = nil
        -- 延迟结束后再检查一次，确认对方队伍仍未复活。
        local r, b = GetLivingPlayersByTeam()
        if pending_winner == TEAM_BLUE and #r == 0 then
            GLOBAL.BirdEndMatch(TEAM_BLUE, "red eliminated")
        elseif pending_winner == TEAM_RED and #b == 0 then
            GLOBAL.BirdEndMatch(TEAM_RED, "blue eliminated")
        end
    end)
end

local function ResetMatchEndState()
    _match_ended = false
    CancelWorldReset()
end

local function ParseWinner(text)
    if text == nil then
        return nil
    end
    text = string.lower(tostring(text))
    if text == "red" or text == "r" or text == "红" or text == "红队" then
        return TEAM_RED
    elseif text == "blue" or text == "b" or text == "蓝" or text == "蓝队" then
        return TEAM_BLUE
    end
    return nil
end

-- Server RPC so the console command works from any shard (including caves).
local function IsAdminPlayer(player)
    if player == nil then
        return true
    end
    local ok, is_admin = pcall(function()
        if player.Network ~= nil and player.Network.IsServerAdmin ~= nil then
            return player.Network:IsServerAdmin()
        end
        if TheNet ~= nil and TheNet.GetIsServerAdmin ~= nil then
            return TheNet:GetIsServerAdmin(player.userid)
        end
        return false
    end)
    return ok and is_admin
end

AddModRPCHandler("bird_pvp_match", "admin_end", function(player, winner)
    if not IsAdminPlayer(player) then
        return
    end
    GLOBAL.BirdEndMatch(ParseWinner(winner), "admin command")
end)

AddModRPCHandler("bird_pvp_match", "admin_cancel_reset", function(player)
    if not IsAdminPlayer(player) then
        return
    end
    CancelWorldReset("世界重置已取消。")
end)

-- [PATCH] 控制台命令：管理员强制结束本局或取消自动重置，支持从地下分片发送 RPC 到地面执行。
function GLOBAL.c_bird_endmatch(winner)
    local team = ParseWinner(winner)
    if TheWorld ~= nil and TheWorld.ismastersim then
        GLOBAL.BirdEndMatch(team, "console command")
    elseif SendModRPCToServer ~= nil and GetModRPC ~= nil then
        SendModRPCToServer(GetModRPC("bird_pvp_match", "admin_end"), tostring(winner or ""))
    end
end

function GLOBAL.c_bird_cancelreset()
    if TheWorld ~= nil and TheWorld.ismastersim then
        CancelWorldReset("世界重置已取消。")
    elseif SendModRPCToServer ~= nil and GetModRPC ~= nil then
        SendModRPCToServer(GetModRPC("bird_pvp_match", "admin_cancel_reset"))
    end
end

AddPrefabPostInit("world", function(inst)
    if not inst.ismastersim then
        return
    end

    inst:ListenForEvent("ms_playerdied", function(_, data)
        if data ~= nil and data.player ~= nil then
            inst:DoTaskInTime(0.5, CheckMatchEnd)
        end
    end, inst)

    -- Reset when a new lobby/round begins.
    inst:ListenForEvent("ms_clientauthenticationcomplete", function()
        if not IsGameStarted() then
            ResetMatchEndState()
        end
    end, inst)
end)

-- Also check on player death in case the world event is missed.
AddPlayerPostInit(function(inst)
    if inst.components.health ~= nil then
        local old_OnDeath = inst.components.health.OnDeath
        inst.components.health.OnDeath = function(self, ...)
            old_OnDeath(self, ...)
            if TheWorld ~= nil then
                TheWorld:DoTaskInTime(0.5, CheckMatchEnd)
            end
        end
    end
end)
