//
//  MissionManager.swift
//  Mission Planning Software
//
//  Global, observable state for the active mission and its waypoints.
//

import CoreLocation
import Observation

/// Top-level interaction mode for the map.
enum AppMode {
    case navigation   // tracking + telemetry
    case edit         // authoring waypoints
}

@Observable
final class MissionManager {

    var missionName: String
    var waypoints: [Waypoint]
    var currentActiveWaypointIndex: Int

    /// Current interaction mode. Navigation is the launch default.
    var mode: AppMode = .navigation
    /// Waypoint currently selected for editing (used from Phase 2B onward).
    var selectedWaypointID: Waypoint.ID?

    init(
        missionName: String = "Orivesi Recon",
        waypoints: [Waypoint] = MissionManager.mockWaypoints,
        currentActiveWaypointIndex: Int = 0
    ) {
        self.missionName = missionName
        self.waypoints = waypoints
        self.currentActiveWaypointIndex = currentActiveWaypointIndex
    }

    /// The waypoint currently being navigated to, if the index is valid.
    var activeWaypoint: Waypoint? {
        guard waypoints.indices.contains(currentActiveWaypointIndex) else { return nil }
        return waypoints[currentActiveWaypointIndex]
    }

    var canAdvance: Bool { currentActiveWaypointIndex < waypoints.count - 1 }
    var canRetreat: Bool { currentActiveWaypointIndex > 0 }

    /// Manual override: advance to the next waypoint in the route.
    func advance() {
        guard canAdvance else { return }
        currentActiveWaypointIndex += 1
    }

    /// Manual override: step back to the previous waypoint in the route.
    func retreat() {
        guard canRetreat else { return }
        currentActiveWaypointIndex -= 1
    }

    // MARK: - Mode

    func enterEditMode() { mode = .edit }

    func exitEditMode() {
        mode = .navigation
        selectedWaypointID = nil
    }

    // MARK: - Editing

    /// Append a new waypoint at the given coordinate and return it.
    @discardableResult
    func addWaypoint(at coordinate: CLLocationCoordinate2D, radius: Double = 25) -> Waypoint {
        let waypoint = Waypoint(coordinate: coordinate, activationRadius: radius)
        waypoints.append(waypoint)
        return waypoint
    }

    /// Remove a waypoint and keep the active index / selection consistent.
    func deleteWaypoint(id: Waypoint.ID) {
        guard let index = waypoints.firstIndex(where: { $0.id == id }) else { return }
        waypoints.remove(at: index)
        if selectedWaypointID == id { selectedWaypointID = nil }
        clampActiveIndex()
    }

    /// Clamp `currentActiveWaypointIndex` into the valid range after edits.
    private func clampActiveIndex() {
        guard !waypoints.isEmpty else {
            currentActiveWaypointIndex = 0
            return
        }
        currentActiveWaypointIndex = min(max(currentActiveWaypointIndex, 0), waypoints.count - 1)
    }

    // MARK: - Phase 1 mock data

    /// Hardcoded route near Orivesi, Pirkanmaa (~61.677, 24.356) for field
    /// testing of GPS tracking and route rendering. Replaced by imported /
    /// user-authored missions in later phases.
    static let mockWaypoints: [Waypoint] = [
        Waypoint(name: "Alpha",   coordinate: .init(latitude: 61.6770, longitude: 24.3560), activationRadius: 25),
        Waypoint(name: "Bravo",   coordinate: .init(latitude: 61.6805, longitude: 24.3625), activationRadius: 25),
        Waypoint(name: "Charlie", coordinate: .init(latitude: 61.6840, longitude: 24.3540), activationRadius: 30),
        Waypoint(name: "Delta",   coordinate: .init(latitude: 61.6795, longitude: 24.3470), activationRadius: 20),
        Waypoint(name: "Echo",    coordinate: .init(latitude: 61.6760, longitude: 24.3500), activationRadius: 25),
    ]
}
