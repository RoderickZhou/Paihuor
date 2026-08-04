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
| `images` | Array | 图片附件元数据数组，每项 `{ id, mime, w, h, size }`；空数组/缺省表示无图。详见「图片附件」节 |

图片元素结构（`images` 数组每一项）：

```json
{ "id": "服务端分配的附件id(uuid)", "mime": "image/jpeg", "w": 1080, "h": 1440, "size": 234567 }
```

`images` 与 `negotiation` 一致，采用**整段数组覆盖**写回（`POST /tasks/{objectId}` 带完整 `images` 即替换）。图片二进制不进任务 JSON，仅存 `id` 等元数据；真实 URL 由端上用 `中继base + /uploads/{id}` 拼接。服务端封顶每任务 9 张，超出截断，并过滤缺 `id` 的脏元素。

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
- `DELETE /tasks/{objectId}?by=<userId>`：默认软删，服务端置 `deleted=true`、记录 `deletedBy` 并刷新 `updatedAt`；`?hard=1` 为管理台物理删除
- `POST /devices`：注册设备推送 token

### 图片附件（Uploads）

图片走**两阶段、旁路上传**：先把二进制传到中继换回 `id`，再把 `{id,...}` 元数据放进任务的 `images` 字段随任务同步。图片字节**不进任务 JSON、不进 `GET /tasks` 增量**，避免撑大同步体积（沿用降低轮询流量的思路）。

- `POST /uploads?familyId=<familyId>&w=<可选>&h=<可选>`
  - Header：`x-paihuor-key: <KEY>`，`Content-Type: image/jpeg|image/png|image/webp|image/gif`（**必填且决定存储格式**）
  - Body：**原始图片字节**（非 multipart、非 base64、非 JSON）
  - 上限：单图 **15 MiB**（超出 `413`）；不支持的 `Content-Type` 返回 `415`
  - `w`/`h` 为端上尺寸提示；服务端会自行嗅探 PNG/JPEG/GIF/WebP 尺寸，嗅探不到才用提示兜底
  - 返回：`{ "id","url":"/uploads/{id}","mime","ext","size","w","h","createdAt" }`
- `GET /uploads/{id}`：返回图片字节。鉴权二选一：`x-paihuor-key` header **或** `?key=<KEY>`（供 `<img>` 直接引用）。响应 `Cache-Control: immutable`，可长期缓存
- `DELETE /uploads/{id}`：物理删除图片文件+元数据（管理台清理用；正常同步不需要，孤儿图由服务端 GC 回收）

跨端注意：

- **URL 由端上拼**：`RELAY_LAN_URL`/`RELAY_BASE_URL` + `/uploads/{id}`（+ 需要时带 `?key=`）。不要把绝对 URL 存进 `images`，因为 LAN/公网 base 不同。
- **iOS 的 HEIC 必须先转码成 JPEG 再传**（Harmony/浏览器不识别 HEIC）。中继只接 jpg/png/webp/gif。
- 上传前**端上先降采样**（建议最长边 ≤1600px、JPEG≈0.8、单图目标 ~1MB），省穿透隧道流量、加快对端加载。
- **孤儿回收**：上传后若 24h 内没有任何任务引用该 `id`，服务端会当孤儿清掉。因此**先上传拿 id、尽快随任务保存**；不要长期只上传不落任务。
- 权限沿用任务规则：编辑/删除（含改 `images`）仅**新建方**（`fromUserId==我`）可做。

用户主动删除自己发起的任务时，客户端调用 `DELETE /tasks/{objectId}?by=<userId>` 做软删除；两端拉取到 `deleted=true` 后应从日常任务列表隐藏。`deletedAt` / `deletedBy` 是跨端审计字段，服务端以 `deleted` 墓碑为准。

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

首次启动填写 `familyId`，选择 `userId`，并保存显示名 `userName`。两端固定使用 `wife` / `husband` 两个 userId，对方身份由当前身份自动推导。HarmonyOS 身份必须保存在运行时 Profile 中，同一个 HAP 可分别配置为老公或老婆；不得再从 `AppConfig` 写死本机身份。
