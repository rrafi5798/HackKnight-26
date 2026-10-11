import Foundation
import simd

struct RouteWaypoint: Codable, Identifiable, Hashable {
    let id: String
    var name: String
    var position: [Float]
    var headingRadians: Float

    init(id: String = UUID().uuidString, name: String, position: SIMD3<Float>, headingRadians: Float) {
        self.id = id
        self.name = name
        self.position = [position.x, position.y, position.z]
        self.headingRadians = headingRadians
    }

    var vector: SIMD3<Float> {
        SIMD3(position[0], position[1], position[2])
    }
}

struct SavedMap: Codable, Identifiable, Hashable {
    let id: UUID
    var name: String
    let createdAt: Date
    let waypointCount: Int
    let wallCount: Int
    let doorCount: Int
    let openingCount: Int
    let objectCount: Int
    let hasWorldMap: Bool

    var supportsNavigation: Bool {
        waypointCount >= 2 && hasWorldMap
    }
}

struct RoutePackage: Codable {
    struct Coordinate: Codable {
        let x: Float
        let y: Float
        let z: Float

        init(_ vector: SIMD3<Float>) {
            x = vector.x
            y = vector.y
            z = vector.z
        }

        var vector: SIMD3<Float> { SIMD3(x, y, z) }
    }

    struct PackageWaypoint: Codable {
        let id: String
        let position: [Float]
    }

    let schemaVersion: Int
    let zoneId: String
    let coordinateSystem: String
    let heightReference: String
    let waypoints: [PackageWaypoint]

    init(mapID: UUID, waypoints: [RouteWaypoint]) {
        schemaVersion = 1
        zoneId = mapID.uuidString
        coordinateSystem = "arkit-world-meters"
        heightReference = "device"
        self.waypoints = waypoints.map {
            PackageWaypoint(id: $0.id, position: $0.position)
        }
    }
}

struct LandmarkPackage: Codable {
    struct Landmark: Codable {
        let id: String
        let name: String
        let position: RoutePackage.Coordinate
        let headingRadians: Float
    }

    let schemaVersion: Int
    let zoneId: String
    let landmarks: [Landmark]

    init(mapID: UUID, waypoints: [RouteWaypoint]) {
        schemaVersion = 1
        zoneId = mapID.uuidString
        landmarks = waypoints.map {
            Landmark(
                id: $0.id,
                name: $0.name,
                position: RoutePackage.Coordinate($0.vector),
                headingRadians: $0.headingRadians
            )
        }
    }
}

struct ARNavigationSnapshot {
    let position: SIMD3<Float>
    let headingRadians: Float
    let trackingDescription: String
    let isRelocalized: Bool
    let nearbyObjectDistance: Float?
}

enum Wayfinding {
    static func horizontalDistance(from start: SIMD3<Float>, to end: SIMD3<Float>) -> Float {
        let dx = end.x - start.x
        let dz = end.z - start.z
        return sqrt(dx * dx + dz * dz)
    }

    static func clockPosition(from position: SIMD3<Float>, heading: Float, to target: SIMD3<Float>) -> Int {
        let dx = target.x - position.x
        let dz = target.z - position.z
        let targetHeading = atan2(-dx, -dz)
        var relative = targetHeading - heading
        while relative > .pi { relative -= 2 * .pi }
        while relative < -.pi { relative += 2 * .pi }

        let rounded = Int((relative / (.pi / 6)).rounded())
        let clock = ((12 + rounded - 1) % 12 + 12) % 12 + 1
        return clock == 13 ? 1 : clock
    }

    static func directionText(
        from position: SIMD3<Float>,
        heading: Float,
        to waypoint: RouteWaypoint,
        distance: Float
    ) -> String {
        let feet = max(1, Int((distance * 3.28084).rounded()))
        let clock = clockPosition(from: position, heading: heading, to: waypoint.vector)
        if distance < 1.2 {
            return "You are near \(waypoint.name)."
        }
        return "Continue toward \(waypoint.name), about \(feet) feet away, at \(clock) o’clock."
    }
}
