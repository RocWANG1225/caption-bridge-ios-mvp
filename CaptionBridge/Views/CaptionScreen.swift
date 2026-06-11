import SwiftUI

struct CaptionScreen: View {
    @EnvironmentObject private var session: CaptionSession
    @EnvironmentObject private var settings: CaptionSettings
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

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

                controlBar
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
            if case .idle = session.state, session.canAutoStart {
                await session.start()
            }
        }
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(statusColor)
                .frame(width: 10, height: 10)

            Text(statusText)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)

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

            Text(session.latestText)
                .font(.system(size: latestFontSize, weight: .bold, design: .rounded))
                .minimumScaleFactor(0.38)
                .lineLimit(5)
                .frame(maxWidth: .infinity, minHeight: 260, alignment: .center)
                .multilineTextAlignment(.center)

            permissionView

            hintView

            recentList
                .frame(maxHeight: 180)
        }
    }

    private var landscapeBody: some View {
        HStack(spacing: 22) {
            VStack(spacing: 16) {
                Text(session.latestText)
                    .font(.system(size: latestFontSize + 10, weight: .bold, design: .rounded))
                    .minimumScaleFactor(0.34)
                    .lineLimit(4)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    .multilineTextAlignment(.center)

                permissionView

                hintView
            }

            recentList
                .frame(width: horizontalSizeClass == .regular ? 340 : 260)
        }
    }

    private var recentList: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(session.recentLines) { line in
                Text(line.text)
                    .font(.system(size: recentFontSize, weight: .semibold, design: .rounded))
                    .foregroundStyle(settings.secondaryText)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var permissionView: some View {
        if !session.canAutoStart && session.state != .listening {
            VStack(spacing: 12) {
                Text(session.permissionStatusText)
                    .font(.title3.weight(.semibold))
                    .multilineTextAlignment(.center)

                Button {
                    session.requestAutoStart()
                } label: {
                    Label("启用麦克风和语音识别", systemImage: "mic.badge.plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(CaptionButtonStyle())
            }
            .padding(16)
            .background(.primary.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private var hintView: some View {
        HStack(spacing: 10) {
            Image(systemName: "speaker.wave.2.fill")
            Text(session.noiseHint ?? "请打开电话或微信扬声器，手机靠近外放声音")
                .lineLimit(2)
                .minimumScaleFactor(0.8)
            Spacer()
            LevelMeter(level: session.inputLevel, tint: settings.primaryText)
                .frame(width: 72, height: 12)
        }
        .font(.callout.weight(.medium))
        .foregroundStyle(settings.secondaryText)
    }

    private var controlBar: some View {
        HStack(spacing: 12) {
            Button {
                switch session.state {
                case .listening:
                    session.pause()
                case .paused, .idle, .failed:
                    session.requestAutoStart()
                case .requestingPermission:
                    break
                }
            } label: {
                Label(primaryButtonTitle, systemImage: primaryButtonIcon)
            }
            .buttonStyle(CaptionButtonStyle())

            Button {
                settings.landscapeMode.toggle()
            } label: {
                Label(settings.landscapeMode ? "竖屏" : "横屏", systemImage: "rectangle.rotate.90")
            }
            .buttonStyle(CaptionButtonStyle())

            Button {
                showEndDialog = true
            } label: {
                Label("结束", systemImage: "xmark.circle")
            }
            .buttonStyle(CaptionButtonStyle())
        }
        .padding(.top, 12)
    }

    private var latestFontSize: CGFloat {
        CGFloat(42 + settings.fontScale * 34)
    }

    private var recentFontSize: CGFloat {
        CGFloat(18 + settings.fontScale * 8)
    }

    private var statusText: String {
        switch session.state {
        case .idle: "待命"
        case .requestingPermission: "正在请求权限"
        case .listening: "正在实时字幕"
        case .paused: "已暂停"
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
        case .listening: "暂停"
        case .requestingPermission: "启动中"
        default: "开始"
        }
    }

    private var primaryButtonIcon: String {
        session.state == .listening ? "pause.fill" : "mic.fill"
    }
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
