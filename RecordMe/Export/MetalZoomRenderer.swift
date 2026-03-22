import Metal
import CoreVideo
import CoreGraphics

final class MetalZoomRenderer {
    private let context: MetalContext
    private var textureCache: CVMetalTextureCache?

    init(context: MetalContext = .shared) {
        self.context = context
        CVMetalTextureCacheCreate(nil, nil, context.device, nil, &textureCache)
    }

    struct ZoomParams {
        var scale: Float
        var focalX: Float
        var focalY: Float
        var outputWidth: UInt32
        var outputHeight: UInt32
        var sourceWidth: UInt32
        var sourceHeight: UInt32
    }

    func render(
        source: CVPixelBuffer,
        destination: CVPixelBuffer,
        zoomState: ZoomState,
        sourceSize: CGSize
    ) {
        guard let cache = textureCache else { return }

        let srcWidth = CVPixelBufferGetWidth(source)
        let srcHeight = CVPixelBufferGetHeight(source)
        let dstWidth = CVPixelBufferGetWidth(destination)
        let dstHeight = CVPixelBufferGetHeight(destination)

        guard let srcTexture = makeTexture(from: source, cache: cache),
              let dstTexture = makeTexture(from: destination, cache: cache) else {
            return
        }

        // Normalize focal point to [0, 1] using the logical source size
        // When focalPoint is .zero (identity/no zoom), use center (0.5, 0.5)
        let focalX: Float
        let focalY: Float
        if zoomState.focalPoint == .zero || zoomState.scale <= 1.01 {
            focalX = 0.5
            focalY = 0.5
        } else {
            focalX = Float(max(0, min(1, zoomState.focalPoint.x / sourceSize.width)))
            focalY = Float(max(0, min(1, zoomState.focalPoint.y / sourceSize.height)))
        }

        var params = ZoomParams(
            scale: Float(zoomState.scale),
            focalX: focalX,
            focalY: focalY,
            outputWidth: UInt32(dstWidth),
            outputHeight: UInt32(dstHeight),
            sourceWidth: UInt32(srcWidth),
            sourceHeight: UInt32(srcHeight)
        )

        guard let commandBuffer = context.commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeComputeCommandEncoder() else {
            return
        }

        encoder.setComputePipelineState(context.zoomPipeline)
        encoder.setTexture(srcTexture, index: 0)
        encoder.setTexture(dstTexture, index: 1)
        encoder.setBytes(&params, length: MemoryLayout<ZoomParams>.size, index: 0)

        let threadGroupSize = MTLSize(width: 16, height: 16, depth: 1)
        let threadGroups = MTLSize(
            width: (dstWidth + 15) / 16,
            height: (dstHeight + 15) / 16,
            depth: 1
        )
        encoder.dispatchThreadgroups(threadGroups, threadsPerThreadgroup: threadGroupSize)
        encoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
    }

    private func makeTexture(from pixelBuffer: CVPixelBuffer, cache: CVMetalTextureCache) -> MTLTexture? {
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)

        var cvTexture: CVMetalTexture?
        let status = CVMetalTextureCacheCreateTextureFromImage(
            nil, cache, pixelBuffer, nil,
            .bgra8Unorm, width, height, 0, &cvTexture
        )
        guard status == kCVReturnSuccess, let cvTexture else { return nil }
        return CVMetalTextureGetTexture(cvTexture)
    }
}
