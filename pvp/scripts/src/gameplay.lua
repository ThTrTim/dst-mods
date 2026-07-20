-- General gameplay-rule loader.
-- Registration scripts are imported into the root mod environment.
modimport("scripts/src/gameplay/balance.lua")
modimport("scripts/src/gameplay/early_game.lua")
-- [PATCH] 加载输出/承伤统计：记录玩家/队伍对其他队的伤害与叫醒次数，仅当前对局。
modimport("scripts/src/gameplay/damage_stats.lua")
-- [PATCH] 加载比赛结束判定：一方全灭 1 分钟后判胜，胜利队燃放烟花并 30 秒后重置世界。
modimport("scripts/src/gameplay/match_end.lua")
