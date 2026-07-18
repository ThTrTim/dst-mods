-- Per-player team resolution state plus the replicated entity team_var.
-- The Lua state prevents entity-spawn timing from guessing; the netvar is the
-- client-visible game-time team mirror.
local team_state = require("src/team/lobby_team_state")

local M = {}

local STATUS_PENDING = "pending"
local STATUS_READY = "ready"
local STATUS_FAILED = "failed"
local EVENT_PENDING = "bird_team_state_pending"
local EVENT_READY = "bird_team_state_ready"
local EVENT_FAILED = "bird_team_state_failed"
local NET_DIRTY_EVENT = "bird_player_team_dirty"
local NET_VAR_NAME = "bird_player_team._team"
local NET_PENDING = 0

M.STATUS_PENDING = STATUS_PENDING
M.STATUS_READY = STATUS_READY
M.STATUS_FAILED = STATUS_FAILED
M.EVENT_PENDING = EVENT_PENDING
M.EVENT_READY = EVENT_READY
M.EVENT_FAILED = EVENT_FAILED
M.NET_DIRTY_EVENT = NET_DIRTY_EVENT

local function push_player_event(inst, event, data)
    if inst ~= nil and inst.PushEvent ~= nil then
        inst:PushEvent(event, data)
    end
    if TheWorld ~= nil and TheWorld.PushEvent ~= nil then
        TheWorld:PushEvent(event, data)
    end
end

local function encode_team(team_id)
    team_id = team_state.normalize(team_id)
    return team_id ~= nil and team_id + 1 or NET_PENDING
end

local function decode_team(value)
    value = tonumber(value)
    if value == nil or value == NET_PENDING then
        return nil, false
    end

    local team_id = team_state.normalize(value - 1)
    return team_id, team_id ~= nil
end

function M.install_netvar(inst)
    if inst == nil or inst._bird_team_var ~= nil or net_tinybyte == nil then
        return inst ~= nil and inst._bird_team_var or nil
    end

    inst._bird_team_var = net_tinybyte(inst.GUID, NET_VAR_NAME, NET_DIRTY_EVENT)
    return inst._bird_team_var
end

local function set_netvar(inst, value)
    local netvar = M.install_netvar(inst)
    if netvar ~= nil and TheWorld ~= nil and TheWorld.ismastersim then
        netvar:set(value)
    end
end

function M.get_netvar(inst)
    local netvar = inst ~= nil and inst._bird_team_var or nil
    if netvar == nil then
        return nil, false
    end

    return decode_team(netvar:value())
end

function M.ensure(inst)
    if inst == nil then
        return nil
    end

    if inst._bird_team_state == nil then
        inst._bird_team_state = {
            status = STATUS_PENDING,
            team_id = nil,
            requested = false,
            revision = 0,
        }
    end

    return inst._bird_team_state
end

function M.set_pending(inst, reason)
    local state = M.ensure(inst)
    if state == nil then
        return nil
    end

    state.status = STATUS_PENDING
    state.team_id = nil
    state.source = nil
    state.requested = false
    state.reason = reason
    state.revision = (state.revision or 0) + 1
    push_player_event(inst, EVENT_PENDING, {
        player = inst,
        reason = reason,
        revision = state.revision,
    })
    set_netvar(inst, NET_PENDING)
    return state
end

function M.mark_requested(inst, reason)
    local state = M.ensure(inst)
    if state == nil then
        return nil
    end

    state.status = STATUS_PENDING
    state.requested = true
    state.reason = reason
    return state
end

function M.set_ready(inst, team_id, source)
    team_id = team_state.normalize(team_id)
    if team_id == nil then
        return false
    end

    local state = M.ensure(inst)
    if state == nil then
        return false
    end

    local changed = state.status ~= STATUS_READY or state.team_id ~= team_id
    state.status = STATUS_READY
    state.team_id = team_id
    state.source = source
    state.requested = false
    state.revision = (state.revision or 0) + 1

    if changed then
        push_player_event(inst, EVENT_READY, {
            player = inst,
            team_id = team_id,
            source = source,
            revision = state.revision,
        })
    end
    set_netvar(inst, encode_team(team_id))
    return true
end

function M.set_failed(inst, reason)
    local state = M.ensure(inst)
    if state == nil then
        return nil
    end

    state.status = STATUS_FAILED
    state.reason = reason
    state.requested = false
    state.revision = (state.revision or 0) + 1
    push_player_event(inst, EVENT_FAILED, {
        player = inst,
        reason = reason,
        revision = state.revision,
    })
    set_netvar(inst, NET_PENDING)
    return state
end

function M.get(inst)
    local state = inst ~= nil and inst._bird_team_state or nil
    if state == nil or state.status ~= STATUS_READY then
        return nil, false
    end

    local team_id = team_state.normalize(state.team_id)
    if team_id == nil then
        return nil, false
    end

    return team_id, true
end

function M.is_requested(inst)
    local state = inst ~= nil and inst._bird_team_state or nil
    return state ~= nil and state.requested == true
end

function M.is_failed(inst)
    local state = inst ~= nil and inst._bird_team_state or nil
    return state ~= nil and state.status == STATUS_FAILED
end

return M
