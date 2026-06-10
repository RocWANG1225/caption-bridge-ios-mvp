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

    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh_CN"))
    private let audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var silenceSamples = 0
    private var isStoppingIntentionally = false

    var latestText: String {
        if !partialText.isEmpty {
            return partialText
        }
        return lines.last?.text ?? "请打开通话扬声器"
    }

    var recentLines: [TranscriptLine] {
        Array(lines.suffix(4).reversed())
    }

    func requestAutoStart() {
        Task {
            await start()
        }
    }

    func start() async {
        guard state != .listening else { return }
        state = .requestingPermission

        do {
            try await requestPermissions()
            try startRecognition()
            UIApplication.shared.isIdleTimerDisabled = true
            state = .listening
        } catch {
            state = .failed(error.localizedDescription)
            UIApplication.shared.isIdleTimerDisabled = false
        }
    }

    func pause() {
        stopAudio(keepText: true)
        state = .paused
    }

    func resume() {
        Task {
            await start()
        }
    }

    func endSession(autoClear: Bool) {
        stopAudio(keepText: !autoClear)
        if autoClear {
            clear()
        }
        state = .idle
    }

    func clear() {
        lines.removeAll()
        partialText = ""
        noiseHint = nil
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
        let speechAllowed = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }

        guard speechAllowed else {
            throw CaptionError.permissionDenied("需要允许语音识别权限，才能生成实时字幕。")
        }

        let microphoneAllowed = await withCheckedContinuation { continuation in
            AVAudioSession.sharedInstance().requestRecordPermission { allowed in
                continuation.resume(returning: allowed)
            }
        }
        guard microphoneAllowed else {
            throw CaptionError.permissionDenied("需要允许麦克风权限，才能听到外放声音。")
        }
    }

    private func startRecognition() throws {
        stopAudio(keepText: true)
        isStoppingIntentionally = false

        guard let speechRecognizer, speechRecognizer.isAvailable else {
            throw CaptionError.recognizerUnavailable
        }

        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker, .allowBluetooth])
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        if #available(iOS 16.0, *) {
            request.addsPunctuation = true
        }
        recognitionRequest = request

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
            Task { @MainActor in
                self?.updateInputLevel(from: buffer)
            }
        }

        audioEngine.prepare()
        try audioEngine.start()

        recognitionTask = speechRecognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor in
                guard let self else { return }
                if let result {
                    self.handleRecognition(result)
                }
                if let error, !self.isStoppingIntentionally {
                    self.state = .failed(error.localizedDescription)
                    self.stopAudio(keepText: true)
                }
            }
        }
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

        if silenceSamples > 80 {
            noiseHint = "声音较小，请确认已打开扬声器并靠近手机"
        } else if inputLevel > 0.86 {
            noiseHint = "环境声较大，字幕可能不准"
        } else {
            noiseHint = nil
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
        audioEngine.inputNode.removeTap(onBus: 0)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        UIApplication.shared.isIdleTimerDisabled = false

        if !partialText.isEmpty && keepText {
            appendFinal(partialText)
        }
        partialText = ""
    }
}

enum CaptionError: LocalizedError {
    case permissionDenied(String)
    case recognizerUnavailable
    case emptyTranscript

    var errorDescription: String? {
        switch self {
        case .permissionDenied(let message): message
        case .recognizerUnavailable: "当前设备暂时无法使用普通话语音识别。"
        case .emptyTranscript: "当前没有可保存的字幕文字。"
        }
    }
}
