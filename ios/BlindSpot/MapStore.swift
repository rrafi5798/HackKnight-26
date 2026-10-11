import Foundation
import Combine
import RoomPlan

@MainActor
final class MapStore: ObservableObject {
    @Published private(set) var maps: [SavedMap] = []
    @Published var errorMessage: String?

    private let fileManager = FileManager.default
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()
    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    private var rootURL: URL {
        fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("BlindSpotMaps", isDirectory: true)
    }

    func refresh() {
        do {
            try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
            let folders = try fileManager.contentsOfDirectory(
                at: rootURL,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )
            maps = try folders.compactMap { folder in
                let metadataURL = folder.appendingPathComponent("building.json")
                guard fileManager.fileExists(atPath: metadataURL.path) else { return nil }
                return try decoder.decode(SavedMap.self, from: Data(contentsOf: metadataURL))
            }
            .sorted { $0.createdAt > $1.createdAt }
            errorMessage = nil
        } catch {
            errorMessage = "Saved spaces could not be loaded: \(error.localizedDescription)"
        }
    }

    func save(
        name: String,
        room: CapturedRoom,
        worldMapData: Data?,
        waypoints: [RouteWaypoint]
    ) throws -> SavedMap {
        errorMessage = nil
        let id = UUID()
        let cleanedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let safeName = cleanedName.isEmpty ? "Indoor space" : cleanedName
        let folder = rootURL.appendingPathComponent(id.uuidString, isDirectory: true)
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)

        do {
            var warningMessage: String?
            let roomURL = folder.appendingPathComponent("scan.json")
            try encoder.encode(room).write(to: roomURL, options: .atomic)

            if let worldMapData {
                try worldMapData.write(to: folder.appendingPathComponent("worldmap-floor-1.bin"), options: .atomic)
            }

            let route = RoutePackage(mapID: id, waypoints: waypoints)
            try encoder.encode(route).write(to: folder.appendingPathComponent("route.json"), options: .atomic)

            let landmarks = LandmarkPackage(mapID: id, waypoints: waypoints)
            try encoder.encode(landmarks).write(to: folder.appendingPathComponent("landmarks.json"), options: .atomic)

            let record = SavedMap(
                id: id,
                name: safeName,
                createdAt: Date(),
                waypointCount: waypoints.count,
                wallCount: room.walls.count,
                doorCount: room.doors.count,
                openingCount: room.openings.count,
                objectCount: room.objects.count,
                hasWorldMap: worldMapData != nil
            )
            try encoder.encode(record).write(to: folder.appendingPathComponent("building.json"), options: .atomic)

            if worldMapData == nil {
                warningMessage = "The room scan was saved, but ARKit could not save its position map. This space can be previewed but not used for navigation."
            }

            do {
                try room.export(to: folder.appendingPathComponent("scan.usdz"))
            } catch {
                let exportMessage = "The room and route were saved, but the 3D preview could not be exported: \(error.localizedDescription)"
                warningMessage = warningMessage.map { "\($0) \(exportMessage)" } ?? exportMessage
            }

            refresh()
            if let warningMessage {
                errorMessage = warningMessage
            }
            return record
        } catch {
            do {
                try fileManager.removeItem(at: folder)
            } catch {
                errorMessage = "Saving the scan failed: \(error.localizedDescription). Partial scan files may remain on this device."
            }
            throw error
        }
    }

    func worldMapData(for map: SavedMap) throws -> Data {
        let url = rootURL
            .appendingPathComponent(map.id.uuidString, isDirectory: true)
            .appendingPathComponent("worldmap-floor-1.bin")
        return try Data(contentsOf: url)
    }

    func waypoints(for map: SavedMap) throws -> [RouteWaypoint] {
        let folder = rootURL.appendingPathComponent(map.id.uuidString, isDirectory: true)
        let url = folder.appendingPathComponent("landmarks.json")
        let package = try decoder.decode(LandmarkPackage.self, from: Data(contentsOf: url))
        return package.landmarks.map {
            RouteWaypoint(
                id: $0.id,
                name: $0.name,
                position: $0.position.vector,
                headingRadians: $0.headingRadians
            )
        }
    }

    func previewURL(for map: SavedMap) -> URL? {
        let url = rootURL
            .appendingPathComponent(map.id.uuidString, isDirectory: true)
            .appendingPathComponent("scan.usdz")
        return fileManager.fileExists(atPath: url.path) ? url : nil
    }

    func delete(_ map: SavedMap) {
        let folder = rootURL.appendingPathComponent(map.id.uuidString, isDirectory: true)
        do {
            try fileManager.removeItem(at: folder)
            refresh()
        } catch {
            errorMessage = "“\(map.name)” could not be deleted: \(error.localizedDescription)"
        }
    }
}
