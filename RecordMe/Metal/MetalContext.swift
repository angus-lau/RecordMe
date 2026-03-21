import Metal

final class MetalContext {
    let device: MTLDevice
    let commandQueue: MTLCommandQueue
    let library: MTLLibrary
    let zoomPipeline: MTLComputePipelineState

    static let shared: MetalContext = {
        do {
            return try MetalContext()
        } catch {
            fatalError("MetalContext: Failed to initialize Metal: \(error)")
        }
    }()

    private init() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw RecordMeError.exportFailed("No Metal device available")
        }
        self.device = device

        guard let queue = device.makeCommandQueue() else {
            throw RecordMeError.exportFailed("Failed to create Metal command queue")
        }
        self.commandQueue = queue

        guard let library = device.makeDefaultLibrary() else {
            throw RecordMeError.exportFailed("Failed to load Metal shader library")
        }
        self.library = library

        guard let function = library.makeFunction(name: "zoomTransform") else {
            throw RecordMeError.exportFailed("Failed to find zoomTransform function")
        }
        self.zoomPipeline = try device.makeComputePipelineState(function: function)
    }
}
