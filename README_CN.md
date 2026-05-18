# KnowType / 知键

[English](README.md)

KnowType 是一款面向 macOS 的中英文输入法。它的 AI 能力围绕一个很明确的产品规则展开：可以先纠正用户正在输入的内容，但默认不能改写用户已经确认的前缀。

更直白地说，KnowType 先让前半句更准，再让后半句更顺。它会把不完整或带错误的拼音、中英混输、英文拼写先解析成一个锁定前缀，然后只在这个前缀后面给出延续。

一句话定位：

```text
先懂你打错了什么，再顺着你已经写下的内容继续写。
```

## 它做什么

- **先做好中文输入**：支持拼音解码、连续拼音切分、轻量错拼纠正、同音候选、`sm`/`zmb`/`wsm` 这类常用声母缩写和尾部半音节输入。
- **本地候选学习**：最近选择过的前缀候选会在输入法重启后继续影响排序，不发送给 provider。
- **前缀锁定的 AI 延续**：AI 只补前缀后面的内容；只有用户主动润色时，才允许改写已输入文本。
- **macOS 原生输入流程**：使用 marked text、候选选择、翻页、标点处理和跟随文本光标的自适应 AppKit 候选窗。
- **多协议 provider 兼容**：OpenAI-compatible chat、OpenAI Responses、Anthropic Messages、Gemini native、Ollama native 和 custom HTTP 都归一化到同一层接口。
- **本地隐私保护**：URL、邮箱、路径、命令、代码片段和受保护 app 场景走无 provider 路径。

## 产品规则

KnowType 的默认链路是：

```text
用户原始输入 -> 输入纠错 -> 锁定前缀 -> 后续延续 -> 上屏
```

例子：

```text
原始输入：       wo jue de zhege fagnan
锁定前缀：       我觉得这个方案
AI 延续：        还有进一步优化空间
Tab 上屏：       我觉得这个方案还有进一步优化空间
```

这里 AI 候选只是 `还有进一步优化空间`。它不能把前缀擅自改成 `我认为当前方案...`。只有用户主动触发润色，才进入改写路径。

## 当前 MVP 范围

KnowType 当前是用于本地开发和手动验收的 MVP。已经包含：

- Swift Package 形式的核心纠错、provider adapter 和输入法交互逻辑
- 构建到 `dist/KnowType.app` 的本地 InputMethodKit app bundle
- 自绘紧凑候选窗，按真实测量结果切换横向/竖向布局，不把 `IMKCandidates` 作为主候选 UI
- clean-room 的 MVP 拼音引擎
- SwiftUI 设置页，覆盖 provider、本地词库状态、隐私、输入/候选行为和调试安装说明
- Debug Install 设置页会同步展示本地构建、安装、诊断、选择输入源和日志命令
- API key 通过 Keychain 存储
- 本地候选学习历史与 provider 配置分开存储

它还不是签名安装器、公证发行包或 App Store 包。

## 工程结构

```text
Sources/KnowTypeCore/          产品模型、保护规则、纠错、延续
Sources/KnowTypeProviders/     Provider profile、运行时加载、adapter、HTTP 归一化
Sources/KnowTypeInputMethod/   IMK controller、会话动作、候选窗、按键行为
Sources/KnowTypeInputMethodApp 本地 macOS 输入法 app 入口
Sources/KnowTypeSettingsUI/    共享 SwiftUI 设置与 provider profile 编辑
Sources/KnowTypeSettingsApp/   独立设置 App 宿主
Sources/KnowTypePreferencePane/ 系统设置 PreferencePane 宿主
Tests/                         core、provider、输入法逻辑单元测试
doc/                           当前架构、接口、验收和源码说明
plan/                          当前或近期完成的实施计划
Resources/                     词典、码表、保护词和未来资源
```

文档入口见 [doc/README.md](doc/README.md)。

## 构建与本地安装

要求：

- 本地 InputMethodKit bundle 需要 macOS 13 或更新版本
- Swift 6.2 工具链

运行包级检查：

```bash
swift build
swift test
```

构建并安装本地输入法 bundle：

```bash
./scripts/build-inputmethod-bundle.sh
./scripts/install-inputmethod.sh
```

安装后先运行只读诊断，再开始手动打字测试：

```bash
./scripts/diagnose-inputmethod.sh
```

详细安装、签名、Text Input Source 和排障说明放在 [doc/src/scripts/inputmethod-diagnostics.plan.md](doc/src/scripts/inputmethod-diagnostics.plan.md)。

移除本地 bundle：

```bash
./scripts/uninstall-inputmethod.sh
```

## 不安装输入法先跑 Demo

可以先用命令行体验包级流程：

```bash
swift run knowtype-demo --locale zh-CN --action tab wo jue de zhege fagnan
swift run knowtype-demo --locale mixed --action tab zhege api latnecy youdian gao
swift run knowtype-demo --locale en-US --action tab I thikn this approch
```

## Provider 配置

KnowType 通过 `ProviderProfile` 和 `ProviderFactory` 加载模型 provider。Profile 只保存 JSON 元数据，API key 单独保存。

默认 profile 文件：

```text
~/Library/Application Support/KnowType/providers.json
```

本地候选学习历史文件：

```text
~/Library/Application Support/KnowType/user-selection-history.json
```

本地 JSON/TSV 词库目录：

```text
~/Library/Application Support/KnowType/Lexicons
```

设置页会显示这个目录是否存在、加载了多少词条、已安装哪些托管词库包，以及资源诊断；也可以一键创建缺失目录、创建示例 TSV，或安装推荐的 Rime 简体拼音词库包。目录不存在是允许的；KnowType 会继续使用内置 seed 词库。
开发时也可以通过 `KNOWTYPE_LEXICON_DIR` 和冒号分隔的 `KNOWTYPE_LEXICON_DIRS` 指定额外目录，这些目录会排在默认目录之前。

也可以通过命令行安装同一个推荐词库：

```bash
scripts/install-lexicon-pack.sh rime-pinyin-simp
```

安装器会下载固定 commit 的 Apache-2.0 Rime 词库，校验 SHA256，转换为 KnowType TSV，并在 TSV 旁写入本地 metadata。第三方大词库数据不会直接提交到本仓库。

Profile 字段：

```text
id, displayName, kind, baseURL, model, timeoutSeconds, headers,
secretName, customBodyTemplate, customResponsePath, isDefault
```

`secretName` 通过 `SecretStore` 解析。macOS 上，`KeychainSecretStore` 会把 API key 存入 Keychain，service 为 `KnowType`。Provider JSON 只保存 secret name，不保存 key 明文。

自定义 `headers` 会按配置原样写入 provider JSON。MVP 阶段不要把 bearer token、API key 或其他密钥放进自定义 headers；应使用 profile 的 API key 字段，并通过 Keychain-backed secret storage 保存。

当 `providers.json` 不存在或为空时，KnowType 会使用本地 OpenAI-compatible 默认配置：`http://127.0.0.1:8317/v1`。model 可以留空并通过 `/v1/models` 发现。源码和 provider JSON 不内置 API key；如果本地 runtime 需要 key，请在设置页保存到 Keychain。

AI Provider 设置页可以测试当前 draft profile 的连接。测试时输入框里的 API key 只用于本次请求；如果 key 为空，则复用已保存的 Keychain secret。测试不会保存 provider JSON，也不会修改 Keychain。

支持的 provider kind：

- `openai_chat`：`/v1/chat/completions`
- `openai_responses`：`/v1/responses`
- `anthropic_messages`：`/v1/messages`
- `gemini_native`：Gemini `models.generateContent`
- `ollama_native`：Ollama `/api/chat`
- `custom_http`：自定义 body template 和 response path

本地 OpenAI-compatible runtime 可以留空 model，由 `/v1/models` 发现。远程 OpenAI-compatible profile 必须显式填写 model ID。Custom HTTP profile 可不填 API key，用于本地代理 endpoint。

## 输入行为

- `Space`：提交当前 raw input 对应的可见完整前缀候选，或把当前分段候选应用到组合区。
- `Return` / `Enter`：提交原始 composition，例如 `nishishei`。
- `Tab`：在前缀已完整解析时，提交当前前缀 + 第一条或当前选中的延续。
- `0`：候选可见时提交原始 composition。
- 普通标点：提交 composition + 标点；没有 composition 时直接插入标点。
- `Option + .`：切换当前输入会话的中文/英文标点。
- `Option + 数字`：提交当前前缀 + 对应延续。`Option + 1` 对应第一条延续，候选窗中用 `⇥` 表示，因为 `Tab` 会直接提交第一条延续。
- `Option + R`：主动润色，这是默认交互里唯一允许改写前缀的路径。

Input 设置页会持久化普通 App 和代码类 App 的默认标点语言、符号宽度。Terminal、iTerm、Xcode、VS Code 和 Codex desktop 使用代码类 App 默认值，同时仍保留中文输入管线；内置的代码类 App 标点默认值是中文，用户仍可改成英文。

候选窗先显示前缀候选，再显示延续候选。候选可以覆盖整个 raw buffer，也可以只覆盖当前分段；选择分段候选只更新 marked text，不会立刻上屏。候选按 9 行一页分页。候选窗会先测量候选文本再渲染，短候选优先使用 4-6 项横向布局，长词组切换为竖向布局，并做屏幕边缘避让。最近选择过的前缀候选会在输入法重启后继续影响本地排序。配置 provider 后，KnowType 会先发布本地前缀候选，再在 provider 返回后更新延续候选。如果 provider 失败或没有返回可用延续，KnowType 会保留传统前缀候选，不再用固定本地 fallback 文本伪装成 AI 输出。提交行为跟随当前可见快照：如果候选窗只显示 raw input，`Space` 不会提交隐藏中文 fallback。

## 隐私基线

Level 0 输入不能调用云端 provider。它会走无 provider 路径，并清空云端延续候选。

已保护的例子包括：

- URL 和 `www.` 地址
- 邮箱格式输入
- 绝对路径、`~/` 路径、相对路径
- `swift test`、`git status` 等命令类输入
- 包含大括号、分号或 `=>` 的代码类输入
- 通过 bundle identifier 识别的 Terminal、iTerm 和 Xcode 会话

`API`、`JSON`、`FastAPI`、`iOS`、`macOS`、`InputMethodKit`、`snake_case`、`camelCase` 等技术 token 会被保留或规范化。

## MVP 手动验收

标记 MVP 前先运行：

```bash
swift build
swift test
./scripts/install-inputmethod.sh
./scripts/diagnose-inputmethod.sh --strict
./scripts/select-inputmethod.sh --require-selected
```

然后在每个目标 app 里实际打字验证：

- TextEdit：候选窗出现在文本光标附近，`Space` 只提交前缀。
- Safari 和 Chrome：文本框中 `Tab` 提交前缀 + 第一条延续。
- Xcode：技术 token 和代码类标识符被保留。
- Terminal：路径和命令保持 Level 0，不调用 provider。
- 微信和飞书：聊天输入框中候选窗可见、可用。
- Provider 失败：仍可使用本地纠错，上屏不被阻塞。
- Keychain：API key 从 Keychain 解析，不写入 provider JSON。

完整清单见 [doc/mvp-acceptance.plan.md](doc/mvp-acceptance.plan.md)。

## 分支流程

- `main`：稳定分支。
- `dev`：集成分支。
- 主题分支：`feature/<desc>`、`fix/<desc>`、`docs/<desc>`、`refactor/<desc>`、`test/<desc>`、`release/<version>`。

使用 Conventional Commits，主题 PR 先合入 `dev`。文档变更尽量和运行时代码变更分开提交。
