// RecordMeTests/ZoomModelTests.swift
import XCTest
@testable import RecordMe

final class ZoomModelTests: XCTestCase {
    func testZoomRegionDefaults() {
        let region = ZoomRegion(
            startTime: 1.0, endTime: 5.0,
            focalPoint: CGPoint(x: 100, y: 200), scale: 2.0, source: .manual
        )
        XCTAssertEqual(region.duration, 4.0)
        XCTAssertEqual(region.source, .manual)
    }

    func testZoomRegionOverlaps() {
        let a = ZoomRegion(startTime: 1.0, endTime: 5.0, focalPoint: .zero, scale: 2.0, source: .manual)
        let b = ZoomRegion(startTime: 4.0, endTime: 8.0, focalPoint: .zero, scale: 2.0, source: .typing)
        let c = ZoomRegion(startTime: 6.0, endTime: 9.0, focalPoint: .zero, scale: 2.0, source: .typing)
        XCTAssertTrue(a.overlaps(b))
        XCTAssertFalse(a.overlaps(c))
    }

    func testZoomStateIdentity() {
        let state = ZoomState.identity
        XCTAssertEqual(state.scale, 1.0)
        XCTAssertEqual(state.focalPoint, .zero)
        XCTAssertEqual(state.animationProgress, 0.0)
    }

    func testExportPresetResolutions() {
        let preset1080 = ExportPreset.hd1080p(codec: .hevc)
        XCTAssertEqual(preset1080.width, 1920)
        XCTAssertEqual(preset1080.height, 1080)
        let preset4k = ExportPreset.uhd4k(codec: .hevc)
        XCTAssertEqual(preset4k.width, 3840)
        XCTAssertEqual(preset4k.height, 2160)
    }

    func testExportPresetCodec() {
        let hevc = ExportPreset.hd1080p(codec: .hevc)
        let h264 = ExportPreset.hd1080p(codec: .h264)
        XCTAssertNotEqual(hevc.codec, h264.codec)
    }
}
