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
    private var sessionDir: URL?

    var intermediateFileURL: URL?
    /// Screen size in points (for coordinate normalization)
    private(set) var screenPointSize: CGSize = .zero

    func startRecording(filter: SCContentFilter, sessionDir: URL) async throws {
        let fileURL = sessionDir.appendingPathComponent("intermediate.mp4")
        intermediateFileURL = fileURL
        self.sessionDir = sessionDir

        // Get actual screen dimensions for capture
        guard let screen = NSScreen.main else {
            throw RecordMeError.exportFailed("No screen found")
        }
        let scale = screen.backingScaleFactor
        let pixelWidth = Int(screen.frame.width * scale)
        let pixelHeight = Int(screen.frame.height * scale)
        screenPointSize = screen.frame.size

        // Configure stream with native retina resolution
        let config = SCStreamConfiguration()
        config.width = pixelWidth
        config.height = pixelHeight
        config.minimumFrameInterval = CMTime(value: 1, timescale: 60)
        config.showsCursor = true
        config.capturesAudio = false
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.queueDepth = 8

        let s = SCStream(filter: filter, configuration: config, delegate: self)
        try s.addStreamOutput(self, type: .screen, sampleHandlerQueue: .global(qos: .userInitiated))
        try await s.startCapture()
        stream = s
        lock.lock()
        isRecording = true
        lock.unlock()
    }

    func stopRecording() async throws -> URL {
        guard let stream, let writer = assetWriter else {
            // If writer was never created (no frames), return the file URL anyway
            lock.lock()
            isRecording = false
            lock.unlock()
            if let s = self.stream {
                try await s.stopCapture()
                self.stream = nil
            }
            throw RecordMeError.notRecording
        }
        lock.lock()
        isRecording = false
        lock.unlock()
        try await stream.stopCapture()
        self.stream = nil

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
        videoInput = nil
        pixelBufferAdaptor = nil
        return url
    }

    /// Create the AVAssetWriter lazily on the first frame — so we know the exact dimensions
    private func setupWriter(width: Int, height: Int) {
        guard let fileURL = intermediateFileURL, assetWriter == nil else { return }

        do {
            let writer = try AVAssetWriter(url: fileURL, fileType: .mp4)

            let videoSettings: [String: Any] = [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: width,
                AVVideoHeightKey: height,
                AVVideoCompressionPropertiesKey: [
                    AVVideoAverageBitRateKey: 120_000_000,
                ],
            ]

            let vInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
            vInput.expectsMediaDataInRealTime = true

            let adaptorAttrs: [String: Any] = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: width,
                kCVPixelBufferHeightKey as String: height,
            ]
            let adaptor = AVAssetWriterInputPixelBufferAdaptor(
                assetWriterInput: vInput,
                sourcePixelBufferAttributes: adaptorAttrs
            )

            writer.add(vInput)
            writer.startWriting()

            assetWriter = writer
            videoInput = vInput
            pixelBufferAdaptor = adaptor
        } catch {
            // Writer setup failed — frames will be silently dropped
        }
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

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        guard timestamp.isValid && timestamp.isNumeric else { return }

        // Lazily create writer with actual frame dimensions
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        if assetWriter == nil {
            setupWriter(width: width, height: height)
        }

        guard let videoInput, videoInput.isReadyForMoreMediaData else { return }

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
