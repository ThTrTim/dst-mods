-- Observer system loader.
-- Registration scripts use modimport; shared state/action modules continue to use require.
modimport("scripts/src/observer/status_rpc.lua")
modimport("scripts/src/observer/admin_rules.lua")
modimport("scripts/src/observer/camera_hooks.lua")
modimport("scripts/src/observer/ui.lua")
modimport("scripts/src/observer/player.lua")