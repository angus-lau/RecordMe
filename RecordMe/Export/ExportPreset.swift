// RecordMe/Export/ExportPreset.swift
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

    static func hd1080p(codec: VideoCodec) -> ExportPreset {
        ExportPreset(width: 1920, height: 1080, codec: codec, label: "1080p")
    }

    static func uhd4k(codec: VideoCodec) -> ExportPreset {
        ExportPreset(width: 3840, height: 2160, codec: codec, label: "4K")
    }

    static func source(width: Int, height: Int, codec: VideoCodec) -> ExportPreset {
        ExportPreset(width: width, height: height, codec: codec, label: "Source")
    }
}
