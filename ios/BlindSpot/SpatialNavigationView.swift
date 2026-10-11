import ARKit
import AVFoundation
import SceneKit
import SwiftUI
import UIKit

struct SpatialNavigationView: UIViewRepresentable {
    let map: SavedMap
    let worldMapData: Data
    let isNavigationRunning: Bool
    let onUpdate: (ARNavigationSnapshot) -> Void
    let onFailure: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onUpdate: onUpdate, onFailure: onFailure)
    }

    func makeUIView(context: Context) -> ARSCNView {
        let view = ARSCNView(frame: .zero)
        view.delegate = context.coordinator
        view.automaticallyUpdatesLighting = false
        view.scene = SCNScene()

        do {
            guard let worldMap = try NSKeyedUnarchiver.unarchivedObject(
                ofClass: ARWorldMap.self,
                from: worldMapData
            ) else {
                throw NavigationSetupError.invalidWorldMap
            }

            let configuration = ARWorldTrackingConfiguration()
            configuration.initialWorldMap = worldMap
            if ARWorldTrackingConfiguration.supportsFrameSemantics(.smoothedSceneDepth) {
                configuration.frameSemantics.insert(.smoothedSceneDepth)
            } else if ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {
                configuration.frameSemantics.insert(.sceneDepth)
            }
            view.session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
        } catch {
            onFailure("This space's saved position map could not be opened: \(error.localizedDescription)")
        }
        return view
    }

    func updateUIView(_ uiView: ARSCNView, context: Context) {
        context.coordinator.setNavigationRunning(isNavigationRunning, session: uiView.session)
    }

    static func dismantleUIView(_ uiView: ARSCNView, coordinator: Coordinator) {
        uiView.session.pause()
    }

    @MainActor
    final class Coordinator: NSObject, ARSCNViewDelegate {
        private let onUpdate: (ARNavigationSnapshot) -> Void
        private let onFailure: (String) -> Void
        private var lastUpdateTime: TimeInterval = 0
        private var lastObstacleReadTime: TimeInterval = 0
        private var latestObstacleDistance: Float?
        private var isNavigationRunning = true

        init(
            onUpdate: @escaping (ARNavigationSnapshot) -> Void,
            onFailure: @escaping (String) -> Void
        ) {
            self.onUpdate = onUpdate
            self.onFailure = onFailure
        }

        func setNavigationRunning(_ isRunning: Bool, session: ARSession) {
            guard isNavigationRunning != isRunning else { return }
            isNavigationRunning = isRunning
            if !isRunning {
                session.pause()
            }
        }

        func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
            guard time - lastUpdateTime >= 0.25,
                  let sceneView = renderer as? ARSCNView,
                  let frame = sceneView.session.currentFrame else { return }
            lastUpdateTime = time

            let camera = frame.camera
            let transform = camera.transform
            let position = SIMD3<Float>(
                transform.columns.3.x,
                transform.columns.3.y,
                transform.columns.3.z
            )
            let forward = -SIMD3<Float>(
                transform.columns.2.x,
                transform.columns.2.y,
                transform.columns.2.z
            )
            let heading = atan2(-forward.x, -forward.z)

            let status: (String, Bool)
            switch camera.trackingState {
            case .normal:
                status = ("Tracking the mapped space", true)
            case .limited(let reason):
                status = (reasonDescription(reason), false)
            case .notAvailable:
                status = ("Position tracking is unavailable", false)
            @unknown default:
                status = ("Checking position tracking", false)
            }

            if time - lastObstacleReadTime >= 0.5 {
                lastObstacleReadTime = time
                latestObstacleDistance = nearestDepth(in: frame)
            }

            let snapshot = ARNavigationSnapshot(
                position: position,
                headingRadians: heading,
                trackingDescription: status.0,
                isRelocalized: status.1,
                nearbyObjectDistance: latestObstacleDistance
            )
            DispatchQueue.main.async { [onUpdate] in onUpdate(snapshot) }
        }

        private func nearestDepth(in frame: ARFrame) -> Float? {
            guard let depthMap = (frame.smoothedSceneDepth ?? frame.sceneDepth)?.depthMap else {
                return nil
            }
            CVPixelBufferLockBaseAddress(depthMap, .readOnly)
            defer { CVPixelBufferUnlockBaseAddress(depthMap, .readOnly) }
            guard let baseAddress = CVPixelBufferGetBaseAddress(depthMap) else { return nil }

            let width = CVPixelBufferGetWidth(depthMap)
            let height = CVPixelBufferGetHeight(depthMap)
            let rowStride = CVPixelBufferGetBytesPerRow(depthMap) / MemoryLayout<Float32>.stride
            let values = baseAddress.assumingMemoryBound(to: Float32.self)
            let xRange = (width * 4 / 10)...(width * 6 / 10)
            let yRange = (height * 4 / 10)...(height * 7 / 10)
            var nearest: Float?

            for y in stride(from: yRange.lowerBound, through: yRange.upperBound, by: 4) {
                for x in stride(from: xRange.lowerBound, through: xRange.upperBound, by: 4) {
                    let distance = values[y * rowStride + x]
                    guard distance.isFinite, distance > 0.2, distance < 1.25 else { continue }
                    nearest = min(nearest ?? distance, distance)
                }
            }
            return nearest
        }

        private func reasonDescription(_ reason: ARCamera.TrackingState.Reason) -> String {
            switch reason {
            case .initializing:
                "Finding the saved space. Slowly look around."
            case .relocalizing:
                "Reconnecting to this map. Slowly look toward familiar walls."
            case .excessiveMotion:
                "Tracking is unstable. Slow down and hold the phone steady."
            case .insufficientFeatures:
                "Not enough visual detail. Slowly turn toward textured surfaces."
            case .unsupported:
                "This device cannot track the saved space."
            @unknown default:
                "Position is uncertain. Pause and look around."
            }
        }
    }
}

private enum NavigationSetupError: LocalizedError {
    case invalidWorldMap

    var errorDescription: String? {
        "The saved ARKit world map is invalid or incomplete."
    }
}
