# 派活儿 iOS 开发摘要

当前阶段先做 M1：建工程、数据模型、本地缓存、卡片列表 UI、家庭配对设置页。M2 再接桌面小组件深链到录音页、`SFSpeechRecognizer` 实时转写、MiniMax 解析与预览发送。M3 接 LeanCloud Storage + LiveQuery。

## 技术选择

- Swift + SwiftUI
- 最低 iOS 16.0
- WidgetKit 小组件保留一个大加号入口
- M1 离线运行，不依赖 MiniMax、LeanCloud 或网络
- 本地任务缓存为 App 沙盒 Documents 下的 `paihuor_tasks.json`

## M1 已实现

- 首次启动家庭配对：`familyId`、`userId`、`userName`
- 默认角色：iOS 端默认 `wife`，默认收件人 `husband`
- 本地创建任务：字段结构对齐 LeanCloud `Task`
- 任务列表：薄荷绿主题、状态徽章、友好时间、倒计时文案
- 状态流转：`pending`、`received`、`negotiating`、`done`
- 商量记录：追加到 `negotiation`
- Widget 骨架：`paihuor://record` 打开 App 并进入新建任务页

## 待接入

- M2: ASR 录音页、MiniMax 结构化解析、审核预览卡
- M3: LeanCloud SDK、Storage、LiveQuery、Device 登记
- M4: 本地通知提醒
- M5: 商量闭环增强

## 真机注意

免费 Apple ID 真机调试需要在 Xcode 里选择个人 Team，并保证主 App 与 Widget 两个 Bundle ID 唯一。当前默认 Bundle ID 为：

- `dev.zx.paihuor`
- `dev.zx.paihuor.widget`

当前仓库里已经生成了 `Paihuor/Resources/Assets.xcassets` 和 AppIcon PNG。由于 Codex 沙盒无法访问 CoreSimulator 服务，资源编译器会在命令行构建时失败，所以 M1 暂未把 asset catalog 加入构建阶段；这不影响 App 与 Widget 的代码编译和真机功能测试。需要正式图标时，在 Xcode 中把 `Assets.xcassets` 加回 App target 的 Copy Bundle Resources，并设置 App Icon 为 `AppIcon`。
