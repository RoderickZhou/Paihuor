# 派活儿 iOS 开发摘要

当前阶段已完成 M1，并补上 M2 的核心链路：桌面小组件深链到新建任务页、`SFSpeechRecognizer` 实时转写、MiniMax 解析与预览发送。M3 接 LeanCloud Storage + LiveQuery。

## 技术选择

- Swift + SwiftUI
- 最低 iOS 16.0
- WidgetKit 小组件保留一个大加号入口
- M1 离线运行；M2 新建任务页长按录音后自动调用 MiniMax 生成任务草稿
- 本地任务缓存为 App 沙盒 Documents 下的 `paihuor_tasks.json`
- MiniMax Key 通过 `Paihuor/Config/Secrets.xcconfig` 本地注入，该文件不提交

## 已实现

- 首次启动家庭配对：`familyId`、`userId`、`userName`
- 默认角色：iOS 端默认 `wife`，默认收件人 `husband`
- 本地创建任务：字段结构对齐 LeanCloud `Task`
- 任务列表：薄荷绿主题、状态徽章、友好时间、倒计时文案
- 状态流转：`pending`、`received`、`negotiating`、`done`
- 商量记录：追加到 `negotiation`
- Widget 骨架：`paihuor://record` 打开 App 并进入新建任务页
- 新建任务页：中文语音识别转写，长按录入、松开停止
- MiniMax 解析：录音完成后自动从原话生成标题、细节、截止时间，用户审核后再发送

## 待接入

- M3: LeanCloud SDK、Storage、LiveQuery、Device 登记
- M4: 本地通知提醒
- M5: 商量闭环增强

## 真机注意

免费 Apple ID 真机调试需要在 Xcode 里选择个人 Team，并保证主 App 与 Widget 两个 Bundle ID 唯一。当前默认 Bundle ID 为：

- `com.xiangzhou.paihuor`
- `com.xiangzhou.paihuor.widget`

## MiniMax 本地配置

`Paihuor/Config/Debug.xcconfig` 与 `Paihuor/Config/Release.xcconfig` 会可选包含 `Secrets.xcconfig`。本机调试时创建：

```xcconfig
MINIMAX_API_KEY = <你的 MiniMax Key>
```

不要提交 `Paihuor/Config/Secrets.xcconfig`。仓库只保留 `Secrets.xcconfig.example`。

当前仓库里已经生成了 `Paihuor/Resources/Assets.xcassets` 和 AppIcon PNG。由于 Codex 沙盒无法访问 CoreSimulator 服务，资源编译器会在命令行构建时失败，所以 M1 暂未把 asset catalog 加入构建阶段；这不影响 App 与 Widget 的代码编译和真机功能测试。需要正式图标时，在 Xcode 中把 `Assets.xcassets` 加回 App target 的 Copy Bundle Resources，并设置 App Icon 为 `AppIcon`。
