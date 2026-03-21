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
    private var pixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor?
    private var isRecording = false
    private var sessionStarted = false

    var intermediateFileURL: URL?
    private(set) var assetWriterExposed: AVAssetWriter?

    func startRecording(filter: SCContentFilter, sessionDir: URL) async throws {
        let fileURL = sessionDir.appendingPathComponent("intermediate.mp4")
        intermediateFileURL = fileURL

        // Get display info for dimensions
        let content = try await SCShareableContent.current
        let display = content.displays.first!
        let scaleFactor = Int(NSScreen.main?.backingScaleFactor ?? 2)
        let captureWidth = display.width * scaleFactor
        let captureHeight = display.height * scaleFactor

        // Configure stream
        let config = SCStreamConfiguration()
        config.width = captureWidth
        config.height = captureHeight
        config.minimumFrameInterval = CMTime(value: 1, timescale: 60)
        config.showsCursor = true
        config.capturesAudio = false
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.queueDepth = 8  // larger buffer to prevent frame drops

        // Configure AVAssetWriter
        let writer = try AVAssetWriter(url: fileURL, fileType: .mp4)

        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: captureWidth,
            AVVideoHeightKey: captureHeight,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: 120_000_000,
            ],
        ]

        let vInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        vInput.expectsMediaDataInRealTime = true

        // Use pixel buffer adaptor to handle format conversion
        let adaptorAttrs: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: captureWidth,
            kCVPixelBufferHeightKey as String: captureHeight,
        ]
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: vInput,
            sourcePixelBufferAttributes: adaptorAttrs
        )

        writer.add(vInput)

        assetWriter = writer
        assetWriterExposed = writer
        videoInput = vInput
        pixelBufferAdaptor = adaptor
        writer.startWriting()

        // Start capture stream
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

        // Only finish writing if the session actually started (frames were received)
        if sessionStarted && writer.status == .writing {
            videoInput?.markAsFinished()
            await writer.finishWriting()
        } else {
            writer.cancelWriting()
        }

        let url = writer.outputURL
        assetWriter = nil
        assetWriterExposed = nil
        videoInput = nil
        pixelBufferAdaptor = nil
        sessionStarted = false
        return url
    }
}

extension ScreenCaptureManager: SCStreamDelegate {
    func stream(_ stream: SCStream, didStopWithError error: Error) {
        // Stream interrupted — expected when stopping recording or on permission issues
    }
}

extension ScreenCaptureManager: SCStreamOutput {
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard isRecording, type == .screen else { return }
        guard let videoInput, videoInput.isReadyForMoreMediaData else { return }

        // ScreenCaptureKit provides IOSurface-backed buffers — extract the pixel buffer
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)

        // Skip invalid timestamps
        guard timestamp.isValid && timestamp.isNumeric else { return }

        if !sessionStarted {
            assetWriter?.startSession(atSourceTime: timestamp)
            sessionStarted = true
        }

        pixelBufferAdaptor?.append(pixelBuffer, withPresentationTime: timestamp)
    }
}
