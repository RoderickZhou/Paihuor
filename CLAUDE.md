# Paihuor Development Handoff

This repository is a multi-platform private task app for a couple. It contains:

- iOS SwiftUI app: `Paihuor/`
- iOS Widget extension: `PaihuorWidget/`
- HarmonyOS ArkTS app: `harmony/`
- Node relay server: `server/`
- Cross-platform docs and contracts: `docs/`

Current source of truth is GitHub `main`. As of 2026-07-10 the latest important commit is:

```text
fec1216 fix(sync): align delete tombstone handling
```

There may be a local untracked `.pushloop.log`; ignore it.

## Operating Principles

- Treat `docs/CONTRACT.md` as the data/API contract.
- Append cross-platform decisions to `docs/INTEROP.md` before changing behavior that affects both iOS and HarmonyOS.
- Never commit secrets or signing material.
- Do not overwrite the live relay blindly. The live relay on `paihuor-175` is its own Git repo and may contain deployed changes not yet mirrored into GitHub.
- Prefer small, verifiable changes. For sync/server work, verify with a create/delete tombstone smoke test.

## Private Config Files

Do not commit these:

- `Paihuor/Config/Secrets.xcconfig`
- `harmony/entry/src/main/ets/config/AppConfig.ets`
- Harmony signing cert/profile files
- `/home/zx/paihuor-relay/hw-service-account.json`
- `paihuor.db` backups or live DB files

Templates/examples:

- iOS: `Paihuor/Config/Secrets.xcconfig.example`
- HarmonyOS: `harmony/entry/src/main/ets/config/AppConfig.example.ets`
- Server service template: `server/paihuor-relay.service`

## Product Model

Core task fields live in `docs/CONTRACT.md`.

Important invariants:

- `familyId` identifies the couple/family.
- `fromUserId` / `toUserId` are fixed role strings: `wife` and `husband`.
- Time fields use epoch milliseconds.
- `status` is one of `pending`, `received`, `negotiating`, `done`.
- Completed tasks should be archived, not deleted.
- Deletion is soft-delete tombstone sync:
  - client calls `DELETE /tasks/{objectId}?by=<userId>`
  - server writes `deleted=true`, `deletedAt`, `deletedBy`, updates `updatedAt`
  - clients that fetch with `caps=v2` receive tombstones and remove/hide local tasks

## Relay Server

The backend is a self-hosted Node relay, not LeanCloud.

Live host:

```text
SSH alias: paihuor-175
LAN IP: 10.1.30.175
Service: paihuor-relay
Live path: /home/zx/paihuor-relay
Port: 8787
Health: http://10.1.30.175:8787/health
```

Main implementation:

```text
server/server.js
```

Runtime traits:

- Node built-in `node:sqlite`; no npm package install is needed.
- SQLite DB file is `paihuor.db` beside `server.js`.
- Admin page is served from the same file at `/admin`.
- Huawei Push uses JWT service-account auth:
  - `HW_PROJECT_ID`
  - `HW_SERVICE_ACCOUNT_FILE` or `HW_SERVICE_ACCOUNT_JSON`
  - optional `HW_ENABLE_EXTENDED_PUSH`
  - optional `HW_TEST_MESSAGE`
  - optional `HW_NOTIFICATION_CATEGORY`

API summary:

```text
GET    /health
GET    /tasks?familyId=<familyId>&since=<epochMs>&caps=v2
POST   /tasks
POST   /tasks/{objectId}
DELETE /tasks/{objectId}?by=<userId>
POST   /devices
POST   /push-test
GET    /admin
GET    /admin/list
```

Before changing the server:

```powershell
ssh paihuor-175 "git -C /home/zx/paihuor-relay status --short --branch; systemctl status paihuor-relay --no-pager"
```

Deploy safely from Windows:

```powershell
node --check C:\Users\Administrator\Documents\PaihuorRepo\server\server.js
scp C:\Users\Administrator\Documents\PaihuorRepo\server\server.js paihuor-175:/tmp/paihuor-server.js
ssh paihuor-175 'node --check /tmp/paihuor-server.js && ts=$(date +%Y%m%d%H%M%S) && cp /home/zx/paihuor-relay/server.js /home/zx/paihuor-relay/server.js.bak-codex-$ts && cp /home/zx/paihuor-relay/paihuor.db /home/zx/paihuor-relay/paihuor.db.bak-codex-$ts && mv /tmp/paihuor-server.js /home/zx/paihuor-relay/server.js && chown zx:zx /home/zx/paihuor-relay/server.js && chmod 664 /home/zx/paihuor-relay/server.js && sudo systemctl restart paihuor-relay && sleep 1 && systemctl is-active paihuor-relay && curl -fsS http://127.0.0.1:8787/health'
```

After deployment, commit the live relay repo if it is dirty:

```powershell
ssh paihuor-175 "git -C /home/zx/paihuor-relay status --short; git -C /home/zx/paihuor-relay add server.js && git -C /home/zx/paihuor-relay commit -m 'Describe server change' || true"
```

Server smoke test for delete sync:

```powershell
$key = '<PAIHUOR_KEY>'
$base = 'http://10.1.30.175:8787'
$headers = @{ 'x-paihuor-key' = $key }
$body = @{
  familyId = 'codex-delete-test'
  fromUserId = 'wife'
  toUserId = 'husband'
  rawText = 'codex delete probe'
  title = 'codex delete probe'
  detail = 'temporary'
  deadline = 0
  status = 'pending'
} | ConvertTo-Json -Compress
$created = Invoke-RestMethod -Method Post -Uri "$base/tasks" -Headers $headers -ContentType 'application/json' -Body $body
$deleted = Invoke-RestMethod -Method Delete -Uri "$base/tasks/$($created.objectId)?by=codex" -Headers $headers
$list = Invoke-RestMethod -Method Get -Uri "$base/tasks?familyId=codex-delete-test&since=0&caps=v2" -Headers $headers
Invoke-RestMethod -Method Delete -Uri "$base/tasks/$($created.objectId)?hard=1" -Headers $headers | Out-Null
```

Expected: `deleted.deleted == true`, `deleted.deletedBy == 'codex'`, and the tombstone appears in the `caps=v2` list before hard cleanup.

## iOS App

Main files:

```text
Paihuor/PaihuorApp.swift
Paihuor/App/AppView.swift
Paihuor/Models/PaihuorTask.swift
Paihuor/Services/TaskStore.swift
Paihuor/Services/TaskSyncService.swift
Paihuor/Services/MiniMaxTaskParser.swift
Paihuor/Features/Tasks/
Paihuor/Features/Settings/
Paihuor/Design/PaihuorTheme.swift
PaihuorWidget/PaihuorWidget.swift
```

Current behavior:

- SwiftUI, minimum iOS 16.
- Default local role is `wife`; default receiver is `husband`.
- Uses local JSON cache in app Documents.
- If relay config is missing, falls back to `MockTaskSyncService`.
- Real relay implementation is `PaihuorRelayTaskSyncService`.
- Foreground task page silently polls every 8 seconds.
- iOS currently does not have APNs relay push; do not assume background delivery.
- Task delete now calls `DELETE /tasks/{objectId}?by=<userId>`.

Local iOS secret config:

```text
Paihuor/Config/Secrets.xcconfig
```

Example values:

```xcconfig
MINIMAX_API_KEY = <MiniMax key>
PAIHUOR_RELAY_KEY = <relay key>
PAIHUOR_RELAY_BASE_URL = <public relay URL>
PAIHUOR_RELAY_LAN_URL = http:/$()/10.1.30.175:8787
```

Build/test notes:

- Use Xcode on macOS for real iOS builds and device installs.
- On this Windows machine, `xcodebuild` is unavailable.
- Bundle IDs:
  - App: `com.xiangzhou.paihuor`
  - Widget: `com.xiangzhou.paihuor.widget`
- Free Apple ID device testing requires selecting a personal Team for both targets.

## HarmonyOS App

The HarmonyOS app is under:

```text
harmony/
```

The separate DevEco working copy on this Windows machine has also been used:

```text
C:\Users\Administrator\DevEcoStudioProjects\Paihuor
```

If you change Harmony code in `harmony/`, keep the DevEco project and GitHub repo synchronized, or open the `harmony/` subdirectory directly in DevEco.

Main files:

```text
harmony/entry/src/main/ets/pages/Index.ets
harmony/entry/src/main/ets/models/TaskModels.ets
harmony/entry/src/main/ets/services/TaskStore.ets
harmony/entry/src/main/ets/services/RelayService.ets
harmony/entry/src/main/ets/services/AIService.ets
harmony/entry/src/main/ets/services/AsrService.ets
harmony/entry/src/main/ets/services/ReminderService.ets
harmony/entry/src/main/ets/services/NotificationService.ets
harmony/entry/src/main/ets/services/DeviceService.ets
harmony/entry/src/main/ets/services/WidgetCardData.ets
harmony/entry/src/main/ets/widget/pages/WidgetCard.ets
```

Current behavior:

- HarmonyOS Stage app, single `entry` module.
- Main screen is `Index.ets`.
- UI was aligned with latest iOS task-list design:
  - inbox/archive switch in the same page
  - bottom icon dock
  - top menu/grid resource icons
  - FAB add button
  - task cards open a detail half-sheet
  - widget left-top uses task icon, not the old leaf emoji
- Local storage uses Preferences:
  - preference name: `paihuor_store`
  - key: `tasks`
- Relay sync prefers LAN URL then public URL.
- Pulls with `caps=v2` and handles delete tombstones.
- Huawei Push currently targets Harmony devices.

Local Harmony config:

```text
harmony/entry/src/main/ets/config/AppConfig.ets
```

Create it from:

```text
harmony/entry/src/main/ets/config/AppConfig.example.ets
```

Important values:

```text
MINIMAX_API_KEY
RELAY_BASE_URL
RELAY_LAN_URL = http://10.1.30.175:8787
RELAY_KEY
FAMILY_ID
MY_USER_ID = husband
OTHER_USER_ID = wife
```

Windows command-line build:

```powershell
$env:DEVECO_SDK_HOME = [Environment]::GetEnvironmentVariable('DEVECO_SDK_HOME', 'User')
& 'C:\Program Files\Huawei\DevEco Studio\tools\hvigor\bin\hvigorw.bat' clean assembleApp --no-daemon
```

Expected signed outputs:

```text
build\outputs\default\Paihuor-default-signed.app
entry\build\default\outputs\default\entry-default-signed.hap
```

Install to connected Huawei device:

```powershell
& 'C:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe' list targets
& 'C:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe' install -r 'C:\Users\Administrator\DevEcoStudioProjects\Paihuor\entry\build\default\outputs\default\entry-default-signed.hap'
& 'C:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe' shell aa start -b com.example.paihuor -a EntryAbility
```

If `aa start` fails with a locked-screen error, unlock the phone; install may already have succeeded.

Common Harmony build pitfalls:

- `DEVECO_SDK_HOME` must point to `C:\Program Files\Huawei\DevEco Studio\sdk`, not `sdk\default`.
- DevEco signing is machine-specific. If install fails with signature mismatch, uninstall the app from the phone or regenerate signing.
- A previous build blocker was a stray full-width Chinese comma in `Index.ets`; if ArkTS reports invalid character, inspect the exact line first.
- Read/write source files with UTF-8 in PowerShell to avoid garbled Chinese.

## MiniMax Task Parsing

Both clients should use:

```text
Model: MiniMax-M3
Endpoint: https://api.minimaxi.com/v1/chat/completions
thinking: { "type": "disabled" }
```

Do not switch back to MiniMax M2.7 for task extraction. M2.7 forces thinking output and is slower/noisier for this app.

Parser output must be strict JSON:

```json
{
  "title": "一句话动作标题",
  "detail": "补充细节",
  "hasDeadline": true,
  "deadlineISO": "2026-06-21T20:00:00+08:00"
}
```

No Markdown, no code fences, no `<think>`.

## UI Direction

iOS is the visual reference for the main task UI. Harmony should follow it unless the user explicitly asks otherwise.

Current shared direction:

- Pale blue background, blue primary action color.
- Large title: `收集箱` or `归档`.
- Top left menu icon and top right grid icon in circular white buttons.
- Empty states use task/archive illustrations, not emoji.
- Bottom dock uses icons, not text labels.
- Archive switches in-place; it should not feel like opening a new page.
- Cards should feel calm, compact, and direct.

When matching iOS, inspect:

```text
Paihuor/Design/PaihuorTheme.swift
Paihuor/Features/Tasks/TaskListView.swift
Paihuor/Features/Tasks/TaskCardView.swift
Paihuor/Features/Tasks/TaskDetailSheet.swift
```

## Cross-Platform Sync Checklist

For any change to task fields, status flow, archive/delete behavior, or relay API:

1. Update `docs/CONTRACT.md`.
2. Add a dated note to `docs/INTEROP.md`.
3. Update iOS DTO/model code:
   - `Paihuor/Models/PaihuorTask.swift`
   - `Paihuor/Services/TaskSyncService.swift`
   - `Paihuor/Services/TaskStore.swift`
4. Update Harmony model/store code:
   - `harmony/entry/src/main/ets/models/TaskModels.ets`
   - `harmony/entry/src/main/ets/services/TaskStore.ets`
   - `harmony/entry/src/main/ets/services/RelayService.ets`
5. Update `server/server.js`.
6. Smoke test:
   - server `node --check`
   - relay `/health`
   - create/update/delete tombstone path
   - Harmony build if ArkTS touched
   - iOS build in Xcode if Swift touched

## Recommended First Reads For A New Agent

Read in this order:

```text
README.md
CLAUDE.md
docs/CONTRACT.md
docs/INTEROP.md
docs/DEV_GUIDE_IOS.md
docs/DEV_GUIDE_HARMONY.md
server/server.js
Paihuor/Services/TaskSyncService.swift
harmony/entry/src/main/ets/services/RelayService.ets
```

Then inspect the specific feature files you plan to change.

## Git Hygiene

- Main GitHub repo: `C:\Users\Administrator\Documents\PaihuorRepo`
- Live relay repo: `ssh paihuor-175 "git -C /home/zx/paihuor-relay ..."`
- Ignore `.pushloop.log`.
- Keep commits scoped.
- Do not commit generated build outputs.
- If changing live server behavior, push GitHub and also leave the live relay repo clean.
