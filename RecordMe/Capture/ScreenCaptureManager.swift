import AVFoundation
import ScreenCaptureKit

enum RecordMeError: Error {
    case notRecording
    case exportFailed(String)
}

final class ScreenCaptureManager: NSObject {
    private var stream: SCStream?
    private var assetWriter: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var isRecording = false
    private var sessionStarted = false

    var intermediateFileURL: URL?
    private(set) var assetWriterExposed: AVAssetWriter?

    func startRecording(filter: SCContentFilter, sessionDir: URL) async throws {
        let fileURL = sessionDir.appendingPathComponent("intermediate.mp4")
        intermediateFileURL = fileURL

        let config = SCStreamConfiguration()
        let display = try await SCShareableContent.current.displays.first!
        config.width = display.width * 2
        config.height = display.height * 2
        config.minimumFrameInterval = CMTime(value: 1, timescale: 60)
        config.showsCursor = true
        config.capturesAudio = false

        let writer = try AVAssetWriter(url: fileURL, fileType: .mp4)
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: config.width,
            AVVideoHeightKey: config.height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: 120_000_000,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
            ],
        ]
        let vInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        vInput.expectsMediaDataInRealTime = true
        writer.add(vInput)

        assetWriter = writer
        assetWriterExposed = writer
        videoInput = vInput
        writer.startWriting()

        let s = SCStream(filter: filter, configuration: config, delegate: self)
        try s.addStreamOutput(self, type: .screen, sampleHandlerQueue: .global(qos: .userInitiated))
        try await s.startCapture()
        stream = s
        isRecording = true
    }

    func stopRecording() async throws -> URL {
        guard let stream, let writer = assetWriter else { throw RecordMeError.notRecording }
        isRecording = false
        try await stream.stopCapture()
        self.stream = nil
        videoInput?.markAsFinished()
        await writer.finishWriting()
        let url = writer.outputURL
        assetWriter = nil
        assetWriterExposed = nil
        videoInput = nil
        sessionStarted = false
        return url
    }
}

extension ScreenCaptureManager: SCStreamDelegate {
    func stream(_ stream: SCStream, didStopWithError error: Error) {
        print("ScreenCaptureManager: stream stopped with error: \(error)")
    }
}

extension ScreenCaptureManager: SCStreamOutput {
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard isRecording, type == .screen, let videoInput, videoInput.isReadyForMoreMediaData else { return }
        if !sessionStarted {
            let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            assetWriter?.startSession(atSourceTime: timestamp)
            sessionStarted = true
        }
        videoInput.append(sampleBuffer)
    }
}
