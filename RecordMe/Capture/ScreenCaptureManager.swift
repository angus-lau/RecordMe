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
    private let lock = NSLock()

    var intermediateFileURL: URL?
    private(set) var assetWriterExposed: AVAssetWriter?
    /// Screen size in points (for coordinate normalization — cursor events are in point space)
    private(set) var screenPointSize: CGSize = .zero

    func startRecording(filter: SCContentFilter, sessionDir: URL, pixelSize: CGSize, pointSize: CGSize) async throws {
        let fileURL = sessionDir.appendingPathComponent("intermediate.mp4")
        intermediateFileURL = fileURL

        let captureWidth = Int(pixelSize.width)
        let captureHeight = Int(pixelSize.height)
        screenPointSize = pointSize

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
        lock.lock()
        isRecording = true
        lock.unlock()
    }

    func stopRecording() async throws -> URL {
        guard let stream, let writer = assetWriter else { throw RecordMeError.notRecording }
        lock.lock()
        isRecording = false
        lock.unlock()
        try await stream.stopCapture()
        self.stream = nil

        // Only finish writing if the session actually started (frames were received)
        lock.lock()
        let started = sessionStarted
        sessionStarted = false
        lock.unlock()

        if started && writer.status == .writing {
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
        lock.lock()
        let recording = isRecording
        lock.unlock()
        guard recording, type == .screen else { return }
        guard let videoInput, videoInput.isReadyForMoreMediaData else { return }

        // ScreenCaptureKit provides IOSurface-backed buffers — extract the pixel buffer
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)

        // Skip invalid timestamps
        guard timestamp.isValid && timestamp.isNumeric else { return }

        lock.lock()
        let started = sessionStarted
        if !started {
            sessionStarted = true
        }
        lock.unlock()

        if !started {
            assetWriter?.startSession(atSourceTime: timestamp)
        }

        pixelBufferAdaptor?.append(pixelBuffer, withPresentationTime: timestamp)
    }
}
