-- Optional UI/helper integrations and lobby UI customizations.
modimport("scripts/src/ui/quick_announce.lua")
modimport("scripts/src/ui/lobby_team.lua")
modimport("scripts/src/ui/health_bar.lua")
modimport("scripts/src/ui/team_scoreboard.lua")
-- [PATCH] 加载输出/承伤统计面板：按 P 键打开，仅显示当前对局个人数据。
modimport("scripts/src/ui/damage_stats_panel.lua")
-- [PATCH] 加载每局结束结算面板：显示两队当局输出与承伤。
modimport("scripts/src/ui/settlement_panel.lua")
