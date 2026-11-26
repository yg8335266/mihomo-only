# mihomo-only

Windows 便携 Mihomo 懒人包：示例配置 + 原生桌面管理端（内置 Zashboard 面板），内核自行从官方获取。

> 本项目参考自 [hubentuan/mihomo-lazy](https://github.com/hubentuan/mihomo-lazy)，并重构为单文件原生桌面端与便携管理方式。  
> 核心能力来自上游开源项目，详见文末「致谢」。

---

## 功能概览

- **原生桌面管理端（`MihomoManager.exe`）**
  - 纯 C# WinForms 原生编译（不依赖 PowerShell），Forest 深色主题，默认最大化打开
  - **基础管理**：核心启动 / 停止 / 重启、系统代理一键开关（自动通知 WinINet 实时刷新）、开机自启开关
  - **内置 Zashboard 面板**：基于系统 WebView2 内嵌显示，无需跳转外部浏览器；窗口最小化/切回管理页超过 5 分钟自动休眠释放 WebView2 内存，再次打开自动唤醒
  - **系统托盘驻留**：关闭窗口最小化到托盘，右键可快捷启停核心、开关系统代理或彻底退出
  - **在线更新配置**：弹窗输入配置 raw 地址（本地记忆至 `update_url.txt`）→ 下载 → `mihomo -t` 本地校验 → 自动备份（最多保留 5 份）→ 覆盖 → API 热重载
- **便携运行**：通过 `-d` 将配置、节点、规则与缓存固定在软件目录；WebView2 数据统一存放在 `manager-data/`
- **示例配置**：`config.example.yaml`（`.mrs` 域名/IP 分离 + `direct-nameserver` 分流）
- **内置面板资源**：`ui/zashboard/`

---

## 目录结构

```text
.
├── MihomoManager.exe      # 原生管理端（双击打开界面；带 /start 参数静默启动核心）
├── config.example.yaml    # 示例配置（复制为 config.yaml）
├── ui/zashboard/          # Web 控制面板静态资源
└── .gitignore
```

本地运行后还会生成或存放（已忽略，不会上传）：

- `mihomo.exe` 或 `mihomo-*.exe`（如 `mihomo-windows-amd64-v3.exe`）
- `config.yaml` / `config-*.yaml.bak`
- `proxy_provider/`
- `rule_set/`
- `manager-data/`（WebView2 运行依赖与内置面板缓存）
- `cache.db`
- `update_url.txt`

---

## 快速开始

### 1. 准备内核

下载官方内核（现代 x64 CPU 推荐 **windows-amd64-v3** 变体，Windows 10/11 选不带 `goXXX` 的标准版）：

- 上游发布页：<https://github.com/MetaCubeX/mihomo/releases>
- 示例包名：`mihomo-windows-amd64-v3-v1.19.34.zip`

解压后将 `.exe` 放到本目录（与 `MihomoManager.exe` 同级）即可。  
支持直接保留原文件名（如 `mihomo-windows-amd64-v3.exe`），程序会优先查找 `mihomo.exe`，若不存在则自动选用最新的 `mihomo-*.exe`。

> 本仓库不内置、不分发 mihomo 内核，请从官方 Releases 下载。

### 2. 准备配置

```bat
copy config.example.yaml config.yaml
```

然后编辑 `config.yaml`，至少修改：

1. `secret`（面板密钥）
2. `proxy-providers` 里的订阅 URL
3. 如需：`mixed-port` / `external-controller`

### 3. 启动

双击 `MihomoManager.exe`。

建议流程：

1. 点 **首次安装**（自动检查文件、启动核心并开启系统代理），或先点 **▶ 启动核心**
2. 切换到顶部 **Zashboard 面板** 标签页（或点 **打开面板**）即可直接在客户端内管理节点
3. 需要时可点击 **开启开机自启**（将创建指向 `MihomoManager.exe /start` 的开机静默启动项）

> 首次启动核心可能弹出 UAC（管理员权限），TUN 模式通常需要。

---

## 管理面板说明

| 按钮 / 区域 | 作用 |
|-------------|------|
| 基础管理 / Zashboard 面板 | 在基础管理与内置 WebUI 之间切换（未看面板 5 分钟自动休眠释放内存） |
| ▶ 启动核心 / ■ 停止核心 / ↻ 重启核心 | 管理当前目录下的 `mihomo.exe` / `mihomo-*.exe` |
| 开启 / 关闭系统代理 | 修改当前用户系统代理，并通知浏览器立即生效 |
| 开启 / 关闭开机自启 | 写入/删除指向 `MihomoManager.exe /start` 的启动项快捷方式 |
| 更新配置 | 弹窗输入 URL 下载配置，本地 `mihomo -t` 校验通过后覆盖，并尝试 API 热重载 |
| 首次安装 | 一键执行文件检查、启动核心并开启系统代理 |
| 打开面板 / 打开目录 | 切换至内置 Zashboard 面板 / 打开当前软件目录 |

说明：

- 控制面板地址只从 `config.yaml` 读取，不写死端口
- 面板页面（如 `/ui/zashboard/`）和 API（如 `/configs`）共用 `external-controller` 地址
- 若 Mihomo 以管理员权限运行，在普通权限下停止/重启时会自动提权并可能再弹一次 UAC

---

## 更新配置（可选）

点击 **更新配置** 后在弹窗中输入配置文件的 raw 地址（支持 GitHub Gist 等 `http/https` 链接），程序会自动记忆到同级 `update_url.txt` 中。

更新流程：

1. 下载到临时文件（带时间戳防缓存）
2. 本地 `mihomo -t` 校验（不通过则绝不覆盖）
3. 自动备份当前 `config.yaml`（仅保留最近 5 份 `.bak`）
4. 写入新配置并回读 SHA256 确认
5. 优先通过 API 热重载；若失败则询问是否重启核心

---

## 致谢（Credits）

本项目站在以下开源工作之上，谨致谢意：

### 核心与生态

- **[MetaCubeX/mihomo](https://github.com/MetaCubeX/mihomo)**  
  Mihomo（Clash Meta）内核。本项目的代理能力完全依赖该项目。

- **[hubentuan/mihomo-lazy](https://github.com/hubentuan/mihomo-lazy)**  
  本项目参考自该仓库的「便携懒人包」形态与配置组织思路，感谢原作者提供的易用组织方式。

### 面板与规则

- **[Zephyruso/zashboard](https://github.com/Zephyruso/zashboard)**  
  本目录内置 `ui/zashboard` Web 控制面板。

- **[MetaCubeX/meta-rules-dat](https://github.com/MetaCubeX/meta-rules-dat)** & **[blackmatrix7/ios_rule_script](https://github.com/blackmatrix7/ios_rule_script)**  
  示例配置中的 `.mrs` 与补充规则集来源。

### 说明

- 本项目主要改动：纯 C# 原生桌面管理端、内置 WebView2 Zashboard 面板与空闲休眠、便携目录启动（`-d`）、动态内核识别（`mihomo-*.exe`）、配置更新校验与热重载等。
- 内核版权与许可以 [MetaCubeX/mihomo](https://github.com/MetaCubeX/mihomo) 及其依赖为准。
- 若致谢有遗漏，欢迎补充。

---

## License

- 本仓库新增的管理端与示例配置：可按你的发布需要自行声明许可（建议与上游兼容，例如 MIT）。
- Mihomo 内核、面板、规则集请遵守各自上游项目的开源许可证。

---

## 免责声明

本项目不提供任何代理服务，不包含商业节点。  
使用第三方订阅与规则的风险由使用者自行承担，使用前请遵守当地法律法规。
