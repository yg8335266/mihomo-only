# mihomo-lazy（优化版）

Windows 便携 Mihomo 懒人包：**内核 + 示例配置 + 图形管理面板 + 可选 GitHub 自动同步内核**。

> 本项目由原 [mihomo-lazy](https://github.com/yg8335266/mihomo-lazy) 思路改进而来，并在本地重构了启动/管理方式。  
> **核心能力来自上游开源项目，详见文末「致谢」。**

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
- GitHub Actions：自动跟随官方内核上游（`windows-amd64-v3`）

---

## 目录结构

```text
.
├── MihomoManager.vbs      # 双击打开管理面板
├── MihomoManager.ps1      # 管理面板逻辑
├── start-mihomo.vbs       # 提权 + 便携目录启动
├── config.example.yaml    # 示例配置（复制为 config.yaml）
├── ui/zashboard/          # Web 控制面板
├── .github/workflows/     # 自动同步内核
└── .gitignore
```

本地运行后还会生成（已忽略，不要提交）：

- `mihomo.exe`
- `config.yaml`
- `proxy_provider/`
- `rules/`
- `cache.db` / geo 数据等

---

## 快速开始

### 1. 准备内核

下载官方内核（本仓库默认跟随 **windows-amd64-v3**）：

- 上游发布页：<https://github.com/MetaCubeX/mihomo/releases>
- 示例包名：`mihomo-windows-amd64-v3-v1.19.29.zip`

解压后把 `mihomo.exe` 放到本目录（与 `MihomoManager.vbs` 同级）。

### 2. 准备配置

```bat
copy config.example.yaml config.yaml
```

然后编辑 `config.yaml`，至少修改：

1. `secret`（面板密钥）
2. `proxy-providers` 里的订阅 URL
3. 如需：`mixed-port` / `external-controller`

### 3. 启动

双击：

```text
MihomoManager.vbs
```

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

- 控制面板地址 **只从 `config.yaml` 读取**，不写死端口
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

## GitHub 自动同步内核（仓库侧）

工作流：`.github/workflows/update-mihomo-core.yml`

- 定时检查 `MetaCubeX/mihomo` 最新 Release
- 匹配资源：`windows-amd64-v3`
- 在你自己的仓库创建 Release：`core-vX.Y.Z`，附件为 `mihomo.exe`

使用前请在仓库设置中开启：

**Settings → Actions → General → Workflow permissions → Read and write permissions**

也可在 Actions 页手动 **Run workflow**。

> 这是 GitHub 侧自动跟上游，不是管理面板里的按钮。

---

## 安全提醒

- **不要**把含真实订阅、token、`secret` 的 `config.yaml` 推到公开仓库
- 仓库只应保留 `config.example.yaml` 这类脱敏示例
- 建议 `allow-lan: false`，除非你明确需要局域网共享
- 面板密钥请使用强密码

---

## 常见问题

### 1. 双击管理面板没反应 / 杀软拦截
`MihomoManager.vbs` 会静默启动 PowerShell 显示 GUI。若火绒等拦截“隐藏 PowerShell”，请对本目录放行。

### 2. 停止/重启提示权限不足
Mihomo 可能以管理员运行。按 UAC 提示允许，或用管理员身份重试。

### 3. 改了端口，旧端口浏览器还能打开
多半是浏览器缓存。用无痕窗口验证；并确认已重启 Mihomo。

### 4. 用户目录又出现 `.config\mihomo`
请确认使用新的 `start-mihomo.vbs`（带 `-d` 便携目录参数）启动，并重启一次。

### 5. 只有脚本没有内核/配置
这是正常的干净仓库状态。按「快速开始」自行放置 `mihomo.exe` 并生成 `config.yaml`。

---

## 致谢（Credits）

本项目站在以下开源工作之上，谨致谢意：

### 核心与生态

- **[MetaCubeX/mihomo](https://github.com/MetaCubeX/mihomo)**  
  Mihomo（Clash Meta）内核。本项目的代理能力完全依赖该项目。

- **原 mihomo-lazy 项目思路与作者**  
  本仓库最初由 [yg8335266/mihomo-lazy](https://github.com/yg8335266/mihomo-lazy) 发展而来；该仓库曾作为上游懒人包的 fork/使用基础。  
  感谢原作者提供「便携懒人包」这一易用形态与配置组织思路。  
  > 若你知道更准确的原始上游仓库地址，欢迎补充到此处。

### 面板与规则

- **[Zashboard](https://github.com/Zephyruso/zashboard)**（及 MetaCubeX 面板生态相关项目）  
  本目录内置 `ui/zashboard` Web 面板。

- **[Loyalsoldier/clash-rules](https://github.com/Loyalsoldier/clash-rules)**  
  示例配置中的规则集来源之一。

### 说明

- 本优化版主要改动：Windows 图形管理、便携目录启动（`-d`）、配置更新校验与热重载、仓库侧内核同步工作流等。
- 内核版权与许可以 [MetaCubeX/mihomo](https://github.com/MetaCubeX/mihomo) 及其依赖为准。
- 若本 README 致谢有遗漏，请提交 issue/PR，我们会尽快补全。

---

## License

- 本仓库新增的管理脚本与工作流：可按你的发布需要自行声明许可（建议与上游兼容，例如 MIT）。
- **Mihomo 内核、面板、规则集** 请遵守各自上游项目的开源许可证。
- 使用前请阅读并遵守当地法律法规与服务条款；本项目仅供学习与个人网络调试参考。

---

## 免责声明

本项目不提供任何代理服务，不包含商业节点。  
使用第三方订阅与规则的风险由使用者自行承担。
