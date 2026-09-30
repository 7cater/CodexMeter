# Changelog

## v0.1.0 — 2026-09-30

首次发布原生 macOS Codex 用量仪表盘。

- 单色双排菜单栏用量条，分别展示 5h / 7d 已用和剩余比例，自动适配深浅色菜单栏。
- 读取本机 Codex app-server RPC 的额度与重置时间，支持自动、手动及唤醒后刷新。
- 从 sessions 和 archived_sessions 解析 Token；去除重复通知、归档和 fork 中的重复事件，按本地日期聚合。
- 展示今日 Input / Cached / Output / Total 和模型 API 单价折算的费用明细；未知价格明确标注。
- 每日 Token 柱状图支持 7 / 14 / 30 天、悬停明细和周期汇总。
- 首屏收紧为额度与今日 Token，向下滚动查看图表；弹框重新打开时返回顶部，不默认聚焦设置。
- 登录时启动、刷新间隔、菜单栏显示模式、费用开关与 CLI 路径设置。
- 提供无需完整 Xcode 的构建、打包脚本和 14 项核心校验。

发布包：Apple Silicon（arm64），macOS 14+，ad-hoc 签名，未进行 Apple 公证。

Estimated API Cost 是当前 API 单价折算的估计值，不是 ChatGPT 订阅账单；内置价格表核对日期为 2026-09-30。
