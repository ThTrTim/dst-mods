# 管理员与客户端 MOD 策略

## 身份分离

管理员判断集中在 [`admin/privileges.lua`](../../pvp/scripts/src/admin/privileges.lua)，OB 判断集中在 [`observer/privileges.lua`](../../pvp/scripts/src/observer/privileges.lua)。两者是独立身份:

- 管理员可以不是 OB。
- OB 可以不是管理员。
- 观察、全图、队伍聊天旁观和血条接收只属于 OB。
- 服务器管理、统一锁和管理动作只属于管理员。

## RPC 权限

[`core/rpc.lua`](../../pvp/scripts/src/core/rpc.lua) 将动作分组后再调用 [`observer/actions.lua`](../../pvp/scripts/src/observer/actions.lua)。

OB 动作:

- `chuansong`: 地图传送。
- `ditu`: 强制重新获取地图。

管理员动作:

- `give_team_item`: 给指定红队或蓝队发木手杖。
- `wanjia`: 传送到玩家、复活鬼魂或处死玩家。
- `youxi`: 解除开局暂停，或调用服务器暂停切换。
- `zhaoji`: 召集玩家到管理员附近。

所有服务端 RPC 都必须再次验证身份，不能只依赖客户端按钮是否可见。

## 队伍管理

- 自动分队命令要求管理员权限。
- 管理员和普通玩家一样参与分队，筛选依据是当前队伍，不依据管理员身份。
- 统一锁只禁止非管理员自行改队。
- 自动分队不受统一锁限制。

`is_excluded_from_auto_team` 当前没有调用点，是旧策略遗留接口。后续清理时可以删除，但新代码不应引用它。

## 客户端 MOD 策略

[`client_mod_check.lua`](../../pvp/scripts/src/security/client_mod_check.lua) 使用本 MOD 的最高安全整数优先级 `9007199254740991`。

非管理员客户端:

1. Hook `ModManager.InitializeModMain`，阻止 client-only MOD 继续加载。
2. 从 `package.path` 移除被阻止的客户端 MOD 路径。
3. 进入 HUD 后临时禁用已启用的低优先级客户端 MOD。
4. 若发现优先级大于等于 Bird PVP 的客户端 MOD，显示警告、请求服务端封禁 20 秒并离开游戏。
5. 客户端控制台命令被静默阻止。

管理员客户端:

- 保留本地客户端 MOD 加载。
- 跳过高优先级违规检查和临时禁用。
- 保留客户端控制台命令。

管理员身份在客户端通过当前用户的 client table 判断，服务端踢出 RPC 还会再次检查管理员，避免管理员被误封。

## 已知边界

- 加载优先级只能保证本 MOD 尽早执行，不能逆转已经先执行的同级或更高优先级代码，因此高优先级客户端 MOD 必须拒绝连接。
- client-only MOD 的阻止策略只针对客户端本地 MOD，服务器要求的 MOD 仍按原版流程加载。
- `bypasses_client_mod_check` 是兼容接口，当前安全模块直接检查本地管理员身份。
- 修改安全策略后必须分别测试普通玩家、客户端房主、专服管理员和非管理员连接。
