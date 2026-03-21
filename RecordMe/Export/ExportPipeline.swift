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
        sourceSize: CGSize,
        trimStart: Double = 0,
        trimEnd: Double? = nil
    ) async throws {
        await MainActor.run { isExporting = true; progress = 0.0 }

        let asset = AVAsset(url: intermediateURL)
        let duration = try await asset.load(.duration)
        let durationSeconds = CMTimeGetSeconds(duration)
        let effectiveTrimEnd = trimEnd ?? durationSeconds
        let trimmedDuration = effectiveTrimEnd - trimStart
        guard trimmedDuration > 0 else { throw RecordMeError.exportFailed("Trim range is empty") }

        let reader = try AVAssetReader(asset: asset)

        // Set time range for trimming
        let startCMTime = CMTime(seconds: trimStart, preferredTimescale: 600)
        let rangeDuration = CMTime(seconds: trimmedDuration, preferredTimescale: 600)
        reader.timeRange = CMTimeRange(start: startCMTime, duration: rangeDuration)

        guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first else {
            throw RecordMeError.exportFailed("No video track")
        }
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

            // Use original timestamp for zoom state lookup (matches event log times)
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

            // Offset timestamp so trimmed output starts at 0
            let outputTime = CMTime(seconds: seconds - trimStart, preferredTimescale: 600)

            while !writerVideoInput.isReadyForMoreMediaData {
                try await Task.sleep(nanoseconds: 10_000_000)
            }
            pixelBufferAdaptor.append(dest, withPresentationTime: outputTime)

            let elapsed = seconds - trimStart
            await MainActor.run { progress = elapsed / trimmedDuration }
        }

        if let audioOutput = readerAudioOutput, let audioInput = writerAudioInput {
            while let sampleBuffer = audioOutput.copyNextSampleBuffer() {
                while !audioInput.isReadyForMoreMediaData {
                    try await Task.sleep(nanoseconds: 10_000_000)
                }
                // Rebase audio timestamp for trim
                let originalTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
                let offsetTime = CMTime(seconds: CMTimeGetSeconds(originalTime) - trimStart, preferredTimescale: 600)
                var timingInfo = CMSampleTimingInfo(duration: CMSampleBufferGetDuration(sampleBuffer), presentationTimeStamp: offsetTime, decodeTimeStamp: .invalid)
                var newBuffer: CMSampleBuffer?
                CMSampleBufferCreateCopyWithNewTiming(allocator: nil, sampleBuffer: sampleBuffer, sampleTimingEntryCount: 1, sampleTimingArray: &timingInfo, sampleBufferOut: &newBuffer)
                if let newBuffer { audioInput.append(newBuffer) }
            }
            audioInput.markAsFinished()
        }

        writerVideoInput.markAsFinished()
        await writer.finishWriting()
        reader.cancelReading()

        await MainActor.run { progress = 1.0; isExporting = false }
    }
}
