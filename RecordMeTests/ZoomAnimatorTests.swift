import XCTest
@testable import RecordMe

final class ZoomAnimatorTests: XCTestCase {
    func testEaseInOutAtZero() {
        XCTAssertEqual(ZoomAnimator.easeInOut(progress: 0.0), 0.0, accuracy: 0.001)
    }
    func testEaseInOutAtOne() {
        XCTAssertEqual(ZoomAnimator.easeInOut(progress: 1.0), 1.0, accuracy: 0.001)
    }
    func testEaseInOutMidpoint() {
        let value = ZoomAnimator.easeInOut(progress: 0.5)
        XCTAssertEqual(value, 0.5, accuracy: 0.001)  // smoothstep is exactly 0.5 at midpoint
    }
    func testEaseInOutClampsInput() {
        XCTAssertEqual(ZoomAnimator.easeInOut(progress: -1.0), 0.0, accuracy: 0.001)
        XCTAssertEqual(ZoomAnimator.easeInOut(progress: 2.0), 1.0, accuracy: 0.001)
    }
    func testEaseInOutNeverOvershoots() {
        for i in 0...100 {
            let t = Double(i) / 100.0
            let v = ZoomAnimator.easeInOut(progress: t)
            XCTAssertGreaterThanOrEqual(v, 0.0)
            XCTAssertLessThanOrEqual(v, 1.0)
        }
    }
    func testZoomStateBeforeRegion() {
        let region = ZoomRegion(startTime: 2.0, endTime: 6.0, focalPoint: CGPoint(x: 100, y: 200), scale: 2.0, source: .manual)
        let state = ZoomAnimator.zoomState(at: 0.5, regions: [region], zoomInDuration: 0.3, zoomOutDuration: 0.5)
        XCTAssertEqual(state.scale, 1.0, accuracy: 0.001)
    }
    func testZoomStateFullyInRegion() {
        let region = ZoomRegion(startTime: 2.0, endTime: 6.0, focalPoint: CGPoint(x: 100, y: 200), scale: 2.0, source: .manual)
        let state = ZoomAnimator.zoomState(at: 4.0, regions: [region], zoomInDuration: 0.3, zoomOutDuration: 0.5)
        XCTAssertEqual(state.scale, 2.0, accuracy: 0.001)
        XCTAssertEqual(state.focalPoint.x, 100, accuracy: 0.001)
    }
    func testZoomStateDuringZoomIn() {
        let region = ZoomRegion(startTime: 2.0, endTime: 6.0, focalPoint: CGPoint(x: 100, y: 200), scale: 2.0, source: .manual)
        let state = ZoomAnimator.zoomState(at: 1.85, regions: [region], zoomInDuration: 0.3, zoomOutDuration: 0.5)
        XCTAssertGreaterThan(state.scale, 1.0)
        XCTAssertLessThanOrEqual(state.scale, 2.0)
    }
    func testZoomStateDuringZoomOut() {
        let region = ZoomRegion(startTime: 2.0, endTime: 6.0, focalPoint: CGPoint(x: 100, y: 200), scale: 2.0, source: .manual)
        let state = ZoomAnimator.zoomState(at: 6.25, regions: [region], zoomInDuration: 0.3, zoomOutDuration: 0.5)
        XCTAssertGreaterThanOrEqual(state.scale, 1.0)
        XCTAssertLessThan(state.scale, 2.0)
    }
    func testZoomStateAfterRegion() {
        let region = ZoomRegion(startTime: 2.0, endTime: 6.0, focalPoint: CGPoint(x: 100, y: 200), scale: 2.0, source: .manual)
        let state = ZoomAnimator.zoomState(at: 10.0, regions: [region], zoomInDuration: 0.3, zoomOutDuration: 0.5)
        XCTAssertEqual(state.scale, 1.0, accuracy: 0.001)
    }
}
