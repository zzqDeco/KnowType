# KnowType / 知键

KnowType 是一款面向 macOS 的中英文 AI 输入法。它先纠正并准确理解用户正在输入的内容，再在保持用户前缀不变的前提下提供更自然、更准确的后续延续。

一句话定位：

```text
先懂你打错了什么，再顺着你已经写下的内容继续写。
```

## 核心原则

KnowType 默认必须遵守：

```text
用户原始输入 -> 输入错误纠正 -> 得到准确前缀 -> 锁定前缀 -> 生成后续延续
```

AI 只补后面，不自动改写前面。只有用户主动触发 `Option + R` 润色时，才允许改写已输入文本。

## API 协议兼容

KnowType 的“云端优先”不是绑定某一家厂商，而是优先兼容常见大模型 API 协议：

- `openai_chat`：兼容 `/v1/chat/completions`
- `openai_responses`：兼容 `/v1/responses`
- `anthropic_messages`：兼容 `/v1/messages`
- `gemini_native`：兼容 Gemini `models.generateContent`
- `ollama_native`：兼容 Ollama `/api/chat`
- `custom_http`：自定义 endpoint、headers、body template、response path

所有 adapter 都会归一化为统一的 `LLMResponse`，再经过本地前缀锁定校验。

## 工程结构

```text
Sources/KnowTypeCore/          核心模型、纠错、前缀锁定延续
Sources/KnowTypeProviders/     Provider profile、运行时加载、多协议 adapter
Sources/KnowTypeInputMethod/   输入法交互、候选窗、IMK 启动入口
Sources/KnowTypeInputMethodApp 本地 macOS IMK 后台 app 入口
Sources/KnowTypeSettingsApp/   SwiftUI 设置与 provider profile 编辑
Tests/                         单元测试与协议 adapter 测试
plan/                          当前有效实施计划
doc/                           架构、接口和文件级文档
Resources/                     词典、码表、保护词和未来资源
```

## 构建与安装

要求：

- 本地 InputMethodKit bundle 需要 macOS 13 或更新版本。
- Swift 6.2 工具链。

包级检查：

```bash
swift build
swift test
```

构建本地输入法 app bundle：

```bash
./scripts/build-inputmethod-bundle.sh
```

bundle 会输出到 `dist/KnowType.app`。

安装本地 macOS 输入法 bundle：

```bash
./scripts/install-inputmethod.sh
```

脚本会把 bundle 复制到 `~/Library/Input Methods/KnowType.app`。安装后到「系统设置 > 键盘 > 文本输入 > 输入源」启用 KnowType。如果输入源列表没有刷新，可以重新登录，或重启需要使用输入法的 app。

本地输入时，KnowType 会先把输入中的文本作为 marked text 标记在当前 app 里，然后通过独立几何解析层把紧凑的 macOS 风格候选窗锚定到光标附近。解析层优先使用 IMK caret rect、line-height rect、已授权时的 Accessibility focused-range bounds，以及同一组合内的 last usable anchor；不再把鼠标指针作为移动候选窗兜底。按 `Space` 会用最佳纠错前缀替换 marked text，按 `Tab` 会用前缀 + 第一条延续替换 marked text。

本地纠错路径包含一个 clean-room 的 MVP 拼音引擎。它支持文档中的全拼例子、`wojuedezhegefagnan` 这类连续拼音、`fangan` 常见错拼、`ni -> 你/尼/呢` 这类同音单字候选、`nih`、`niw`、`xianz` 这类尾部半音节输入、`wsm` 这类声母缩写，以及中英混输里的技术 token 保护。在 `en-US` 模式下，本地纠错会保留英文拼写纠错路径，不会先把拼音解码成中文。

移除本地 bundle：

```bash
./scripts/uninstall-inputmethod.sh
```

这是 MVP 本地打包方式，不是已签名安装器、公证发行包或 App Store 包。

## Demo 流程

在完整安装输入法之前，可以先用命令行体验包级 MVP 流程：

```bash
swift run knowtype-demo --locale zh-CN --action tab wo jue de zhege fagnan
swift run knowtype-demo --locale mixed --action tab zhege api latnecy youdian gao
swift run knowtype-demo --locale en-US --action tab I thikn this approch
```

## Provider 配置

KnowType 通过 `ProviderProfile` 和 `ProviderFactory` 在运行时加载 provider。Profile 会以 JSON 保存，但不保存 API key。默认文件位置是：

```text
~/Library/Application Support/KnowType/providers.json
```

Profile 字段包括：

```text
id, displayName, kind, baseURL, model, timeoutSeconds, headers,
secretName, customBodyTemplate, customResponsePath, isDefault
```

`secretName` 通过 `SecretStore` 解析。macOS 上的 `KeychainSecretStore` 会把 API key 存入 Keychain，service 为 `KnowType`；provider JSON 保存 `secretName`，不保存 API key 明文。自定义 `headers` 会按配置写入 provider JSON，因此 MVP 阶段不要把 bearer token 或其他密钥放进 headers。测试和非 UI 流程可以使用内存或只读字典 secret store。

设置 App 会读写同一套 profile schema，可编辑 OpenAI、Anthropic、Gemini、Ollama 和自定义 HTTP profile。云端 profile 需要填写新 key，或复用已有 Keychain 密钥。远程 OpenAI 兼容 profile 必须显式填写真实 model ID，并拒绝 `<model-id>` 这类发现占位符；本地 OpenAI 兼容运行时可以留空 model，由本地 `/v1/models` 发现。自定义 HTTP profile 可不填写 API key，以支持本地代理 endpoint；如果填写 key，则会保存为 profile 级密钥。把 profile 切换到本地或不需要密钥的 provider 时，会清除过期的非本地密钥引用；只有没有其他已保存 profile 继续引用旧密钥时，才会删除旧的 profile 级密钥。已有本地 OpenAI 兼容 profile 的 API key 留空保存时，只有对应 Keychain 项仍可解析，才会保留已有的可选密钥。

设置 App 按 MVP 分为 Input、Candidates、AI Provider、Privacy 和 Debug Install。Debug Install 会概括本地开发流程：构建/签名输入法 bundle，可通过 `CODESIGN_IDENTITY` 传入 Apple Development 身份，安装到 `~/Library/Input Methods`，必要时刷新 macOS 输入源注册状态，在系统设置中启用 KnowType，并通过 Console.app 或 `log stream` 查看 `KnowTypeInputMethodApp` 日志。

当前运行时支持：

- `openai_chat`：兼容 `/v1/chat/completions`
- `openai_responses`：兼容 `/v1/responses`
- `anthropic_messages`：兼容 `/v1/messages`
- `gemini_native`：兼容 Gemini `models.generateContent`
- `ollama_native`：兼容 Ollama `/api/chat`
- `custom_http`：自定义 body template 和 response path

所有 provider 响应都必须先归一化为 `LLMResponse`，再进入 core 或输入法层。

## 交互规则

- `Space`：只提交当前选中的前缀。
- `Tab`：提交当前选中的前缀 + 第一条或当前选中的延续。
- `Option + 数字`：提交全局快捷键对应的延续。`Option + 1` 对应第一条延续，候选窗中用 `⇥` 表示，因为 `Tab` 会直接提交第一条延续；后续分页不会复用延续快捷键标签。
- `Option + R`：主动润色，这时才允许改写前缀。

候选窗现在采用扁平的 macOS 风格列表：前缀候选在前，延续候选在后；只有还没有纠错候选时才显示原始输入。候选按 9 行一页分页，并支持 PageUp/PageDown 翻页。配置了 provider 时，本地即时阶段只显示前缀候选，延续候选等 provider 返回后再发布。未配置 provider 或 provider 失败时，才使用本地 fallback 延续。

## 隐私基线

URL、邮箱、路径、命令类输入、代码片段、Terminal/iTerm 输入、Xcode 输入等 Level 0 场景不发云端。Level 0 会走无 provider 路径，不产生云端续写候选，并默认原样提交。

已覆盖的保护例子：

- URL 和 `www.` 地址。
- 邮箱格式输入。
- 绝对路径、`~/` 路径、相对路径。
- 包含大括号、分号或 `=>` 的代码类输入。
- `swift test`、`git status` 等命令类输入。
- 通过 bundle identifier 识别的 Terminal、iTerm 和 Xcode 会话。

`API`、`JSON`、`FastAPI`、`iOS`、`macOS`、`InputMethodKit`、`snake_case`、`camelCase` 等技术 token 属于保留/规范化规则。包含这些 token 的普通混合文本不一定是 Level 0，除非它同时命中上面的 Level 0 规则。

## MVP 手动验收

MVP 标记前，应运行 `swift build`、`swift test`，构建并安装本地输入法 bundle，然后手动验证：

- TextEdit：候选窗出现在光标附近，`Space` 只提交前缀。
- Safari 和 Chrome：文本框中 `Tab` 提交前缀 + 第一条延续。
- Xcode：技术 token 和代码类标识符被保留。
- Terminal：路径和命令保持 Level 0，不调用云端 provider。
- WeChat 和 Feishu：聊天输入框中候选窗可见、可用。
- 云端失败：provider 报错时回退到本地纠错和续写，不影响提交。
- Keychain：API key 从 Keychain 解析，不写入 provider JSON。

完整清单见 `doc/mvp-acceptance.plan.md`。

## MVP 分支与 PR 管理

- 发布就绪文档以 `origin/dev` 为基础。
- 文档定稿前先应用待合入的 provider runtime 分支，确保运行时加载和 Keychain 行为与发布候选一致。
- runtime 合入后应 rebase 文档分支，不要把旧文档直接覆盖到较新的 runtime、settings、privacy 或候选窗变更上。
- 发布文档变更应与 runtime 代码变更保持独立；打 tag 或开发布 PR 前运行 `swift build`、`swift test` 和 `git diff --check`。
