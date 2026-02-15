import AVFoundation
import Foundation

@Observable
final class AudioRecorderService {

    private(set) var isRecording = false
    private(set) var duration: TimeInterval = 0

    /// ストリーミング認識用: 音声バッファをリアルタイムで転送するコールバック
    var onAudioBuffer: ((AVAudioPCMBuffer) -> Void)?

    /// false にするとWAVファイル書き込みをスキップ（ストリーミング時）
    var writeToFile: Bool = true

    private let engine = AVAudioEngine()
    private var audioFile: AVAudioFile?
    private var tempFileURL: URL?
    private var recordingStartTime: Date?
    private var durationTimer: Timer?

    private let sampleRate: Double = 16000
    private let channels: AVAudioChannelCount = 1

    func start() throws {
        guard !isRecording else { return }

        // ファイルベース時のみWAVファイルを作成
        if writeToFile {
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
        } else {
            tempFileURL = nil
            audioFile = nil
        }

        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        // ファイルベース用の変換器（writeToFile時のみ使用）
        let converter: AVAudioConverter?
        let outputFormat: AVAudioFormat?
        if writeToFile {
            let fmt = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: sampleRate,
                channels: channels,
                interleaved: false
            )!
            outputFormat = fmt
            converter = AVAudioConverter(from: inputFormat, to: fmt)
            guard converter != nil else {
                throw AudioRecorderError.converterFailed
            }
        } else {
            converter = nil
            outputFormat = nil
        }

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            guard let self else { return }

            // ストリーミング: ネイティブフォーマットのバッファをそのまま転送（軽い処理のみ）
            self.onAudioBuffer?(buffer)

            // ファイルベース: 16kHz mono に変換して書き込み
            if self.writeToFile, let audioFile = self.audioFile,
               let converter, let outputFormat {
                let ratio = self.sampleRate / inputFormat.sampleRate
                let outputFrameCount = AVAudioFrameCount(Double(buffer.frameLength) * ratio)

                guard let convertedBuffer = AVAudioPCMBuffer(
                    pcmFormat: outputFormat,
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
