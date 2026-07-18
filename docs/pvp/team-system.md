# 队伍系统

## 队伍编号

队伍常量定义在 [`lobby_team_state.lua`](../../pvp/scripts/src/team/lobby_team_state.lua):

| 编号 | 状态 | 含义 |
| --- | --- | --- |
| `0` | OB | 观察模式 |
| `1` | 红队 | 正式比赛队伍 |
| `2` | 蓝队 | 正式比赛队伍 |
| `3` | 等待 | 尚未参与分队，不应用比赛或 OB 能力 |

不要使用 `nil` 表示等待。`nil` 主要表示队伍数据尚未同步或无效。

## 四层状态

### 1. 地上权威表

[`lobby_team_sync.lua`](../../pvp/scripts/src/team/lobby_team_sync.lua) 在 `forest_network` 上维护:

- `_bird_lobby_teams[userid] = team_id`
- `_bird_lobby_teams_ready`
- `_bird_lobby_team_global_lock`

地上世界是唯一写入权威。数据按存档会话持久化到 `mod_config_data/bird_pvp_lobby_teams_*`。服务器重启后先加载持久化表，再发布镜像。

### 2. 预选客户端镜像

`bird_preselect_teams._value` 是序列化 `net_string`，供玩家实体创建前的大厅 UI 使用。内容包含 `userid=team` 条目以及统一锁状态。

它不是权威表。客户端点击选队后可以先更新本地显示，但最终结果由服务器用户命令写入权威表并重新发布。

### 3. 玩家实体状态

[`player_state.lua`](../../pvp/scripts/src/team/player_state.lua) 给每个玩家挂载 Lua 状态:

- `pending`: 正在等待可靠队伍值。
- `ready`: 已取得稳定队伍，允许应用队伍行为。
- `failed`: 本次解析失败，等待后续事件或重试。

同时挂载 `net_tinybyte` `bird_player_team._team`，供客户端读取游戏内队伍。编码规则为 `team_id + 1`，值 `0` 专门表示 `pending`。

状态事件:

- `bird_team_state_pending`
- `bird_team_state_ready`
- `bird_team_state_failed`
- `bird_player_team_dirty`

绝大多数队伍效果只应响应一次 `ready` 广播，而不是每帧轮询。

### 4. 迁移组件

[`player_duiwu_qe.lua`](../../pvp/scripts/components/player_duiwu_qe.lua) 保存随玩家迁移的数据:

- `bird_team`: 当前完整队伍，可保存等待状态。
- `duiwu`: 旧版兼容字段，只承载 OB、红队、蓝队。

组件还负责红蓝队脚下的 `bird_duiwufx1/2`。队伍圈只由 `ready` 阶段应用，OB 和等待不创建队伍圈。

## 生命周期

### 进入预选大厅

- 游戏尚未开始时，没有记录的玩家默认为等待。
- 游戏已经开始且允许后加入时，没有记录的新玩家默认为 OB。
- 已存在于权威表的玩家保留原队伍，服务器加载期间的临时客户端选择会在合并时保留。

### 手动选队

大厅使用用户命令 `bird_lobby_team`，因为玩家实体创建前不能依赖普通玩家 Mod RPC。服务器验证 `userid`、队伍编号和统一锁，再写权威表。

### 自动分队

管理员入口支持两种模式:

- `waiting`: 只分配等待玩家，现有红蓝队人数参与平衡。
- `all`: 重新分配等待、红队和蓝队，不包含 OB。

当前实现按可玩客户端和队伍状态筛选，管理员与其他玩家一样参与分队。`admin/privileges.lua` 中的 `is_excluded_from_auto_team` 是未被调用的遗留接口，不代表当前行为。

### 统一锁

统一锁只阻止非管理员自行修改队伍。管理员仍可修改，自动分队也仍可覆盖队伍。锁状态通过预选镜像同步给所有客户端。

### 玩家生成

[`component.lua`](../../pvp/scripts/src/team/component.lua) 的处理顺序:

1. 安装玩家 `team_var`。
2. 将状态设为 `pending`。
3. 从地上权威表解析队伍，必要时按短延迟重试。
4. 解析成功后广播 `ready`。
5. 设置迁移组件、队伍圈、OB camera 模式和地图标记。

地上比赛已开始而玩家没有任何队伍记录时，默认 OB；开局前默认等待。

## 上下洞同步

地上世界通过 Shard RPC `bird_pvp_team` 发送完整快照:

- `snapshot`: 地上向地下发布权威表镜像。
- `request_snapshot`: 地下启动时主动请求。

地下 `cave_network` 维护只读镜像，同时把同一份预选序列化值发给地下客户端。玩家下洞时优先使用迁移组件中的 `bird_team` 预置状态，不需要等待一次地上查询；快照到达后会纠正旧值。

地下永远不应成为第二个写入权威。若地下没有迁移值和快照，应保持 `pending`，不能临时猜成 OB、红队或蓝队。

## 消费队伍状态

业务代码统一调用:

```lua
local team_id, pending = team_state.get_player_team(player)
```

使用规则:

- `pending == true` 时，不显示玩家地图位置，不发送队伍聊天，不应用 OB 权限。
- 红蓝规则使用 `team_state.is_playing_team(team_id)`。
- OB 规则使用 `team_state.is_player_observer(player)` 或 `observer/privileges.lua`。
- 不直接读取 `_bird_team_var:value()`，除非正在维护状态模块本身。
- 不以旧组件字段 `duiwu` 作为客户端权威。

这样可以避免上下洞、暂停阶段和玩家实体刚生成时短暂泄露敌方位置或聊天。
