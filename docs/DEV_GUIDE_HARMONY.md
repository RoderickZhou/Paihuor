# 派活儿 鸿蒙端 开发 / 部署指南

鸿蒙端工程在仓库的 `harmony/` 目录（**不是仓库根目录**）。下面是在一台新电脑上从零拉代码、跑到华为 Pura70 真机的完整步骤。

## 0. 前置

- **DevEco Studio**（建议最新版，支持 HarmonyOS）+ HarmonyOS SDK **6.0.1(21)**
- 一个**华为账号**（用于自动签名 / 免费真机调试）
- **华为 Pura70**（HarmonyOS），已开「开发者模式 + USB 调试」
- 中继服务在 `10.1.30.175` 上常驻运行（systemd：`paihuor-relay` + `frpc@...`），无需在本机起任何后端

## 1. 拉代码并打开

```bash
git clone https://github.com/RoderickZhou/Paihuor.git
```

DevEco Studio → **Open**，选择 `Paihuor/harmony` 这个**子目录**（不要选仓库根目录，根目录是多端混合）。
等 DevEco 自动 `ohpm install`（或手动 `ohpm install`）拉依赖（`oh-package-lock.json5` 已入库，版本锁定）。

## 2. 创建本地私密配置 AppConfig.ets（必须，否则编译报错）

`entry/src/main/ets/config/AppConfig.ets` 含密钥，已被 `.gitignore` 排除，clone 下来**没有**，必须手动创建：

1. 复制同目录的 `AppConfig.example.ets` 为 `AppConfig.ets`；
2. 按模板填入真实值（MiniMax Key、中继地址、中继密钥、familyId 等）。

> 真实值不放仓库。问周翔要那份「AppConfig.ets 实配」直接整段粘贴即可。
> - `RELAY_BASE_URL`：当前公网中继地址（SakuraFrp 东京隧道，形如 `http://frp-xxx.com:端口`）。
> - `RELAY_LAN_URL`：`http://10.1.30.175:8787`（在家/同局域网时自动走它，秒同步）。

## 3. 配置签名（换电脑必做）

签名材料是上一台机器本地的（`C:\Users\...\.ohos\config\...`），**新机器没有**，仓库里的 `build-profile.json5` 的 `signingConfigs` 是空的。clone 后：

1. **File → Project Structure → Signing Configs**；
2. 勾选 **Automatically generate signature**，登录华为账号；
3. DevEco 会自动生成证书/profile 并回填 `build-profile.json5`。

## 4. 真机运行

1. USB 连上 Pura70，DevEco 右上角选到该设备；
2. 点 **Run**（▶）编译 + 安装 + 启动；
3. 首次启动按系统弹窗授予 **麦克风**（语音）、**通知**（提醒）权限。

> 若 Pura70 上已装过**别的电脑**签名的同包名版本，会因签名不一致装不上 —— 先在手机上卸载旧的「派活儿」再装。

## 5. 验证联通

- **在家（同 `10.1.30.x` 局域网）**：自动走 `RELAY_LAN_URL`，派活/收到/商量秒同步。
- **在外（流量）**：自动回退 `RELAY_BASE_URL`（SakuraFrp 东京隧道），单次请求约 0.85s（海外节点固有延迟，功能正常）。
- 中继健康检查：浏览器/curl 打 `<RELAY_BASE_URL>/health` 应返回 `{"ok":true}`。

## 6. 命令行构建（可选，不用 IDE 跑时）

```powershell
$env:DEVECO_SDK_HOME="C:\Program Files\Huawei\DevEco Studio\sdk"
cd <工程>\harmony
& "C:\Program Files\Huawei\DevEco Studio\tools\hvigor\bin\hvigorw.bat" assembleHap --no-daemon
```

产物：`entry/build/default/outputs/default/entry-default-signed.hap`（需先完成第 3 步签名）。
真机安装：`hdc install <hap路径>`（hdc 在 `...\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe`）。

## 已知约束 / 坑

- **MiniMax 必须用 `MiniMax-M3` + 请求体 `thinking:{type:"disabled"}`**：M2.7 系列强制思考、慢；M3 关思考后干净 JSON、省 token、更快。
- 鸿蒙 http 须声明 `ohos.permission.INTERNET`（已在 module.json5）。
- **后端是 175 自建 Node 中继，不是 LeanCloud**（与 `CONTRACT.md` 早期约定不同，详见 `INTEROP.md`）。
- SakuraFrp 国内节点封明文 HTTP（备案合规），故走海外（东京）节点；若隧道迁移节点 / SakuraFrp 改节点域名，`RELAY_BASE_URL` 要同步更新并重打包。
