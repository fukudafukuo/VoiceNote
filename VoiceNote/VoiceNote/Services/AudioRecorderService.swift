import AVFoundation
import Foundation

@Observable
final class AudioRecorderService {

    private(set) var isRecording = false
    private(set) var duration: TimeInterval = 0

    private let engine = AVAudioEngine()
    private var audioFile: AVAudioFile?
    private var tempFileURL: URL?
    private var recordingStartTime: Date?
    private var durationTimer: Timer?

    private let sampleRate: Double = 16000
    private let channels: AVAudioChannelCount = 1

    func start() throws {
        guard !isRecording else { return }

        let tempDir = FileManager.default.temporaryDirectory
        let filename = "voicenote_\(Int(Date().timeIntervalSince1970)).wav"
        let url = tempDir.appendingPathComponent(filename)
        tempFileURL = url

        let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: channels,
            interleaved: false
        )!

        audioFile = try AVAudioFile(
            forWriting: url,
            settings: format.settings,
            commonFormat: .pcmFormatFloat32,
            interleaved: false
        )

        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        guard let converter = AVAudioConverter(from: inputFormat, to: format) else {
            throw AudioRecorderError.converterFailed
        }

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            guard let self, let audioFile = self.audioFile else { return }

            let ratio = self.sampleRate / inputFormat.sampleRate
            let outputFrameCount = AVAudioFrameCount(Double(buffer.frameLength) * ratio)

            guard let convertedBuffer = AVAudioPCMBuffer(
                pcmFormat: format,
                frameCapacity: outputFrameCount
            ) else { return }

            var error: NSError?
            let status = converter.convert(to: convertedBuffer, error: &error) { _, outStatus in
                outStatus.pointee = .haveData
                return buffer
            }

            if status == .haveData || status == .inputRanDry {
                try? audioFile.write(from: convertedBuffer)
            }
        }

        try engine.start()
        isRecording = true
        recordingStartTime = Date()
        duration = 0

        durationTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self, let start = self.recordingStartTime else { return }
            self.duration = Date().timeIntervalSince(start)
        }
    }

    func stop() -> URL? {
        guard isRecording else { return nil }

        durationTimer?.invalidate()
        durationTimer = nil

        engine.inputNode.removeTap(onBus: 0)
        engine.stop()

        audioFile = nil
        isRecording = false

        return tempFileURL
    }

    static func cleanup(_ url: URL?) {
        guard let url else { return }
        try? FileManager.default.removeItem(at: url)
    }
}

enum AudioRecorderError: LocalizedError {
    case converterFailed

    var errorDescription: String? {
        switch self {
        case .converterFailed:
            return "オーディオフォーマット変換器の作成に失敗しました"
        }
    }
}
