import ARKit
import AVFoundation
import RoomPlan
import SwiftUI
import UIKit

@MainActor
final class RoomScanController: ObservableObject {
    @Published var isSaving = false
    @Published var waypoints: [RouteWaypoint] = []
    @Published var errorMessage: String?

    weak var captureView: RoomCaptureView?
    private var capturedWorldMap: Data?
    private let store: MapStore
    private let spaceName: String
    private let onComplete: () -> Void

    init(store: MapStore, spaceName: String, onComplete: @escaping () -> Void) {
        self.store = store
        self.spaceName = spaceName
        self.onComplete = onComplete
    }

    func markCurrentLocation(name: String, hapticsEnabled: Bool) {
        guard let frame = captureView?.captureSession.arSession.currentFrame else {
            errorMessage = "The camera is not ready to record this location. Keep scanning and try again."
            return
        }
        let transform = frame.camera.transform
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
        let fallbackName = waypoints.isEmpty ? "Starting point" : "Landmark \(waypoints.count)"
        let label = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if let previous = waypoints.last,
           Wayfinding.horizontalDistance(from: previous.vector, to: position) < 1.2 {
            errorMessage = "Move at least a few steps before marking the next point. Nearby marks can make route guidance skip ahead."
            return
        }
        waypoints.append(RouteWaypoint(
            name: label.isEmpty ? fallbackName : label,
            position: position,
            headingRadians: heading
        ))
        if hapticsEnabled {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        }
        UIAccessibility.post(notification: .announcement, argument: "Marked \(waypoints.last?.name ?? fallbackName).")
    }

    func stopAndSave() {
        guard !isSaving else { return }
        guard waypoints.count >= 2 else {
            errorMessage = "Mark a starting point and at least one destination before saving a navigable space."
            return
        }
        guard let captureView else {
            errorMessage = "The camera session ended unexpectedly. Close the scanner and try again."
            return
        }

        isSaving = true
        captureView.captureSession.arSession.getCurrentWorldMap { [weak self] worldMap, error in
            let archived: Data?
            if let worldMap {
                do {
                    archived = try NSKeyedArchiver.archivedData(
                        withRootObject: worldMap,
                        requiringSecureCoding: true
                    )
                } catch {
                    archived = nil
                    DispatchQueue.main.async { [weak self] in
                        self?.errorMessage = "The room was scanned, but its position map could not be saved: \(error.localizedDescription)"
                    }
                }
            } else {
                archived = nil
                let detail = error?.localizedDescription ?? "ARKit did not return a world map."
                DispatchQueue.main.async { [weak self] in
                    self?.errorMessage = "The room was scanned, but its position map could not be saved: \(detail)"
                }
            }

            DispatchQueue.main.async { [weak self, weak captureView] in
                guard let self, let captureView else { return }
                self.capturedWorldMap = archived
                captureView.captureSession.stop()
            }
        }
    }

    func didProcess(room: CapturedRoom, error: Error?) {
        if let error {
            errorMessage = "RoomPlan could not finish processing this scan: \(error.localizedDescription)"
            isSaving = false
            return
        }

        do {
            let map = try store.save(
                name: spaceName,
                room: room,
                worldMapData: capturedWorldMap,
                waypoints: waypoints
            )
            isSaving = false
            UIAccessibility.post(notification: .announcement, argument: "Space saved. \(map.wallCount) walls and \(map.doorCount) doors captured.")
            onComplete()
        } catch {
            errorMessage = store.errorMessage ?? "The scan could not be saved: \(error.localizedDescription)"
            isSaving = false
        }
    }
}

struct RoomCaptureSurface: UIViewRepresentable {
    @ObservedObject var controller: RoomScanController

    func makeCoordinator() -> Coordinator {
        Coordinator(controller: controller)
    }

    func makeUIView(context: Context) -> RoomCaptureView {
        let view = RoomCaptureView(frame: .zero)
        view.delegate = context.coordinator
        controller.captureView = view
        let permission = AVCaptureDevice.authorizationStatus(for: .video)
        guard permission != .denied, permission != .restricted else {
            controller.errorMessage = "Camera access is off. Allow camera access for BlindSpot in Settings, then reopen the scanner."
            return view
        }
        view.captureSession.run(configuration: RoomCaptureSession.Configuration())
        return view
    }

    func updateUIView(_ uiView: RoomCaptureView, context: Context) {}

    static func dismantleUIView(_ uiView: RoomCaptureView, coordinator: Coordinator) {
        uiView.captureSession.stop()
    }

    @MainActor
    final class Coordinator: NSObject, RoomCaptureViewDelegate {
        private let controller: RoomScanController

        init(controller: RoomScanController) {
            self.controller = controller
        }

        func captureView(shouldPresent roomDataForProcessing: CapturedRoomData, error: Error?) -> Bool {
            true
        }

        func captureView(didPresent processedResult: CapturedRoom, error: Error?) {
            controller.didProcess(room: processedResult, error: error)
        }
    }
}

struct RoomScannerScreen: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var controller: RoomScanController
    @AppStorage("blindspot.haptics") private var hapticsEnabled = true
    @State private var landmarkName = ""
    @State private var showError = false
    @State private var confirmClose = false

    init(store: MapStore, spaceName: String, onComplete: @escaping () -> Void) {
        _controller = StateObject(wrappedValue: RoomScanController(
            store: store,
            spaceName: spaceName,
            onComplete: onComplete
        ))
    }

    var body: some View {
        ZStack {
            RoomCaptureSurface(controller: controller)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                HStack {
                    Button("Close scanner") { confirmClose = true }
                        .accessibilityLabel("Close scanner")
                    Spacer()
                    Label("LiDAR scan", systemImage: "viewfinder")
                        .font(.headline)
                    Spacer()
                    Color.clear.frame(width: 44, height: 44)
                        .accessibilityHidden(true)
                }
                .padding(12)
                .background(.black.opacity(0.78), in: RoundedRectangle(cornerRadius: 14))

                Text("Move slowly and keep walls, doors and the floor in view.")
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(.black.opacity(0.78), in: RoundedRectangle(cornerRadius: 14))

                Spacer()

                VStack(alignment: .leading, spacing: 12) {
                    TextField(landmarkName.isEmpty ? (controller.waypoints.isEmpty ? "Starting point name" : "Landmark name") : "Landmark name", text: $landmarkName)
                        .textFieldStyle(.roundedBorder)
                        .font(.body)
                        .accessibilityLabel(controller.waypoints.isEmpty ? "Starting point name" : "Landmark name")
                        .submitLabel(.done)

                    Button {
                        controller.markCurrentLocation(name: landmarkName, hapticsEnabled: hapticsEnabled)
                        landmarkName = ""
                    } label: {
                        Label(
                            controller.waypoints.isEmpty ? "Mark starting point" : "Mark landmark",
                            systemImage: "mappin.and.ellipse"
                        )
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(BlindSpotButtonStyle())

                    if !controller.waypoints.isEmpty {
                        Text("Saved landmarks: \(controller.waypoints.map(\.name).joined(separator: ", "))")
                            .font(.footnote.weight(.medium))
                            .lineLimit(2)
                            .accessibilityLabel("Saved landmarks: \(controller.waypoints.map(\.name).joined(separator: ", "))")
                    }

                    Button {
                        controller.stopAndSave()
                    } label: {
                        Label(controller.isSaving ? "Processing scan" : "Finish and save space", systemImage: "checkmark")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(BlindSpotButtonStyle(prominent: false))
                    .disabled(controller.isSaving)

                    Text("You must mark a start and destination landmark for navigation. Scan quality depends on lighting, movement and the space.")
                        .font(.footnote)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(16)
                .foregroundStyle(.white)
                .background(.black.opacity(0.86), in: RoundedRectangle(cornerRadius: 18))
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 12)
        }
        .preferredColorScheme(.dark)
        .interactiveDismissDisabled(controller.isSaving)
        .confirmationDialog(
            "End this scan?",
            isPresented: $confirmClose,
            titleVisibility: .visible
        ) {
            Button("Discard scan and close", role: .destructive) { dismiss() }
            Button("Continue scanning", role: .cancel) {}
        } message: {
            Text("This unsaved capture and its marked locations will be lost.")
        }
        .onChange(of: controller.errorMessage) { _, message in
            showError = message != nil
        }
        .alert("Scanner message", isPresented: $showError) {
            Button("OK") { controller.errorMessage = nil }
        } message: {
            Text(controller.errorMessage ?? "")
        }
    }
}
