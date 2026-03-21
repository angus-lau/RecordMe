// RecordMe/Zoom/ZoomState.swift
import Foundation

struct ZoomState {
    var scale: CGFloat
    var focalPoint: CGPoint
    var animationProgress: CGFloat

    static let identity = ZoomState(scale: 1.0, focalPoint: .zero, animationProgress: 0.0)
}
