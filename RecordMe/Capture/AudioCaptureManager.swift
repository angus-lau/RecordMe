import AVFoundation

final class AudioCaptureManager {
    private let engine = AVAudioEngine()
    private var assetWriter: AVAssetWriter?
    private var audioInput: AVAssetWriterInput?
    private var isRecording = false

    func attachToWriter(_ writer: AVAssetWriter) {
        let audioSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 128_000,
        ]
        let input = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
        input.expectsMediaDataInRealTime = true
        if writer.canAdd(input) { writer.add(input) }
        audioInput = input
        assetWriter = writer
    }

    func startCapture() throws {
        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, time in
            self?.handleAudioBuffer(buffer, time: time)
        }
        engine.prepare()
        try engine.start()
        isRecording = true
    }

    func stopCapture() {
        isRecording = false
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        audioInput?.markAsFinished()
        audioInput = nil
        assetWriter = nil
    }

    private func handleAudioBuffer(_ buffer: AVAudioPCMBuffer, time: AVAudioTime) {
        guard isRecording, let audioInput, audioInput.isReadyForMoreMediaData else { return }
        guard let sampleBuffer = buffer.toCMSampleBuffer(time: time) else { return }
        audioInput.append(sampleBuffer)
    }
}

private extension AVAudioPCMBuffer {
    func toCMSampleBuffer(time: AVAudioTime) -> CMSampleBuffer? {
        let framesCount = CMItemCount(frameLength)
        let bytesPerFrame = CMItemCount(format.streamDescription.pointee.mBytesPerFrame)
        let blockSize = framesCount * bytesPerFrame

        var blockBuffer: CMBlockBuffer?
        guard CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault, memoryBlock: nil, blockLength: blockSize,
            blockAllocator: kCFAllocatorDefault, customBlockSource: nil,
            offsetToData: 0, dataLength: blockSize, flags: 0, blockBufferOut: &blockBuffer
        ) == noErr, let blockBuffer else { return nil }

        guard CMBlockBufferReplaceDataBytes(
            with: audioBufferList.pointee.mBuffers.mData!,
            blockBuffer: blockBuffer, offsetIntoDestination: 0, dataLength: blockSize
        ) == noErr else { return nil }

        var formatDesc: CMAudioFormatDescription?
        CMAudioFormatDescriptionCreate(
            allocator: kCFAllocatorDefault, asbd: format.streamDescription,
            layoutSize: 0, layout: nil, magicCookieSize: 0, magicCookie: nil,
            extensions: nil, formatDescriptionOut: &formatDesc
        )

        var sampleBuffer: CMSampleBuffer?
        let sampleRate = format.sampleRate
        var timing = CMSampleTimingInfo(
            duration: CMTime(value: CMTimeValue(frameLength), timescale: CMTimeScale(sampleRate)),
            presentationTimeStamp: CMTime(
                seconds: AVAudioTime.seconds(forHostTime: time.hostTime),
                preferredTimescale: CMTimeScale(sampleRate)
            ),
            decodeTimeStamp: .invalid
        )

        guard let formatDesc else { return nil }
        var sampleSize = blockSize
        CMSampleBufferCreate(
            allocator: kCFAllocatorDefault, dataBuffer: blockBuffer, dataReady: true,
            makeDataReadyCallback: nil, refcon: nil, formatDescription: formatDesc,
            sampleCount: framesCount, sampleTimingEntryCount: 1, sampleTimingArray: &timing,
            sampleSizeEntryCount: 1, sampleSizeArray: &sampleSize, sampleBufferOut: &sampleBuffer
        )
        return sampleBuffer
    }
}
