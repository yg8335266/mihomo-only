# mihomo-only

Windows 便携 Mihomo 懒人包：示例配置 + 图形管理面板，内核自行从官方获取。

> 本项目参考自 [hubentuan/mihomo-lazy](https://github.com/hubentuan/mihomo-lazy)，并重构了启动与管理方式。
> 核心能力来自上游开源项目，详见文末「致谢」。

---

## 功能概览

- 图形管理面板（`MihomoManager.vbs`）
  - 启动 / 停止 / 重启
  - 系统代理开关
  - 开机自启开关
  - 更新配置（下载 → 本地校验 → 覆盖 → API 热重载）
  - 打开 Web 面板 / 打开目录
- 便携启动：`start-mihomo.vbs` 使用 `-d` 固定家目录到软件目录
- 示例配置：`config.example.yaml`
- 内置面板：`ui/zashboard`

---

## 目录结构

```text
.
├── MihomoManager.vbs      # 双击打开管理面板
├── MihomoManager.ps1      # 管理面板逻辑
├── start-mihomo.vbs       # 提权 + 便携目录启动
├── config.example.yaml    # 示例配置（复制为 config.yaml）
├── ui/zashboard/          # Web 控制面板
└── .gitignore
```

本地运行后还会生成（已忽略，不会上传）：

- `mihomo.exe`
- `config.yaml`
- `proxy_provider/`
- `rules/`
- `cache.db` / geo 数据等

---

## 快速开始

### 1. 准备内核

下载官方内核（本项目按 **windows-amd64-v3** 变体适配说明）：

- 上游发布页：<https://github.com/MetaCubeX/mihomo/releases>
- 示例包名：`mihomo-windows-amd64-v3-v1.19.29.zip`

解压后把 `mihomo.exe` 放到本目录（与 `MihomoManager.vbs` 同级）。

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

双击 `MihomoManager.vbs`。

建议流程：

1. 点 **首次安装**（启动 + 开系统代理），或先 **启动**
2. 点 **打开面板** 进入 Web UI
3. 需要时再设置 **开机自启**

> 首次启动可能弹出 UAC（管理员权限），TUN 模式通常需要。

---

## 管理面板说明

| 按钮 | 作用 |
|------|------|
| 启动 / 停止 / 重启 | 管理 `mihomo.exe` |
| 开启/关闭系统代理 | 修改当前用户系统代理 |
| 开启/关闭开机自启 | 写入/删除启动项快捷方式 |
| 更新配置 | 从设定 URL 下载配置，本地 `mihomo -t` 校验后覆盖，并尝试热重载 |
| 首次安装 | 启动服务并开启系统代理 |
| 打开面板 | 读取 `config.yaml` 中的 `external-controller` / `external-ui-name` 打开 |
| 打开目录 | 打开当前软件目录 |

说明：

- 控制面板地址只从 `config.yaml` 读取，不写死端口
- 面板页面（如 `/ui/zashboard/`）和 API（如 `/configs`）不是同一个地址
- 若 Mihomo 以管理员运行，停止/重启时可能再弹一次 UAC

---

## 更新配置（可选）

`MihomoManager.ps1` 顶部有：

```powershell
$GistUrl = '你的配置 raw 地址'
```

流程：

1. 下载到临时文件（防缓存）
2. 本地 `mihomo -t` 校验（不通过则不覆盖）
3. 备份旧 `config.yaml`
4. 写入新配置并回读确认
5. 优先 API 热重载；失败再提示重启

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

- **[Loyalsoldier/clash-rules](https://github.com/Loyalsoldier/clash-rules)**
  示例配置中的规则集来源之一。

### 说明

- 本项目主要改动：Windows 图形管理、便携目录启动（`-d`）、配置更新校验与热重载等。
- 内核版权与许可以 [MetaCubeX/mihomo](https://github.com/MetaCubeX/mihomo) 及其依赖为准。
- 若致谢有遗漏，欢迎补充。

---

## License

- 本仓库新增的管理脚本：可按你的发布需要自行声明许可（建议与上游兼容，例如 MIT）。
- Mihomo 内核、面板、规则集请遵守各自上游项目的开源许可证。

---

## 免责声明

本项目不提供任何代理服务，不包含商业节点。
使用第三方订阅与规则的风险由使用者自行承担，使用前请遵守当地法律法规。
