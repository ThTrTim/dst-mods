# 发布检查

## 发布边界

创意工坊只上传 [`pvp/`](../../pvp/) 目录。以下内容不属于发布包:

- `docs/`
- `tools/`
- Git 元数据
- 下载文件、临时 ZIP、日志和备份
- 其他本地 MOD 目录

当前动画源包位于 [`tools/pvp/generated_assets/`](../../tools/pvp/generated_assets/)，发布用动画包位于 [`pvp/anim/`](../../pvp/anim/)。

## `pvp/` 允许内容

- `modinfo.lua`、`modmain.lua`、`modworldgenmain.lua`
- `modicon.tex`、`modicon.xml`、`mod.manifest`
- `anim/`、`announcestrings/`
- `scripts/` 下的运行源码、组件、prefab 和 widget

不要在 `pvp/` 中加入:

- `docs/`
- `tools/`
- `backup/`、`temp/`、`downloads/`
- 原始 PSD、工程文件、解包后的动画源码
- 客户端和服务端日志

## 提交前检查

1. 查看 `git status --short`，确认没有误加入其他本地 MOD。
2. 查看 `git diff --check`，排除空白错误。
3. 搜索旧命名 `qiaoer`，确认不是兼容需求。
4. 搜索 `pvp/docs` 和 `pvp/tools`，结果应为空。
5. 检查 `modinfo.lua` 版本和配置默认值。
6. 使用包含 `beta` 的版本完成地上、地下、重连和大厅测试。
7. 发布前确认动画 bank、prefab 名和资源 ZIP 一致。

## 最小回归场景

- 新存档进入大厅，默认等待，手动选红蓝和 OB。
- 等待人员分队与全部人员分队，人数保持平衡。
- 统一锁阻止普通玩家自选，但管理员和自动分队可修改。
- 游戏开始时有人未选角色，不进入其生成流程且客户端不崩溃。
- 红蓝玩家上下洞、死亡、重连后队伍不变。
- pending 阶段不显示敌方地图头像，不发送队伍聊天。
- OB 上下洞后仍有移动、地图、视野和血条观察能力。
- 普通客户端 MOD 被静默禁用，高优先级客户端 MOD 被拒绝。
