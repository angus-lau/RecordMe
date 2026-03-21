import AVFoundation

final class AudioCaptureManager {
    private let engine = AVAudioEngine()
    private var audioFile: AVAudioFile?
    private var isRecording = false

    /// Records mic audio to a separate WAV file in the session directory.
    /// This avoids the fragile CMSampleBuffer conversion — we merge audio during export.
    var audioFileURL: URL?

    func startCapture(sessionDir: URL) throws {
        // Check mic permission first
        guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else { return }

        let fileURL = sessionDir.appendingPathComponent("mic.wav")
        audioFileURL = fileURL

        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)

        // Create audio file for writing
        audioFile = try AVAudioFile(forWriting: fileURL, settings: format.settings)

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, _ in
            guard let self, self.isRecording else { return }
            try? self.audioFile?.write(from: buffer)
        }

        engine.prepare()
        try engine.start()
        isRecording = true
    }

    func stopCapture() {
        guard isRecording else { return }
        isRecording = false
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        audioFile = nil
    }
}
