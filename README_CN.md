# KnowType / 知键

[![CI](https://github.com/zzqDeco/KnowType/actions/workflows/ci.yml/badge.svg?branch=dev)](https://github.com/zzqDeco/KnowType/actions/workflows/ci.yml)

[English](README.md)

KnowType 是一款面向 macOS 的中英文输入法，使用 Swift 编写。它的 AI
能力围绕一个严格规则展开：纠错可以优化正在输入的前缀，但延续不能改写
已经锁定的前缀。

| 项目 | 当前状态 |
|---|---|
| 语言 | Swift 6.2 |
| 平台 | macOS 13+ |
| 核心包 | Swift Package Manager |
| 输入法宿主 | AppKit + InputMethodKit |
| 设置 UI | SwiftUI |
| 集成分支 | `dev` |

## 为什么做 KnowType

KnowType 把“把我打错的内容变准确”和“顺着我确认的内容继续写”分开处理。

```text
原始输入 -> 纠错 -> 锁定前缀 -> 延续 -> 上屏
```

例子：

```text
原始输入：       wo jue de zhege fagnan
锁定前缀：       我觉得这个方案
延续候选：       还有进一步优化空间
Tab 上屏：       我觉得这个方案还有进一步优化空间
```

这里 AI 延续只负责 `还有进一步优化空间`。它不能把已经锁定的前缀改写成
另一句话，除非用户显式触发 polish。

## 功能

- 中文输入优先：生产 IMK 热路径使用内置 `librime` 负责同步拼音转换、
  Space 上屏、数字选词和翻页。
- 本地候选学习：最近选择过的前缀会在输入法重启后继续影响本地排序，
  不发送给 provider。
- 前缀锁定的 AI 推荐：第一候选固定为 Rime 转换，第二候选固定为 AI 推荐；
  显式 polish 才是改写路径。
- macOS 输入法流程：marked text、候选选择、翻页、标点处理，以及紧凑、
  原生风格并能覆盖 Spotlight/search 浮层的 AppKit 候选窗。
- 多 provider 兼容：OpenAI-compatible chat、OpenAI Responses、
  Anthropic Messages、Gemini native、Ollama native 和 custom HTTP 都归一化到
  同一套 provider 接口。
- 隐私保护：纠错会保护 URL、邮箱、路径、命令、代码片段和受保护 app
  场景不被改写；实时 AI 只在 raw input 或已确认前缀疑似 secret 时硬禁用。
- 本地词库：内置 seed 词库、用户自有 JSON/TSV 词库，以及托管安装
  Rime 简体拼音词库的路径。

## 当前状态

KnowType 目前是用于本地开发和手动验收的 MVP。它包含 Swift package、单元测试、
本地 InputMethodKit app bundle、SwiftUI 设置宿主、provider profile 存储、
Keychain-backed API key 和本地词库工具。

它还不是签名安装器、公证发行包、自动更新程序或 App Store 应用。

GitHub Releases 可以提供名为 `KnowType-vX.Y.Z-macos-local-mvp.zip` 的本地
MVP zip。这个压缩包包含 ad-hoc 签名的 `KnowType.app` 输入法 bundle 和
`KnowType.prefPane`，并附带 SHA256 文件和 release manifest。它仍然只是本地
MVP 打包，不是公证安装器。

## 快速开始

要求：

- macOS 13 或更新版本
- Swift 6.2 工具链

构建和测试：

```bash
swift build
swift test
```

不安装输入法，先跑 package-level 流程：

```bash
swift run knowtype-demo --locale zh-CN --action tab wo jue de zhege fagnan
swift run knowtype-demo --locale mixed --action tab zhege api latnecy youdian gao
swift run knowtype-demo --locale en-US --action tab I thikn this approch
```

## 安装本地输入法

构建并安装本地开发 bundle：

```bash
./scripts/build-inputmethod-bundle.sh --configuration release
./scripts/install-inputmethod.sh
./scripts/diagnose-inputmethod.sh
```

本地安装脚本会刷新传统 InputMethodKit app 注册，清理过期的 `.Mode`
开发状态，补齐系统设置需要的第三方 parent anchor 和可见 `.Hans` mode，并启动已安装的
app，让注册和 best-effort 选择从 macOS 输入法切换使用的 app 上下文中执行。KnowType 采用
Squirrel、McBopomofo、macSKK 这类成熟 IMK 的 component mode 形态：parent id 是
`com.knowtype.inputmethod.KnowType`，系统可见输入源是
`com.knowtype.inputmethod.KnowType.Hans`。

`scripts/install-inputmethod.sh` 默认使用 release 构建，方便本地打字测试覆盖优化后的热路径。
Rime runtime 文件会打包在 `KnowType.app` 中；如果文件缺失或加载失败，KnowType 会保留
raw 输入可用并报告 degraded conversion state，而不是回退到已经退役的自研转换器。

覆盖安装会先在 `~/Library/Application Support/KnowType/Backups/` 创建 app 级回滚备份，
并把当前安装来源、版本、build、commit/tag 和备份 id 写入
`~/Library/Application Support/KnowType/install-state.json`。备份只包含安装产物：
`KnowType.app` 和可选 `KnowType.prefPane`；不会复制或回滚 Rime userdb、provider 配置、
Keychain secret、AI 上下文文档或本地词库。

KnowType 的专属设置入口对齐 McBopomofo、OpenVanilla 这类原生 IMK 输入法：先在
macOS 输入法菜单中选中 KnowType，然后点击 `KnowType Settings...`。它会打开
macOS 原生 sidebar 和 grouped settings 页面；中文 macOS locale 下使用简体中文文案，
非中文 locale 使用英文 fallback 文案。本地安装默认不安装独立 Settings app。默认安装会移除
本机过期的兼容 `KnowType.prefPane`，避免它和新安装的输入法版本不一致；需要匹配版本的兼容 pane 时，再执行
`./scripts/install-inputmethod.sh --with-prefpane` 构建并安装。
如果默认安装后系统设置侧边栏仍显示 `KnowType`，那是 macOS PreferencePane 缓存残留；
重新运行安装脚本或 `./scripts/uninstall-inputmethod.sh` 刷新缓存，然后重新打开系统设置。

首次安装或 mode id 迁移后，macOS 仍可能要求通过系统设置完成第三方输入源授权。
打开“系统设置 > 键盘 > 输入源”，移除过期的 KnowType/知键条目，重新添加
`知键` / `KnowType`，如果系统弹出允许提示则点击允许。如果菜单仍显示旧条目，注销再登录以清理
Text Input Source 缓存。这个边界与成熟 IMK 输入法一致：安装流程使用 TIS 注册和启用，
受保护的第三方输入源授权行由系统设置写入。

需要时，在当前目标 app 上选择 KnowType：

```bash
./scripts/select-inputmethod.sh --require-selected
```

移除本地 bundle：

```bash
./scripts/uninstall-inputmethod.sh
```

列出或恢复本地回滚点：

```bash
./scripts/rollback-inputmethod.sh --list
./scripts/rollback-inputmethod.sh --latest
```

本地 IME 行为仍需要在真实 host app 中打字验证。macOS policy、输入源选择和
手动验收流程见 [Local Input Method Testing](doc/local-inputmethod-testing.plan.md)
和 [MVP Acceptance](doc/mvp-acceptance.plan.md)。

使用 GitHub Release zip 时，先用发布页提供的 `.sha256` 文件校验下载的 zip。
然后通过本地脚本安装，这样 release metadata、备份和诊断状态会被记录：

```bash
./scripts/install-inputmethod.sh --from-release-zip ~/Downloads/KnowType-v0.2.0-macos-local-mvp.zip
```

只有需要兼容 System Settings pane 时才额外传 `--with-prefpane`。除非已安装匹配版本的 pane，
否则不要使用系统设置侧边栏里残留的 KnowType 入口。

## 配置

Provider profile 以 JSON 元数据保存，API key 单独保存。

```text
~/Library/Application Support/KnowType/providers.json
```

本地候选学习历史：

```text
~/Library/Application Support/KnowType/user-selection-history.json
```

本地 JSON/TSV 词库目录：

```text
~/Library/Application Support/KnowType/Lexicons
```

开发时可以用 `KNOWTYPE_LEXICON_DIR` 和冒号分隔的
`KNOWTYPE_LEXICON_DIRS` 在默认目录前追加词库目录。

安装推荐托管词库：

```bash
scripts/install-lexicon-pack.sh rime-pinyin-simp
```

安装器会下载固定版本的 Apache-2.0 Rime 词库，校验 SHA256，转换成
KnowType TSV，并在 TSV 旁写入本地 metadata。第三方大词库数据不会提交到本仓库。

当 `providers.json` 不存在或为空时，KnowType 会使用本地 OpenAI-compatible
默认 profile：`http://127.0.0.1:8317/v1`，不内置 API key。远程
OpenAI-compatible profile 必须显式填写 model ID；本地 OpenAI-compatible
profile 可以留空 model，并通过 `/v1/models` 发现。

AI 上下文文件位于 `~/.knowtype/`。`ENV.md` 保存 AI 推荐槽使用的本地上下文
记忆，`CORRECTION.md` 保存用户可编辑的 AI 纠错说明，`LEXICAL_PROFILE.md`
是由 Rime userdb 词频、KnowType 近期提交和选择历史合成的本地 top-K 词汇画像镜像。
Canonical JSON 存在 `~/Library/Application Support/KnowType/AI/`。传统输入引擎不依赖
这些文件。
实时 AI 推荐使用任务专属的后缀生成 prompt，runtime 超时为 10 秒；可用时
优先使用 provider 级结构化 JSON Schema 输出，并通过 macOS unified logging
输出不含原文的子状态诊断。Rime 正在 composition 时，当前页候选不会发送给
实时 AI 请求；未选择的候选不会被当成 locked prefix。还没有 locked prefix 时，
AI 会基于 raw input、上下文文档和持久 `LEXICAL_PROFILE.md` 返回可直接上屏的
完整推荐，而不是拼到第一候选后的后缀。
日志可以区分 schema 降级、结构化解析失败、prefix-lock sanitizer 拒绝、
prefix 太短等原因。查看命令：
`log stream --predicate 'subsystem == "com.knowtype.inputmethod.KnowType" && category == "ai"' --style compact`。

## 输入行为

| 快捷键 | 行为 |
|---|---|
| `Space` | composition 活跃时提交 Rime 当前高亮候选；没有 active composition 时插入普通空格。 |
| `1...9` | 原生 Rime composition 活跃时选择当前页候选，即使自绘候选窗暂时隐藏；没有 active composition 时插入普通数字。 |
| 方向键、`PageUp` / `PageDown`、`-` / `=`、`,` / `.` | 在当前 Rime 页内移动选择；到候选列表边界且还有上一页或下一页时翻页；不能翻页时回退到普通标点提交路径。第一页首项按左/上会到上一页最后一项。 |
| `Return` / `Enter` | 提交原始 composition。 |
| `Tab` | 第二候选位的 AI 推荐 ready 时提交 AI 推荐；pending 或 unavailable 时保持 composition。 |
| `0` | 有纠错候选可见时提交原始 composition；没有 active composition 时插入 `0`。 |
| 普通标点 | composition 活跃时先交给 Rime schema 处理；Rime 不处理时再提交 composition 加标点，或在没有 composition 时直接插入标点。 |
| `Option + .` | 切换当前输入会话的中文/英文标点。 |
| `Option + 1` | 显式提交 ready AI 推荐。 |
| `Option + 2...9` | legacy continuation 行存在时提交对应延续。 |
| `Option + R` | 请求显式 polish，也是默认交互中的改写路径。 |

候选窗显示 Rime 前缀候选、固定 AI 推荐状态行，以及没有建议时的 raw input。它是
紧凑的 AppKit 自绘 panel，使用 macOS 材质、系统高亮色、鼠标 hover/click
选择、滚轮翻页和候选行 Accessibility label。配置 provider 后，KnowType 会
先发布 Rime 前缀候选，再异步更新 provider-backed AI 推荐。Provider 失败时，不会
把固定本地 fallback 文本伪装成 AI 输出。

候选窗第一项固定为 Rime 转换推荐，第二项固定为 AI 推荐状态。Provider 返回后
只更新第二项，不重排 Rime 候选列表。Ready AI 使用 Tab 或显式 Option+数字，不占用
普通数字选词。Pending、unavailable 或 ineligible AI 状态会显示为更弱的状态行，
没有数字快捷键，也不会响应点击提交。

## 隐私

Level 0 纠错保护用于避免把本应原样提交的文本改写，例如 URL、路径、命令、
代码片段和受保护 app 场景。

纠错保护输入包括：

- URL 和 `www.` 地址
- 邮箱格式输入
- 绝对路径、`~/` 路径和相对路径
- `swift test`、`git status` 等命令类输入
- 包含大括号、分号或 `=>` 的代码片段
- 通过 bundle identifier 识别的 Terminal、iTerm 和 Xcode 会话

实时 AI 推荐使用更窄的云端隐私门禁：只有 raw input 或已确认前缀疑似包含
API key、Bearer token、JWT、私钥、password/token 赋值等 credential 时才显示
`AI 已禁用`。

`API`、`JSON`、`FastAPI`、`iOS`、`macOS`、`InputMethodKit`、
`snake_case`、`camelCase` 等技术 token 会被保留或规范化。

## 文档

- [文档入口](doc/README.md)
- [架构](doc/architecture.plan.md)
- [接口](doc/interfaces.plan.md)
- [MVP 验收](doc/mvp-acceptance.plan.md)
- [源码说明](doc/src/README.md)
- [实施计划](plan/README.md)

## 开发

仓库结构：

```text
Sources/KnowTypeCore/           产品模型、保护规则、纠错、延续
Sources/KnowTypeProviders/      Provider profile、运行时加载、adapter
Sources/KnowTypeAI/             AI 推荐、上下文记忆、纠错说明
Sources/KnowTypeInputMethod/    IMK controller、会话动作、候选窗
Sources/KnowTypeInputMethodApp/ 本地 macOS 输入法 app 入口
Sources/KnowTypeSettingsUI/     共享 SwiftUI 设置 UI
Sources/KnowTypeSettingsApp/    开发预览设置 app 宿主
Sources/KnowTypePreferencePane/ 兼容 PreferencePane 宿主
Tests/                          单元测试
doc/                            当前工程文档
plan/                           当前和近期交付的实施计划
Resources/                      macOS bundle 资源
```

分支流程：

- `main`：稳定分支
- `dev`：集成分支
- 主题分支：`feature/<desc>`、`fix/<desc>`、`docs/<desc>`、
  `refactor/<desc>`、`test/<desc>`、`release/<version>`

使用 Conventional Commits，主题 PR 先合入 `dev`。代码变更运行
`swift test`；输入法热路径变更还要运行 `./scripts/perf-input-hotpath.sh`。
文档-only 变更至少运行 `git diff --check`，并同步 `doc/` 和 `plan/` 的索引。

## Roadmap / Non-Goals

当前 non-goals：

- 签名安装器、公证发行包、自动更新或 App Store 分发
- 不依赖授权本地词库就宣称完整真实世界拼音覆盖
- 对所有 macOS host app 做通用兼容性承诺
- 把本地 fallback 延续伪装成配置 provider 的输出
- 除显式 polish 外改写锁定前缀

## License

License not declared yet.
