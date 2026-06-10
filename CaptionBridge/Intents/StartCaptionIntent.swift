import AppIntents

struct StartCaptionIntent: AppIntent {
    static var title: LocalizedStringResource = "开始实时字幕"
    static var description = IntentDescription("打开字幕工具并自动开始麦克风实时字幕。")
    static var openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        return .result()
    }
}

struct CaptionShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartCaptionIntent(),
            phrases: [
                "开始\(.applicationName)",
                "打开\(.applicationName)字幕",
                "用\(.applicationName)开始实时字幕"
            ],
            shortTitle: "开始字幕",
            systemImageName: "captions.bubble"
        )
    }
}
