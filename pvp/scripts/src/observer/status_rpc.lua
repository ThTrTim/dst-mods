-- Client-side observer status RPC registration.
-- Runtime subscription/state functions live in the required observer/status module.
local checkstring = GLOBAL.checkstring
local RPC_NAMESPACE = "bird_mode_clientrpc"
local RPC_NAME = "bird_mode_clientrpc"

AddClientModRPCHandler(RPC_NAMESPACE, RPC_NAME, function(payload)
    if ThePlayer == nil or not checkstring(payload) then
        return
    end

    local ok, decoded = pcall(json.decode, payload)
    if ok then
        ThePlayer.duiwuinfo = decoded
        ThePlayer:PushEvent("updateduiwuinfo")
    end
end)
