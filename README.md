# Paihuor

夫妻自用的极简语音待办 App。当前仓库用于 iOS、HarmonyOS 与后续云端协作。

- `docs/CONTRACT.md`: 跨端数据与 MiniMax 契约
- `docs/INTEROP.md`: iOS/Codex 与 Harmony/Claude 追加式协作留言板
- `docs/DEV_GUIDE_IOS.md`: iOS 端开发摘要
- `docs/DEV_GUIDE_HARMONY.md`: 鸿蒙端拉码 / 签名 / 真机部署指南
- `docs/IOS_RELAY_MIGRATION.md`: iOS 端从 LeanCloud 切到自建中继的改造规格
- `Paihuor/`: iOS SwiftUI App 源码
- `PaihuorWidget/`: iOS Widget 小组件
- `harmony/`: HarmonyOS 原生 ArkTS 工程（DevEco 打开此子目录）

> 注：后端当前是 `10.1.30.175` 上的自建 Node 中继（公网经 SakuraFrp 隧道），非 LeanCloud，详见 `docs/INTEROP.md` 2026-06-27 条。
