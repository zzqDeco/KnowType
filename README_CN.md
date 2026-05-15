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
- **macOS 原生输入流程**：使用 marked text、候选选择、翻页、标点处理和跟随文本光标的 AppKit 候选窗。
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
- 自绘紧凑候选窗，不把 `IMKCandidates` 作为主候选 UI
- clean-room 的 MVP 拼音引擎
- SwiftUI 设置页，覆盖 provider、本地词库状态、隐私、输入/候选行为和调试安装说明
- API key 通过 Keychain 存储
- 本地候选学习历史与 provider 配置分开存储

它还不是签名安装器、公证发行包或 App Store 包。

## 工程结构

```text
Sources/KnowTypeCore/          产品模型、保护规则、纠错、延续
Sources/KnowTypeProviders/     Provider profile、运行时加载、adapter、HTTP 归一化
Sources/KnowTypeInputMethod/   IMK controller、会话动作、候选窗、按键行为
Sources/KnowTypeInputMethodApp 本地 macOS 输入法 app 入口
Sources/KnowTypeSettingsApp/   SwiftUI 设置与 provider profile 编辑
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

构建输入法 app bundle：

```bash
./scripts/build-inputmethod-bundle.sh
```

bundle 会输出到：

```text
dist/KnowType.app
```

本地安装：

```bash
./scripts/install-inputmethod.sh
```

脚本会把 bundle 复制到：

```text
~/Library/Input Methods/KnowType.app
```

然后到「系统设置 > 键盘 > 文本输入 > 输入源」启用 KnowType。如果输入源列表没有刷新，可以重新登录，或重启要测试输入法的 app。

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

设置页会显示这个目录是否存在、加载了多少词条，以及资源诊断，也可以一键创建缺失目录。目录不存在是允许的；KnowType 会继续使用内置 seed 词库。
开发时也可以通过 `KNOWTYPE_LEXICON_DIR` 和冒号分隔的 `KNOWTYPE_LEXICON_DIRS` 指定额外目录，这些目录会排在默认目录之前。

Profile 字段：

```text
id, displayName, kind, baseURL, model, timeoutSeconds, headers,
secretName, customBodyTemplate, customResponsePath, isDefault
```

`secretName` 通过 `SecretStore` 解析。macOS 上，`KeychainSecretStore` 会把 API key 存入 Keychain，service 为 `KnowType`。Provider JSON 只保存 secret name，不保存 key 明文。

自定义 `headers` 会按配置原样写入 provider JSON。MVP 阶段不要把 bearer token、API key 或其他密钥放进自定义 headers；应使用 profile 的 API key 字段，并通过 Keychain-backed secret storage 保存。

支持的 provider kind：

- `openai_chat`：`/v1/chat/completions`
- `openai_responses`：`/v1/responses`
- `anthropic_messages`：`/v1/messages`
- `gemini_native`：Gemini `models.generateContent`
- `ollama_native`：Ollama `/api/chat`
- `custom_http`：自定义 body template 和 response path

本地 OpenAI-compatible runtime 可以留空 model，由 `/v1/models` 发现。远程 OpenAI-compatible profile 必须显式填写 model ID。Custom HTTP profile 可不填 API key，用于本地代理 endpoint。

## 输入行为

- `Space`：提交当前选中的前缀候选。
- `Tab`：提交当前选中的前缀 + 第一条或当前选中的延续。
- `0`：候选可见时提交原始 composition。
- 普通标点：提交 composition + 标点；没有 composition 时直接插入标点。
- `Option + .`：切换当前输入会话的中文/英文标点。
- `Option + 数字`：提交当前前缀 + 对应延续。`Option + 1` 对应第一条延续，候选窗中用 `⇥` 表示，因为 `Tab` 会直接提交第一条延续。
- `Option + R`：主动润色，这是默认交互里唯一允许改写前缀的路径。

Terminal、iTerm、Xcode、VS Code 和 Codex desktop 默认英文半角标点，但仍保留中文输入管线。

候选窗先显示前缀候选，再显示延续候选。候选按 9 行一页分页。最近选择过的前缀候选会在输入法重启后继续影响本地排序。配置 provider 后，KnowType 会先发布本地前缀候选，再在 provider 返回后更新延续候选。

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
```

然后构建并安装本地 bundle，手动验证：

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
