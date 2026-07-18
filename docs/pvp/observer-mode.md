# OB 模式

## 判定入口

OB 的唯一业务身份是队伍 `0`。统一权限入口为 [`observer/privileges.lua`](../../pvp/scripts/src/observer/privileges.lua)。只有玩家队伍已经 `ready` 且为 OB 时，才开放观察能力。

不要用管理员身份、角色 prefab、旧 `wudi` 字段或 UI 是否存在来推断 OB。

## Camera shell

[`camera_mode.lua`](../../pvp/scripts/src/observer/camera_mode.lua) 保留 DST 必需的玩家网络实体，把它降为不可交互的 camera shell。直接删除玩家实体会破坏客户端所有权、HUD、迁移和洞穴切换，因此当前实现隐藏表现并隔离世界交互，而不是销毁网络实体。

启用 OB 时主要执行:

- 添加 `bird_observer_camera`、`notarget`、`noclick`、`noauradamage` 等标签。
- 隐藏角色动画、影子和普通世界表现。
- 移除物理碰撞与陷阱触发能力。
- 屏蔽普通动作、睡眠和死亡状态跳转。
- 设置 4 倍移动速度。
- 分批获取当前世界地图。
- 允许地图传送以及洞穴、楼梯等必要世界切换交互。

## 组件策略

可以安全移除的生存或世界交互组件包括:

- `drownable`
- `grogginess`
- `sleeper`
- `playerlightningtarget`
- `sanityaura`
- `bloomer`

以下组件虽然 OB 不使用其普通玩法能力，但原版 HUD、状态机或控制器会直接访问，因此必须保留或确保存在:

- `inventory`
- `playeractionpicker`
- `builder`
- `combat`
- `talker`
- `burnable`
- `freezable`

不要为了追求“只剩 camera”继续盲删组件。此前 `statusdisplays.health`、`sanity_replica`、`crafting inventory`、`playercontroller.combat`、`SGwilson.burnable` 和 `playervision.inventory` 崩溃都来自原版代码对组件存在性的硬假设。

## 地图与移动

全图获取采用增量任务，而不是一次扫描整张地图:

- 网格步长 `30`。
- 每次处理 `80` 个区域。
- 周期 `0.05` 秒。
- 每个世界记录完成状态，重复传送不会重新扫描。

第一次进入地上或地下时会启动该世界的获取任务。地图右键传送只发送目标坐标，不应触发完整地图重算。

OB 地面点击和洞穴交互应走有限动作链，不使用持续高频寻路轮询。地图远距离移动优先使用传送，洞穴入口保留必要点击和切换行为。

## 视野开关

[`camera_hooks.lua`](../../pvp/scripts/src/observer/camera_hooks.lua) 提供两个客户端开关:

- 大视野: 放宽相机距离到 `999`，开启时自动拉到默认距离 `120`，关闭后恢复原限制。
- 夜视: 默认关闭，使用 identity colour cube，避免额外阴暗滤镜。

全局接口以 `BirdObserver*` 命名，由 [`birdui1.lua`](../../pvp/scripts/widgets/birdui1.lua) 的 OB 面板调用。

## 权限边界

OB 权限:

- 地图传送和分批开图。
- 查看所有玩家地图标记。
- 查看红蓝双方队伍聊天。
- 接收附近生物和非 OB 玩家血条。
- 排除普通 PvE 选敌和部分世界负面效果。

管理员权限不因 OB 身份自动获得，OB 也不因观察身份获得踢人、复活、自杀、召集、暂停或发物品能力。管理员动作见 [管理员与客户端 MOD 策略](admin-security.md)。

## 血条规则

OB 是血条接收者，不是血条目标:

- 附近存在有效 OB 时，目标血条 classified 定向发送给该 OB。
- OB 自身永远不创建血条。
- 隐藏的 camera shell 虽然 `entity:IsVisible()` 为假，仍可以作为合法接收者。

## 性能注意

- 地图获取任务完成后立即停止。
- 裁判状态广播只在有订阅者时每 `0.5` 秒运行。
- HUD 安全刷新目前有少量 `0.5` 秒任务，只处理本地 OB 界面。
- 新增 OB 能力优先绑定 `ready` 事件或按钮操作，不增加永久服务端轮询。
