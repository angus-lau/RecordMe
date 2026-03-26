import Foundation
import AVFoundation

enum VideoCodec: String {
    case h264
    case hevc

    var avCodecType: AVVideoCodecType {
        switch self {
        case .h264: return .h264
        case .hevc: return .hevc
        }
    }
}

struct ExportPreset {
    let width: Int
    let height: Int
    let codec: VideoCodec
    let label: String

    /// Creates a 1080p preset that preserves the source aspect ratio
    static func hd1080p(codec: VideoCodec, sourceAspect: CGFloat = 16.0/9.0) -> ExportPreset {
        let height = 1080
        let width = Int(round(CGFloat(height) * sourceAspect))
        // Width must be even for H.264/HEVC
        let evenWidth = width % 2 == 0 ? width : width + 1
        return ExportPreset(width: evenWidth, height: height, codec: codec, label: "1080p")
    }

    /// Creates a 4K preset that preserves the source aspect ratio
    static func uhd4k(codec: VideoCodec, sourceAspect: CGFloat = 16.0/9.0) -> ExportPreset {
        let height = 2160
        let width = Int(round(CGFloat(height) * sourceAspect))
        let evenWidth = width % 2 == 0 ? width : width + 1
        return ExportPreset(width: evenWidth, height: height, codec: codec, label: "4K")
    }

    static func source(width: Int, height: Int, codec: VideoCodec) -> ExportPreset {
        // Ensure even dimensions
        let evenWidth = width % 2 == 0 ? width : width + 1
        let evenHeight = height % 2 == 0 ? height : height + 1
        return ExportPreset(width: evenWidth, height: evenHeight, codec: codec, label: "Source")
    }
}
