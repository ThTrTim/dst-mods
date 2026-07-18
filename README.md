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
