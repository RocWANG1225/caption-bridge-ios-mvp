import SwiftUI

struct CaptionScreen: View {
    @EnvironmentObject private var session: CaptionSession
    @EnvironmentObject private var settings: CaptionSettings

    @State private var showSettings = false
    @State private var showEndDialog = false
    @State private var saveMessage: String?

    var body: some View {
        ZStack {
            settings.background.ignoresSafeArea()

            VStack(spacing: 0) {
                topBar

                if settings.landscapeMode {
                    landscapeBody
                } else {
                    portraitBody
                }

                Spacer(minLength: 18)

                primaryControlBar

                hintView
            }
            .foregroundStyle(settings.primaryText)
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }
        .preferredColorScheme(settings.theme == .blackWhite || settings.theme == .yellowBlack ? .dark : nil)
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .environmentObject(settings)
        }
        .confirmationDialog("结束本次字幕", isPresented: $showEndDialog, titleVisibility: .visible) {
            Button("保存文字记录") {
                do {
                    let url = try session.saveTranscriptToDocuments()
                    saveMessage = "已保存到本机：\(url.lastPathComponent)"
                    session.endSession(autoClear: false)
                } catch {
                    saveMessage = error.localizedDescription
                }
            }
            Button("不保存并清空", role: .destructive) {
                session.endSession(autoClear: true)
            }
            Button("暂时保留在屏幕") {
                session.endSession(autoClear: false)
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("默认不保存音频。文字可保留在本机，或立即清空。")
        }
        .alert("文字记录", isPresented: Binding(
            get: { saveMessage != nil },
            set: { if !$0 { saveMessage = nil } }
        )) {
            Button("好") {
                saveMessage = nil
            }
        } message: {
            Text(saveMessage ?? "")
        }
        .task {
            session.refreshPermissions()
        }
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(statusColor)
                .frame(width: 10, height: 10)

            Text(statusText)
                .font(.subheadline.weight(.semibold))
                .lineLimit(2)
                .minimumScaleFactor(0.72)

            Spacer()

            Button {
                showSettings = true
            } label: {
                Image(systemName: "textformat.size")
                    .font(.title3)
            }
            .accessibilityLabel("设置字号和主题")
        }
        .foregroundStyle(settings.secondaryText)
        .frame(height: 36)
    }

    private var portraitBody: some View {
        VStack(alignment: .leading, spacing: 18) {
            Spacer(minLength: 8)

            lyricCaptionView(fontSize: latestFontSize)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
    }

    private var landscapeBody: some View {
        lyricCaptionView(fontSize: latestFontSize + 10)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    private var hintView: some View {
        HStack(spacing: 10) {
            Image(systemName: "speaker.wave.2.fill")
            Text(session.noiseHint ?? "\(session.audioDebugText)，音量 \(inputPercent)%")
                .lineLimit(2)
                .minimumScaleFactor(0.8)
            Spacer()
            LevelMeter(level: session.inputLevel, tint: settings.primaryText)
                .frame(width: 72, height: 12)
        }
        .font(.callout.weight(.medium))
        .foregroundStyle(settings.secondaryText)
    }

    private var primaryControlBar: some View {
        HStack(spacing: 14) {
            Button {
                settings.landscapeMode.toggle()
            } label: {
                Label(settings.landscapeMode ? "竖屏" : "横屏", systemImage: "rectangle.rotate.90")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(CaptionButtonStyle())

            microphoneButton

            Button {
                showEndDialog = true
            } label: {
                Label("结束", systemImage: "xmark.circle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(CaptionButtonStyle())
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 10)
    }

    private func lyricCaptionView(fontSize: CGFloat) -> some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                VStack(spacing: 18) {
                    if lyricLines.isEmpty {
                        Text("请打开通话扬声器")
                            .font(.system(size: fontSize, weight: .bold, design: .rounded))
                            .foregroundStyle(settings.primaryText)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                    } else {
                        ForEach(lyricLines) { line in
                            Text(line.text)
                                .font(.system(size: fontSize, weight: .bold, design: .rounded))
                                .foregroundStyle(line.isCurrent ? settings.primaryText : settings.secondaryText)
                                .lineLimit(nil)
                                .fixedSize(horizontal: false, vertical: true)
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: .infinity)
                                .padding(.horizontal, line.isCurrent ? 18 : 0)
                                .padding(.vertical, line.isCurrent ? 12 : 0)
                                .background {
                                    if line.isCurrent {
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(translatingHighlightColor)
                                    }
                                }
                                .overlay {
                                    if line.isCurrent {
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(settings.primaryText.opacity(0.28), lineWidth: 1)
                                    }
                                }
                                .id(line.id)
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                                .animation(.easeInOut(duration: 0.18), value: line.text)
                        }
                    }

                    if case .failed(let message) = session.state {
                        Text(message)
                            .font(.system(size: fontSize * 0.64, weight: .bold, design: .rounded))
                            .foregroundStyle(.red)
                            .lineLimit(nil)
                            .fixedSize(horizontal: false, vertical: true)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                            .id("caption-error")
                    }

                    Color.clear
                        .frame(height: 1)
                        .id("lyric-caption-bottom")
                }
                .frame(maxWidth: .infinity, minHeight: 1, alignment: .center)
                .padding(.vertical, 12)
            }
            .scrollIndicators(.hidden)
            .onChange(of: lyricScrollKey) { _, _ in
                withAnimation(.easeOut(duration: 0.22)) {
                    proxy.scrollTo("lyric-caption-bottom", anchor: .bottom)
                }
            }
        }
    }

    private var lyricLines: [LyricCaptionLine] {
        var lines = session.lines.suffix(12).map {
            LyricCaptionLine(id: $0.id.uuidString, text: $0.text, isCurrent: false)
        }
        let currentText = session.partialText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !currentText.isEmpty {
            if let lastIndex = lines.indices.last, lines[lastIndex].text == currentText {
                lines[lastIndex] = LyricCaptionLine(
                    id: lines[lastIndex].id,
                    text: currentText,
                    isCurrent: true
                )
            } else {
                lines.append(LyricCaptionLine(
                    id: "current-\(currentText)",
                    text: currentText,
                    isCurrent: true
                ))
            }
        }
        return Array(lines.suffix(12))
    }

    private var lyricScrollKey: String {
        if case .failed(let message) = session.state {
            return "failed-\(message)"
        }
        return lyricLines.map { "\($0.id):\($0.text)" }.joined(separator: "|")
    }

    private var microphoneButton: some View {
        Button {
            session.toggleMicrophone()
        } label: {
            Image(systemName: primaryButtonIcon)
                .font(.system(size: 38, weight: .bold))
                .frame(width: 96, height: 96)
                .foregroundStyle(microphoneIconColor)
                .background(microphoneBackgroundColor, in: Circle())
                .overlay {
                    Circle()
                        .stroke(settings.primaryText.opacity(0.22), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.22), radius: 14, y: 8)
        }
        .buttonStyle(.plain)
        .disabled(session.state == .requestingPermission)
        .opacity(session.state == .requestingPermission ? 0.64 : 1)
        .accessibilityLabel(primaryButtonTitle)
    }

    private var latestFontSize: CGFloat {
        CGFloat(42 + settings.fontScale * 34)
    }

    private var statusText: String {
        switch session.state {
        case .idle: "待命"
        case .requestingPermission: "正在请求权限"
        case .listening: "正在实时字幕"
        case .paused: "麦克风已关闭"
        case .failed(let message): message
        }
    }

    private var statusColor: Color {
        switch session.state {
        case .listening: .green
        case .requestingPermission: .orange
        case .failed: .red
        default: settings.secondaryText
        }
    }

    private var primaryButtonTitle: String {
        switch session.state {
        case .requestingPermission: "启动中"
        case .listening: "麦克风关"
        default: "麦克风开"
        }
    }

    private var primaryButtonIcon: String {
        session.isMicrophoneEnabled ? "mic.fill" : "mic.slash.fill"
    }

    private var microphoneBackgroundColor: Color {
        switch session.state {
        case .listening:
            .green.opacity(0.26)
        case .requestingPermission:
            .orange.opacity(0.24)
        case .failed:
            .red.opacity(0.24)
        default:
            settings.primaryText.opacity(0.14)
        }
    }

    private var microphoneIconColor: Color {
        switch session.state {
        case .listening:
            .green
        case .requestingPermission:
            .orange
        case .failed:
            .red
        default:
            settings.primaryText
        }
    }

    private var isTranslatingText: Bool {
        !session.partialText.isEmpty
    }

    private var translatingHighlightColor: Color {
        switch settings.theme {
        case .yellowBlack:
            Color.white.opacity(0.18)
        case .whiteBlack:
            Color.yellow.opacity(0.36)
        default:
            Color.yellow.opacity(0.24)
        }
    }

    private var inputPercent: Int {
        Int((session.inputLevel * 100).rounded())
    }
}

private struct LyricCaptionLine: Identifiable, Equatable {
    let id: String
    let text: String
    let isCurrent: Bool
}

private struct CaptionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .padding(.horizontal, 14)
            .frame(height: 48)
            .background(.primary.opacity(configuration.isPressed ? 0.18 : 0.12), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct LevelMeter: View {
    var level: Float
    var tint: Color

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(tint.opacity(0.16))
                Capsule()
                    .fill(tint.opacity(0.72))
                    .frame(width: max(6, proxy.size.width * CGFloat(level)))
            }
        }
    }
}
