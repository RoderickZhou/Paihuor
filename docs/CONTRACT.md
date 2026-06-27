# 派活儿跨端契约

本文件记录 iOS 与 HarmonyOS 必须保持一致的数据、模型调用与家庭配对约定。任何契约改动都先追加到 `docs/INTEROP.md`，对方确认后再改。

## Task 数据模型

所有自定义时间字段使用 `Number`，含义为 UTC epoch milliseconds。`0` 表示未设置。

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `objectId` | String | 服务端主键 |
| `createdAt` / `updatedAt` | Number | 服务端维护，epoch ms |
| `familyId` | String | 家庭配对码 |
| `fromUserId` | String | 发送方，固定取值 `wife` / `husband` |
| `toUserId` | String | 接收方，固定取值 `wife` / `husband` |
| `rawText` | String | 语音或输入原文 |
| `title` | String | MiniMax 抽取标题 |
| `detail` | String | 细节，可为空字符串 |
| `deadline` | Number | 截止时间 epoch ms，`0` 表示无 |
| `status` | String | `pending` / `received` / `negotiating` / `done` |
| `reminder` | Object | `{ "intervalMinutes": Number, "rampUpLastMinutes": Number, "ringtone": String }` |
| `negotiation` | Array | `{ "fromUserId": String, "text": String, "proposedDeadline": Number, "at": Number }` |
| `receivedAt` | Number | 接收方点收到的时刻，`0` 未收到 |
| `doneAt` | Number | 完成时刻，`0` 未完成 |
| `archived` | Boolean | 服务端归档标志，缺省 `false` |
| `deleted` | Boolean | 服务端软删除墓碑，缺省 `false` |
| `archivedAt` | Number | 归档时刻 epoch ms，`0` 或缺省表示未归档 |
| `archivedBy` | String | 归档来源，建议 `system` / `wife` / `husband`，可缺省 |
| `deletedAt` | Number | 软删除时刻 epoch ms，`0` 或缺省表示未删除 |
| `deletedBy` | String | 删除发起人，只允许原 `fromUserId` 发起，建议 `wife` / `husband` |

默认 `reminder`：

```json
{
  "intervalMinutes": 30,
  "rampUpLastMinutes": 5,
  "ringtone": "default"
}
```

## Device 数据模型

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `familyId` | String | 家庭配对码 |
| `userId` | String | `wife` / `husband` |
| `platform` | String | `ios` 或 `harmony` |
| `harmonyPushToken` | String | 仅鸿蒙端写入；iOS 留空 |

## 查询与同步

拉取任务：`familyId == 我的 familyId`，且 `toUserId == 我` 或 `fromUserId == 我`，按 `createdAt` 倒序。

实时同步：当前 iOS 前台轮询自建中继；HarmonyOS 可由自建中继推送通知。

## Paihuor Relay 中继 API

当前跨端互通使用 Claude 提供的自建 Node 中继 REST。中继返回的 `createdAt` / `updatedAt` 为 epoch milliseconds，iOS 通过 DTO 转换成本地 Date。

- Header: `x-paihuor-key: <PAIHUOR_RELAY_KEY>`
- 默认 `familyId`: `fam-zx-001`
- `GET /health`：LAN 探测，无需 key
- `GET /tasks?familyId=<familyId>&since=<epochMs>&caps=v2`：返回当前家庭 `updatedAt > since` 的任务数组，含归档与软删墓碑
- `POST /tasks`：创建任务，body 使用 Task 字段；服务端返回最终任务，并可能生成新的 `objectId`
- `POST /tasks/{objectId}`：更新任务，body 使用 Task 字段，可用于 `status`、`receivedAt`、`doneAt`、`negotiation`、`archivedAt`、`deletedAt` 等状态变化
- `DELETE /tasks/{objectId}`：默认软删，服务端置 `deleted=true` 并刷新 `updatedAt`；`?hard=1` 为管理台物理删除
- `POST /devices`：注册设备推送 token

用户主动删除自己发起的任务时，客户端调用 `DELETE /tasks/{objectId}` 做软删除；两端拉取到 `deleted=true` 后应从日常任务列表隐藏。`deletedAt` / `deletedBy` 是 iOS 兼容字段，服务端当前以 `deleted` 墓碑为准。

归档策略：客户端不要用删除来清理完成记录。服务端归档标志为 `archived=true`；iOS 同时兼容 `archivedAt` / `archivedBy`，完成超过 24 小时也会视图归档。两端拉取任务时仍保留归档记录，再由客户端分栏展示。

## MiniMax 契约

- Endpoint: `POST https://api.minimaxi.com/v1/chat/completions`
- Header: `Authorization: Bearer <MINIMAX_API_KEY>`，`Content-Type: application/json`
- Model: `MiniMax-M3`，用于 OpenAI-compatible Chat Completions；解析任务不要求深度推理，prompt 明确禁止输出思考过程
- Body: `{ "model": <model>, "messages": [system, user], "temperature": 0.2, "max_tokens": 300, "thinking": { "type": "disabled" } }`
- Result: `choices[0].message.content`，内容必须是严格 JSON 字符串

System prompt:

```text
你是"派活儿"App 的待办解析助手。用户会口述/输入一件要交代对方做的事。
只输出一个严格的 JSON 对象，不要任何多余文字、不要 markdown 代码块：
{"title":"一句话动作标题(不超过15字)","detail":"补充细节，没有则空字符串","hasDeadline":true或false,"deadlineISO":"ISO8601带时区的截止时间，如 2026-06-21T20:00:00+08:00；无截止则空字符串"}
这是简单的信息抽取任务，不需要深度推理。不要输出 <think>、思考过程、解释、注释或前后缀。
解析规则：
- 基于用户消息里给出的"当前时间"解析相对时间。
- "今晚X点"=当天X:00；"明早/明天X点"=次日X:00；"X小时后/X分钟后"=当前时间加对应时长；"下班前"约当天18:00；没提到时间则 hasDeadline=false。
- 时区固定 Asia/Shanghai (+08:00)。
```

User message:

```text
当前时间：<本地ISO8601含+08:00，如 2026-06-21T15:30:00+08:00>
口述内容：<ASR/输入的文本>
```

## 家庭配对

首次启动填写 `familyId`，选择 `userId`，并保存显示名 `userName`。两端固定使用 `wife` / `husband` 两个 userId。iOS 默认 `wife`，默认收件人 `husband`；HarmonyOS 默认相反。
