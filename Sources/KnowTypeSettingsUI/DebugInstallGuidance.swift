import Foundation

struct DebugInstallStep: Equatable, Identifiable {
    let title: String
    let detail: String

    var id: String { title }
}

enum DebugInstallGuidance {
    static let steps: [DebugInstallStep] = [
        DebugInstallStep(
            title: "构建并签名",
            detail: "运行输入法 bundle 构建脚本。脚本会优先选择可用的 Apple Development 签名身份，只有找不到证书时才回退到 ad-hoc 签名。"
        ),
        DebugInstallStep(
            title: "安装 bundle",
            detail: "将 KnowType.app 复制到 ~/Library/Input Methods。安装脚本会清理过期的 .Mode 开发状态，然后从已安装 app 上下文执行注册、启用和选择。设置入口在输入法菜单里的 KnowType Settings..."
        ),
        DebugInstallStep(
            title: "诊断安装",
            detail: "运行只读诊断，检查 bundle metadata、签名、打包资源、Text Input Source 注册、本地数据路径，以及可选的 Gatekeeper 或 sandbox 日志线索。"
        ),
        DebugInstallStep(
            title: "请求切换",
            detail: "先激活要测试的文本 app，再用选择脚本做预检。脚本会通过已安装的 KnowType app 请求切换；最终验收仍需要在该 app 中实际输入探针。"
        ),
        DebugInstallStep(
            title: "启用输入源",
            detail: "如果 macOS 弹出是否允许 知键/KnowType 作为输入法，请点击允许。然后打开 System Settings > Keyboard > Text Input > Input Sources；如果没有自动切换，请手动启用或选择 KnowType。"
        ),
        DebugInstallStep(
            title: "刷新注册状态",
            detail: "如果 macOS 保留旧注册，运行修复脚本。它会通过已安装输入法 app 移除过期 LaunchServices 记录、禁用 legacy .Mode 注册、恢复 third-party parent anchor 与 .Hans mode，并重新测试切换。"
        ),
        DebugInstallStep(
            title: "查看日志",
            detail: "本地 smoke test 时，可以使用诊断日志模式、Console.app 或 log 命令查看 KnowTypeInputMethodApp、Gatekeeper 和 input-source sandbox 消息。"
        )
    ]

    static let commands: [String] = [
        "./scripts/build-inputmethod-bundle.sh",
        "CODESIGN_IDENTITY=\"Apple Development: Name (TEAMID)\" ./scripts/install-inputmethod.sh",
        "./scripts/install-inputmethod.sh",
        "./scripts/install-inputmethod.sh --with-prefpane",
        "./scripts/diagnose-inputmethod.sh --strict",
        "./scripts/diagnose-inputmethod.sh --strict --logs",
        "./scripts/repair-inputmethod-selection.sh",
        "./scripts/select-inputmethod.sh",
        "./scripts/select-inputmethod.sh --require-selected",
        "log stream --predicate 'process == \"KnowTypeInputMethodApp\"'"
    ]
}
