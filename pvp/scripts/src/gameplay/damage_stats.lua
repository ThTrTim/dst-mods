-- [PATCH] 新增：服务器端输出/承伤统计。
-- 记录玩家/队伍对其他队造成的伤害（输出）和承受其他队的伤害（承伤），
-- 以及同队玩家叫醒次数。仅统计当前对局，不持久化、不跨局累加。
--
-- 实现要点：
-- 1. 使用 AddComponentPostInit("combat", ...) 在每个战斗组件实例创建时安装钩子。
--    只覆盖 Combat 类方法会被 health_bar、protection 等 Mod 的实例级覆盖绕过，
--    因此改为实例级包装，确保无论攻击/受击对象是谁都能记录到伤害。
-- 2. 以血量差作为实际伤害，避免 armor/absorb/spdamage 导致传入的 damage 参数不准。
-- 3. 对投掷物、召唤物等，通过 follower / projectile 追溯真正的玩家主人。

local team_state = require("src/team/lobby_team_state")

local TEAM_RED = team_state.TEAM_RED
local TEAM_BLUE = team_state.TEAM_BLUE

local ROUND_KEY = "mod_config_data/bird_pvp_current_round"

-- In-memory data.
local _round_stats = nil
local _round_id = nil
local _name_cache = {}
local _team_cache = {}
local _debug_stats = false


local function NewStats()
    return {
        players = {},
        teams = {
            red = { dealt = 0, taken = 0 },
            blue = { dealt = 0, taken = 0 },
        },
    }
end

local function NewPlayerStats(name)
    return {
        name = name or "",
        dealt = 0,
        taken = 0,
        wakes = 0,
        team_dealt_red = 0,
        team_dealt_blue = 0,
        team_taken_red = 0,
        team_taken_blue = 0,
    }
end

local function GetRoundStats()
    if _round_stats == nil then
        _round_stats = NewStats()
    end
    return _round_stats
end

local function GetPlayerName(userid)
    if userid == nil or userid == "" then
        return ""
    end
    local cached = _name_cache[userid]
    if cached ~= nil then
        return cached
    end

    local name = userid
    local client = TheNet:GetClientTableForUser(userid)
    if client ~= nil and client.name ~= nil and client.name ~= "" then
        name = client.name
    else
        local stats = GetRoundStats()
        if stats.players[userid] ~= nil and stats.players[userid].name ~= nil and stats.players[userid].name ~= "" then
            name = stats.players[userid].name
        end
    end

    _name_cache[userid] = name
    return name
end

local function RecordDamage(attacker_userid, attacker_team, target_userid, target_team, amount)
    if attacker_team ~= TEAM_RED and attacker_team ~= TEAM_BLUE then
        return
    end
    if target_team ~= TEAM_RED and target_team ~= TEAM_BLUE then
        return
    end
    if attacker_team == target_team then
        return
    end
    if amount == nil or amount <= 0 then
        return
    end

    local round = GetRoundStats()
    local attacker_name = GetPlayerName(attacker_userid)
    local target_name = GetPlayerName(target_userid)

    -- Attacker (output)
    if attacker_userid ~= nil and attacker_userid ~= "" then
        round.players[attacker_userid] = round.players[attacker_userid] or NewPlayerStats(attacker_name)
        round.players[attacker_userid].name = attacker_name
        round.players[attacker_userid].dealt = round.players[attacker_userid].dealt + amount
        if target_team == TEAM_RED then
            round.players[attacker_userid].team_dealt_red = round.players[attacker_userid].team_dealt_red + amount
        elseif target_team == TEAM_BLUE then
            round.players[attacker_userid].team_dealt_blue = round.players[attacker_userid].team_dealt_blue + amount
        end
    end

    -- Target (taken)
    if target_userid ~= nil and target_userid ~= "" then
        round.players[target_userid] = round.players[target_userid] or NewPlayerStats(target_name)
        round.players[target_userid].name = target_name
        round.players[target_userid].taken = round.players[target_userid].taken + amount
        if attacker_team == TEAM_RED then
            round.players[target_userid].team_taken_red = round.players[target_userid].team_taken_red + amount
        elseif attacker_team == TEAM_BLUE then
            round.players[target_userid].team_taken_blue = round.players[target_userid].team_taken_blue + amount
        end
    end

    -- Team totals
    local attacker_team_key = attacker_team == TEAM_RED and "red" or "blue"
    local target_team_key = target_team == TEAM_RED and "red" or "blue"
    round.teams[attacker_team_key].dealt = round.teams[attacker_team_key].dealt + amount
    round.teams[target_team_key].taken = round.teams[target_team_key].taken + amount
end

local function RecordWakeUp(waker_userid, waker_team, sleeper_userid)
    if waker_team ~= TEAM_RED and waker_team ~= TEAM_BLUE then
        return
    end
    if waker_userid == nil or waker_userid == "" or sleeper_userid == nil or sleeper_userid == "" then
        return
    end
    if waker_userid == sleeper_userid then
        return
    end

    local round = GetRoundStats()
    local waker_name = GetPlayerName(waker_userid)
    round.players[waker_userid] = round.players[waker_userid] or NewPlayerStats(waker_name)
    round.players[waker_userid].name = waker_name
    round.players[waker_userid].wakes = (round.players[waker_userid].wakes or 0) + 1
end

local function GetEntityOwner(inst)
    if inst == nil then
        return nil
    end
    if inst.userid ~= nil and inst.userid ~= "" then
        return inst
    end

    -- Follower minions/summons are attributed to their leader.
    if inst.components.follower ~= nil and inst.components.follower.leader ~= nil then
        return GetEntityOwner(inst.components.follower.leader)
    end

    -- Projectiles (boomerangs, darts, etc.) carry their original attacker.
    if inst.components.projectile ~= nil and inst.components.projectile.attacker ~= nil then
        return GetEntityOwner(inst.components.projectile.attacker)
    end

    return nil
end

local function GetEntityTeam(inst)
    local owner = GetEntityOwner(inst)
    if owner == nil or owner.userid == nil or owner.userid == "" then
        return nil, nil
    end
    local userid = owner.userid
    local cached = _team_cache[userid]
    if cached ~= nil then
        return cached, userid
    end

    -- 优先使用大厅/网络同步的队伍状态。
    local team, _ = team_state.get_player_team(owner, nil)

    -- 若网络状态尚未就绪，回退到玩家实体上的队伍组件（无缝加载/分片迁移时更可靠）。
    if team == nil and owner.components ~= nil and owner.components.player_duiwu_qe ~= nil then
        local component_team = owner.components.player_duiwu_qe.duiwu
        if component_team ~= nil then
            team = team_state.normalize(component_team)
        end
    end

    -- 只缓存非空结果，避免早期 nil 被永久缓存。
    if team ~= nil then
        _team_cache[userid] = team
    end
    return team, userid
end

-- [PATCH] 在每个 combat 组件实例上安装 GetAttacked 包装器。
-- 实例级包装比类方法覆盖更可靠：health_bar、protection 等 Mod 也会在实例上
-- 覆盖，它们都会调用之前的函数，最终仍会进入这里的统计逻辑。
local function InstallCombatHook(combat)
    local inst = combat.inst
    local old_GetAttacked = combat.GetAttacked
    if old_GetAttacked == nil then
        return
    end

    combat.GetAttacked = function(self, attacker, damage, weapon, stimuli, spdamage, ...)
        local target = self.inst
        if target == nil then
            return old_GetAttacked(self, attacker, damage, weapon, stimuli, spdamage, ...)
        end

        -- 记录受击前血量，用于计算实际伤害（护甲、位面伤害等都已被结算）。
        local healthcmp = target.components.health
        local health_before = nil
        if healthcmp ~= nil and healthcmp.currenthealth ~= nil then
            health_before = healthcmp.currenthealth
        end

        local was_sleeping = target:HasTag("sleeping")
        local target_is_player = target:HasTag("player")
        local attacker_is_player = attacker ~= nil and attacker:HasTag("player")

        -- 先调用原函数，让伤害真正作用到目标身上。
        local result = old_GetAttacked(self, attacker, damage, weapon, stimuli, spdamage, ...)

        if not (TheWorld ~= nil and TheWorld.ismastersim) then
            return result
        end
        if attacker == nil then
            return result
        end

        -- 只关心玩家参与的交互，减少非 PVP 战斗的额外开销。
        if not target_is_player and not attacker_is_player then
            return result
        end

        -- 以血量差作为实际伤害，比 damage 参数更准确。
        local actual_damage = 0
        local health_after = nil
        if healthcmp ~= nil and healthcmp.currenthealth ~= nil then
            health_after = healthcmp.currenthealth
            if health_before ~= nil and health_before > health_after then
                actual_damage = health_before - health_after
            end
        elseif type(damage) == "number" and damage > 0 then
            -- 血量组件不可用时回退到传入参数（仅作兜底）。
            actual_damage = damage
        end

        local attacker_team, attacker_userid = GetEntityTeam(attacker)
        local target_team, target_userid = GetEntityTeam(target)

        if _debug_stats then
            print(string.format(
                "[BirdPVP Stats] hit: attacker=%s(%s) target=%s(%s) before=%s after=%s actual=%s param=%s sp=%s",
                tostring(attacker_userid),
                tostring(attacker_team),
                tostring(target_userid),
                tostring(target_team),
                tostring(health_before),
                tostring(health_after),
                tostring(actual_damage),
                tostring(damage),
                tostring(spdamage)
            ))
        end

        if attacker_team ~= nil and target_team ~= nil then
            if attacker_team ~= target_team then
                if actual_damage > 0 then
                    RecordDamage(attacker_userid, attacker_team, target_userid, target_team, actual_damage)
                end
            elseif was_sleeping and target_is_player and attacker_is_player then
                -- 同队玩家攻击正在睡觉的队友，视为叫醒。
                RecordWakeUp(attacker_userid, attacker_team, target_userid)
            end
        end

        return result
    end
end

AddComponentPostInit("combat", function(combat, inst)
    -- 兼容不同 Mod 环境：第一个参数是 combat 组件，第二个参数是所属实体。
    if inst == nil and combat ~= nil then
        inst = combat.inst
    end
    if combat == nil or inst == nil then
        return
    end
    InstallCombatHook(combat)
end)


-- Return the current round stats and save a snapshot for the settlement panel.
function GLOBAL.BirdFinalizeRoundStats()
    local round = GetRoundStats()
    local snapshot = json.encode(round)
    SavePersistentString(ROUND_KEY, snapshot, false, nil)
    return round
end

function GLOBAL.BirdResetRoundStats()
    _round_stats = NewStats()
    _round_id = os.time ~= nil and os.time() or GetTime()
    _name_cache = {}
    _team_cache = {}

    -- [PATCH] 给当前已在线的玩家预生成默认 0 记录，避免打开面板时看不到自己。
    for _, player in ipairs(AllPlayers or {}) do
        if player.userid ~= nil and player.userid ~= "" then
            local name = GetPlayerName(player.userid)
            _round_stats.players[player.userid] = NewPlayerStats(name)
        end
    end
end

function GLOBAL.BirdGetRoundStats()
    return GetRoundStats()
end

-- [PATCH] 调试开关：开启后每次受击都会打印队伍、血量、伤害参数，方便定位统计问题。
function GLOBAL.c_bird_debug_stats(enabled)
    _debug_stats = enabled ~= false and enabled ~= "false" and enabled ~= 0
    print("[BirdPVP Stats] debug = " .. tostring(_debug_stats))
end

-- [PATCH] 新玩家加入时也要生成默认 0 记录。
AddPlayerPostInit(function(inst)
    if not (TheWorld ~= nil and TheWorld.ismastersim) then
        return
    end
    if inst.userid == nil or inst.userid == "" then
        return
    end

    local round = GetRoundStats()
    if round.players[inst.userid] == nil then
        round.players[inst.userid] = NewPlayerStats(GetPlayerName(inst.userid))
    end
end)

local function FilterStatsForPlayer(stats, userid, name)
    local filtered = NewStats()
    filtered.teams = {
        red = { dealt = stats.teams.red.dealt, taken = stats.teams.red.taken },
        blue = { dealt = stats.teams.blue.dealt, taken = stats.teams.blue.taken },
    }
    local entry = stats.players[userid]
    if entry ~= nil then
        filtered.players[userid] = entry
    else
        -- Always include the requesting player so all values default to 0.
        filtered.players[userid] = NewPlayerStats(name ~= nil and name ~= "" and name or userid)
    end

    -- Attach the player's actual team so the client doesn't have to infer it.
    local player_entity = nil
    for _, p in ipairs(AllPlayers or {}) do
        if p.userid == userid then
            player_entity = p
            break
        end
    end
    if player_entity ~= nil then
        local team, _ = team_state.get_player_team(player_entity, nil)
        if team == TEAM_RED or team == TEAM_BLUE then
            filtered.players[userid].team = team
        end
    end

    return filtered
end

-- [PATCH] RPC：客户端请求统计时，服务端只返回该玩家自己的当局数据，避免看到他人数据。
AddModRPCHandler("bird_pvp_stats", "request", function(player)
    if player == nil or player.userid == nil or player.userid == "" then
        return
    end

    local name = player.name
    if name == nil or name == "" then
        local client = TheNet:GetClientTableForUser(player.userid)
        name = client ~= nil and client.name or nil
    end

    local payload = json.encode({
        round = FilterStatsForPlayer(GetRoundStats(), player.userid, name),
    })
    SendModRPCToClient(GetClientModRPC("bird_pvp_stats", "response"), player.userid, payload)
end)

-- Fallback slash command to open the panel if the key binding conflicts.
AddUserCommand("stats", {
    prettyname = "统计面板",
    desc = "打开输出/承伤统计面板",
    permission = COMMAND_PERMISSION.USER,
    slash = true,
    usermenu = false,
    servermenu = false,
    params = {},
    vote = false,
    canstartfn = function(command, caller, targetid)
        return true
    end,
    serverfn = function(params, caller)
        SendModRPCToClient(GetClientModRPC("bird_pvp_stats", "open"), caller.userid)
    end,
})

AddPrefabPostInit("world", function(inst)
    if not inst.ismastersim then
        return
    end
    BirdResetRoundStats()
end)
