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

这里 AI 延续只负责 `还有进一步优化空间`，不能把已经锁定的前缀改写成
另一句话。

## 功能

- 中文输入优先：生产 IMK 热路径使用内置 `librime` 负责同步拼音转换、
  Space 上屏、数字选词和翻页。
- 本地候选学习：最近选择过的前缀会在输入法重启后继续影响本地排序，
  不发送给 provider。
- 前缀锁定的 AI 推荐：第一候选固定为 Rime 转换，第二候选固定为 AI 推荐；
  已锁定前缀永不改写。
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

它还不是公证安装器、自动更新程序或 App Store 应用。

GitHub Releases 默认提供名为 `KnowType-vX.Y.Z-macos-dev-preview.dmg` 的
Developer Preview DMG。它包含 `KnowType.app`、命令文件安装入口、release manifest
和 SHA256 文件。该 DMG 没有 Developer ID 签名，也未公证；macOS 可能要求右键打开，
或在“隐私与安全性”里点击“仍要打开”。旧的本地 MVP zip 仍保留为开发者调试资产。

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
开发状态，从已安装 app 上下文注册并启用 KnowType parent input method 与可见 `.Hans` 输入模式，并修复 history 但不会把 KnowType 移到当前保留输入源之前；默认安装不改 selected preference，不会启动已安装的输入法 host，不会自动选择 KnowType，也不会在安装阶段初始化
Rime 用户数据。即使 macOS 在刷新 TIS 或 LaunchServices 状态时预热启动 host，controller 冷启动
也会把 Rime session、provider profile、AI learning/profile 文件、`ENV.md` 和 `CORRECTION.md`
延迟到真实输入、AI 请求或显式维护动作时才初始化。推荐用
`./scripts/install-inputmethod.sh --configuration release` 做本地打字测试，不要直接注册
`dist/KnowType.app`。安装脚本会把 source bundle 复制到
`~/Library/Input Methods/KnowType.app`，清理 source、临时解包和 backup 路径上的 stale
LaunchServices 记录，并且只注册这个 canonical installed target。替换前，安装脚本会先
switch-away，disable 既有 KnowType 输入源行，重启 text-input menu agents，并对仍在运行的
`KnowTypeInputMethodApp` 发送 `TERM`。如果 host 仍不退出，请手动退出，或在本地开发时显式传
`--force-stop-host`。KnowType 使用成熟 macOS IMK 形态：
`com.knowtype.inputmethod.KnowType` 是不可直接选择的 parent input method，
`com.knowtype.inputmethod.KnowType.Hans` 是唯一用户可选的可见输入模式；旧 `.Mode`
记录以及 parent-only selected/history 行只作为历史缓存清理对象。System Settings
和右上角输入法菜单里应只显示一个用户可选的 `知键`。

`scripts/install-inputmethod.sh` 默认使用 release 构建，方便本地打字测试覆盖优化后的热路径。
Rime runtime 文件会打包在 `KnowType.app` 中；如果文件缺失或加载失败，KnowType 会保留
raw 输入可用并报告 degraded conversion state，而不是回退到已经退役的自研转换器。

覆盖安装会先在 `~/Library/Application Support/KnowType/Backups/` 创建 app 级回滚备份，
并把当前安装来源、版本、build、commit/tag 和备份 id 写入
`~/Library/Application Support/KnowType/install-state.json`。备份只包含安装产物：
`KnowType.app` 和可选 `KnowType.prefPane`；不会复制、回滚或改写 Rime userdb、provider 配置、
Keychain secret、AI 上下文文档、`~/.knowtype` 或本地词库。用户手动选择 KnowType 并开始真实输入后，
Rime 初始化属于正常使用行为，不属于安装阶段副作用。

新版回滚 manifest 会记录两个安装产物各自的 checksum、bundle ID、版本/build 和签名
requirement/identity。回滚会在替换前核对全部字段，并执行
`codesign --verify --deep --strict`。旧 schema-v1 备份默认拒绝恢复；只有在独立确认备份可信后，
才能显式使用高风险参数 `--allow-unverified-backup`，而且该参数不能绕过新版 manifest
校验失败。安装、卸载和回滚也只允许删除 canonical、非 symlink 且 bundle ID 为
`com.knowtype.preferencepane` 的 `KnowType.prefPane`，同名外部 bundle 会被保留并阻断操作。

KnowType 的专属设置入口对齐 McBopomofo、OpenVanilla 这类原生 IMK 输入法：先在
macOS 输入法菜单中选中 KnowType，然后点击 `KnowType 设置...`（显式英文资源路径下为
`KnowType Settings...`）。它会打开 macOS 原生 sidebar 和 grouped settings 页面；
默认首页是面向普通用户的“概览”，用于查看输入法、AI 续写、词库和隐私状态；
Provider、Base URL、Custom HTTP、日志和本地路径等技术项集中在 AI 的高级配置或“高级”
故障排查页。设置界面默认使用简体中文文案，英文资源仅作为显式英文 locale 查询和缺失 key
fallback 保留。
本地安装默认不安装独立 Settings app。默认安装会移除
本机过期的兼容 `KnowType.prefPane`，避免它和新安装的输入法版本不一致；需要匹配版本的兼容 pane 时，再执行
`./scripts/install-inputmethod.sh --with-prefpane` 构建并安装。
如果默认安装后系统设置侧边栏仍显示 `KnowType`，那是 macOS PreferencePane 缓存残留；
重新运行安装脚本或 `./scripts/uninstall-inputmethod.sh` 刷新缓存，然后重新打开系统设置。

首次安装或 mode id 迁移后，macOS 仍可能要求通过系统设置完成第三方输入源授权。
打开“系统设置 > 键盘 > 输入源”，移除过期的 KnowType/知键条目，重新添加
`知键` / `KnowType`，如果系统弹出允许提示则点击允许。如果菜单仍显示旧条目，注销再登录以清理
Text Input Source 缓存。这个边界与成熟 IMK 输入法一致：安装流程使用 TIS 注册和启用，
受保护的第三方输入源授权行由系统设置写入。

安装后先激活目标 app，再从 macOS 输入法菜单选择 KnowType；也可以在目标 app 激活时运行：

```bash
./scripts/select-inputmethod.sh --require-selected
```

手动验收必须看真实 macOS 输入法菜单：右上角应有 `K` 图标，菜单里应有 `知键` /
`KnowType` 条目。只看 helper selection 成功还不够。

移除本地 bundle：

```bash
./scripts/uninstall-inputmethod.sh
```

列出或恢复本地回滚点：

```bash
./scripts/rollback-inputmethod.sh --list
./scripts/rollback-inputmethod.sh --latest
```

回滚会保留 profile 内容和 Keychain secret。若目标备份早于 provider storage
generation 2，当前 app 会先把最新 profile 元数据无损转换为旧版可读的数字 schema，
再发布旧 app；无法证明转换安全时会直接拒绝回滚。

只对已独立确认可信的旧备份，先执行 dry-run 并显式开启兼容覆盖：

```bash
./scripts/rollback-inputmethod.sh --to BACKUP_ID --dry-run --allow-unverified-backup
```

本地 IME 行为仍需要在真实 host app 中打字验证。macOS policy、输入源选择和
手动验收流程见 [Local Input Method Testing](doc/local-inputmethod-testing.plan.md)
和 [MVP Acceptance](doc/mvp-acceptance.plan.md)。

使用 GitHub Release DMG 时，先用发布页提供的 `.sha256` 文件校验下载的 DMG：

```bash
cd ~/Downloads
shasum -a 256 -c KnowType-v0.2.8-macos-dev-preview.dmg.sha256
```

打开 DMG 后运行 `Install KnowType.command`。如果 macOS 阻止运行，使用右键打开，
或到“系统设置 > 隐私与安全性”点击“仍要打开”。安装命令会在诊断中记录
`source=dmg-dev-preview`、release commit/tag 和 manifest digest，但不会启动输入法 host
或做真实打字探测。只有需要兼容 System Settings pane 时才额外传 `--with-prefpane`。
除非已安装匹配版本的 pane，否则不要使用系统设置侧边栏里残留的 KnowType 入口。

旧的本地 MVP zip 仍可用于开发者调试：

```bash
./scripts/install-inputmethod.sh --from-release-zip ~/Downloads/KnowType-v0.2.8-macos-local-mvp.zip
```

## 配置

Provider profile 以 JSON 元数据保存，API key 单独保存。
Profile 文件使用带 revision 的事务格式，多个设置窗口不会静默覆盖彼此的
修改。变更后的 Keychain 凭据使用不可变引用。Base URL 可以保留运行时兼容
所需的 query，但不能包含 userinfo 或 fragment；诊断输出会移除 userinfo、
query 和 fragment。
运行中的输入法 host 会观察已提交的 profile revision。下一次满足条件的推荐或
context digest 会直接使用新 provider，无需重启 host；旧的 in-flight provider
请求会被取消，普通按键热路径不会轮询 provider 文件。

```text
~/Library/Application Support/KnowType/providers.v2.json
```

升级时安装器会把旧 `providers.json` 的原始内容保存在
`providers.legacy.json`，重新绑定 Keychain 引用，再把旧路径写成兼容
tombstone。请不要手工编辑这两个兼容文件；诊断发现旧版 Settings 回写后，
先关闭旧进程并保留两份 payload 进行冲突处理，安装器不会静默丢弃旧版回写。

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

当全新安装的 `providers.v2.json` 不存在或为空时，KnowType 会使用本地 OpenAI-compatible
默认 profile：`http://127.0.0.1:8317/v1`，不内置 API key。远程
OpenAI-compatible profile 必须显式填写 model ID；本地 OpenAI-compatible
profile 可以留空 model，并通过 `/v1/models` 发现。

新建 Anthropic 和 Gemini profile 分别使用 `claude-haiku-4-5-20251001` 与
`gemini-3.5-flash`。已有 profile 只有在 model 精确等于退役模板 ID、且 endpoint
仍是对应官方 API 时才会按 revision 一次性更新；自定义代理 endpoint 保留原 model。
Custom HTTP body placeholder 只对原始模板扫描一次，因此用户输入中的 placeholder
字面量不会被二次替换；未知或未闭合的 `{{...}}` 会在发请求前报模板无效。

AI 上下文文件位于 `~/.knowtype/`。`ENV.md` 保存 AI 推荐槽使用的本地上下文
记忆，`CORRECTION.md` 保存用户可编辑的 AI 纠错说明，`LEXICAL_PROFILE.md`
是由 Rime userdb 词频、KnowType 近期提交、选择历史，以及用户明确接受过的
AI 推荐摘要合成的本地 top-K 词汇画像镜像。用户接受 AI 推荐后立即发生、
且光标范围可验证的编辑会单独汇总为本地 AI feedback；普通 Backspace 不会
自动当成负反馈。完整 accepted-AI 和 feedback 历史只保存在本机
Application Support 中，不会直接注入 provider 请求。Canonical JSON 存在
`~/Library/Application Support/KnowType/AI/`。传统输入引擎不依赖
这些文件。可以用 `./scripts/accepted-learning.sh status`、`rebuild` 或
`clear --yes` 查看、重建或删除 accepted-AI learning/feedback 数据；clear 会
删除 accepted-learning/feedback history/summary/mirror，并从 lexical profile
中清理 accepted-AI 上下文，但不会删除 Rime、provider、Keychain、ENV 或
CORRECTION 数据。
已提交的 Context Digest 事件会先以 JSONL 保存在本机
`~/.knowtype/events/`。文本字段最多保留 2,048 个 Unicode scalar；pending
最多保留 500 条或 1 MiB，溢出后丢弃最旧的派生事件。每次 provider digest
最多发送最旧的 50 条或 256 KiB。成功 claim 会移入 `events/processed/`，该目录
最多保留 7 天、100 个文件和 10 MiB；清理只在 digest 成功后执行，启动和安装
不会改写历史数据。Context 诊断仅包含计数、字节数和冷却时长，不包含输入原文、
provider 输出或 Key。
实时 AI 推荐使用任务专属的后缀生成 prompt，runtime 超时为 10 秒；可用时
优先使用 provider 级结构化 JSON Schema 输出，并通过 macOS unified logging
输出不含原文的子状态诊断。Rime 正在 composition 时，当前页候选不会发送给
实时 AI 请求；未选择的候选不会被当成 locked prefix。还没有 locked prefix 时，
AI 会基于 raw input、上下文文档和持久 `LEXICAL_PROFILE.md` 返回可直接上屏的
完整推荐，而不是拼到第一候选后的后缀。
日志可以区分 schema 降级、结构化解析失败、prefix-lock sanitizer 拒绝、
prefix 太短等原因。查看命令：
`log stream --predicate 'subsystem == "com.knowtype.inputmethod.KnowType" && category == "ai"' --style compact`。

## 调试诊断

Debug 输出默认关闭。开启后，诊断只使用隐私安全的 key/value 字段：id、长度、
revision、generation、reason、耗时、bundle id、write mode、anchor source
以及 handled/pass-through 状态。日志不会记录 raw input、preedit、候选文本、
上屏文本、prompt、provider 输出、context body 或 API key。

使用 `KNOWTYPE_PERF_DEBUG=1` 可以打开关键性能链路，也可以按问题组合更窄的开关，
例如 `KNOWTYPE_AI_DEBUG=1`、`KNOWTYPE_PANEL_DEBUG=1`、
`KNOWTYPE_TURN_DEBUG=1`、`KNOWTYPE_CLIENT_WRITE_DEBUG=1` 和
`KNOWTYPE_ANCHOR_DEBUG=1`。

```bash
launchctl setenv KNOWTYPE_PERF_DEBUG 1
log stream --predicate 'subsystem == "com.knowtype.inputmethod.KnowType"' --style compact
```

排查 AI 请求取消和 token 消耗时，可以用
`python3 scripts/summarize-ai-debug-log.py /tmp/knowtype-ai-debug.log`
汇总已捕获日志。

验收结束后清理调试变量：

```bash
launchctl unsetenv KNOWTYPE_PERF_DEBUG
launchctl unsetenv KNOWTYPE_AI_DEBUG
launchctl unsetenv KNOWTYPE_PANEL_DEBUG
launchctl unsetenv KNOWTYPE_TURN_DEBUG
launchctl unsetenv KNOWTYPE_CLIENT_WRITE_DEBUG
launchctl unsetenv KNOWTYPE_ANCHOR_DEBUG
```

首键卡顿、AI 延迟、候选窗残留、host 写入和 anchor 错位的推荐日志组合见
[Debug Diagnostics](doc/debug-diagnostics.plan.md)。

## 输入行为

| 快捷键 | 行为 |
|---|---|
| `Space` | composition 活跃时提交 Rime 当前高亮候选；没有 active composition 时输入普通空格，全角模式下输入 U+3000。 |
| `1...9` | 原生 Rime composition 活跃时选择当前页候选，即使自绘候选窗暂时隐藏；没有 active composition 时按字符宽度输入半角或全角数字。 |
| 方向键、`PageUp` / `PageDown`、`-` / `=`、`,` / `.` | 在当前 Rime 页内移动选择；到候选列表边界且还有上一页或下一页时翻页；不能翻页时回退到普通标点提交路径。第一页首项按左/上会到上一页最后一项。 |
| `Return` / `Enter` | 提交原始 composition。 |
| `Tab` | 第二候选位的 AI 推荐 ready 时提交 AI 推荐；pending 或 unavailable 时保持 composition。 |
| `0` | 有纠错候选可见时提交原始 composition；没有 active composition 时输入 `0`，或在兼容宿主中直通给宿主。 |
| 普通标点 | composition 活跃时先交给 Rime schema 处理；Rime 不处理时只生成最终 direct 输出或有序符号候选。空闲半角 ASCII 由宿主兼容 writer 决定由 KnowType 插入还是交还宿主；直通时不会打开符号 session。 |
| `/` 等多义符号 | 中文标点模式下打开符号 composition。inline 宿主以 marked text 预览当前符号；commit-only 宿主保留 placeholder，并在候选窗顶部显示同一预览。`Space`、Return、当前页有效数字或鼠标选择提交；`Escape`、Backspace 取消；再次按相同 trigger 会移动到下一候选。候选活动期间方向键和翻页命令均被消费，包括首尾边界；其他 printable 输入会先提交当前符号，再正常处理一次原按键。 |
| Command/Control 宿主快捷键 | 先清理并取消已打开的符号 composition，再把快捷键交给当前宿主，避免残留 marked text 或后续 `Space` 提交旧符号。 |
| `Option + .` | 中文输入模式下手动切换中文/英文标点，覆盖持续到下一次中英切换；ASCII 模式下保持英文标点并仅重显状态。 |
| `Option + /` | 切换进程级中文/ASCII 输入模式，同时恢复中文/英文标点联动；所有 App 共享。 |
| `Shift + Space` | 切换进程级半角/全角字符，不改变中英输入或标点模式。全角会转换 ASCII `!` 到 `~` 及普通空格，不转换控制字符、Tab 或换行。 |
| `Option + 1` | 显式提交 ready AI 推荐。 |
| `Option + 2...9` | legacy continuation 行存在时提交对应延续。 |

中英输入、标点语言和字符宽度仍是三层状态，但中英输入与标点采用可预测的全局
联动：中文输入默认中文标点，ASCII 输入始终英文标点，`Option + /` 每次切换都会
恢复联动。中文阶段可用 `Option + .` 临时改成英文标点，该手动覆盖到下一次中英
切换时失效；全半角始终独立。当前输入法 host 运行期间所有 App 共享状态，host
重启后重新从“中文 + 中文标点 + 已保存全局宽度”开始。原生 Rime session 创建及
进程模式 generation 变化时会同步 `ascii_mode`、`ascii_punct` 和 `full_shape`。紧邻 ASCII 数字后的 `.`
固定输出半角点，适配小数和编号，即使当前为中文标点或全角；逗号、选区和未知
光标上下文仍走普通标点规则。中文引号会读取光标前字符：空白或开标点输出开引号，
文本、数字或闭标点输出闭引号；上下文未知时才使用 session 内交替。外部删除、
焦点或选区变化、模式 generation 变化都会重置该 fallback。模式切换后会短暂显示
类似 `中 · 中文标点 · 半角` 的状态行。

宿主兼容策略优先保证不吞普通输入。标准 AppKit 风格文本框、浏览器、编辑器、
IDE、Electron shell 和未知客户端默认都使用 inline attributed marked text，
因此 raw preedit 会显示在当前宿主输入框内。宿主身份不再改变全局中英或标点
状态。KnowType 只向 InputMethodKit 注册 key-down 事件，以保留 IMK 的默认行为：
用户点击 marked range 外部时提交 active composition。快捷键修饰键仍从 key-down
flags 读取。InputMethodKit responder 导航命令只在符号候选活动时单独处理，避免
同一次方向键继续移动宿主光标或选区。文字 composition 会在符号 session 打开前先
完整提交；取消符号不会恢复或删除已经提交的文字。显式 commit 会确认当前符号；
点击外部或 deactivate 只有在焦点、宿主身份和光标范围仍与 session 创建时一致时
才确认，宿主上下文变化或缺失时会取消且不写入。reset、close、宿主快捷键和输入
模式变化也会取消。符号 session 不启动 AI、Rime 学习或 Provider context。inline
宿主以 marked text 显示当前符号；终端类或 override commit-only 宿主保留 U+3000
carrier，并在候选窗 preedit 行显示同一当前符号。选择变化会同步更新预览，首尾
边界未移动时不会重复改写 mark。已打开的符号 session 在偏好刷新后仍沿用创建时
的分页大小，保证候选窗分页与数字选择一致。焦点生命周期会先同步共享输入模式，模式已变化时取消
旧符号而不提交；兼容直通的标点会在读取文档上下文或改变引号状态前交还宿主。
因此 Terminal、iTerm、MacVim 和 Emacs 风格宿主也默认进入中文模式；
它们的中文 composition 使用带 marked attributes 的全角空格 attributed marked-text placeholder 稳住宿主
composition 和候选窗 anchor；真实 raw/preedit 会显示在 KnowType 候选窗候选行
上方，符号 composition 也在同一位置显示当前符号，确认时再通过 `insertText`
上屏。切到 ASCII 后，空闲半角 printable 输入会直通
当前宿主；全角 printable 输入由 KnowType 转换后插入。仍可用 UserDefaults override 将任意
bundle 强制回 `commitOnlyComposition`，用于处理真实不兼容 inline marked text 的宿主。

候选窗显示 Rime 前缀候选、符号候选、固定 AI 推荐状态行、模式状态行、
终端/override commit-only placeholder 宿主中的真实 preedit，以及没有建议时的 raw input。preedit 行没有
快捷键、不可选、不能提交；inline 宿主不会额外显示这一行，避免和宿主输入框里的
preedit 重复。它是紧凑的 AppKit 自绘 panel，使用 macOS 材质、系统高亮色、鼠标
hover/click 选择、一次 trackpad 手势最多翻一页，并支持 VoiceOver press 提交启用的
候选行；禁用状态行只读、不能提交。配置 provider 后，
KnowType 会先发布 Rime 前缀候选，再异步更新 provider-backed AI 推荐。Provider
失败时，不会把固定本地 fallback 文本伪装成 AI 输出。

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
Accepted AI learning 也只用 secret-like hard block：疑似 credential 的 AI
接受文本不会被记录，普通技术文本可以留在本地摘要中用于后续推荐。AI feedback
learning 同样只拦截 secret-like 内容，并且只记录可验证的 post-accept edit。

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
- 改写锁定前缀

## License

License not declared yet.
