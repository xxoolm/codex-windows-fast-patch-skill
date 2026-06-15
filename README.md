# Codex Windows Fast Patch Skill

语言：中文 | [English](README.en.md)

这是 `codex-windows-fast-patch` skill 的公开版本，用于指导支持 Agent Skills 的智能体在 Windows 上修复 Codex Desktop 升级后失效的本地补丁、能力开关和运行时问题。

## 主要功能

- 在 Codex Desktop 升级后重新应用 Windows MSIX 补丁。
- 修复 Fast Mode 请求路径和设置页 UI 路径，并验证请求是否真的带上 `service_tier=priority`。
- 保持 locale/i18n 可用，避免重启后语言设置被包内门控重置。
- 注册和修复本地插件市场配置。
- 修复本地插件市场清单目录结构。
- 解开 in-app browser、browser pane 和外部 Chrome/browser_use 的本地 feature / Statsig 门控。
- 修复 Windows Computer Use 本地插件、运行时兼容文件和 helper 路径。
- 解开 Computer Control 页面里 `Any App` / `任意应用` 被组织或地区门控禁用的问题。
- 修复 Windows 手机远控设置路径，包括连接页显示、二维码配对、隔离远控授权和 native app-server WebSocket 连接，同时保留第三方/API-key 主应用使用方式。
- 在用户明确要求时，可选安装随 skill 分发的自定义 `model_instructions_file` 提示词配置。
- 在覆盖 `config.toml` 前自动生成时间戳备份，降低配置误写风险。
- 每次正式使用前尝试从 GitHub 同步最新版本；网络不可用时不会阻断本地修复。

## 平台支持

当前只支持 Windows。

这个 skill 依赖 Windows Store / MSIX 包结构、PowerShell、`Get-AppxPackage`、`makeappx.exe`、`signtool.exe`、Windows 用户环境变量，以及 Windows Computer Use helper 路径。

不要在 macOS 上直接运行。macOS 需要单独的实现流程，例如处理 Codex `.app` 包、ASAR 解包和重打包、`codesign` 或 quarantine、shell 脚本，以及 macOS 自己的 Computer Use 可用性门控。

## 文件说明

- `SKILL.md`：Agent skill 主说明。
- `agents/openai.yaml`：Agent UI 元数据。
- `scripts/repatch-codex-windows.ps1`：主工作流参考脚本。
- `scripts/patch_codex_fast_mode_windows_msix.ps1`：Fast Mode、插件、浏览器、Computer Use 等 MSIX / ASAR 补丁参考实现。
- `scripts/patch-remote-control-windows-msix.ps1`：手机远控 MSIX / ASAR 补丁和 marker 校验参考实现。
- `scripts/patch-remote-control-asar.cjs`：手机远控 Electron bundle patcher。
- `scripts/install-computer-use-local.ps1`：Windows Computer Use 本地兼容文件安装和校验参考实现。
- `scripts/install-model-instructions-file.ps1`：可选安装内置 `model_instructions_file` 提示词资源。
- `scripts/manage-codex-backups.ps1`：本地 Codex 配置、MCP、skills 和 marketplaces 的备份管理脚本。
- `scripts/update-skill-from-github.ps1`：使用前尽力同步 GitHub 最新版本的自更新脚本。
- `assets/system-prompt.md`：仅在用户明确要求可选提示词配置时使用的内置提示词资源。
- `references/restriction-debug-cases.md`：限制解除、Chrome/browser_use、Computer Use 和 CPA Fast Mode 的按需诊断案例。
- `references/remote-control-debug-cases.md`：手机远控配对、隔离授权、native app-server 网络、版本过期状态和配对后 API 地址诊断案例。

## 安装

先克隆仓库，然后在仓库根目录打开 PowerShell，只复制 skill 需要的文件：

```powershell
$source = (Get-Location).ProviderPath
if (-not (Test-Path -LiteralPath (Join-Path $source 'SKILL.md'))) {
  throw '请在 codex-windows-fast-patch-skill 仓库根目录运行此命令。'
}

$dest = Join-Path $env:USERPROFILE '.codex\skills\codex-windows-fast-patch'
New-Item -ItemType Directory -Force -Path $dest | Out-Null

Copy-Item -Force -LiteralPath (Join-Path $source 'SKILL.md') -Destination $dest
Copy-Item -Recurse -Force -LiteralPath (Join-Path $source 'agents') -Destination $dest
Copy-Item -Recurse -Force -LiteralPath (Join-Path $source 'scripts') -Destination $dest
Copy-Item -Recurse -Force -LiteralPath (Join-Path $source 'references') -Destination $dest
Copy-Item -Recurse -Force -LiteralPath (Join-Path $source 'assets') -Destination $dest
```

安装到 Codex 后，重启 Codex，让它重新加载 skill 元数据。

## 使用

安装后，让支持 Agent Skills 的智能体使用 `codex-windows-fast-patch` 工作流处理当前机器上的 Codex Desktop 问题。

这个 skill 支持自更新：智能体每次正式使用前会先尝试从 GitHub 检查并同步最新版本。网络不可用、GitHub 访问失败或下载失败时，更新步骤会被跳过，智能体应继续使用当前本地版本处理问题。

这些脚本是参考实现和操作模板，不是跨所有机器都能直接运行的一键方案。实际处理时应先读取 `SKILL.md`，检查当前机器的 Codex 安装方式、MSIX 包路径、ASAR 内容、签名工具、插件目录、Computer Use 文件状态和远控相关日志，再决定执行、改写或只借鉴其中步骤。

## 使用建议

- Computer Use 提示插件不可用、`missing-helper-path`、重启后又失效，或 Chrome/browser helper 路径、缓存、native-host 坏了：可以让当前 Codex Desktop 会话用这个 skill 修。使用 `scripts/install-computer-use-local.ps1` 或 `scripts/install-computer-use-local.ps1 -VerifyOnly`，修完重启 Codex。
- 插件市场配置坏了、`codex plugin list` 因 marketplace manifest 报错、本地 marketplace 缺 `.agents\plugins\marketplace.json`：可以使用 `scripts/repatch-codex-windows.ps1 -RegisterMarketplaceOnly` 或本地 marketplace 修复流程。
- 用户明确要求安装随 skill 分发的自定义提示词配置：使用 `scripts/install-model-instructions-file.ps1`，然后重启 Codex CLI/Desktop 或开启新会话。
- 手机远控被隐藏、二维码一直转圈、跳 ChatGPT 登录、点允许后失败、手机提示 Codex 环境版本过期：使用 `references/remote-control-debug-cases.md` 和显式手机远控脚本。这是 opt-in 工作流，不属于默认 Fast Mode repatch。
- 手机远控配对成功后，如果手机创建的对话请求到了错误的模型 API 地址：按 `references/remote-control-debug-cases.md` 作为配对后配置案例处理，先查实际请求 URL 和当前配置，再依据证据修改。
- Fast Mode 看不到或请求不带 `service_tier=priority`、插件入口/安装按钮灰、Computer Control 的 `Any App` 灰、Browser/Chrome/browser_use 灰、语言重启回英文、Goal 入口消失：这些通常需要修改 Codex Desktop MSIX/ASAR。建议让外部 PowerShell 或另一个 agent 跑完整 repatch，避免当前 Desktop 停止/重装自己导致会话中断。

一个典型请求是：

```text
使用 codex-windows-fast-patch 这个 skill，检查并修复这台 Windows 机器上的 Codex Desktop Fast Mode、语言/locale、Chrome browser_use、插件市场和 Computer Use 可用性问题。
```

手机远控请求示例：

```text
使用 codex-windows-fast-patch 这个 skill，修复 Windows Codex Desktop 手机远控，同时保留我的第三方 API 主使用方式和现有会话记录。
```

## 预期验证

- 补丁日志包含 `fast-mode UI patch result`、`locale i18n patch result` 和 `browser-use gate patch result`，结果为 `patched` 或 `already-patched`。
- Fast Mode 线缆验证能在 Codex Desktop 的 `/v1/responses` 请求里捕获 `service_tier=priority`。
- 如果本次修复包含浏览器能力，Desktop 日志里 `browser_use_availability_resolved` 显示 `available=true` 和 `reason=local-patched`。
- 如果需要 Chrome 控制，`codex plugin list` 显示 `chrome@openai-bundled` 为 `installed, enabled`，native messaging host manifest 指向存在的文件，并且真实 smoke test 能读到受控标签页标题，例如 `Example Domain`。
- 如果修复手机远控，连接页应显示手机/移动设备设置路径，二维码应出现，手机扫码不再提示 Codex 版本过期，native 日志应看到 remote-control WebSocket ping/pong/ack，手机发送消息能到达 Desktop。

## 备份管理

修复脚本在写入 `config.toml` 前会自动把旧文件备份到 `.codex\backups\config\`。如果要手动备份或迁移本地 Codex 的关键状态，可以使用独立备份脚本：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.codex\skills\codex-windows-fast-patch\scripts\manage-codex-backups.ps1" -Action Backup
```

列出现有备份：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.codex\skills\codex-windows-fast-patch\scripts\manage-codex-backups.ps1" -Action List
```

从某个备份恢复：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.codex\skills\codex-windows-fast-patch\scripts\manage-codex-backups.ps1" -Action Restore -BackupPath "<backup path>"
```

默认备份自定义 skills、marketplaces、`config.toml`、解析出的 `mcp_servers.json` 和 `chrome-native-hosts.json`，并排除 `.git`、`node_modules`、构建产物和虚拟环境等容易变大的目录。需要完整离线依赖副本时再加 `-IncludeDependencyDirs`；插件缓存和 `.tmp\bundled-marketplaces` 也可能较大，需要时再加 `-IncludePluginCache` 或 `-IncludeTmpBundledMarketplaces`。

## CPA 上游配置

如果 Codex 请求的上游是 CPA，仅在本地把请求改成 `service_tier=priority` 还不够。还需要在 CPA 的覆盖规则中，对承接 Codex 的模型强制覆盖参数：`service_tier`、类型为字符串、值为 `priority`，这样上游才会真正按 Fast / Priority 路径处理。

图中的模型名只是示例，实际应按 CPA 中当前承接 Codex 的模型填写。

![CPA 覆盖规则示例](assets/cpa-override-rule.svg)

## 致谢

感谢 [LinuxDo community](https://linux.do/) 中相关讨论和反馈对这个工作流的启发。
