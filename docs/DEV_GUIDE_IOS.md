# 派活儿 iOS 开发摘要

当前阶段已完成 M1，并补上 M2 的核心链路：桌面小组件深链到新建任务页、`SFSpeechRecognizer` 实时转写、MiniMax 解析与预览发送。M3 的 iOS 侧已接入 Paihuor Relay 中继服务，支持跨端拉取、发送与状态更新。

## 技术选择

- Swift + SwiftUI
- 最低 iOS 16.0
- WidgetKit 小组件保留一个大加号入口
- M1 离线运行；M2 新建任务页长按录音后自动调用 MiniMax 生成任务草稿
- M3 配置齐全时走 Paihuor Relay；配置缺失时回退 Mock 远端
- 本地任务缓存为 App 沙盒 Documents 下的 `paihuor_tasks.json`
- Mock 远端任务库为 App 沙盒 Documents 下的 `paihuor_mock_remote_tasks.json`
- MiniMax Key 与 Paihuor Relay Key 通过 `Paihuor/Config/Secrets.xcconfig` 本地注入，该文件不提交

## 已实现

- 首次启动家庭配对：`familyId`、`userId`、`userName`
- 默认角色：iOS 端默认 `wife`，默认收件人 `husband`
- 本地创建任务：字段结构对齐 LeanCloud `Task`
- 任务列表：薄荷绿主题、状态徽章、友好时间、倒计时文案
- 状态流转：`pending`、`received`、`negotiating`、`done`
- 商量记录：追加到 `negotiation`
- 同步适配层：`TaskSyncServicing` 协议 + `PaihuorRelayTaskSyncService` 真实中继 + `MockTaskSyncService` 文件远端模拟
- 任务列表：顶部显示同步状态，支持下拉刷新、手动刷新、前台任务页 8 秒静默轮询
- 任务操作：创建、收到、完成、商量会先更新本地缓存，再异步推送到 Paihuor Relay
- Widget 骨架：`paihuor://record` 打开 App 并进入新建任务页
- 新建任务页：中文语音识别转写，长按录入、松开停止
- MiniMax 解析：录音完成后自动从原话生成标题、细节、截止时间，用户审核后再发送

## 待接入

- M3: 服务端长连接/推送、Device 登记
- M4: 本地通知提醒
- M5: 商量闭环增强

## 同步适配层

`TaskStore` 现在只负责本地缓存、合并、状态发布和调用同步接口。远端能力通过 `TaskSyncServicing` 注入：

- `fetchTasks(for:localTasks:)`：拉取当前家庭/身份相关任务，并允许先把本地缓存合并到远端
- `upsertTask(_:for:)`：创建或更新任务
- `deleteTask(_:for:)`：软删除自己发起的任务
- `deleteTasks(for:)`：清空当前家庭的远端任务

当前默认实现会优先使用 `PaihuorRelayTaskSyncService`。如果 `PaihuorRelayBaseURL` / `PaihuorRelayLanURL` 与 `PaihuorRelayKey` 缺失，则自动回退 `MockTaskSyncService`，UI 不需要重写。

Paihuor Relay 当前接口为自建 Node 中继 REST：

- `GET /health`：LAN 探测，无需 key
- `GET /tasks?familyId=<familyId>&since=<epochMs>&caps=v2`：按 `updatedAt` 增量拉取家庭任务，含归档与软删墓碑，iOS 再过滤当前用户相关任务
- `POST /tasks`：创建任务，使用服务端返回的 `objectId`
- `POST /tasks/{objectId}`：更新任务状态、商量记录、归档等字段；对象/数组字段需整段写回
- `DELETE /tasks/{objectId}`：软删除任务，服务端写入 `deleted=true` 墓碑并刷新 `updatedAt`
- `POST /devices`：注册推送 token；iOS 暂无 APNs，可后续接入

注意：“清空本机任务”只清本地缓存，不会删除服务端任务。用户删除自己发起的任务时，iOS 调用 `DELETE /tasks/{objectId}` 做软删除；已完成任务点“归档”时写入 `archived=true`，并兼容本地 `archivedAt` / `archivedBy` 字段，数据库记录继续保留。

当前中继只给鸿蒙端发华为 Push。iOS 为了先跑通互通，任务页可见且 App 在前台时每 8 秒静默拉取一次；退后台或切到设置页时停止。后续可由服务端补 APNs，再替换同步实现。

## 真机注意

免费 Apple ID 真机调试需要在 Xcode 里选择个人 Team，并保证主 App 与 Widget 两个 Bundle ID 唯一。当前默认 Bundle ID 为：

- `com.xiangzhou.paihuor`
- `com.xiangzhou.paihuor.widget`

## MiniMax 本地配置

`Paihuor/Config/Debug.xcconfig` 与 `Paihuor/Config/Release.xcconfig` 会可选包含 `Secrets.xcconfig`。本机调试时创建：

```xcconfig
MINIMAX_API_KEY = <你的 MiniMax Key>
PAIHUOR_RELAY_KEY = <中继服务 Key>
PAIHUOR_RELAY_BASE_URL = <公网中继地址>
PAIHUOR_RELAY_LAN_URL = http:/$()/10.1.30.175:8787
```

不要提交 `Paihuor/Config/Secrets.xcconfig`。仓库只保留 `Secrets.xcconfig.example`。

当前仓库里已经生成了 `Paihuor/Resources/Assets.xcassets` 和 AppIcon PNG。由于 Codex 沙盒无法访问 CoreSimulator 服务，资源编译器会在命令行构建时失败，所以 M1 暂未把 asset catalog 加入构建阶段；这不影响 App 与 Widget 的代码编译和真机功能测试。需要正式图标时，在 Xcode 中把 `Assets.xcassets` 加回 App target 的 Copy Bundle Resources，并设置 App Icon 为 `AppIcon`。
