import AVFoundation
import Combine
import Speech
import UIKit

@MainActor
final class CaptionSession: ObservableObject {
    enum State: Equatable {
        case idle
        case requestingPermission
        case listening
        case paused
        case failed(String)
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var lines: [TranscriptLine] = []
    @Published private(set) var partialText = ""
    @Published private(set) var inputLevel: Float = 0
    @Published private(set) var noiseHint: String?
    @Published private(set) var permissionStatusText = "点击开始后允许麦克风和语音识别"
    @Published private(set) var canAutoStart = false
    @Published private(set) var audioDebugText = "麦克风待命"
    @Published private(set) var isMicrophoneEnabled = false

    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh_CN"))
    private let audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var silenceSamples = 0
    private var isStoppingIntentionally = false
    private var loudSamples = 0
    private var startTask: Task<Void, Never>?
    private var isInputTapInstalled = false
    private let audioSessionAttempts: [AudioSessionAttempt] = [
        AudioSessionAttempt(
            name: "外放监听",
            category: .playAndRecord,
            mode: .measurement,
            options: [.defaultToSpeaker, .mixWithOthers],
            tuneForSpeech: true
        ),
        AudioSessionAttempt(
            name: "兼容监听",
            category: .playAndRecord,
            mode: .default,
            options: [.defaultToSpeaker, .mixWithOthers],
            tuneForSpeech: false
        ),
        AudioSessionAttempt(
            name: "纯麦克风",
            category: .record,
            mode: .measurement,
            options: [],
            tuneForSpeech: true
        ),
        AudioSessionAttempt(
            name: "基础麦克风",
            category: .record,
            mode: .default,
            options: [],
            tuneForSpeech: false
        )
    ]

    var latestText: String {
        if case .failed(let message) = state {
            return message
        }
        if !partialText.isEmpty {
            return partialText
        }
        return lines.last?.text ?? "请打开通话扬声器"
    }

    var recentLines: [TranscriptLine] {
        Array(lines.suffix(20))
    }

    func requestAutoStart() {
        guard startTask == nil else { return }
        startTask = Task {
            await start()
            startTask = nil
        }
    }

    func toggleMicrophone() {
        switch state {
        case .listening:
            turnMicrophoneOff()
        case .requestingPermission:
            break
        case .idle, .paused, .failed:
            requestAutoStart()
        }
    }

    func refreshPermissions() {
        let microphoneReady = microphonePermissionGranted()
        let speechReady = SFSpeechRecognizer.authorizationStatus() == .authorized
        canAutoStart = microphoneReady && speechReady

        switch (microphoneReady, speechReady) {
        case (true, true):
            permissionStatusText = "权限已开启，可以开始字幕"
        case (false, true):
            permissionStatusText = "需要开启麦克风权限"
        case (true, false):
            permissionStatusText = "需要开启语音识别权限"
        case (false, false):
            permissionStatusText = "需要开启麦克风和语音识别权限"
        }
    }

    func start() async {
        guard state != .listening, state != .requestingPermission else { return }
        state = .requestingPermission

        do {
            try await requestPermissions()
            refreshPermissions()
            try startRecognition()
            UIApplication.shared.isIdleTimerDisabled = true
            isMicrophoneEnabled = true
            state = .listening
        } catch {
            stopAudio(keepText: true)
            state = .failed("启动失败：\(error.localizedDescription)")
            isMicrophoneEnabled = false
            UIApplication.shared.isIdleTimerDisabled = false
        }
    }

    func pause() {
        turnMicrophoneOff()
    }

    func resume() {
        Task {
            await start()
        }
    }

    func turnMicrophoneOff() {
        startTask?.cancel()
        startTask = nil
        stopAudio(keepText: true)
        isMicrophoneEnabled = false
        inputLevel = 0
        noiseHint = nil
        audioDebugText = "麦克风已关闭"
        state = .paused
    }

    func endSession(autoClear: Bool) {
        stopAudio(keepText: !autoClear)
        if autoClear {
            clear()
        }
        isMicrophoneEnabled = false
        inputLevel = 0
        state = .idle
    }

    func clear() {
        lines.removeAll()
        partialText = ""
        noiseHint = nil
        audioDebugText = "麦克风待命"
    }

    func exportTranscript() -> String {
        lines.map { $0.text }.joined(separator: "\n")
    }

    func saveTranscriptToDocuments() throws -> URL {
        let transcript = exportTranscript()
        guard !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw CaptionError.emptyTranscript
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let fileName = "实时字幕-\(formatter.string(from: Date())).txt"
        let documents = try FileManager.default.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let url = documents.appendingPathComponent(fileName)
        try transcript.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func requestPermissions() async throws {
        let microphoneAllowed = await requestMicrophonePermission()
        refreshPermissions()
        guard microphoneAllowed else {
            throw CaptionError.permissionDenied("需要允许麦克风权限，才能听到外放声音。")
        }

        let speechAllowed = await requestSpeechPermission()
        refreshPermissions()
        guard speechAllowed else {
            throw CaptionError.permissionDenied("需要允许语音识别权限，才能生成实时字幕。")
        }
    }

    private func microphonePermissionGranted() -> Bool {
        AVAudioApplication.shared.recordPermission == .granted
    }

    private func requestMicrophonePermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { allowed in
                continuation.resume(returning: allowed)
            }
        }
    }

    private func requestSpeechPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }

    private func startRecognition() throws {
        stopAudioIfNeeded(keepText: true)
        isStoppingIntentionally = false
        loudSamples = 0
        silenceSamples = 0

        guard let speechRecognizer, speechRecognizer.isAvailable else {
            throw CaptionError.recognizerUnavailable
        }

        try configureAudioSessionForSpeakerListening()

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.taskHint = .dictation
        if #available(iOS 16.0, *) {
            request.addsPunctuation = true
        }
        recognitionRequest = request

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        removeInputTapIfNeeded()
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
            Task { @MainActor in
                self?.updateInputLevel(from: buffer)
            }
        }
        isInputTapInstalled = true

        audioEngine.prepare()
        try audioEngine.start()

        recognitionTask = speechRecognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor in
                guard let self else { return }
                if let result {
                    self.handleRecognition(result)
                }
                if let error, !self.isStoppingIntentionally {
                    self.stopAudio(keepText: true)
                    self.isMicrophoneEnabled = false
                    self.state = .failed("识别失败：\(error.localizedDescription)")
                }
            }
        }
    }

    private func configureAudioSessionForSpeakerListening() throws {
        let audioSession = AVAudioSession.sharedInstance()
        var lastError: Error?

        for attempt in audioSessionAttempts {
            do {
                try? audioSession.setActive(false, options: .notifyOthersOnDeactivation)
                try audioSession.setCategory(attempt.category, mode: attempt.mode, options: attempt.options)

                if attempt.tuneForSpeech {
                    try? audioSession.setPreferredSampleRate(16_000)
                    try? audioSession.setPreferredIOBufferDuration(0.02)
                }

                try audioSession.setActive(true)

                if let builtInMic = audioSession.availableInputs?.first(where: { $0.portType == .builtInMic }) {
                    try? audioSession.setPreferredInput(builtInMic)
                }

                updateAudioRouteDebug(prefix: attempt.name)
                return
            } catch {
                lastError = error
            }
        }

        throw CaptionError.audioSessionActivationFailed(lastError?.localizedDescription ?? "系统拒绝启动麦克风")
    }

    private func handleRecognition(_ result: SFSpeechRecognitionResult) {
        let text = result.bestTranscription.formattedString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        if result.isFinal {
            appendFinal(text)
            partialText = ""
        } else {
            partialText = text
        }
    }

    private func appendFinal(_ text: String) {
        if lines.last?.text == text { return }
        lines.append(TranscriptLine(text: text, date: Date(), isFinal: true))
        if lines.count > 80 {
            lines.removeFirst(lines.count - 80)
        }
    }

    private func updateInputLevel(from buffer: AVAudioPCMBuffer) {
        guard let channel = buffer.floatChannelData?[0] else { return }
        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0 else { return }

        var sum: Float = 0
        for index in 0..<frameLength {
            sum += abs(channel[index])
        }
        let average = sum / Float(frameLength)
        inputLevel = min(1, average * 24)

        if inputLevel < 0.03 {
            silenceSamples += 1
        } else {
            silenceSamples = 0
        }

        if inputLevel > 0.10 {
            loudSamples += 1
        }

        if silenceSamples > 80 {
            noiseHint = "麦克风几乎没收到声音，请确认外放并靠近另一台设备"
        } else if inputLevel > 0.86 {
            noiseHint = "环境声较大，字幕可能不准"
        } else if loudSamples > 50 && partialText.isEmpty && lines.isEmpty {
            noiseHint = "已听到声音，正在识别；请尽量使用普通话并保持外放清晰"
        } else {
            noiseHint = nil
        }

        updateAudioRouteDebug()
    }

    private func updateAudioRouteDebug(prefix: String? = nil) {
        let route = AVAudioSession.sharedInstance().currentRoute
        let inputName = route.inputs.first?.portName ?? "无输入"
        let inputType = route.inputs.first?.portType.rawValue ?? "unknown"
        if let prefix {
            audioDebugText = "\(prefix)：\(inputName) / \(inputType)"
        } else {
            audioDebugText = "输入：\(inputName) / \(inputType)"
        }
    }

    private func stopAudio(keepText: Bool) {
        isStoppingIntentionally = true
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest?.endAudio()
        recognitionRequest = nil

        if audioEngine.isRunning {
            audioEngine.stop()
        }
        removeInputTapIfNeeded()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        UIApplication.shared.isIdleTimerDisabled = false

        if !partialText.isEmpty && keepText {
            appendFinal(partialText)
        }
        partialText = ""
    }

    private func stopAudioIfNeeded(keepText: Bool) {
        guard recognitionTask != nil || recognitionRequest != nil || audioEngine.isRunning || isInputTapInstalled else {
            return
        }
        stopAudio(keepText: keepText)
    }

    private func removeInputTapIfNeeded() {
        guard isInputTapInstalled else { return }
        audioEngine.inputNode.removeTap(onBus: 0)
        isInputTapInstalled = false
    }
}

private struct AudioSessionAttempt {
    let name: String
    let category: AVAudioSession.Category
    let mode: AVAudioSession.Mode
    let options: AVAudioSession.CategoryOptions
    let tuneForSpeech: Bool
}

enum CaptionError: LocalizedError {
    case permissionDenied(String)
    case recognizerUnavailable
    case emptyTranscript
    case audioSessionActivationFailed(String)

    var errorDescription: String? {
        switch self {
        case .permissionDenied(let message): message
        case .recognizerUnavailable: "当前设备暂时无法使用普通话语音识别。"
        case .emptyTranscript: "当前没有可保存的字幕文字。"
        case .audioSessionActivationFailed(let detail):
            "麦克风启动失败。本机如果正在电话或微信通话，iOS 可能正在占用麦克风；请让字幕手机不要加入通话，只靠近另一台手机的扬声器。系统信息：\(detail)"
        }
    }
}
