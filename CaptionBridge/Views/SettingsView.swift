import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var settings: CaptionSettings
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("显示") {
                    Picker("主题", selection: Binding(
                        get: { settings.theme },
                        set: { settings.theme = $0 }
                    )) {
                        ForEach(CaptionTheme.allCases) { theme in
                            Text(theme.title).tag(theme)
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("字号")
                        Slider(value: $settings.fontScale, in: 0...2, step: 0.1)
                        Text("通话时可以把字号调到很大，手机放在桌上也能看清。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    Toggle("横屏家庭模式", isOn: $settings.landscapeMode)
                }

                Section("隐私") {
                    Toggle("结束后默认清空文字", isOn: $settings.privacyAutoClear)
                    Text("第一版默认不保存音频。实时识别可能会使用 Apple 语音识别服务，正式接入云识别前需要在隐私说明中明确告知。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("字幕设置")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") {
                        dismiss()
                    }
                }
            }
        }
    }
}
