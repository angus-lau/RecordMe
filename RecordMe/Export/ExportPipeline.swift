import AVFoundation
import CoreVideo

final class ExportPipeline: ObservableObject {
    @Published var progress: Double = 0.0
    @Published var isExporting = false

    private let renderer = MetalZoomRenderer()

    func export(
        intermediateURL: URL,
        outputURL: URL,
        timeline: ZoomTimeline,
        preset: ExportPreset,
        sourceSize: CGSize
    ) async throws {
        await MainActor.run { isExporting = true; progress = 0.0 }

        let asset = AVAsset(url: intermediateURL)
        let duration = try await asset.load(.duration)
        let durationSeconds = CMTimeGetSeconds(duration)

        let reader = try AVAssetReader(asset: asset)

        let videoTrack = try await asset.loadTracks(withMediaType: .video).first!
        let readerVideoOutput = AVAssetReaderTrackOutput(
            track: videoTrack,
            outputSettings: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            ]
        )
        reader.add(readerVideoOutput)

        var readerAudioOutput: AVAssetReaderTrackOutput?
        if let audioTrack = try? await asset.loadTracks(withMediaType: .audio).first {
            let audioOutput = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: nil)
            reader.add(audioOutput)
            readerAudioOutput = audioOutput
        }

        let writer = try AVAssetWriter(url: outputURL, fileType: .mp4)

        let videoSettings: [String: Any] = [
            AVVideoCodecKey: preset.codec.avCodecType,
            AVVideoWidthKey: preset.width,
            AVVideoHeightKey: preset.height,
        ]
        let writerVideoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        writerVideoInput.expectsMediaDataInRealTime = false

        let pixelBufferAdaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: writerVideoInput,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: preset.width,
                kCVPixelBufferHeightKey as String: preset.height,
            ]
        )
        writer.add(writerVideoInput)

        var writerAudioInput: AVAssetWriterInput?
        if readerAudioOutput != nil {
            let audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: nil)
            audioInput.expectsMediaDataInRealTime = false
            writer.add(audioInput)
            writerAudioInput = audioInput
        }

        reader.startReading()
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        while let sampleBuffer = readerVideoOutput.copyNextSampleBuffer() {
            let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            let seconds = CMTimeGetSeconds(timestamp)

            guard let sourcePixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { continue }

            let zoomState = timeline.zoomState(at: seconds)

            var destPixelBuffer: CVPixelBuffer?
            guard let pool = pixelBufferAdaptor.pixelBufferPool else { continue }
            CVPixelBufferPoolCreatePixelBuffer(nil, pool, &destPixelBuffer)
            guard let dest = destPixelBuffer else { continue }

            renderer.render(
                source: sourcePixelBuffer,
                destination: dest,
                zoomState: zoomState,
                sourceSize: sourceSize
            )

            while !writerVideoInput.isReadyForMoreMediaData {
                try await Task.sleep(nanoseconds: 10_000_000)
            }
            pixelBufferAdaptor.append(dest, withPresentationTime: timestamp)

            await MainActor.run { progress = seconds / durationSeconds }
        }

        if let audioOutput = readerAudioOutput, let audioInput = writerAudioInput {
            while let sampleBuffer = audioOutput.copyNextSampleBuffer() {
                while !audioInput.isReadyForMoreMediaData {
                    try await Task.sleep(nanoseconds: 10_000_000)
                }
                audioInput.append(sampleBuffer)
            }
            audioInput.markAsFinished()
        }

        writerVideoInput.markAsFinished()
        await writer.finishWriting()
        reader.cancelReading()

        await MainActor.run { progress = 1.0; isExporting = false }
    }
}
