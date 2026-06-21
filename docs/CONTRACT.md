# 派活儿跨端契约

本文件记录 iOS 与 HarmonyOS 必须保持一致的数据、模型调用与家庭配对约定。任何契约改动都先追加到 `docs/INTEROP.md`，对方确认后再改。

## LeanCloud Class: Task

所有自定义时间字段使用 `Number`，含义为 UTC epoch milliseconds。`0` 表示未设置。

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `objectId` | String | LeanCloud 自动主键 |
| `createdAt` / `updatedAt` | Date | LeanCloud 内置字段 |
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

默认 `reminder`：

```json
{
  "intervalMinutes": 30,
  "rampUpLastMinutes": 5,
  "ringtone": "default"
}
```

## LeanCloud Class: Device

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `familyId` | String | 家庭配对码 |
| `userId` | String | `wife` / `husband` |
| `platform` | String | `ios` 或 `harmony` |
| `harmonyPushToken` | String | 仅鸿蒙端写入；iOS 留空 |

## 查询与同步

拉取任务：`familyId == 我的 familyId`，且 `toUserId == 我` 或 `fromUserId == 我`，按 `createdAt` 倒序。

实时同步：LiveQuery 订阅同一个 query，收到 create/update 后刷新 UI。

## MiniMax 契约

- Endpoint: `POST https://api.minimaxi.com/v1/chat/completions`
- Header: `Authorization: Bearer <MINIMAX_API_KEY>`，`Content-Type: application/json`
- Model: `MiniMax-M2.7-highspeed`，待在 MiniMax 控制台最终核对
- Body: `{ "model": <model>, "messages": [system, user], "temperature": 0.2, "max_tokens": 300 }`
- Result: `choices[0].message.content`，内容必须是严格 JSON 字符串

System prompt:

```text
你是"派活儿"App 的待办解析助手。用户会口述/输入一件要交代对方做的事。
只输出一个严格的 JSON 对象，不要任何多余文字、不要 markdown 代码块：
{"title":"一句话动作标题(不超过15字)","detail":"补充细节，没有则空字符串","hasDeadline":true或false,"deadlineISO":"ISO8601带时区的截止时间，如 2026-06-21T20:00:00+08:00；无截止则空字符串"}
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
