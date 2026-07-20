-- Lobby feature loader.
if GetModConfigData("preselect_lobby") then
    modimport("scripts/src/lobby/preselect.lua")
end
-- [PATCH] 加载开局暂停逻辑：游戏开始后自动暂停，待红/蓝两队各自确认“准备好”后继续。
modimport("scripts/src/lobby/ready_pause.lua")
-- [PATCH] 加载掉线自动暂停与预留位置保护：红/蓝队玩家掉线时自动暂停，人满时保留位置，掉线玩家回归后自动恢复。
modimport("scripts/src/lobby/reserved_slots.lua")
