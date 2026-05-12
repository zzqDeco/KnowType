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
Sources/KnowTypeProviders/     多协议 provider adapter
Sources/KnowTypeInputMethod/   输入法交互规则与 IMK 启动入口
Tests/                         单元测试与协议 adapter 测试
plan/                          当前有效实施计划
doc/                           架构、接口和文件级文档
Resources/                     词典、码表、保护词和未来资源
```

## 开发命令

```bash
swift build
swift test
```

## 交互规则

- `Space`：提交当前最佳前缀。
- `Tab`：提交当前最佳前缀 + 第一条延续。
- `Option + 数字`：提交当前最佳前缀 + 指定延续。
- `Option + R`：主动润色，这时才允许改写前缀。

## 隐私基线

URL、邮箱、路径、代码片段、终端输入等 Level 0 场景不发云端。后续 macOS App 层加入配置 UI 时，API key 必须进入 Keychain，不能明文写入配置文件。
