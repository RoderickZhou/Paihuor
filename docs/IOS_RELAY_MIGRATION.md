# iOS 端：从 LeanCloud 切到自建中继（必读）

鸿蒙端实际后端**不是 LeanCloud，而是 `10.1.30.175` 上的自建 Node 中继**（公网经 SakuraFrp 隧道）。
iOS 若要和鸿蒙互通（含商量），必须改为对接这套**中继 REST API**，而不是 LeanCloud。否则两端不同后端，永远同步不到一起。

本文件是给 iOS 端（Codex/手改）的改造规格。配置真实值（密钥、地址）不入库，问周翔，填进 `Config/AppConfig.swift`（已 gitignore）。

---

## 1. 中继 REST 契约

- **Base URL**：公网 `RELAY_BASE_URL`（形如 `http://frp-xxx.com:端口`，SakuraFrp 隧道）；同局域网时可优先用 `RELAY_LAN_URL`（`http://10.1.30.175:8787`，更快）。
- **鉴权**：除 `/health` 外，所有请求带 header `x-paihuor-key: <RELAY_KEY>`。
- **Content-Type**：`application/json`。

| 方法 | 路径 | 说明 |
| --- | --- | --- |
| GET | `/health` | 返回 `{"ok":true}`，无需 key。用于「LAN 探测优先、否则走公网」。 |
| POST | `/tasks` | body=完整 task JSON。**服务端**分配 `objectId`(UUID)、`createdAt`、`updatedAt`(epoch ms)，并对 `toUserId` 的**鸿蒙**设备发推送；返回保存后的 task（含 objectId）。 |
| POST | `/tasks/:objectId` | body=patch 对象（浅合并）+ 刷新 `updatedAt`；返回更新后的 task。找不到返回 404。可 patch `archived`/`title`/`detail`/`deadline`/`status`/`negotiation` 等。 |
| DELETE | `/tasks/:objectId` | **软删**：置 `deleted=true` + 刷新 `updatedAt`（这样对端轮询能拿到墓碑并本地移除）。`?hard=1` 为物理删（管理台用）。 |
| GET | `/tasks?familyId=<>&since=<ms>` | 返回该 familyId 下 `updatedAt > since` 的 task 数组（增量轮询），**含已归档与已软删(墓碑)行**，客户端据 `archived`/`deleted` 自行处理。 |
| POST | `/devices` | body=`{familyId,userId,platform,pushToken}` 注册推送 token。 |

> ⚠️ **浅合并**：改 `negotiation`/`reminder` 这类数组/对象字段时，patch 里要带**整段**新值（服务端是整字段覆盖，不会数组追加）。

---

## 2. iOS 必改清单

### A.（必做）新增 `RelayClient`（网络层）
封装上面 5 个调用。`POST /tasks` 后用**服务端返回的 `objectId`** 覆盖本地记录的 objectId（它是跨设备主键，别用本地 UUID）。

### B.（必做，否则解析崩）数据模型时间字段改 epoch ms
`PaihuorTask.createdAt / updatedAt` 现在是 `Date`，且 `JSONDecoder.dateDecodingStrategy = .iso8601`。
中继里这俩是 **Number(epoch ms)**。用现在的解码器去 decode 一个数字会**直接抛错、整条响应解析失败**。
- 改法：把 `createdAt` / `updatedAt` 改为 `Int64`(epoch ms)，由服务端拥有（本地别再 `updatedAt = Date()`，以服务端返回为准）。
- 或保留 `Date` 但为这两个字段写自定义 Codable，按 epoch ms 数字编解码。
- 同时**不要**对整个模型用 `.iso8601` 日期策略（其它时间字段 deadline/receivedAt/doneAt/at/proposedDeadline 本就是 Int64 ms）。

### C.（必做，否则解析崩）`NegotiationMessage.id` 改为可选/有默认
鸿蒙发来的 negotiation 每条是 `{fromUserId, text, proposedDeadline, at}`，**没有 `id`**。
iOS 的 `NegotiationMessage.id` 是非可选 `String`，decode 缺 `id` 的对象会**抛错**。
- 改法：自定义 `init(from:)`，`id` 缺失时默认 `UUID().uuidString`。
- 反向无碍：iOS 发的 negotiation 多带一个 `id`，鸿蒙解析时忽略。

### D.（必做）同步逻辑接进 `TaskStore`
- **建任务**：本地插入后 `POST /tasks`，用返回的 objectId 回填本地。
- **轮询**：定时 `GET /tasks?familyId=&since=<上次最大 updatedAt>`，按 `objectId` 合并到本地，更新游标 since=本批最大 updatedAt。建议间隔 **8s**（与鸿蒙一致，省流量）。
- **收到/完成**：`POST /tasks/:objectId`，patch=`{status, receivedAt, doneAt}`。
- **商量**：本地把消息 append 进 `negotiation` 后，`POST /tasks/:objectId`，patch=`{status:"negotiating", negotiation:<整段数组>, deadline:<如采纳了新时间>}`。
- 合并时按 `objectId` 去重；忽略鸿蒙多发的 `reminderIds` 字段。

### E.（必做）ATS：允许明文 HTTP
中继是 **http（非 https）**。iOS ATS 默认禁明文，请求会被拦。
自用侧载 App，最简单在 `Info.plist` 加：
```xml
<key>NSAppTransportSecurity</key>
<dict>
  <key>NSAllowsArbitraryLoads</key>
  <true/>
</dict>
```
（如想收紧，可改为只对中继域名 + `10.1.30.175` 开 `NSExceptionDomains`。）

### F.（必做）配置 `AppConfig.swift`
`AppConfig.example.swift` 现在只有 MiniMax + LeanCloud 占位。新增中继字段、改 MiniMax 模型：
```swift
enum AppConfig {
    // MiniMax —— 切到 M3 + 关思考（见 INTEROP 2026-06-22）
    static let minimaxApiKey = "<填>"
    static let minimaxModel = "MiniMax-M3"   // 原 M2.7 强制思考、慢
    static let minimaxURL = "https://api.minimaxi.com/v1/chat/completions"
    // 请求体顶层加 thinking:{"type":"disabled"}

    // 自建中继（值问周翔，与鸿蒙端同一套）
    static let relayBaseURL = "<填，如 http://frp-xxx.com:端口>"
    static let relayLanURL  = "http://10.1.30.175:8787"
    static let relayKey     = "<填>"

    // 家庭配对（与鸿蒙同一 familyId；iOS 端默认 wife）
    static let familyId    = "fam-xxx"
    static let myUserId    = "wife"
    static let otherUserId = "husband"
}
```
LeanCloud 三个字段可删（不再使用）。

### G.（已知限制，非阻塞）iOS 暂无推送
中继的华为 Push **只发鸿蒙端**。iOS 没接 APNs，所以：
- 老婆(iOS)发给老公(鸿蒙)：老公能收到关闭态推送 ✅
- 老公(鸿蒙)发给老婆(iOS)：老婆只能**打开 App 靠轮询**看到，后台收不到推送。
APNs 是后续工作；先靠前台 8s 轮询。`POST /devices` iOS 可注册(platform=`ios`)但当前不会被推送，注册与否都行。

---

## 3. 字段对照（与 CONTRACT 第 4 节 / 鸿蒙端一致）

所有时间字段 = **epoch ms (Number)**，`0` 表示未设。`status` 四值全小写：`pending`/`received`/`negotiating`/`done`。`userId` 取值 `wife`/`husband`。

| 字段 | 类型 | 备注 |
| --- | --- | --- |
| objectId | String | 服务端主键(create 返回)，跨设备去重用 |
| familyId / fromUserId / toUserId | String | userId ∈ {wife, husband} |
| rawText / title / detail | String | |
| deadline / receivedAt / doneAt | Number(ms) | 0=未设 |
| status | String | pending/received/negotiating/done |
| reminder | Object | `{intervalMinutes, rampUpLastMinutes, ringtone}` |
| negotiation | Array | `{fromUserId, text, proposedDeadline, at}`，**无 id** |
| archived | Bool | 已归档（**完成即自动归档**：鸿蒙端 onDone 同时置 status=done + archived=true）。主列表只显示未归档，归档区单独看。 |
| deleted | Bool | 软删墓碑。客户端轮询见到 `deleted=true` 即**本地移除**该任务（并撤销其本地提醒）。默认 false。 |
| createdAt / updatedAt | Number(ms) | 服务端维护；updatedAt 用于增量轮询 since |

> iOS 2026-06-28 状态：已补 `archived` / `deleted` 解码与发送；轮询已带 `caps=v2`；删除已改调 `DELETE /tasks/:objectId` 软删；仅新建方可删除。当前 iPhone 端按单向派发阶段隐藏接收方分栏，归档区保留。

> 注：`CONTRACT.md` 的「LeanCloud Class」「MiniMax model=M2.7」等为早期约定，现以本文件 + `INTEROP.md` 2026-06-27 条为准。
