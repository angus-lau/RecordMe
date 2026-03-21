// RecordMeTests/ZoomAnimatorTests.swift
import XCTest
@testable import RecordMe

final class ZoomAnimatorTests: XCTestCase {
    func testCubicBezierAtZero() {
        let value = ZoomAnimator.cubicBezier(t: 0.0, x1: 0.25, y1: 0.1, x2: 0.25, y2: 1.0)
        XCTAssertEqual(value, 0.0, accuracy: 0.001)
    }
    func testCubicBezierAtOne() {
        let value = ZoomAnimator.cubicBezier(t: 1.0, x1: 0.25, y1: 0.1, x2: 0.25, y2: 1.0)
        XCTAssertEqual(value, 1.0, accuracy: 0.001)
    }
    func testCubicBezierMidpoint() {
        let value = ZoomAnimator.cubicBezier(t: 0.5, x1: 0.25, y1: 0.1, x2: 0.25, y2: 1.0)
        XCTAssertGreaterThan(value, 0.5)
        XCTAssertLessThan(value, 1.0)
    }
    func testEaseInOut() {
        let value = ZoomAnimator.easeInOut(progress: 0.5)
        XCTAssertGreaterThan(value, 0.4)
        XCTAssertLessThan(value, 1.0)
    }
    func testZoomStateForTimestampBeforeRegion() {
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
        XCTAssertLessThan(state.scale, 2.0)
    }
    func testZoomStateDuringZoomOut() {
        let region = ZoomRegion(startTime: 2.0, endTime: 6.0, focalPoint: CGPoint(x: 100, y: 200), scale: 2.0, source: .manual)
        let state = ZoomAnimator.zoomState(at: 6.25, regions: [region], zoomInDuration: 0.3, zoomOutDuration: 0.5)
        XCTAssertGreaterThan(state.scale, 1.0)
        XCTAssertLessThan(state.scale, 2.0)
    }
    func testZoomStateAfterRegion() {
        let region = ZoomRegion(startTime: 2.0, endTime: 6.0, focalPoint: CGPoint(x: 100, y: 200), scale: 2.0, source: .manual)
        let state = ZoomAnimator.zoomState(at: 10.0, regions: [region], zoomInDuration: 0.3, zoomOutDuration: 0.5)
        XCTAssertEqual(state.scale, 1.0, accuracy: 0.001)
    }
}
