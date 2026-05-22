# KnowType AI 10 秒超时与子状态日志方案

## Summary

- 从 `origin/dev` 新拉 `fix/ai-timeout-diagnostics`，所有改动只提 PR 到 `dev`。
- 将 `AIRecommendationRuntime` 内部硬超时从 `2.5s` 提高到 `10s`，避免本地 `CLIProxyAPI` 抖动时过早失败。
- 增加 AI 子状态日志，区分模型慢、空候选、prefix-lock 过滤、用户继续输入导致取消、冷却中等原因。

## Scope

- 修改 `KnowTypeAI` 的实时推荐 runtime、诊断事件和默认 OSLog sink。
- 修改 `InputControllerCoordinator` 的 AI 调度侧诊断日志。
- 更新 AI runtime 接口文档、coordinator source note 和测试。
- 不改模型选择 UI、候选窗文案、Rime 热路径、provider profile 超时或 `main` release 流程。

## Implementation

- 分支准备：
  - `git fetch origin --prune`
  - `git switch dev`
  - `git pull --ff-only origin dev`
  - `git switch -c fix/ai-timeout-diagnostics origin/dev`
- 新增 `AIRecommendationRuntime.Defaults.hardTimeoutMilliseconds = 10_000`，默认构造使用 10 秒；测试仍可注入短超时。
- 新增 `AIRecommendationDiagnosticSink`、`AIRecommendationDiagnosticEvent` 和默认 `OSLogAIRecommendationDiagnosticSink`，subsystem 为 `com.knowtype.inputmethod.KnowType`，category 为 `ai`。
- 每轮 AI 请求通过 `AIRecommendationRequest.requestID` 串联 runtime 与 coordinator 日志；日志只包含状态、耗时、长度、计数、错误类型和 request/composition 标识，不记录用户原文、候选全文或 API key。
- Runtime 记录 `skipped_*`、`debounce_*`、`cache_*`、`context_loaded`、`provider_request_start`、`provider_response`、`sanitize_empty`、`ready`、`timeout`、`provider_error`、`cooldown_active`、`cancelled`。
- Coordinator 记录 `scheduled`、`cancel_previous`、`stale_result_dropped`、`state_applied`，用于确认继续输入或过期 generation 是否丢弃了 AI 结果。
- 本机诊断命令：
  `log stream --predicate 'subsystem == "com.knowtype.inputmethod.KnowType" && category == "ai"' --style compact`

## Test Plan

- 单元测试：
  - 默认硬超时为 `10_000ms`。
  - recording diagnostic sink 覆盖成功、缓存命中、空候选、超时、coordinator cancel/stale drop。
  - 空候选仍返回 `AI 无推荐`，且不进入 cooldown。
- 必跑：
  - `swift test --quiet`
  - `./scripts/smoke-inputmethod-install.sh`
  - `./scripts/perf-input-hotpath.sh`
  - `git diff --check`
- 本机验收：
  - 使用 `gpt-5.3-codex-spark`。
  - 超过 `2.5s` 但低于 `10s` 的 AI 请求仍可返回候选。
  - 日志能区分模型慢、空候选、prefix-lock 过滤、继续输入取消、冷却中。

## Assumptions

- `10s` 是 runtime 硬上限；用户继续输入仍会取消旧请求。
- Provider profile 的 `timeoutSeconds=20` 保持网络层上限，不作为输入法体验层上限。
- 诊断默认走 macOS unified logging，不落盘保存明文输入内容。
