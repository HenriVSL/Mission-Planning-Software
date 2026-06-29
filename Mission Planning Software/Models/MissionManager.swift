//
//  MissionManager.swift
//  Mission Planning Software
//
//  Global, observable state for the active mission and its waypoints.
//

import CoreLocation
import Foundation
import Observation

/// Top-level interaction mode for the map.
enum AppMode {
    case navigation   // tracking + telemetry
    case edit         // authoring waypoints
}

/// Which feature layer Edit Mode is currently authoring.
enum EditLayer {
    case waypoints
    case areas        // TLS (drawn areas)
}

@Observable
final class MissionManager {

    var missionName: String
    var waypoints: [Waypoint]
    /// Tactical Layer Symbols (drawn areas) overlaid on the map.
    var areas: [TLSArea]
    var currentActiveWaypointIndex: Int

    /// Current interaction mode. Navigation is the launch default.
    var mode: AppMode = .navigation
    /// Waypoint currently selected for editing (used from Phase 2B onward).
    var selectedWaypointID: Waypoint.ID?

    /// The library file backing the current mission, if it has been saved/loaded.
    var currentFileURL: URL?

    /// Which layer Edit Mode is authoring (waypoints vs TLS areas).
    var editLayer: EditLayer = .waypoints
    /// Selected TLS area (areas layer).
    var selectedAreaID: TLSArea.ID?
    /// Whether an area is currently being drawn vertex-by-vertex.
    var isDrawingArea = false
    /// Vertices placed so far for the area being drawn.
    var draftVertices: [CLLocationCoordinate2D] = []
    /// Whether the selected area's vertices are being edited (drag/add/remove).
    var isEditingAreaShape = false

    /// Whether press-and-hold dragging of waypoints is unlocked. Locked by
    /// default so waypoints aren't moved by accident; toggled by the lock button.
    var isDragUnlocked = false

    /// Waypoint currently being repositioned via the center reticle ("Move on
    /// map"). While set, the waypoint follows the map center until dropped.
    var movingWaypointID: Waypoint.ID?
    /// Original coordinate of the moving waypoint, restored on cancel.
    @ObservationIgnored private var movingOriginalCoordinate: CLLocationCoordinate2D?

    init(
        missionName: String = "Orivesi Recon",
        waypoints: [Waypoint] = MissionManager.mockWaypoints,
        areas: [TLSArea] = MissionManager.mockAreas,
        currentActiveWaypointIndex: Int = 0
    ) {
        self.missionName = missionName
        self.waypoints = waypoints
        self.areas = areas
        self.currentActiveWaypointIndex = currentActiveWaypointIndex
    }

    // MARK: - Library load / save

    /// Snapshot of the current mission for saving.
    var currentMission: Mission {
        Mission(name: missionName,
                waypoints: waypoints,
                areas: areas,
                currentActiveWaypointIndex: currentActiveWaypointIndex)
    }

    /// Replace the current mission with a loaded one, resetting edit state.
    func load(_ mission: Mission, from url: URL?) {
        cancelMovingOnMap()
        missionName = mission.name
        waypoints = mission.waypoints
        areas = mission.areas
        currentActiveWaypointIndex = mission.waypoints.isEmpty
            ? 0
            : min(max(mission.currentActiveWaypointIndex, 0), mission.waypoints.count - 1)
        currentFileURL = url
        selectedWaypointID = nil
    }

    /// Record that the current mission was saved to `url` under `name`.
    func markSaved(as name: String, url: URL) {
        missionName = name
        currentFileURL = url
    }

    /// Start a fresh, empty mission in Edit Mode so waypoints can be dropped.
    func newMission() {
        cancelMovingOnMap()
        cancelDrawingArea()
        missionName = "New Mission"
        waypoints = []
        areas = []
        currentActiveWaypointIndex = 0
        currentFileURL = nil
        selectedWaypointID = nil
        selectedAreaID = nil
        isEditingAreaShape = false
        editLayer = .waypoints
        mode = .edit
    }

    /// The waypoint currently being navigated to, if the index is valid.
    var activeWaypoint: Waypoint? {
        guard waypoints.indices.contains(currentActiveWaypointIndex) else { return nil }
        return waypoints[currentActiveWaypointIndex]
    }

    var canAdvance: Bool { currentActiveWaypointIndex < waypoints.count - 1 }
    var canRetreat: Bool { currentActiveWaypointIndex > 0 }

    /// When true, the active waypoint auto-advances once the user enters its
    /// activation radius. Manual Prev/Next overrides still work.
    var autoAdvanceEnabled = true

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

    // MARK: - Auto-advance (activation radius)

    /// Advance the active target while the user is inside the active waypoint's
    /// activation radius. Called on each new GPS fix in Navigation Mode. Only
    /// ever moves forward; the final waypoint stays active on arrival.
    func evaluateArrival(at userCoordinate: CLLocationCoordinate2D) {
        guard autoAdvanceEnabled, mode == .navigation else { return }
        while canAdvance, let active = activeWaypoint,
              userCoordinate.distance(to: active.coordinate) <= active.activationRadius {
            advance()
        }
    }

    // MARK: - Mode

    func enterEditMode() { mode = .edit }

    func exitEditMode() {
        cancelMovingOnMap()
        cancelDrawingArea()
        mode = .navigation
        editLayer = .waypoints
        selectedWaypointID = nil
        selectedAreaID = nil
        isEditingAreaShape = false
        isDragUnlocked = false
    }

    /// Switch the editing layer, clearing selections and any in-progress draw.
    func setEditLayer(_ layer: EditLayer) {
        guard layer != editLayer else { return }
        cancelDrawingArea()
        cancelMovingOnMap()
        selectedWaypointID = nil
        selectedAreaID = nil
        isEditingAreaShape = false
        editLayer = layer
    }

    func toggleDragLock() { isDragUnlocked.toggle() }

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

    /// Remove waypoints at the given list offsets (swipe-to-delete / EditButton).
    func deleteWaypoints(atOffsets offsets: IndexSet) {
        for index in offsets.sorted(by: >) where waypoints.indices.contains(index) {
            waypoints.remove(at: index)
        }
        if let id = selectedWaypointID, !waypoints.contains(where: { $0.id == id }) {
            selectedWaypointID = nil
        }
        clampActiveIndex()
    }

    /// Delete the currently selected waypoint, if any.
    func deleteSelectedWaypoint() {
        guard let id = selectedWaypointID else { return }
        deleteWaypoint(id: id)
    }

    // MARK: - Selection

    var selectedWaypoint: Waypoint? {
        guard let id = selectedWaypointID else { return nil }
        return waypoints.first { $0.id == id }
    }

    /// Position of a waypoint in the route (used for index badges / labels).
    func index(of id: Waypoint.ID) -> Int? {
        waypoints.firstIndex { $0.id == id }
    }

    func select(_ id: Waypoint.ID) { selectedWaypointID = id }
    func deselect() { selectedWaypointID = nil }

    /// Update a waypoint's activation radius (clamped to a sane range), used by
    /// the on-map drag handle and the list editor.
    func setRadius(id: Waypoint.ID, meters: Double) {
        guard let index = waypoints.firstIndex(where: { $0.id == id }) else { return }
        waypoints[index].activationRadius = min(max(meters, 2), 3000)
    }

    // MARK: - Moving waypoints

    /// Move a waypoint to a new coordinate (used by both drag and reticle modes).
    func moveWaypoint(id: Waypoint.ID, to coordinate: CLLocationCoordinate2D) {
        guard let index = waypoints.firstIndex(where: { $0.id == id }) else { return }
        waypoints[index].coordinate = coordinate
    }

    var isMovingOnMap: Bool { movingWaypointID != nil }

    var movingWaypoint: Waypoint? {
        guard let id = movingWaypointID else { return nil }
        return waypoints.first { $0.id == id }
    }

    /// Begin repositioning a waypoint via the center reticle.
    func beginMovingOnMap(id: Waypoint.ID) {
        guard let waypoint = waypoints.first(where: { $0.id == id }) else { return }
        selectedWaypointID = id
        movingWaypointID = id
        movingOriginalCoordinate = waypoint.coordinate
    }

    /// Confirm the reticle move at the waypoint's current (followed) position.
    func confirmMovingOnMap() {
        movingWaypointID = nil
        movingOriginalCoordinate = nil
    }

    /// Cancel the reticle move, restoring the waypoint's original coordinate.
    func cancelMovingOnMap() {
        if let id = movingWaypointID, let original = movingOriginalCoordinate {
            moveWaypoint(id: id, to: original)
        }
        movingWaypointID = nil
        movingOriginalCoordinate = nil
    }

    /// Clamp `currentActiveWaypointIndex` into the valid range after edits.
    private func clampActiveIndex() {
        guard !waypoints.isEmpty else {
            currentActiveWaypointIndex = 0
            return
        }
        currentActiveWaypointIndex = min(max(currentActiveWaypointIndex, 0), waypoints.count - 1)
    }

    // MARK: - TLS areas

    var selectedArea: TLSArea? {
        guard let id = selectedAreaID else { return nil }
        return areas.first { $0.id == id }
    }

    func indexOfArea(_ id: TLSArea.ID) -> Int? {
        areas.firstIndex { $0.id == id }
    }

    func selectArea(_ id: TLSArea.ID) { selectedAreaID = id }
    func deselectArea() {
        selectedAreaID = nil
        isEditingAreaShape = false
    }

    // Drawing a new area, vertex by vertex.

    var canFinishArea: Bool { draftVertices.count >= 3 }

    func beginDrawingArea() {
        selectedAreaID = nil
        draftVertices = []
        isDrawingArea = true
    }

    func addDraftVertex(_ coordinate: CLLocationCoordinate2D) {
        guard isDrawingArea else { return }
        draftVertices.append(coordinate)
    }

    func undoDraftVertex() {
        if !draftVertices.isEmpty { draftVertices.removeLast() }
    }

    func cancelDrawingArea() {
        isDrawingArea = false
        draftVertices = []
    }

    /// Commit the drawn vertices as a new area (needs ≥ 3); selects it.
    @discardableResult
    func finishDrawingArea() -> TLSArea? {
        defer {
            isDrawingArea = false
            draftVertices = []
        }
        guard draftVertices.count >= 3 else { return nil }
        let area = TLSArea(vertices: draftVertices, colorHex: TLSPalette.defaultColor, filled: false)
        areas.append(area)
        selectedAreaID = area.id
        return area
    }

    // Editing existing areas.

    func setAreaColor(id: TLSArea.ID, hex: String) {
        guard let index = areas.firstIndex(where: { $0.id == id }) else { return }
        areas[index].colorHex = hex
    }

    func toggleAreaFilled(id: TLSArea.ID) {
        guard let index = areas.firstIndex(where: { $0.id == id }) else { return }
        areas[index].filled.toggle()
    }

    func toggleAreaShowLabel(id: TLSArea.ID) {
        guard let index = areas.firstIndex(where: { $0.id == id }) else { return }
        areas[index].showLabel.toggle()
    }

    // Vertex editing (shape edit) of an existing area.

    func beginEditingAreaShape() {
        guard selectedAreaID != nil else { return }
        isEditingAreaShape = true
    }

    func endEditingAreaShape() { isEditingAreaShape = false }

    func moveAreaVertex(areaID: TLSArea.ID, index: Int, to coordinate: CLLocationCoordinate2D) {
        guard let a = areas.firstIndex(where: { $0.id == areaID }),
              areas[a].vertices.indices.contains(index) else { return }
        areas[a].vertices[index] = coordinate
    }

    /// Insert a new vertex after `index` (used by the edge "+" handles).
    func insertAreaVertex(areaID: TLSArea.ID, afterIndex index: Int, coordinate: CLLocationCoordinate2D) {
        guard let a = areas.firstIndex(where: { $0.id == areaID }) else { return }
        let insertAt = min(index + 1, areas[a].vertices.count)
        areas[a].vertices.insert(coordinate, at: insertAt)
    }

    /// Remove a vertex (keeps at least a triangle).
    func removeAreaVertex(areaID: TLSArea.ID, index: Int) {
        guard let a = areas.firstIndex(where: { $0.id == areaID }),
              areas[a].vertices.count > 3,
              areas[a].vertices.indices.contains(index) else { return }
        areas[a].vertices.remove(at: index)
    }

    func deleteArea(id: TLSArea.ID) {
        areas.removeAll { $0.id == id }
        if selectedAreaID == id { selectedAreaID = nil }
    }

    func deleteSelectedArea() {
        if let id = selectedAreaID { deleteArea(id: id) }
    }

    func deleteAreas(atOffsets offsets: IndexSet) {
        for index in offsets.sorted(by: >) where areas.indices.contains(index) {
            let removed = areas.remove(at: index)
            if selectedAreaID == removed.id { selectedAreaID = nil }
        }
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

    /// Mock TLS areas near the route: a blue outlined operating area and a
    /// filled red no-go zone, for visualizing Phase TLS rendering.
    static let mockAreas: [TLSArea] = [
        TLSArea(
            name: "Op Area",
            vertices: [
                .init(latitude: 61.6790, longitude: 24.3500),
                .init(latitude: 61.6835, longitude: 24.3585),
                .init(latitude: 61.6800, longitude: 24.3660),
                .init(latitude: 61.6760, longitude: 24.3585),
            ],
            colorHex: "0A84FF",
            filled: false
        ),
        TLSArea(
            name: "No-Go",
            vertices: [
                .init(latitude: 61.6758, longitude: 24.3585),
                .init(latitude: 61.6772, longitude: 24.3602),
                .init(latitude: 61.6748, longitude: 24.3608),
            ],
            colorHex: "FF3B30",
            filled: true
        ),
    ]
}
