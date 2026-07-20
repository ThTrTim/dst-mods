# 蔡鸟 Bird 的 DST MOD 开发仓库

## 目录结构

| 路径 | 用途 | 上传创意工坊 |
| --- | --- | --- |
| [`pvp/`](pvp/) |  PVP MOD 运行源码、资源、配置 | 是 |
| [`docs/`](docs/) | 按 MOD 分类的中文维护文档 | 否 |
| [`tools/pvp/`](tools/pvp/) | 反混淆和资源维护工具 | 否 |
| `.gitignore`、`.gitattributes` | 仓库规则 | 否 |

不要把文档、原始素材、调试脚本或备份放进 `pvp/`。发布时应只选择 `pvp/` 目录。

## 文档入口

| MOD | 源码 | 文档 |
| --- | --- | --- |
| 【月落繁星】饥荒pvp专用mod | [`pvp/`](pvp/) | [`docs/pvp/`](docs/pvp/) |

PVP 维护入口:

- [文档导航](docs/pvp/README.md)
- [总体架构](docs/pvp/architecture.md)
- [队伍系统](docs/pvp/team-system.md)
- [排错手册](docs/pvp/troubleshooting.md)

新增其他 MOD 文档时，使用 `docs/<mod目录名>/README.md` 作为入口，并在上表登记。

## 准备与开局

本次对 PVP 选人准备与开局逻辑的优化，相关代码位于 `pvp/scripts/components/worldcharacterselectlobby.lua`、`pvp/scripts/src/lobby/preselect.lua` 与 `pvp/scripts/widgets/` 并带有 `[PATCH]` 注释。

- 等待区 / OB 玩家不显示准备按钮，不参与准备统计。
- 标题“正在等待其他玩家 (x/y)”中的总人数只统计红蓝队玩家。
- 开局条件改为红蓝队全部玩家准备好才开始，等待区 / OB 不影响开局。
- 修复准备按钮因手柄连接被隐藏的问题。
- 修复原版 waitingforplayers 在人未满时弹确认窗导致准备不生效的问题。
