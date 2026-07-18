-- Synchronizes lobby team assignments before player entities exist.
-- Lobby-safe client -> server transport uses user commands because ordinary
-- player Mod RPC handlers depend on an in-world player entity.
local UserCommands = require("usercommands")
local lobby_team_state = require("src/team/lobby_team_state")
local player_state = require("src/team/player_state")
local admin_privileges = require("src/admin/privileges")
local debug_log = require("src/core/debug")

local AUTO_COMMAND_NAME = "bird_auto_lobby_team"
local SELECT_COMMAND_NAME = "bird_lobby_team"
local LOCK_COMMAND_NAME = "bird_lobby_team_lock"
local NET_DIRTY_EVENT = "bird_lobby_teams_dirty"
local NET_VAR_NAME = "bird_preselect_teams._value"
local SHARD_RPC_NAMESPACE = "bird_pvp_team"
local SHARD_RPC_SNAPSHOT = "snapshot"
local SHARD_RPC_REQUEST = "request_snapshot"
local PERSIST_KEY_PREFIX = "mod_config_data/bird_pvp_lobby_teams"
local LOCK_META_ENTRY = "__lock=1"
local AUTO_ASSIGN_WAITING = "waiting"
local AUTO_ASSIGN_ALL = "all"
local TEAM_OBSERVER = 0
local TEAM_RED = 1
local TEAM_BLUE = 2
local TEAM_WAITING = 3
local TEAM_COLOURS = {
    [TEAM_RED] = { 1, 0, 0, 1 },
    [TEAM_BLUE] = { 25 / 255, 88 / 255, 1, 1 },
}

local function IsValidTeam(team_id)
    return lobby_team_state.is_valid(team_id)
end

local function IsValidUserId(userid)
    return userid ~= nil and userid ~= ""
end

local function IsDedicatedHostRecord(client)
    return TheNet ~= nil
        and not TheNet:GetServerIsClientHosted()
        and client ~= nil
        and client.performance ~= nil
end

local function IsPlayableClientRecord(client)
    return client ~= nil
        and IsValidUserId(client.userid)
        and not IsDedicatedHostRecord(client)
end

local function EncodeTeams(teams, global_locked)
    local entries = {}
    for userid, team_id in pairs(teams) do
        if IsValidUserId(userid) and IsValidTeam(team_id) then
            table.insert(entries, userid .. "=" .. tostring(team_id))
        end
    end
    if global_locked == true then
        table.insert(entries, LOCK_META_ENTRY)
    end
    table.sort(entries)
    return table.concat(entries, ";")
end

local function DecodeTeams(payload)
    local teams = {}
    local locks = {}
    local global_locked = false
    if type(payload) ~= "string" or payload == "" then
        return teams, locks, global_locked
    end

    for entry in string.gmatch(payload, "[^;]+") do
        if entry == LOCK_META_ENTRY then
            global_locked = true
        else
            local userid, team_text, locked_text = string.match(entry, "^([^=]+)=([0123])(!?)$")
            local team_id = lobby_team_state.normalize(team_text)
            if IsValidUserId(userid) and team_id ~= nil then
                teams[userid] = team_id
                locks[userid] = locked_text == "!"
            end
        end
    end

    return teams, locks, global_locked
end

local function IsTeamLocked(net, userid)
    return net ~= nil and net._bird_lobby_team_global_lock == true
end

local function GetPersistentSession()
    local session = nil
    if TheWorld ~= nil and TheWorld.meta ~= nil then
        session = TheWorld.meta.session_identifier
            or TheWorld.meta.session_id
            or TheWorld.meta.save_id
    end
    if session == nil and TheNet ~= nil and TheNet.GetSessionIdentifier ~= nil then
        local ok, value = pcall(TheNet.GetSessionIdentifier, TheNet)
        session = ok and value or nil
    end

    return session
end

local function IsCaveShard()
    if TheWorld == nil then
        return false
    end

    if TheWorld.HasTag ~= nil and TheWorld:HasTag("cave") then
        return true
    end

    return TheWorld.worldprefab == "cave"
        or TheWorld.prefab == "cave"
end

local function IsAuthorityShard()
    return not IsCaveShard()
end

local function GetPersistentKey()
    return PERSIST_KEY_PREFIX
        .. "_"
        .. tostring(GetPersistentSession() or "default")
end

local function HasAnyTeam(teams)
    for _ in pairs(teams or {}) do
        return true
    end
    return false
end

local function IsPlayingTeam(team_id)
    return team_id == TEAM_RED or team_id == TEAM_BLUE
end

local function MergeTeams(net, loaded, loaded_locks, loaded_global_locked)
    local merged = {}
    for userid, team_id in pairs(loaded or {}) do
        if IsValidTeam(team_id) then
            merged[userid] = team_id
        end
    end

    -- Keep live lobby selections made while the persisted table was loading.
    for userid, team_id in pairs(net._bird_lobby_teams or {}) do
        if IsValidTeam(team_id) then
            merged[userid] = team_id
        end
    end
    net._bird_lobby_teams = merged
    net._bird_lobby_team_locks = {}
    if type(net._bird_lobby_team_global_lock) ~= "boolean" then
        net._bird_lobby_team_global_lock = loaded_global_locked == true
    end
end

local function SaveTeams(net, reason)
    if not IsAuthorityShard() then
        debug_log.log("team-sync", "persist skipped", reason or "unknown", "non-authority shard")
        return
    end
    if net == nil or net._bird_lobby_teams == nil or SavePersistentString == nil then
        return
    end
    if net._bird_lobby_teams_ready == false then
        debug_log.log("team-sync", "persist deferred", reason or "unknown")
        return
    end

    local payload = EncodeTeams(net._bird_lobby_teams, net._bird_lobby_team_global_lock)
    SavePersistentString(GetPersistentKey(), payload, false, nil)
    debug_log.log("team-sync", "persist", reason or "unknown", payload)
end

local function LoadTeams(net, reason, on_complete)
    if not IsAuthorityShard() or net == nil or TheSim == nil or TheSim.GetPersistentString == nil then
        if on_complete ~= nil then
            on_complete(false, {}, {}, false)
        end
        return
    end

    local key = GetPersistentKey()

    net._bird_lobby_teams_ready = false

    TheSim:GetPersistentString(key, function(success, payload)
        local loaded, loaded_locks, loaded_global_locked = DecodeTeams(success and payload or nil)
        local source = HasAnyTeam(loaded) and "primary" or "empty"
        debug_log.log("team-sync", "loaded", tostring(success), tostring(source), EncodeTeams(loaded, loaded_global_locked))
        if on_complete ~= nil then
            on_complete(success, loaded, loaded_locks, loaded_global_locked)
        end
    end)
end

local function SendShardTeamSnapshot(target_shards, payload, reason)
    if SendModRPCToShard == nil or GetShardModRPC == nil then
        debug_log.log("team-shard", "send skipped", reason or "unknown", "rpc unavailable")
        return false
    end

    local rpc = GetShardModRPC(SHARD_RPC_NAMESPACE, SHARD_RPC_SNAPSHOT)
    if rpc == nil then
        debug_log.log("team-shard", "send skipped", reason or "unknown", "rpc missing")
        return false
    end

    SendModRPCToShard(rpc, target_shards, payload or "")
    debug_log.log("team-shard", "snapshot sent", reason or "unknown", tostring(target_shards), payload or "")
    return true
end

local function PublishTeams(net, reason)
    if net == nil or net.bird_preselect_teams_net == nil then
        debug_log.log("team-sync", "publish skipped", reason or "unknown", "netvar missing")
        return
    end
    if net._bird_lobby_teams_ready == false then
        debug_log.log("team-sync", "publish deferred", reason or "unknown")
        return
    end

    local payload = EncodeTeams(net._bird_lobby_teams or {}, net._bird_lobby_team_global_lock)
    net.bird_preselect_teams_net:set(payload)
    debug_log.log("team-sync", "publish", reason or "unknown", payload)
    if TheWorld ~= nil and TheWorld.PushEvent ~= nil then
        TheWorld:PushEvent(NET_DIRTY_EVENT, {
            reason = reason,
            payload = payload,
        })
    end
    if IsAuthorityShard() then
        SendShardTeamSnapshot(nil, payload, reason or "publish")
    end
end

local function Shuffle(players)
    for i = #players, 2, -1 do
        local j = math.random(i)
        players[i], players[j] = players[j], players[i]
    end
end

local function AnnounceTeam(team_id, message)
    if TheNet ~= nil then
        TheNet:Announce(message, TEAM_COLOURS[team_id] or { 1, 1, 1, 1 })
    end
end

local function GetClientDisplayName(client)
    return tostring(client.name or client.userid or "未知玩家")
end

local function SetLobbyTeam(userid, team_id, reason)
    if not IsAuthorityShard() then
        debug_log.log("team-sync", "set skipped", reason or "unknown", "non-authority shard")
        return
    end

    local net = TheWorld ~= nil and TheWorld.net or nil
    if net == nil or not IsValidUserId(userid) then
        debug_log.log("team-sync", "set skipped", reason or "unknown", "userid", tostring(userid), "net", tostring(net ~= nil))
        return
    end
    net._bird_lobby_teams = net._bird_lobby_teams or {}

    local raw_team = team_id
    team_id = tonumber(team_id)
    if team_id == nil then
        debug_log.log("team-sync", "set invalid", reason or "unknown", tostring(userid), "raw", tostring(raw_team))
        return
    end

    team_id = math.floor(team_id)
    if not IsValidTeam(team_id) then
        debug_log.log("team-sync", "set invalid team", reason or "unknown", tostring(userid), tostring(team_id))
        return
    end

    net._bird_lobby_teams[userid] = team_id
    debug_log.log("team-sync", "set", reason or "unknown", tostring(userid), tostring(team_id))
    SaveTeams(net, reason or "set")
    PublishTeams(net, reason or "set")
end

local function SetLobbyTeamGlobalLock(locked, reason)
    if not IsAuthorityShard() then
        debug_log.log("team-sync", "lock skipped", reason or "unknown", "non-authority shard")
        return false
    end

    local net = TheWorld ~= nil and TheWorld.net or nil
    if net == nil then
        debug_log.log("team-sync", "lock skipped", reason or "unknown", "net missing")
        return false
    end

    net._bird_lobby_teams = net._bird_lobby_teams or {}
    net._bird_lobby_team_locks = net._bird_lobby_team_locks or {}
    net._bird_lobby_team_global_lock = locked == true

    debug_log.log("team-sync", "global lock", reason or "unknown", tostring(locked == true))
    SaveTeams(net, reason or "lock")
    PublishTeams(net, reason or "lock")
    return true
end

local function GetTeamParam(params)
    if type(params) ~= "table" then
        return params
    end
    return params.team or params[1]
end

local function GetLockStateParam(params)
    local value = type(params) == "table" and (params.locked or params[1]) or params
    return value == true or value == "1" or value == "true"
end

local function GetAutoAssignMode(params)
    local mode = type(params) == "table" and (params.mode or params[1]) or params
    return mode == AUTO_ASSIGN_ALL and AUTO_ASSIGN_ALL or AUTO_ASSIGN_WAITING
end

local function SelectLobbyTeam(params, caller)
    local userid = caller ~= nil and caller.userid or nil
    local team = GetTeamParam(params)
    debug_log.log("team-sync", "select command", tostring(userid), "team", tostring(team), "params", tostring(params))
    if not IsValidUserId(userid) then
        return
    end
    local net = TheWorld ~= nil and TheWorld.net or nil
    if IsTeamLocked(net, userid) and not admin_privileges.is_lobby_admin(caller) then
        debug_log.log("team-sync", "select rejected locked", tostring(userid), "team", tostring(team))
        PublishTeams(net, "select-locked")
        return
    end
    SetLobbyTeam(userid, team, "select")
end

local function SetLobbyTeamLockCommand(params, caller)
    if not admin_privileges.is_lobby_admin(caller) then
        debug_log.log("team-sync", "lock rejected", tostring(caller ~= nil and caller.userid or nil))
        return
    end

    SetLobbyTeamGlobalLock(GetLockStateParam(params), "admin-lock")
end

local function IsLobbySelectionOpen()
    local net = TheWorld ~= nil and TheWorld.net or nil
    local lobby = net ~= nil and net.components ~= nil and net.components.worldcharacterselectlobby or nil
    return lobby ~= nil
        and lobby.IsAllowingCharacterSelect ~= nil
        and lobby:IsAllowingCharacterSelect()
end

local function IsLateJoinLobbyOpen()
    local net = TheWorld ~= nil and TheWorld.net or nil
    local lobby = net ~= nil and net.components ~= nil and net.components.worldcharacterselectlobby or nil
    if lobby == nil
        or lobby.LATE_JOIN == false
        or lobby.HasGameStarted == nil
        or not lobby:HasGameStarted() then
        return false
    end

    return lobby.IsServerLockedForShutdown == nil or not lobby:IsServerLockedForShutdown()
end

local function IsPreSpawnLobbyPhase()
    if IsCaveShard() then
        return false
    end

    local net = TheWorld ~= nil and TheWorld.net or nil
    local lobby = net ~= nil and net.components ~= nil and net.components.worldcharacterselectlobby or nil
    if lobby == nil then
        return false
    end

    if lobby.IsAllowingCharacterSelect ~= nil and lobby:IsAllowingCharacterSelect() then
        return true
    end

    return #AllPlayers == 0
        and lobby.GetSpawnDelay ~= nil
        and lobby:GetSpawnDelay() >= 0
end

local function GetDefaultPreselectTeam()
    if IsCaveShard() then
        return nil
    end

    if IsPreSpawnLobbyPhase() then
        return TEAM_WAITING
    end

    if IsLateJoinLobbyOpen() then
        return TEAM_OBSERVER
    end

    return nil
end

local function KeepDisconnectedPreselectTeam(_, data)
    if data ~= nil and IsValidUserId(data.userid) and IsPreSpawnLobbyPhase() then
        debug_log.log("team-sync", "disconnect preselect keep team", tostring(data.userid))
    end
end

local function EnsurePreselectDefaultWaiting(userid, reason)
    local net = TheWorld ~= nil and TheWorld.net or nil
    local default_team = GetDefaultPreselectTeam()
    if not IsValidUserId(userid) or net == nil or default_team == nil then
        return
    end
    if net._bird_lobby_teams_ready == false then
        debug_log.log("team-sync", "default deferred", reason or "unknown", tostring(userid))
        return
    end

    net._bird_lobby_teams = net._bird_lobby_teams or {}
    if net._bird_lobby_teams[userid] == nil then
        SetLobbyTeam(userid, default_team, reason or "preselect-default")
    end
end

local function QueuePreselectWaitingDefault(net, userid, reason)
    if net == nil or not IsValidUserId(userid) then
        return
    end

    net._bird_preselect_waiting_defaults = net._bird_preselect_waiting_defaults or {}
    net._bird_preselect_waiting_defaults[userid] = {
        reason = reason or "enter-select-default",
        team_id = GetDefaultPreselectTeam(),
    }
end

local function ApplyQueuedPreselectWaitingDefaults(net)
    local queued = net ~= nil and net._bird_preselect_waiting_defaults or nil
    if queued == nil then
        return
    end

    net._bird_preselect_waiting_defaults = nil
    net._bird_lobby_teams = net._bird_lobby_teams or {}
    for userid, data in pairs(queued) do
        local team_id = type(data) == "table" and lobby_team_state.normalize(data.team_id) or TEAM_WAITING
        if not IsValidUserId(userid) then
            debug_log.log("team-sync", "queued enter-select skip invalid userid", tostring(userid))
        elseif net._bird_lobby_teams[userid] == nil then
            net._bird_lobby_teams[userid] = team_id or TEAM_WAITING
            debug_log.log("team-sync", "queued enter-select default", tostring(userid), tostring(net._bird_lobby_teams[userid]))
        else
            debug_log.log("team-sync", "queued enter-select keep team", tostring(userid), tostring(net._bird_lobby_teams[userid]))
        end
    end
end

local function SetPreselectDefaultWaiting(userid, reason)
    local net = TheWorld ~= nil and TheWorld.net or nil
    if not IsValidUserId(userid) or net == nil or GetDefaultPreselectTeam() == nil then
        return
    end

    if net._bird_lobby_teams_ready == false then
        QueuePreselectWaitingDefault(net, userid, reason)
        debug_log.log("team-sync", "enter-select default deferred", reason or "unknown", tostring(userid))
        return
    end

    EnsurePreselectDefaultWaiting(userid, reason or "enter-select-default-waiting")
end

local function SetConnectedPreselectDefault(_, data)
    SetPreselectDefaultWaiting(data ~= nil and data.userid or nil, "connect-enter-select-default")
end

local function EnsureCharacterResetPreselectDefault(_, data)
    if data ~= nil and IsValidUserId(data.userid) and (data.prefab_name == nil or data.prefab_name == "") then
        SetPreselectDefaultWaiting(data.userid, "character-reset-enter-select-default")
    end
end

local function SetCurrentPreselectDefaults(inst)
    if inst == nil or not IsPreSpawnLobbyPhase() or TheNet == nil then
        return
    end

    local clients = TheNet:GetClientTable()
    if clients == nil then
        return
    end

    for _, client in ipairs(clients) do
        if IsPlayableClientRecord(client) then
            EnsurePreselectDefaultWaiting(client.userid, "install-preselect-default")
        end
    end
end

local function FinishTeamLoad(net, success, loaded, loaded_locks, loaded_global_locked, reason)
    MergeTeams(net, loaded, loaded_locks, loaded_global_locked)
    net._bird_lobby_teams_ready = true
    ApplyQueuedPreselectWaitingDefaults(net)
    SaveTeams(net, reason or "load")
    PublishTeams(net, reason or "load")
    SetCurrentPreselectDefaults(net)
end

local function QueueTeamLoad(net, reason, on_complete)
    if net == nil then
        return false
    end

    if net._bird_lobby_teams_loading then
        if on_complete ~= nil then
            net._bird_lobby_teams_load_callbacks = net._bird_lobby_teams_load_callbacks or {}
            table.insert(net._bird_lobby_teams_load_callbacks, on_complete)
        end
        return true
    end

    net._bird_lobby_teams_loading = true
    net._bird_lobby_teams_load_callbacks = {}
    if on_complete ~= nil then
        table.insert(net._bird_lobby_teams_load_callbacks, on_complete)
    end

    LoadTeams(net, reason or "load", function(success, loaded, loaded_locks, loaded_global_locked)
        net._bird_lobby_teams_loading = false
        FinishTeamLoad(net, success, loaded, loaded_locks, loaded_global_locked, reason or "load")

        local callbacks = net._bird_lobby_teams_load_callbacks or {}
        net._bird_lobby_teams_load_callbacks = nil
        for _, callback in ipairs(callbacks) do
            callback(success, loaded, loaded_locks, loaded_global_locked)
        end
    end)
    return true
end

function GLOBAL.BirdSetAuthoritativeLobbyTeam(userid, team_id, reason)
    if not IsAuthorityShard() then
        debug_log.log("team-sync", "authoritative set skipped", reason or "unknown", "non-authority shard")
        return false
    end
    if not IsValidUserId(userid) then
        return false
    end

    team_id = lobby_team_state.normalize(team_id) or TEAM_WAITING
    SetLobbyTeam(userid, team_id, reason or "authoritative")
    return true
end

function GLOBAL.BirdReloadLobbyTeams(reason)
    if not IsAuthorityShard() then
        debug_log.log("team-sync", "reload skipped", reason or "unknown", "non-authority shard")
        return false
    end

    local net = TheWorld ~= nil and TheWorld.net or nil
    if net == nil then
        return false
    end

    return QueueTeamLoad(net, reason or "reload")
end

function GLOBAL.BirdRequestAuthoritativeLobbyTeam(userid, reason, on_complete)
    if not IsAuthorityShard() then
        debug_log.log("team-sync", "request skipped", tostring(userid), reason or "unknown", "non-authority shard")
        return false
    end

    local net = TheWorld ~= nil and TheWorld.net or nil
    if net == nil or not IsValidUserId(userid) then
        return false
    end

    net._bird_lobby_teams = net._bird_lobby_teams or {}
    local team_id = lobby_team_state.normalize(net._bird_lobby_teams[userid])
    debug_log.log("team-sync", "request player team", tostring(userid), reason or "unknown", "ready", tostring(net._bird_lobby_teams_ready), "team", tostring(team_id))
    if net._bird_lobby_teams_ready == true then
        if on_complete ~= nil then
            on_complete(team_id, "world", true)
        end
        return true
    end

    return QueueTeamLoad(net, reason or "request-player-team", function(success)
        local resolved_team = lobby_team_state.normalize(net._bird_lobby_teams[userid])
        debug_log.log("team-sync", "request player team resolved", tostring(userid), tostring(resolved_team), "success", tostring(success))
        if on_complete ~= nil then
            on_complete(resolved_team, success and "reload" or "reload-failed", success)
        end
    end)
end

local function AutoAssignLobbyTeams(params, caller)
    if not IsAuthorityShard() then
        debug_log.log("team-sync", "auto skipped", "non-authority shard")
        return
    end

    local net = TheWorld ~= nil and TheWorld.net or nil
    if net == nil or net._bird_lobby_teams == nil then
        debug_log.log("team-sync", "auto skipped", "net/team table missing")
        return
    end

    local clients = TheNet ~= nil and TheNet:GetClientTable() or nil
    if clients == nil then
        debug_log.log("team-sync", "auto skipped", "client table missing")
        return
    end

    local mode = GetAutoAssignMode(params)
    local include_all = mode == AUTO_ASSIGN_ALL
    local players = {}
    local red_total = 0
    local blue_total = 0
    for _, client in ipairs(clients) do
        if IsPlayableClientRecord(client) then
            local current_team = lobby_team_state.normalize(net._bird_lobby_teams[client.userid]) or TEAM_WAITING
            if current_team == TEAM_WAITING or (include_all and IsPlayingTeam(current_team)) then
                players[#players + 1] = client
            elseif not include_all and current_team == TEAM_RED then
                red_total = red_total + 1
            elseif not include_all and current_team == TEAM_BLUE then
                blue_total = blue_total + 1
            end
        end
    end

    table.sort(players, function(a, b)
        return tostring(a.userid or a.name or "") < tostring(b.userid or b.name or "")
    end)
    Shuffle(players)

    local teams = {}
    for userid, team_id in pairs(net._bird_lobby_teams or {}) do
        if IsValidUserId(userid) and IsValidTeam(team_id) then
            teams[userid] = team_id
        end
    end

    local red_count = 0
    local blue_count = 0
    local red_names = {}
    local blue_names = {}
    for _, client in ipairs(players) do
        local team_id = red_total <= blue_total and TEAM_RED or TEAM_BLUE
        teams[client.userid] = team_id
        if team_id == TEAM_RED then
            red_total = red_total + 1
            red_count = red_count + 1
            red_names[#red_names + 1] = GetClientDisplayName(client)
        else
            blue_total = blue_total + 1
            blue_count = blue_count + 1
            blue_names[#blue_names + 1] = GetClientDisplayName(client)
        end
    end

    net._bird_lobby_teams = teams
    debug_log.log("team-sync", "auto assigned", mode, debug_log.team_payload(teams))
    SaveTeams(net, "auto-" .. mode)
    PublishTeams(net, "auto-" .. mode)
    AnnounceTeam(TEAM_RED, string.format("分队结果:红队%d人 %s", red_count, table.concat(red_names, " ")))
    AnnounceTeam(TEAM_BLUE, string.format("分队结果:蓝队%d人 %s", blue_count, table.concat(blue_names, " ")))
end

AddUserCommand(SELECT_COMMAND_NAME, {
    permission = COMMAND_PERMISSION.USER,
    slash = false,
    usermenu = false,
    servermenu = false,
    params = { "team" },
    vote = false,
    serverfn = SelectLobbyTeam,
})

AddUserCommand(AUTO_COMMAND_NAME, {
    permission = COMMAND_PERMISSION.ADMIN,
    slash = false,
    usermenu = false,
    servermenu = false,
    params = { "mode" },
    vote = false,
    serverfn = AutoAssignLobbyTeams,
})

AddUserCommand(LOCK_COMMAND_NAME, {
    permission = COMMAND_PERMISSION.ADMIN,
    slash = false,
    usermenu = false,
    servermenu = false,
    params = { "locked" },
    vote = false,
    serverfn = SetLobbyTeamLockCommand,
})

local function ApplyClientPayload(inst)
    if inst == nil then
        debug_log.log("team-sync", "client payload skipped", "inst missing")
        return
    end

    if inst.bird_preselect_teams_net == nil then
        debug_log.log("team-sync", "client payload skipped", "netvar missing")
        return
    end

    local payload = inst.bird_preselect_teams_net:value()
    lobby_team_state.apply_preselect_serialized(payload)
    debug_log.log("team-sync", "client payload", tostring(payload))
    if TheGlobalInstance ~= nil then
        TheGlobalInstance:PushEvent(NET_DIRTY_EVENT)
    end
end

local function ApplyShardSnapshot(sender_shard, payload)
    if IsAuthorityShard() then
        return
    end

    local net = TheWorld ~= nil and TheWorld.net or nil
    if net == nil then
        debug_log.log("team-shard", "snapshot skipped", tostring(sender_shard), "network missing")
        return
    end

    local teams, locks, global_locked = DecodeTeams(payload)
    net._bird_lobby_teams = teams
    net._bird_lobby_team_locks = locks
    net._bird_lobby_team_global_lock = global_locked == true
    net._bird_lobby_teams_ready = true
    PublishTeams(net, "shard-snapshot")

    -- Correct any cave player whose migration component carried an older value.
    for _, player in ipairs(AllPlayers or {}) do
        local team_id = player ~= nil and lobby_team_state.normalize(teams[player.userid]) or nil
        if team_id ~= nil then
            player_state.set_ready(player, team_id, "shard-snapshot")
        end
    end

    debug_log.log("team-shard", "snapshot applied", tostring(sender_shard), EncodeTeams(teams, global_locked))
end

local function HandleShardSnapshotRequest(sender_shard)
    if not IsAuthorityShard() then
        return
    end

    local net = TheWorld ~= nil and TheWorld.net or nil
    if net == nil or net._bird_lobby_teams_ready ~= true then
        debug_log.log("team-shard", "request deferred", tostring(sender_shard))
        return
    end

    local payload = EncodeTeams(net._bird_lobby_teams or {}, net._bird_lobby_team_global_lock)
    SendShardTeamSnapshot(sender_shard, payload, "request")
end

AddShardModRPCHandler(SHARD_RPC_NAMESPACE, SHARD_RPC_SNAPSHOT, ApplyShardSnapshot)
AddShardModRPCHandler(SHARD_RPC_NAMESPACE, SHARD_RPC_REQUEST, HandleShardSnapshotRequest)

local function RequestShardSnapshot(reason)
    if IsAuthorityShard() or SendModRPCToShard == nil or GetShardModRPC == nil then
        return false
    end

    local rpc = GetShardModRPC(SHARD_RPC_NAMESPACE, SHARD_RPC_REQUEST)
    if rpc == nil then
        return false
    end

    SendModRPCToShard(rpc, nil)
    debug_log.log("team-shard", "snapshot requested", reason or "unknown")
    return true
end

local function InstallLobbyTeamNetwork(inst)
    if inst.bird_preselect_teams_net == nil then
        inst.bird_preselect_teams_net = net_string(inst.GUID, NET_VAR_NAME, NET_DIRTY_EVENT)
    end

    if TheNet ~= nil and TheNet:GetIsServer() then
        inst._bird_lobby_teams = inst._bird_lobby_teams or {}
        inst._bird_lobby_team_locks = inst._bird_lobby_team_locks or {}
        inst._bird_lobby_teams_ready = false

        if not IsAuthorityShard() then
            debug_log.log("team-sync", "cave mirror network installed")
            inst:DoTaskInTime(0, function()
                RequestShardSnapshot("cave-install")
            end)
            inst:DoTaskInTime(2, function(network)
                if network._bird_lobby_teams_ready ~= true then
                    RequestShardSnapshot("cave-install-retry")
                end
            end)
            return
        end

        inst:ListenForEvent("ms_clientauthenticationcomplete", SetConnectedPreselectDefault, TheWorld)
        inst:ListenForEvent("ms_clientdisconnected", KeepDisconnectedPreselectTeam, TheWorld)
        inst:ListenForEvent("ms_requestedlobbycharacter", EnsureCharacterResetPreselectDefault, TheWorld)
        debug_log.log("team-sync", "server network installed")
        if TheSim == nil or TheSim.GetPersistentString == nil then
            inst._bird_lobby_teams_ready = true
            PublishTeams(inst, "install")
        else
            QueueTeamLoad(inst, "install")
        end
        inst:DoTaskInTime(0, SetCurrentPreselectDefaults)
        inst:DoTaskInTime(1, SetCurrentPreselectDefaults)
        return
    end

    debug_log.log("team-sync", "client network installed")
    inst:ListenForEvent(NET_DIRTY_EVENT, ApplyClientPayload)
    ApplyClientPayload(inst)
end

AddPrefabPostInit("forest_network", InstallLobbyTeamNetwork)
AddPrefabPostInit("cave_network", InstallLobbyTeamNetwork)

local function GetLocalCaller()
    if TheNet == nil then
        return nil
    end

    local userid = TheNet:GetUserID()
    return IsValidUserId(userid) and TheNet:GetClientTableForUser(userid) or nil
end

function GLOBAL.BirdSubmitLobbyTeam(team_id)
    local caller = GetLocalCaller()
    debug_log.log("team-sync", "submit", tostring(caller ~= nil and caller.userid or nil), tostring(team_id))
    if caller == nil or not IsValidUserId(caller.userid) then
        return false
    end

    team_id = lobby_team_state.normalize(team_id) or TEAM_WAITING
    if lobby_team_state.is_global_locked() and not admin_privileges.is_lobby_admin(caller) then
        debug_log.log("team-sync", "submit rejected locked", tostring(caller.userid), tostring(team_id))
        if TheGlobalInstance ~= nil then
            TheGlobalInstance:PushEvent(NET_DIRTY_EVENT)
        end
        return false
    end

    lobby_team_state.set_local(caller.userid, team_id)
    if TheGlobalInstance ~= nil then
        TheGlobalInstance:PushEvent(NET_DIRTY_EVENT)
    end
    UserCommands.RunUserCommand(SELECT_COMMAND_NAME, { team = tostring(team_id) }, caller, nil)
    return true
end

function GLOBAL.BirdSetLobbyTeamGlobalLock(locked)
    local caller = GetLocalCaller()
    debug_log.log("team-sync", "submit global lock", tostring(caller ~= nil and caller.userid or nil), tostring(locked == true))
    if caller == nil or not IsValidUserId(caller.userid) or not admin_privileges.is_lobby_admin(caller) then
        return false
    end

    lobby_team_state.set_global_lock_local(locked == true)
    if TheGlobalInstance ~= nil then
        TheGlobalInstance:PushEvent(NET_DIRTY_EVENT)
    end
    UserCommands.RunUserCommand(LOCK_COMMAND_NAME, {
        locked = locked == true and "1" or "0",
    }, caller, nil)
    return true
end

function GLOBAL.BirdSetLobbyTeamLock(locked)
    return GLOBAL.BirdSetLobbyTeamGlobalLock(locked)
end

function GLOBAL.BirdAutoAssignLobbyTeams(mode)
    local caller = GetLocalCaller()
    mode = mode == AUTO_ASSIGN_ALL and AUTO_ASSIGN_ALL or AUTO_ASSIGN_WAITING
    debug_log.log("team-sync", "submit auto", tostring(caller ~= nil and caller.userid or nil), mode)
    if caller == nil or not IsValidUserId(caller.userid) then
        return false
    end

    UserCommands.RunUserCommand(AUTO_COMMAND_NAME, { mode = mode }, caller, nil)
    return true
end
