# 派活儿 Android 兼容端开发说明

本目录用于 HarmonyOS 4.x 等仍基于 Android 兼容层的华为手机。HarmonyOS NEXT 使用 `harmony/` 工程，两者不能混装。

## 工程与配置

- 工程目录：`android/`
- 包名：`dev.zx.paihuor`
- 最低系统：Android 8（API 26）
- 当前测试设备：nova 12 活力版，HarmonyOS 4.2 / Android 12（API 31）
- 私密配置：复制 `android/app/src/main/assets/paihuor_config.example.json` 为 `paihuor_config.json` 后填写；真实文件已被 `.gitignore` 排除。

Android、iOS、HarmonyOS NEXT 共用 `docs/CONTRACT.md` 的任务模型和同一个中继，不需要增加隧道。

## 构建

```powershell
cd android
.\gradlew.bat testDebugUnitTest assembleDebug
```

APK 输出：

```text
android/app/build/outputs/apk/debug/app-debug.apk
```

构建会下载并校验 Vosk 的 `vosk-model-small-cn-0.22.zip`，将模型装进 APK。
已有官方模型文件时可传 `-PvoiceModelZip=<模型文件的绝对路径>`，构建仍会校验 SHA-256。

## 安装

```powershell
adb install -r android/app/build/outputs/apk/debug/app-debug.apk
```

华为 HarmonyOS 4.x 会在手机端要求确认“来源不明应用”，并可能要求输入当前华为账号密码。密码只在手机上输入。

若 APK 签名和手机现有版本不同，先备份 `paihuor_profile.xml`，再卸载旧版。卸载会清空本机缓存，但不会删除服务器任务。

## 功能

- 首次家庭配对，运行时选择老公/老婆
- 收集箱与归档同页切换
- 新建、编辑、删除、收到、完成、商量、归档
- 最多 9 张图片上传，详情页查看图片
- 新建任务长按录音，松手后本地转写中文，再用 MiniMax 整理成可编辑草稿。仅点发送才会投递任务；只发送文字给 MiniMax，录音不上传。
- 首次授予麦克风权限后需重新长按。MiniMax 不可用时将转写填到标题，供手动修改。
- 8 秒后台轮询、开机恢复、系统通知
- UI 尺寸和图标与 HarmonyOS NEXT 端保持一致
