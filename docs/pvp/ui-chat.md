# UI、聊天与血条

## 预选大厅

[`lobby_team.lua`](../../pvp/scripts/src/ui/lobby_team.lua) 在原版大厅上增加:

- 当前队伍按钮，弹出等待、OB、红队、蓝队选择。
- 管理员自动分队按钮，支持等待人员和全部人员两种模式。
- Roll 骰子按钮，使用原版宣告格式和原版冷却，管理员跳过冷却。
- 管理员统一锁按钮，锁定非管理员自行选队。

按钮挂在 `LobbyScreen.root` 的比例缩放坐标系中。调整位置时应保持四个按钮使用同一坐标系，不要根据窗口像素手工换算。

左侧玩家列表由 [`bird_team_playerlist.lua`](../../pvp/scripts/widgets/bird_team_playerlist.lua) 复用原版列表，并增加红队、蓝队、OB、等待四个横向筛选按钮。列表本身保持原版尺寸和滚动行为。

准备阶段布局由 [`bird_team_waitingforplayers.lua`](../../pvp/scripts/widgets/bird_team_waitingforplayers.lua) 和 [`shuiyue_preselect_panel.lua`](../../pvp/scripts/widgets/shuiyue_preselect_panel.lua) 维护。不要在大厅入口重复创建另一套玩家数据源。

## Tab 计分板

[`team_scoreboard.lua`](../../pvp/scripts/src/ui/team_scoreboard.lua) 保留原版 `PlayerStatusScreen` 的玩家行、状态图标和操作按钮，只在顶部增加红队、蓝队、OB、等待筛选栏。

设计原则:

- 不重写原版玩家行。
- 不删除原版按钮或状态。
- 筛选只改变传给列表的数据。
- 队伍镜像更新后刷新计数和当前列表。
- 地下读取同一份 shard 镜像，不能使用洞穴本地猜测队伍。

## 队伍聊天

[`chat.lua`](../../pvp/scripts/src/team/chat.lua) 使用内部前缀 `/d` 编码队伍消息。该前缀只用于网络传输，不是玩家需要输入的公开命令。

处理规则:

- 红队和蓝队消息只发给同队。
- OB 可以旁观双方队伍聊天。
- 队伍为 `pending` 时不发送队伍消息，避免暂停或上下洞期间串队。
- OB 显示色为白色，红蓝队分别使用队伍颜色。

玩家显示名统一格式为 `玩家名(角色名)`。加入、死亡、Roll、表情和命令宣告中的玩家名也会替换；尚未选择角色、随机角色或角色信息不可用时，不添加括号。普通玩家自由输入的消息正文不会被替换。

## 地图头像

[`markers.lua`](../../pvp/scripts/src/team/markers.lua) 控制原生玩家头像和队伍可见性:

- 红蓝玩家看到自己和同队玩家。
- 不同队伍之间不可见。
- OB 可以看到全部非 OB 玩家。
- OB 头像始终对其他人隐藏。
- `pending` 玩家不暴露头像，也不应触发清空全部玩家地图数据。

队伍圈 prefab 为 `bird_duiwufx1` 和 `bird_duiwufx2`，资源 bank 必须保持 `bird_duiwufx`。若只修改 Lua 名称但没有重打动画包，会出现 `Could not find anim bank`。

## 血条

[`health_bar.lua`](../../pvp/scripts/src/ui/health_bar.lua) 注册 `dyc_healthbar`。当前用途是让 OB 观察其他生物或比赛玩家的血量:

- 普通玩家不是接收者。
- OB 自身不是血条目标。
- 目标附近需存在有效 OB，当前搜索距离为 `32`。
- classified 只定向到接收 OB，避免向所有客户端广播。

血条配置来自 `modinfo.lua` 的 `hbstyle`、`value`、`hblength`、`hbpos`、`hbcolor` 和 `ddon`。

## UI 刷新

现有周期刷新只用于本地界面:

- 大厅管理员按钮状态: `0.25` 秒。
- Tab 筛选签名检查: `0.2` 秒。
- OB HUD 安全状态: `0.5` 秒。

新增 UI 时优先监听 `bird_lobby_teams_dirty` 或 `bird_player_team_dirty`，仅在原版界面没有可靠事件时增加低频本地刷新。
