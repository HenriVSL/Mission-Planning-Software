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
    case markers      // emoji icons
}

@Observable
final class MissionManager {

    var missionName: String
    var waypoints: [Waypoint]
    /// Tactical Layer Symbols (drawn areas) overlaid on the map.
    var areas: [TLSArea]
    /// Free-form emoji markers overlaid on the map.
    var markers: [MapMarker]
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
    /// Selected emoji marker (markers layer).
    var selectedMarkerID: MapMarker.ID?
    /// Emoji used for the next dropped marker.
    var currentEmoji: String = "📍"
    /// Marker currently being repositioned via the center reticle.
    var movingMarkerID: MapMarker.ID?
    @ObservationIgnored private var movingMarkerOriginalCoordinate: CLLocationCoordinate2D?
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
        missionName: String = "New Mission",
        waypoints: [Waypoint] = [],
        areas: [TLSArea] = [],
        markers: [MapMarker] = [],
        currentActiveWaypointIndex: Int = 0
    ) {
        self.missionName = missionName
        self.waypoints = waypoints
        self.areas = areas
        self.markers = markers
        self.currentActiveWaypointIndex = currentActiveWaypointIndex
    }

    @ObservationIgnored private var didLoadInitial = false
    private static let lastMissionKey = "lastMissionFileName"

    /// On first launch, load the last-used mission (or the most recently saved
    /// one) from the library. Stays empty if there are no saved missions.
    func loadLastMissionIfAvailable() {
        guard !didLoadInitial else { return }
        didLoadInitial = true

        // Prefer the last-used file (tracked by name, since the sandbox path
        // can change between launches).
        if let name = UserDefaults.standard.string(forKey: Self.lastMissionKey) {
            let url = MissionStore.documentsURL.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: url.path),
               let loaded = MissionStore.load(url) {
                load(loaded, from: url)
                return
            }
        }
        // Fall back to the most recently modified saved mission.
        if let newest = MissionStore.list().first, let loaded = MissionStore.load(newest.url) {
            load(loaded, from: newest.url)
        }
    }

    private func rememberLastMission(_ url: URL?) {
        if let name = url?.lastPathComponent {
            UserDefaults.standard.set(name, forKey: Self.lastMissionKey)
        }
    }

    // MARK: - Library load / save

    /// Snapshot of the current mission for saving.
    var currentMission: Mission {
        Mission(name: missionName,
                waypoints: waypoints,
                areas: areas,
                markers: markers,
                currentActiveWaypointIndex: currentActiveWaypointIndex)
    }

    /// Replace the current mission with a loaded one, resetting edit state.
    func load(_ mission: Mission, from url: URL?) {
        cancelAnyMoveOnMap()
        missionName = mission.name
        waypoints = mission.waypoints
        areas = mission.areas
        markers = mission.markers
        currentActiveWaypointIndex = mission.waypoints.isEmpty
            ? 0
            : min(max(mission.currentActiveWaypointIndex, 0), mission.waypoints.count - 1)
        currentFileURL = url
        selectedWaypointID = nil
        selectedAreaID = nil
        selectedMarkerID = nil
        rememberLastMission(url)
    }

    /// Record that the current mission was saved to `url` under `name`.
    func markSaved(as name: String, url: URL) {
        missionName = name
        currentFileURL = url
        rememberLastMission(url)
    }

    /// Start a fresh, empty mission in Edit Mode so waypoints can be dropped.
    func newMission() {
        cancelMovingOnMap()
        cancelDrawingArea()
        missionName = "New Mission"
        waypoints = []
        areas = []
        markers = []
        currentActiveWaypointIndex = 0
        currentFileURL = nil
        selectedWaypointID = nil
        selectedAreaID = nil
        selectedMarkerID = nil
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
        cancelAnyMoveOnMap()
        cancelDrawingArea()
        mode = .navigation
        editLayer = .waypoints
        selectedWaypointID = nil
        selectedAreaID = nil
        selectedMarkerID = nil
        isEditingAreaShape = false
        isDragUnlocked = false
    }

    /// Switch the editing layer, clearing selections and any in-progress draw.
    func setEditLayer(_ layer: EditLayer) {
        guard layer != editLayer else { return }
        cancelDrawingArea()
        cancelAnyMoveOnMap()
        selectedWaypointID = nil
        selectedAreaID = nil
        selectedMarkerID = nil
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

    var isMovingOnMap: Bool { movingWaypointID != nil || movingMarkerID != nil }

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

    // MARK: - Markers (emoji)

    var selectedMarker: MapMarker? {
        guard let id = selectedMarkerID else { return nil }
        return markers.first { $0.id == id }
    }

    func indexOfMarker(_ id: MapMarker.ID) -> Int? {
        markers.firstIndex { $0.id == id }
    }

    func selectMarker(_ id: MapMarker.ID) { selectedMarkerID = id }
    func deselectMarker() { selectedMarkerID = nil }

    /// Drop a new marker (using `currentEmoji`) at the given coordinate; selects it.
    @discardableResult
    func addMarker(at coordinate: CLLocationCoordinate2D) -> MapMarker {
        let marker = MapMarker(emoji: currentEmoji, coordinate: coordinate)
        markers.append(marker)
        selectedMarkerID = marker.id
        return marker
    }

    func setMarkerEmoji(id: MapMarker.ID, emoji: String) {
        guard let index = markers.firstIndex(where: { $0.id == id }), !emoji.isEmpty else { return }
        markers[index].emoji = emoji
    }

    func toggleMarkerShowLabel(id: MapMarker.ID) {
        guard let index = markers.firstIndex(where: { $0.id == id }) else { return }
        markers[index].showLabel.toggle()
    }

    func deleteMarker(id: MapMarker.ID) {
        markers.removeAll { $0.id == id }
        if selectedMarkerID == id { selectedMarkerID = nil }
    }

    func deleteSelectedMarker() {
        if let id = selectedMarkerID { deleteMarker(id: id) }
    }

    func deleteMarkers(atOffsets offsets: IndexSet) {
        for index in offsets.sorted(by: >) where markers.indices.contains(index) {
            let removed = markers.remove(at: index)
            if selectedMarkerID == removed.id { selectedMarkerID = nil }
        }
    }

    // Moving markers (drag + reticle), mirroring waypoints.

    func moveMarker(id: MapMarker.ID, to coordinate: CLLocationCoordinate2D) {
        guard let index = markers.firstIndex(where: { $0.id == id }) else { return }
        markers[index].coordinate = coordinate
    }

    var movingMarker: MapMarker? {
        guard let id = movingMarkerID else { return nil }
        return markers.first { $0.id == id }
    }

    func beginMovingMarkerOnMap(id: MapMarker.ID) {
        guard let marker = markers.first(where: { $0.id == id }) else { return }
        selectedMarkerID = id
        movingMarkerID = id
        movingMarkerOriginalCoordinate = marker.coordinate
    }

    func confirmMovingMarkerOnMap() {
        movingMarkerID = nil
        movingMarkerOriginalCoordinate = nil
    }

    func cancelMovingMarkerOnMap() {
        if let id = movingMarkerID, let original = movingMarkerOriginalCoordinate {
            moveMarker(id: id, to: original)
        }
        movingMarkerID = nil
        movingMarkerOriginalCoordinate = nil
    }

    /// Cancel any in-progress reticle move (waypoint or marker).
    func cancelAnyMoveOnMap() {
        cancelMovingOnMap()
        cancelMovingMarkerOnMap()
    }
}
