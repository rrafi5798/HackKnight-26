import ARKit
import AVFoundation
import QuickLook
import RoomPlan
import SwiftUI
import UIKit

struct NavigateView: View {
    @EnvironmentObject private var store: MapStore
    @State private var selectedMapID: UUID?
    @State private var navigationMap: SavedMap?
    @State private var routeError: String?

    private var selectedMap: SavedMap? {
        store.maps.first { $0.id == selectedMapID } ?? store.maps.first
    }

    var body: some View {
        Group {
            if !RoomCaptureSession.isSupported {
                ContentUnavailableView(
                    "LiDAR scanning is not supported",
                    systemImage: "camera.metering.unknown",
                    description: Text("Use a LiDAR-equipped iPhone Pro or iPad Pro with a supported version of iOS.")
                )
            } else if store.maps.isEmpty {
                ContentUnavailableView {
                    Label("No mapped spaces yet", systemImage: "point.3.connected.trianglepath.dotted")
                } description: {
                    Text("Scan a place and mark its entrance and destinations. Maps stay on this device.")
                } actions: {
                    NavigationLink {
                        MySpacesView()
                    } label: {
                        Text("Open My spaces")
                            .frame(minHeight: 50)
                    }
                    .buttonStyle(BlindSpotButtonStyle())
                }
            } else if let map = selectedMap {
                routePicker(for: map)
            }
        }
        .navigationTitle("Navigate")
        .navigationBarTitleDisplayMode(.large)
        .sheet(item: $navigationMap) { map in
            NavigationStack {
                GuidanceView(map: map)
            }
        }
        .alert("Could not start navigation", isPresented: Binding(
            get: { routeError != nil },
            set: { if !$0 { routeError = nil } }
        )) {
            Button("OK") { routeError = nil }
        } message: {
            Text(routeError ?? "")
        }
    }

    private func routePicker(for map: SavedMap) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Choose a mapped space. Follow your mobility aid and pause whenever position tracking is uncertain.")
                    .font(.body)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 14) {
                    Text("Destination space")
                        .font(.headline)
                    Picker("Destination space", selection: Binding(
                        get: { selectedMapID ?? map.id },
                        set: { selectedMapID = $0 }
                    )) {
                        ForEach(store.maps) { savedMap in
                            Text(savedMap.name).tag(savedMap.id)
                        }
                    }
                    .pickerStyle(.menu)
                    .font(.title3.weight(.semibold))
                    .accessibilityLabel("Choose a mapped space")

                    Label("\(map.wallCount) walls, \(map.doorCount) doors and \(map.objectCount) objects scanned", systemImage: "view.3d")
                        .font(.subheadline)
                    Label("\(map.waypointCount) named route points", systemImage: "mappin.and.ellipse")
                        .font(.subheadline)

                    if !map.supportsNavigation {
                        Label("Scan again and mark at least two points to enable navigation.", systemImage: "exclamationmark.triangle")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.orange)
                    }
                }
                .padding(18)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))

                VStack(alignment: .leading, spacing: 12) {
                    Label("Before you move", systemImage: "figure.walk")
                        .font(.headline)
                    Text("Relocalization is required in the same physical space used for scanning. If tracking is uncertain, stop and wait. These experimental directions are not a replacement for a cane, guide dog or human assistance.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
                .padding(18)
                .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 18))

                Button {
                    startNavigation(map)
                } label: {
                    Label("Start spatial guidance", systemImage: "location.north.circle.fill")
                        .frame(maxWidth: .infinity, minHeight: 62)
                }
                .buttonStyle(BlindSpotButtonStyle())
                .disabled(!map.supportsNavigation)

                Text("Camera depth alerts are experimental and may miss hazards or report floors and walls as obstacles. Do not rely on them for safety.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(20)
            .frame(maxWidth: 680, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .accessibilityIdentifier("navigate-space-picker")
    }

    private func startNavigation(_ map: SavedMap) {
        guard map.supportsNavigation else { return }
        do {
            _ = try store.worldMapData(for: map)
            navigationMap = map
        } catch {
            routeError = "The saved ARKit position map could not be loaded: \(error.localizedDescription)"
        }
    }
}

struct MySpacesView: View {
    @EnvironmentObject private var store: MapStore
    @State private var showingScanner = false
    @State private var beginScanning = false
    @State private var newSpaceName = ""
    @State private var previewingURL: URL?
    @State private var deleteCandidate: SavedMap?

    var body: some View {
        Group {
            if store.maps.isEmpty {
                ContentUnavailableView {
                    Label("No spaces saved", systemImage: "square.3.layers.3d")
                } description: {
                    Text("Start a RoomPlan scan to create an on-device room model and route landmarks.")
                } actions: {
                    Button("Scan a space") {
                        newSpaceName = ""
                        beginScanning = false
                        showingScanner = true
                    }
                        .buttonStyle(BlindSpotButtonStyle())
                }
            } else {
                List {
                    Section {
                        ForEach(store.maps) { map in
                            mapRow(map)
                        }
                        .onDelete { offsets in
                            guard let index = offsets.first, store.maps.indices.contains(index) else { return }
                            deleteCandidate = store.maps[index]
                        }
                    } header: {
                        Text("Saved on this device")
                    } footer: {
                        Text("Room geometry, route landmarks and ARKit world maps are stored privately in this app's documents folder.")
                    }

                    Section {
                        Button {
                            newSpaceName = ""
                            beginScanning = false
                            showingScanner = true
                        } label: {
                            Label("Scan another space", systemImage: "camera.viewfinder")
                                .frame(minHeight: 48)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle("My spaces")
        .sheet(isPresented: $showingScanner) {
            NavigationStack {
                Group {
                    if beginScanning {
                        RoomScannerScreen(
                            store: store,
                            spaceName: newSpaceName.isEmpty ? "Indoor space" : newSpaceName
                        ) {
                            showingScanner = false
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 22) {
                            Text("Give this place a name so you can find it later.")
                                .font(.body)
                            TextField("Name this space", text: $newSpaceName)
                                .textFieldStyle(.roundedBorder)
                                .font(.body)
                                .accessibilityLabel("Name this space")
                            Button {
                                beginScanning = true
                            } label: {
                                Label("Open camera scanner", systemImage: "camera.viewfinder")
                                    .frame(maxWidth: .infinity, minHeight: 58)
                            }
                            .buttonStyle(BlindSpotButtonStyle())
                            Text("Scan one connected area at a time. Walk the route and mark its start and destinations as you go.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                            Spacer()
                        }
                        .padding(20)
                    }
                }
                .navigationTitle(beginScanning ? "Scan a space" : "New mapped space")
                .navigationBarTitleDisplayMode(.inline)
            }
            .interactiveDismissDisabled(beginScanning)
        }
        .quickLookPreview($previewingURL)
        .confirmationDialog(
            "Delete this saved space?",
            isPresented: Binding(
                get: { deleteCandidate != nil },
                set: { if !$0 { deleteCandidate = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete space", role: .destructive) {
                if let map = deleteCandidate { store.delete(map) }
                deleteCandidate = nil
            }
            Button("Cancel", role: .cancel) { deleteCandidate = nil }
        } message: {
            Text("The local room scan and route landmarks will be removed from this device.")
        }
        .alert("Space issue", isPresented: Binding(
            get: { store.errorMessage != nil },
            set: { if !$0 { store.errorMessage = nil } }
        )) {
            Button("OK") { store.errorMessage = nil }
        } message: {
            Text(presentationError ?? store.errorMessage ?? "")
        }
    }

    @ViewBuilder
    private func mapRow(_ map: SavedMap) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(map.name)
                .font(.title3.weight(.semibold))
            Text(map.createdAt, style: .date)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("\(map.wallCount) walls · \(map.doorCount) doors · \(map.objectCount) objects")
                .font(.subheadline)
            Text("\(map.waypointCount) route landmarks")
                .font(.subheadline)
                .foregroundStyle(map.supportsNavigation ? .primary : .orange)
            if !map.hasWorldMap {
                Text("AR position map not saved. Rescan before navigating.")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.orange)
            }

            HStack(spacing: 12) {
                if let url = store.previewURL(for: map) {
                    Button {
                        previewingURL = url
                    } label: {
                        Label("View 3D scan", systemImage: "cube.transparent")
                            .frame(minHeight: 48)
                    }
                    .buttonStyle(.bordered)
                } else {
                    Text("3D preview unavailable")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Button(role: .destructive) {
                    deleteCandidate = map
                } label: {
                    Label("Delete", systemImage: "trash")
                        .frame(minHeight: 48)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(.vertical, 10)
        .accessibilityElement(children: .contain)
    }
}

struct GuidanceView: View {
    let map: SavedMap
    @EnvironmentObject private var store: MapStore
    @Environment(\.dismiss) private var dismiss
    @State private var worldMapData: Data?
    @State private var waypoints: [RouteWaypoint] = []
    @State private var currentIndex = 1
    @State private var snapshot: ARNavigationSnapshot?
    @State private var errorMessage: String?
    @State private var nearbyAlert = false
    @State private var alertWasSent = false
    @State private var routeComplete = false
    @State private var guidancePaused = false
    @State private var trackingLossAnnounced = false
    @State private var lastSpeech = ""
    @State private var lastAnnouncedDistanceStage: Int?
    @AppStorage("blindspot.spokenDirections") private var speechEnabled = true
    @AppStorage("blindspot.haptics") private var hapticsEnabled = true
    @State private var showAlert = false
    @StateObject private var voice = NavigationVoice()

    private var target: RouteWaypoint? {
        guard waypoints.indices.contains(currentIndex) else { return nil }
        return waypoints[currentIndex]
    }

    private var direction: String {
        if routeComplete { return "You have arrived at \(waypoints.last?.name ?? map.name)." }
        guard let snapshot, let target else {
            return "Look slowly around the starting point to reconnect with this map."
        }
        let distance = Wayfinding.horizontalDistance(from: snapshot.position, to: target.vector)
        return Wayfinding.directionText(
            from: snapshot.position,
            heading: snapshot.headingRadians,
            to: target,
            distance: distance
        )
    }

    var body: some View {
        Group {
            if let errorMessage {
                ContentUnavailableView(
                    "Could not open this map",
                    systemImage: "exclamationmark.triangle",
                    description: Text(errorMessage)
                )
            } else if let worldMapData {
                navigationContent(worldMapData)
            } else {
                ProgressView("Opening the saved position map")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle(map.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("End route", role: .destructive) { dismiss() }
                    .accessibilityLabel("End route and stop position tracking")
            }
        }
        .task {
            do {
                worldMapData = try store.worldMapData(for: map)
                waypoints = try store.waypoints(for: map)
                guard waypoints.count >= 2 else {
                    errorMessage = "This space has fewer than two route landmarks. Scan it again and mark a start plus at least one destination."
                    return
                }
            } catch {
                errorMessage = "Saved route data could not be loaded: \(error.localizedDescription)"
            }
        }
        .onChange(of: snapshot?.isRelocalized) { _, isRelocalized in
            guard isRelocalized == true else { return }
            if lastSpeech.isEmpty {
                announceCurrentDirection()
            }
        }
        .alert("Position map", isPresented: $showAlert) {
            Button("Close navigation") { dismiss() }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func navigationContent(_ worldMapData: Data) -> some View {
        VStack(spacing: 0) {
            SpatialNavigationView(
                map: map,
                worldMapData: worldMapData,
                isNavigationRunning: !routeComplete,
                onUpdate: handleSnapshot,
                onFailure: { message in
                    errorMessage = message
                    showAlert = true
                }
            )
            .frame(minHeight: 180, maxHeight: 270)
            .accessibilityLabel("Camera view used to relocalize in the saved space")

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    trackingStatus
                    Text(direction)
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .minimumScaleFactor(0.7)
                        .accessibilityAddTraits(.updatesFrequently)
                        .accessibilityAddTraits(.isButton)
                        .contentShape(Rectangle())
                        .onTapGesture { speakCurrentDirection() }
                        .simultaneousGesture(
                            DragGesture(minimumDistance: 60)
                                .onEnded { value in
                                    if value.translation.width > 75 {
                                        speakCurrentDirection()
                                    } else if value.translation.width < -75 {
                                        announceUpcomingLandmark()
                                    }
                                }
                        )
                        .accessibilityHint("Tap or swipe right to repeat directions. Swipe left to hear the following landmark.")
                        .accessibilityAction(named: Text("Repeat current direction")) {
                            speakCurrentDirection()
                        }
                        .accessibilityAction(named: Text("Hear following landmark")) {
                            announceUpcomingLandmark()
                        }

                    if let target {
                        Text("Next landmark: \(target.name)")
                            .font(.title3.weight(.semibold))
                    }

                    if nearbyAlert {
                        Label("Possible nearby surface detected. Stop and assess your path.", systemImage: "exclamationmark.triangle.fill")
                            .font(.headline)
                            .foregroundStyle(.orange)
                            .padding(14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.orange.opacity(0.14), in: RoundedRectangle(cornerRadius: 12))
                            .accessibilityAddTraits(.isHeader)
                    }

                    HStack(spacing: 12) {
                        Button {
                            toggleGuidancePause()
                        } label: {
                            Label(guidancePaused ? "Resume guidance" : "Pause guidance", systemImage: guidancePaused ? "play.fill" : "pause.fill")
                                .frame(maxWidth: .infinity, minHeight: 58)
                        }
                        .buttonStyle(BlindSpotButtonStyle())
                        .disabled(routeComplete)

                        Button {
                            speakCurrentDirection()
                        } label: {
                            Label("Repeat direction", systemImage: "arrow.clockwise")
                                .frame(maxWidth: .infinity, minHeight: 58)
                        }
                        .buttonStyle(BlindSpotButtonStyle(prominent: false))
                        .disabled(routeComplete)
                    }

                    Button {
                        voice.stop()
                        dismiss()
                    } label: {
                        Label("End navigation", systemImage: "stop.fill")
                            .frame(maxWidth: .infinity, minHeight: 58)
                    }
                    .buttonStyle(BlindSpotButtonStyle(prominent: false))

                    Text("Keep your mobility aid in use. These experimental camera alerts may be incomplete. Stop if the map, surroundings or spoken directions do not match.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(20)
                .frame(maxWidth: 660, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
        }
        .onAppear { voice.configure() }
        .onDisappear { voice.stop() }
    }

    @ViewBuilder
    private var trackingStatus: some View {
        let isLocated = snapshot?.isRelocalized == true
        Label(
            snapshot?.trackingDescription ?? "Starting ARKit position tracking",
            systemImage: isLocated ? "location.circle.fill" : "location.slash.circle.fill"
        )
        .font(.headline)
        .foregroundStyle(isLocated ? .green : .orange)
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isLocated ? Color.green.opacity(0.12) : Color.orange.opacity(0.14), in: RoundedRectangle(cornerRadius: 12))
    }

    private func handleSnapshot(_ newSnapshot: ARNavigationSnapshot) {
        guard !routeComplete else { return }
        let wasRelocalized = snapshot?.isRelocalized == true
        snapshot = newSnapshot

        guard newSnapshot.isRelocalized else {
            if wasRelocalized, !guidancePaused, !trackingLossAnnounced {
                trackingLossAnnounced = true
                voice.stop()
                let message = "Position is uncertain. Stop walking and wait while BlindSpot reconnects to the saved space."
                speak(message)
                UIAccessibility.post(notification: .announcement, argument: message)
                if hapticsEnabled { UINotificationFeedbackGenerator().notificationOccurred(.warning) }
            }
            return
        }
        guard !guidancePaused else { return }
        trackingLossAnnounced = false
        if !wasRelocalized {
            lastSpeech = ""
            UIAccessibility.post(notification: .announcement, argument: "Tracking the mapped space.")
            announceCurrentDirection()
        }

        if let distance = newSnapshot.nearbyObjectDistance {
            if distance < 0.85, !alertWasSent {
                nearbyAlert = true
                alertWasSent = true
                speak("Possible nearby surface detected. Stop and assess your path.")
                if hapticsEnabled {
                    UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
                }
                UIAccessibility.post(notification: .announcement, argument: "Possible nearby surface detected. Stop and assess your path.")
            }
        } else if alertWasSent {
            nearbyAlert = false
            alertWasSent = false
        }

        guard let target else {
            finishRoute()
            return
        }
        let distance = Wayfinding.horizontalDistance(from: newSnapshot.position, to: target.vector)
        if distance <= 0.8 {
            currentIndex += 1
            lastSpeech = ""
            lastAnnouncedDistanceStage = nil
            if currentIndex >= waypoints.count {
                finishRoute()
            } else {
                if hapticsEnabled {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                }
                announceCurrentDirection()
            }
        } else if let stage = distanceStage(distance), stage != lastAnnouncedDistanceStage {
            announceCurrentDirection()
        }
    }

    private func distanceStage(_ distance: Float) -> Int? {
        if distance <= 1.6 { return 3 }
        if distance <= 6 { return 2 }
        if distance <= 15 { return 1 }
        return lastAnnouncedDistanceStage == nil ? 0 : nil
    }

    private func announceCurrentDirection() {
        guard let snapshot, snapshot.isRelocalized, let target else { return }
        let distance = Wayfinding.horizontalDistance(from: snapshot.position, to: target.vector)
        let text = Wayfinding.directionText(
            from: snapshot.position,
            heading: snapshot.headingRadians,
            to: target,
            distance: distance
        )
        if distance > 15 {
            lastAnnouncedDistanceStage = 0
        } else if distance > 6 {
            lastAnnouncedDistanceStage = 1
        } else if distance > 1.6 {
            lastAnnouncedDistanceStage = 2
        } else {
            lastAnnouncedDistanceStage = 3
        }
        lastSpeech = text
        speak(text)
        UIAccessibility.post(notification: .announcement, argument: text)
    }

    private func speak(_ text: String) {
        guard speechEnabled, !UIAccessibility.isVoiceOverRunning else { return }
        voice.speak(text)
    }

    private func speakCurrentDirection() {
        guard !guidancePaused else {
            UIAccessibility.post(notification: .announcement, argument: "Guidance is paused. Resume guidance to continue.")
            return
        }
        guard snapshot?.isRelocalized == true else {
            UIAccessibility.post(notification: .announcement, argument: "Position is not confirmed. Slowly look around to find the saved space.")
            return
        }
        lastSpeech = ""
        announceCurrentDirection()
        if hapticsEnabled {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
    }

    private func announceUpcomingLandmark() {
        guard !guidancePaused else {
            UIAccessibility.post(notification: .announcement, argument: "Guidance is paused. Resume guidance to continue.")
            return
        }
        guard let target, waypoints.indices.contains(currentIndex + 1) else {
            speakCurrentDirection()
            return
        }
        let message = "After \(target.name), the next marked landmark is \(waypoints[currentIndex + 1].name)."
        speak(message)
        UIAccessibility.post(notification: .announcement, argument: message)
        if hapticsEnabled {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
    }

    private func toggleGuidancePause() {
        guard !routeComplete else { return }
        guidancePaused.toggle()
        if guidancePaused {
            voice.stop()
            UIAccessibility.post(notification: .announcement, argument: "Guidance paused. Position tracking continues. Resume when you are ready.")
            if hapticsEnabled { UINotificationFeedbackGenerator().notificationOccurred(.warning) }
        } else {
            voice.configure()
            if hapticsEnabled { UIImpactFeedbackGenerator(style: .medium).impactOccurred() }
            if snapshot?.isRelocalized == true {
                lastAnnouncedDistanceStage = nil
                announceCurrentDirection()
            } else {
                UIAccessibility.post(notification: .announcement, argument: "Guidance resumed. Position is not confirmed. Slowly look around.")
            }
        }
    }

    private func finishRoute() {
        guard !routeComplete else { return }
        routeComplete = true
        let destination = waypoints.last?.name ?? map.name
        speak("You have arrived at \(destination).")
        UIAccessibility.post(notification: .announcement, argument: "You have arrived at \(destination).")
        if hapticsEnabled {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
    }
}

@MainActor
final class NavigationVoice: ObservableObject {
    private let synthesizer = AVSpeechSynthesizer()

    func configure() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            UIAccessibility.post(notification: .announcement, argument: "Audio guidance could not prepare the audio output.")
        }
    }

    func speak(_ text: String) {
        synthesizer.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.92
        let language = Locale.current.identifier.replacingOccurrences(of: "_", with: "-")
        utterance.voice = AVSpeechSynthesisVoice(language: language)
        synthesizer.speak(utterance)
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            NSLog("BlindSpot could not deactivate the spoken-audio session: %@", error.localizedDescription)
        }
    }
}
