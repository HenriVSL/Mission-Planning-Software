//
//  MissionMapView.swift
//  Mission Planning Software
//
//  Full-screen navigation map: tracks the user, draws the baseline route and
//  the highlighted active leg, and overlays the targeting arrow + HUD.
//

import MapKit
import SwiftUI
import UIKit

struct MissionMapView: View {
    @Environment(MissionManager.self) private var mission
    @Environment(LocationManager.self) private var location
    @Environment(AppSettings.self) private var settings

    /// Camera follows the user's location; falls back to the route region
    /// until the first GPS fix arrives.
    @State private var camera: MapCameraPosition = .userLocation(fallback: .automatic)

    /// Geographic coordinate currently under the screen center — the drop point
    /// for new waypoints in Edit Mode. Kept in sync via `onMapCameraChange`.
    @State private var mapCenter = CLLocationCoordinate2D(latitude: 61.677, longitude: 24.356)

    /// Current map rotation (compass direction that is "up" on screen), in
    /// degrees clockwise from north. Non-zero in heading-up / rotated views;
    /// subtracted from the bearing so the targeting arrow stays correct.
    @State private var mapHeading: CLLocationDirection = 0

    /// Whether the mission menu sheet is presented.
    @State private var showingMenu = false

    /// Whether the waypoint list editor sheet is presented.
    @State private var showingList = false

    /// Whether the TLS area list editor sheet is presented.
    @State private var showingAreaList = false

    /// Whether the marker list editor sheet is presented.
    @State private var showingMarkerList = false

    /// Current camera distance (meters); markers hide past a threshold.
    @State private var mapDistance: CLLocationDistance = 0

    /// Briefly true after a quick-save (control-island checkmark feedback).
    @State private var justSaved = false

    /// Markers are hidden when zoomed out past this camera distance (declutter).
    private let markerVisibilityMaxDistance: CLLocationDistance = 150_000

    // Marker zoom-scaling: emoji grow/shrink with the map (like houses), so they
    // track ground features. Scale == 1 at the reference distance; clamped so
    // they don't get too big zoomed in or vanish before the hide threshold.
    private let markerReferenceDistance: CLLocationDistance = 3_000  // scale 1.0 here
    private let markerMinScale: CGFloat = 0.45
    private let markerMaxScale: CGFloat = 0.9

    private var markerScale: CGFloat {
        guard mapDistance > 0 else { return 1 }
        let raw = CGFloat(markerReferenceDistance / mapDistance)
        return min(max(raw, markerMinScale), markerMaxScale)
    }

    /// True bearing from the user to the active (next) waypoint, in degrees from
    /// north. Always anchored at the user's position regardless of which route
    /// segment is currently highlighted.
    private var bearingToActive: Double {
        guard let user = location.userLocation,
              let active = mission.activeWaypoint else { return 0 }
        return user.bearing(to: active.coordinate)
    }

    /// One drawable leg of the route between two consecutive waypoints. Drawn
    /// exactly once — solid green when it's the active leg, dashed white otherwise
    /// — so no two polylines ever overlap (MapKit's overlap draw order is undefined).
    private struct RouteSegment: Identifiable {
        let id: Int            // index of the segment's starting waypoint
        let coordinates: [CLLocationCoordinate2D]
        let isActive: Bool
    }

    /// The waypoint-to-waypoint legs. The active leg is the one *ending* at the
    /// active waypoint (only when the active index is >= 1; index 0's active leg
    /// runs from the user's position to WP0 and is handled separately).
    private var routeSegments: [RouteSegment] {
        let waypoints = mission.waypoints
        guard waypoints.count >= 2 else { return [] }
        let activeIndex = mission.currentActiveWaypointIndex

        return (0..<(waypoints.count - 1)).map { i in
            RouteSegment(
                id: i,
                coordinates: [waypoints[i].coordinate, waypoints[i + 1].coordinate],
                isActive: (i + 1) == activeIndex
            )
        }
    }

    private var isEditing: Bool { mission.mode == .edit }

    var body: some View {
        // MapReader gives us screen <-> coordinate conversion for the radius handle.
        MapReader { proxy in
            Map(position: $camera) {
                mapContent(proxy)
                radiusContent(proxy)
            }
            .mapStyle(mapStyle)
            .mapControls {
                MapUserLocationButton()
                MapCompass()
                MapScaleView()
            }
            .onMapCameraChange(frequency: .continuous) { context in
                mapCenter = context.region.center
                mapHeading = context.camera.heading
                mapDistance = context.camera.distance
                // While moving via the reticle, keep the feature pinned to center.
                if let id = mission.movingWaypointID {
                    mission.moveWaypoint(id: id, to: context.region.center)
                }
                if let id = mission.movingMarkerID {
                    mission.moveMarker(id: id, to: context.region.center)
                }
            }
            // Edit Mode reticle, pinned to the screen center (waypoint drop or
            // area vertex placement). It ignores the keyboard so it stays aligned
            // with the map center (the drop point) when the emoji keyboard is up.
            .overlay {
                if showsCrosshair {
                    CrosshairView()
                        .ignoresSafeArea(.keyboard, edges: .bottom)
                }
            }
            .overlay(alignment: .topTrailing) { controlIsland }
            .overlay(alignment: .top) { topControls }
            .overlay(alignment: .bottom) { bottomBar }
            // Ignore the home-indicator inset (full-bleed map) but NOT the
            // keyboard, so the bottom bar rises above the emoji keyboard.
            .ignoresSafeArea(.container, edges: .bottom)
            .onAppear {
                mission.loadLastMissionIfAvailable()
                location.start()
                UIApplication.shared.isIdleTimerDisabled = settings.keepAwake
            }
            .onChange(of: settings.keepAwake) { _, keepAwake in
                UIApplication.shared.isIdleTimerDisabled = keepAwake
            }
            .onChange(of: location.updateCount) { _, _ in
                if let user = location.userLocation {
                    mission.evaluateArrival(at: user)
                }
            }
            .onChange(of: mission.mode) { _, newMode in
                // Re-center and follow the user again when returning to navigation.
                if newMode == .navigation {
                    withAnimation { camera = .userLocation(fallback: .automatic) }
                }
            }
            .sheet(isPresented: $showingMenu) {
                MissionMenuView()
            }
            .sheet(isPresented: $showingList) {
                WaypointListView(onLocate: locate(_:), onMove: beginMove(_:))
            }
            .sheet(isPresented: $showingAreaList) {
                AreaListView(onLocate: locateArea(_:))
            }
            .sheet(isPresented: $showingMarkerList) {
                MarkerListView(onLocate: locateMarker(_:))
            }
        }
    }

    private var isMoving: Bool { mission.isMovingOnMap }
    private var isDrawing: Bool { mission.isDrawingArea }
    private var isAreasLayer: Bool { mission.editLayer == .areas }
    private var isWaypointsLayer: Bool { mission.editLayer == .waypoints }
    private var isMarkersLayer: Bool { mission.editLayer == .markers }

    /// The crosshair is shown when placing waypoints/markers or drawing vertices.
    private var showsCrosshair: Bool {
        isEditing && (isWaypointsLayer || isMarkersLayer || isDrawing)
    }

    /// Markers render unless zoomed far out — but always while editing them.
    private var showsMarkers: Bool {
        (isEditing && isMarkersLayer) || mapDistance <= markerVisibilityMaxDistance
    }

    /// Banner + the Waypoints/Areas layer toggle.
    private var topControls: some View {
        VStack(spacing: 8) {
            topBanner
            if isEditing && !isMoving && !isDrawing && !mission.isEditingAreaShape {
                Picker("Layer", selection: Binding(
                    get: { mission.editLayer },
                    set: { mission.setEditLayer($0) }
                )) {
                    Text("Waypoints").tag(EditLayer.waypoints)
                    Text("Areas").tag(EditLayer.areas)
                    Text("Markers").tag(EditLayer.markers)
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 240)
            }
        }
        .padding(.top, 4)
    }

    /// The active base map style.
    private var mapStyle: MapStyle {
        switch settings.mapStyle {
        case .standard: return .standard(elevation: .realistic, pointsOfInterest: .excludingAll)
        case .hybrid: return .hybrid(elevation: .realistic, pointsOfInterest: .excludingAll)
        case .satellite: return .imagery(elevation: .realistic)
        }
    }

    /// Edit-mode control island (top-right): map type + drag lock together.
    @ViewBuilder
    private var controlIsland: some View {
        if isEditing && !isMoving {
            VStack(spacing: 4) {
                mapStyleMenu
                Divider().frame(width: 26).overlay(.white.opacity(0.2))
                saveButton
                if isWaypointsLayer || isMarkersLayer {
                    Divider().frame(width: 26).overlay(.white.opacity(0.2))
                    lockToggle
                }
            }
            .padding(5)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(.white.opacity(0.15), lineWidth: 1))
            .shadow(color: .black.opacity(0.35), radius: 5, y: 2)
            .padding(.trailing, 12)
            .padding(.top, 70)
        }
    }

    private var mapStyleMenu: some View {
        Menu {
            Picker("Map Type", selection: Binding(
                get: { settings.mapStyle },
                set: { settings.mapStyle = $0 }
            )) {
                ForEach(MapStyleOption.allCases) { option in
                    Label(option.label, systemImage: option.systemImage).tag(option)
                }
            }
        } label: {
            Image(systemName: "square.3.layers.3d")
                .font(.headline)
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
        }
    }

    private var lockToggle: some View {
        Button {
            mission.toggleDragLock()
        } label: {
            Image(systemName: mission.isDragUnlocked ? "lock.open.fill" : "lock.fill")
                .font(.headline)
                .foregroundStyle(mission.isDragUnlocked ? .green : .white)
                .frame(width: 40, height: 40)
        }
    }

    /// Quick-save: overwrite the current mission's file (or create it under the
    /// current name if it has never been saved). Briefly shows a checkmark.
    private var saveButton: some View {
        Button {
            saveCurrentMission()
            withAnimation { justSaved = true }
            Task {
                try? await Task.sleep(for: .seconds(1.2))
                withAnimation { justSaved = false }
            }
        } label: {
            Image(systemName: justSaved ? "checkmark" : "square.and.arrow.down")
                .font(.headline)
                .foregroundStyle(justSaved ? .green : .white)
                .frame(width: 40, height: 40)
        }
    }

    private func saveCurrentMission() {
        let name = mission.currentFileURL?.deletingPathExtension().lastPathComponent
            ?? MissionStore.sanitize(mission.missionName)
        if let url = try? MissionStore.save(mission.currentMission, fileName: name) {
            mission.markSaved(as: name, url: url)
        }
    }

    /// Navigation Mode shows telemetry; Edit Mode shows the authoring controls,
    /// with a selected-waypoint action bar stacked above when applicable.
    @ViewBuilder
    private var bottomBar: some View {
        if isMoving {
            MoveModeBar(
                onCancel: { withAnimation { mission.cancelAnyMoveOnMap() } },
                onDrop: { confirmMove() }
            )
        } else if isEditing && isAreasLayer {
            areasBottomBar
        } else if isEditing && isMarkersLayer {
            markersBottomBar
        } else if isEditing {
            VStack(spacing: 8) {
                if let selected = mission.selectedWaypoint,
                   let index = mission.index(of: selected.id) {
                    SelectedWaypointBar(
                        index: index,
                        waypoint: selected,
                        onEdit: { showingList = true },
                        onMove: { beginMove(selected) }
                    )
                }
                EditModeBar(
                    onDrop: { mission.addWaypoint(at: mapCenter) },
                    onOpenList: { showingList = true }
                )
            }
        } else {
            TelemetryHUDView(onOpenMenu: { showingMenu = true })
        }
    }

    @ViewBuilder
    private var areasBottomBar: some View {
        if isDrawing {
            DrawAreaBar(onAddPoint: { mission.addDraftVertex(mapCenter) })
        } else if mission.isEditingAreaShape {
            ShapeEditBar()
        } else {
            VStack(spacing: 8) {
                if let area = mission.selectedArea,
                   let index = mission.indexOfArea(area.id) {
                    SelectedAreaBar(
                        index: index,
                        area: area,
                        onEditShape: { mission.beginEditingAreaShape() }
                    )
                }
                AreaEditBar(onOpenList: { showingAreaList = true })
            }
        }
    }

    @ViewBuilder
    private var markersBottomBar: some View {
        VStack(spacing: 8) {
            if let marker = mission.selectedMarker,
               let index = mission.indexOfMarker(marker.id) {
                SelectedMarkerBar(index: index, marker: marker,
                                  onMove: { beginMoveMarker(marker) })
            }
            MarkerEditBar(
                onDrop: { mission.addMarker(at: mapCenter) },
                onOpenList: { showingMarkerList = true }
            )
        }
    }

    /// Enter reticle-move for a marker (mirrors waypoint move).
    private func beginMoveMarker(_ marker: MapMarker) {
        mission.beginMovingMarkerOnMap(id: marker.id)
        withAnimation {
            camera = .region(MKCoordinateRegion(
                center: marker.coordinate,
                latitudinalMeters: 300,
                longitudinalMeters: 300
            ))
        }
    }

    /// Recenter the camera on a marker and select it (marker list "Show on map").
    private func locateMarker(_ marker: MapMarker) {
        mission.selectMarker(marker.id)
        withAnimation {
            camera = .region(MKCoordinateRegion(
                center: marker.coordinate,
                latitudinalMeters: 400,
                longitudinalMeters: 400
            ))
        }
    }

    /// Recenter the camera on an area and select it (areas list "Show on map").
    private func locateArea(_ area: TLSArea) {
        mission.selectArea(area.id)
        withAnimation {
            camera = .region(MKCoordinateRegion(
                center: area.center,
                latitudinalMeters: 800,
                longitudinalMeters: 800
            ))
        }
    }

    /// Recenter the camera on a waypoint (used by the list's "Show on map").
    private func locate(_ waypoint: Waypoint) {
        mission.select(waypoint.id)
        withAnimation {
            camera = .region(MKCoordinateRegion(
                center: waypoint.coordinate,
                latitudinalMeters: 400,
                longitudinalMeters: 400
            ))
        }
    }

    /// Enter reticle-move mode: center the camera on the waypoint so it sits
    /// under the crosshair, then it follows the center as the map is panned.
    private func beginMove(_ waypoint: Waypoint) {
        mission.beginMovingOnMap(id: waypoint.id)
        withAnimation {
            camera = .region(MKCoordinateRegion(
                center: waypoint.coordinate,
                latitudinalMeters: 300,
                longitudinalMeters: 300
            ))
        }
    }

    /// Confirm the reticle move at the current map center (waypoint or marker).
    private func confirmMove() {
        if let id = mission.movingWaypointID {
            mission.moveWaypoint(id: id, to: mapCenter)
            mission.confirmMovingOnMap()
        } else if let id = mission.movingMarkerID {
            mission.moveMarker(id: id, to: mapCenter)
            mission.confirmMovingMarkerOnMap()
        }
    }

    // MARK: - Map content

    @MapContentBuilder
    private func mapContent(_ proxy: MapProxy) -> some MapContent {
        // TLS areas (tactical overlays) — drawn first, beneath the route and
        // markers. Outline-only unless filled; selected area gets a thicker line.
        ForEach(mission.areas) { area in
            if area.vertices.count >= 3 {
                let color = Color(hex: area.colorHex)
                let isSelected = isEditing && isAreasLayer && mission.selectedAreaID == area.id
                MapPolygon(coordinates: area.vertices)
                    .foregroundStyle(area.filled ? color.opacity(0.25) : .clear)
                    .stroke(color, lineWidth: isSelected ? 6 : 3)
            }
        }

        // Route legs — each drawn once. The active leg is solid green; every
        // other leg is white dashed. No overlapping polylines.
        ForEach(routeSegments) { segment in
            if segment.isActive {
                MapPolyline(coordinates: segment.coordinates)
                    .stroke(.green, style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
            } else {
                MapPolyline(coordinates: segment.coordinates)
                    .stroke(.white, style: StrokeStyle(
                        lineWidth: 3,
                        lineCap: .round,
                        lineJoin: .round,
                        dash: [10, 8]
                    ))
            }
        }

        // The first leg (user → WP0) is the active leg while WP0 is the target;
        // drawn solid green from the user's live position.
        if mission.currentActiveWaypointIndex == 0,
           let user = location.userLocation,
           let first = mission.waypoints.first {
            MapPolyline(coordinates: [user, first.coordinate])
                .stroke(.green, style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
        }

        // Waypoint markers (active one highlighted; tap to select, or — when
        // unlocked — press-and-hold to drag in Edit Mode).
        ForEach(Array(mission.waypoints.enumerated()), id: \.element.id) { index, waypoint in
            Annotation("", coordinate: waypoint.coordinate, anchor: .center) {
                waypointMarker(index: index, waypoint: waypoint, proxy: proxy)
            }
        }

        // Active waypoint's activation radius — a subtle trigger ring shown in
        // Navigation Mode so the auto-advance zone is visible.
        if !isEditing, let active = mission.activeWaypoint {
            MapCircle(center: active.coordinate, radius: active.activationRadius)
                .foregroundStyle(.green.opacity(0.08))
                .stroke(.green.opacity(0.6), style: StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
        }

        // TLS area labels — tappable to select (areas layer, not drawing/shaping).
        if isEditing && isAreasLayer && !isDrawing && !mission.isEditingAreaShape {
            ForEach(mission.areas) { area in
                let index = mission.indexOfArea(area.id) ?? 0
                Annotation("", coordinate: area.center, anchor: .center) {
                    AreaMarkerView(
                        name: area.displayName(index: index),
                        colorHex: area.colorHex,
                        isSelected: mission.selectedAreaID == area.id
                    )
                    .onTapGesture { mission.selectArea(area.id) }
                }
            }
        }

        // Navigation Mode: show labels only for areas opted-in via showLabel.
        if !isEditing {
            ForEach(mission.areas) { area in
                if area.showLabel {
                    let index = mission.indexOfArea(area.id) ?? 0
                    Annotation("", coordinate: area.center, anchor: .center) {
                        AreaMarkerView(
                            name: area.displayName(index: index),
                            colorHex: area.colorHex,
                            isSelected: false
                        )
                    }
                }
            }
        }

        // Shape editing: draggable vertex handles + edge "+" add handles.
        if isEditing && isAreasLayer && mission.isEditingAreaShape,
           let area = mission.selectedArea {
            shapeEditHandles(for: area, proxy: proxy)
        }

        // Emoji markers — hidden when zoomed far out (except while editing them).
        if showsMarkers {
            ForEach(mission.markers) { marker in
                Annotation("", coordinate: marker.coordinate, anchor: .center) {
                    markerAnnotation(marker, proxy: proxy)
                }
            }
        }

        // Draft area being drawn — connecting line + vertex dots.
        if isDrawing {
            if mission.draftVertices.count >= 2 {
                MapPolyline(coordinates: mission.draftVertices)
                    .stroke(.yellow, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
            }
            ForEach(Array(mission.draftVertices.enumerated()), id: \.offset) { _, vertex in
                Annotation("", coordinate: vertex, anchor: .center) {
                    Circle()
                        .fill(.yellow)
                        .overlay(Circle().stroke(.black, lineWidth: 1))
                        .frame(width: 10, height: 10)
                }
            }
        }

        // Targeting arrow pinned at the user's current location (navigation only).
        // Compensate for map rotation so it points at the target on screen even
        // in heading-up or manually-rotated views.
        if !isEditing, let user = location.userLocation {
            Annotation("", coordinate: user, anchor: .center) {
                TargetingArrowView(bearing: bearingToActive - mapHeading)
            }
        }
    }

    // MARK: - Radius editing (Edit Mode)

    /// The selected waypoint's activation-radius circle plus a draggable handle
    /// on its circumference. Only present in Edit Mode with a selection.
    @MapContentBuilder
    private func radiusContent(_ proxy: MapProxy) -> some MapContent {
        if isEditing, !isMoving, isWaypointsLayer,
           let selected = mission.selectedWaypoint {
            MapCircle(center: selected.coordinate, radius: selected.activationRadius)
                .foregroundStyle(.yellow.opacity(0.12))
                .stroke(.yellow, style: StrokeStyle(lineWidth: 2))

            // Radius handle — hidden while drag-to-move is unlocked so it can't be
            // grabbed by mistake when dragging the waypoint itself.
            if !mission.isDragUnlocked {
                // Handle placed due east of the center, on the circle.
                let handle = selected.coordinate.coordinate(
                    bearingDegrees: 90,
                    distanceMeters: selected.activationRadius
                )
                Annotation("", coordinate: handle, anchor: .center) {
                    radiusHandle(for: selected, proxy: proxy)
                }
            }
        }
    }

    // MARK: - Waypoint marker

    /// A waypoint marker. Tapping selects it in Edit Mode. When drag is unlocked
    /// (and not in reticle-move mode), press-and-hold then drag repositions it.
    @ViewBuilder
    private func waypointMarker(index: Int, waypoint: Waypoint, proxy: MapProxy) -> some View {
        let marker = WaypointMarkerView(
            index: index,
            isActive: index == mission.currentActiveWaypointIndex,
            isSelected: isEditing && mission.selectedWaypointID == waypoint.id
        )
        .onTapGesture {
            if isEditing && !isMoving && isWaypointsLayer { mission.select(waypoint.id) }
        }

        if isEditing && !isMoving && isWaypointsLayer && mission.isDragUnlocked {
            marker.gesture(
                LongPressGesture(minimumDuration: 0.25)
                    .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .global))
                    .onChanged { value in
                        if case .second(true, let drag?) = value {
                            mission.select(waypoint.id)
                            if let coordinate = proxy.convert(drag.location, from: .global) {
                                mission.moveWaypoint(id: waypoint.id, to: coordinate)
                            }
                        }
                    }
            )
        } else {
            marker
        }
    }

    // MARK: - Emoji marker

    /// An emoji marker. Tap selects it (markers layer); when drag is unlocked,
    /// press-and-hold then drag repositions it.
    @ViewBuilder
    private func markerAnnotation(_ mapMarker: MapMarker, proxy: MapProxy) -> some View {
        let view = MarkerView(
            emoji: mapMarker.emoji,
            name: mapMarker.name,
            showLabel: mapMarker.showLabel,
            isSelected: isEditing && isMarkersLayer && mission.selectedMarkerID == mapMarker.id,
            backgroundHex: mapMarker.backgroundHex
        )
        .scaleEffect(markerScale)
        .onTapGesture {
            if isEditing && !isMoving && isMarkersLayer { mission.selectMarker(mapMarker.id) }
        }

        if isEditing && !isMoving && isMarkersLayer && mission.isDragUnlocked {
            view.gesture(
                LongPressGesture(minimumDuration: 0.25)
                    .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .global))
                    .onChanged { value in
                        if case .second(true, let drag?) = value {
                            mission.selectMarker(mapMarker.id)
                            if let coordinate = proxy.convert(drag.location, from: .global) {
                                mission.moveMarker(id: mapMarker.id, to: coordinate)
                            }
                        }
                    }
            )
        } else {
            view
        }
    }

    private func radiusHandle(for waypoint: Waypoint, proxy: MapProxy) -> some View {
        ZStack {
            // Live meters label floating above the handle.
            Text("\(Int(waypoint.activationRadius.rounded())) m")
                .font(.caption2.bold().monospacedDigit())
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.yellow, in: Capsule())
                .foregroundStyle(.black)
                .fixedSize()
                .offset(y: -26)

            Circle()
                .fill(.yellow)
                .overlay(Circle().stroke(.black, lineWidth: 1.5))
                .frame(width: 20, height: 20)
        }
        .frame(width: 48, height: 48)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .global)
                .onChanged { value in
                    if let dragged = proxy.convert(value.location, from: .global) {
                        let meters = waypoint.coordinate.distance(to: dragged)
                        mission.setRadius(id: waypoint.id, meters: meters)
                    }
                }
        )
    }

    // MARK: - Area shape editing

    private struct ShapeHandle: Identifiable {
        enum Kind { case vertex(Int); case midpoint(after: Int) }
        let id: String
        let coordinate: CLLocationCoordinate2D
        let kind: Kind
    }

    /// Draggable vertex handles plus an "+" handle at each edge midpoint.
    private func shapeHandles(for area: TLSArea) -> [ShapeHandle] {
        let vertices = area.vertices
        guard vertices.count >= 2 else { return [] }
        var handles: [ShapeHandle] = []
        for i in vertices.indices {
            handles.append(ShapeHandle(id: "v\(i)", coordinate: vertices[i], kind: .vertex(i)))
            let next = vertices[(i + 1) % vertices.count]
            let mid = CLLocationCoordinate2D(
                latitude: (vertices[i].latitude + next.latitude) / 2,
                longitude: (vertices[i].longitude + next.longitude) / 2
            )
            handles.append(ShapeHandle(id: "m\(i)", coordinate: mid, kind: .midpoint(after: i)))
        }
        return handles
    }

    @MapContentBuilder
    private func shapeEditHandles(for area: TLSArea, proxy: MapProxy) -> some MapContent {
        ForEach(shapeHandles(for: area)) { handle in
            Annotation("", coordinate: handle.coordinate, anchor: .center) {
                shapeHandleView(handle, areaID: area.id, proxy: proxy)
            }
        }
    }

    @ViewBuilder
    private func shapeHandleView(_ handle: ShapeHandle, areaID: TLSArea.ID, proxy: MapProxy) -> some View {
        switch handle.kind {
        case .vertex(let index):
            Circle()
                .fill(.white)
                .overlay(Circle().stroke(.black, lineWidth: 1.5))
                .frame(width: 18, height: 18)
                .frame(width: 40, height: 40)
                .contentShape(Rectangle())
                // Hold then drag to move (claims the touch from the map pan);
                // a quick double-tap stays distinct for delete.
                .gesture(
                    LongPressGesture(minimumDuration: 0.2)
                        .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .global))
                        .onChanged { value in
                            if case .second(true, let drag?) = value,
                               let coordinate = proxy.convert(drag.location, from: .global) {
                                mission.moveAreaVertex(areaID: areaID, index: index, to: coordinate)
                            }
                        }
                )
                .onTapGesture(count: 2) {
                    mission.removeAreaVertex(areaID: areaID, index: index)
                }
        case .midpoint(let after):
            ZStack {
                Circle().fill(.white).frame(width: 22, height: 22)
                    .overlay(Circle().stroke(.green, lineWidth: 1.5))
                Image(systemName: "plus").font(.system(size: 12, weight: .bold)).foregroundStyle(.green)
            }
            .frame(width: 36, height: 36)
            .contentShape(Rectangle())
            .onTapGesture {
                mission.insertAreaVertex(areaID: areaID, afterIndex: after, coordinate: handle.coordinate)
            }
        }
    }

    // MARK: - Top banner

    private var topBanner: some View {
        return HStack(spacing: 8) {
            Image(systemName: bannerIcon)
                .foregroundStyle(.green)
            Text(bannerText)
                .font(.system(.headline, design: .rounded).bold())
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().stroke(.white.opacity(0.12), lineWidth: 1))
        .shadow(color: .black.opacity(0.4), radius: 6, y: 2)
        // Keep clear of the top-right map controls / island on all devices.
        .frame(maxWidth: 240)
        .padding(.top, 4)
    }

    private var bannerIcon: String {
        if mission.isEditingAreaShape { return "hand.draw" }
        if isDrawing { return "scribble.variable" }
        if isMoving { return "arrow.up.and.down.and.arrow.left.and.right" }
        if isEditing {
            if isAreasLayer { return "pentagon" }
            if isMarkersLayer { return "mappin" }
            return "pencil.and.outline"
        }
        return "scope"
    }

    private var bannerText: String {
        if mission.isEditingAreaShape { return "EDITING SHAPE" }
        if isDrawing { return "DRAWING — \(mission.draftVertices.count) PT" }
        if isMoving { return "MOVING — PAN & DROP" }
        if isEditing {
            if mission.isDragUnlocked && isWaypointsLayer { return "DRAG UNLOCKED" }
            return "EDIT MODE"
        }
        let index = mission.currentActiveWaypointIndex
        let name = mission.activeWaypoint?.displayName(index: index) ?? "No Target"
        return "WP \(index): \(name.uppercased())"
    }
}

#Preview {
    MissionMapView()
        .environment(MissionManager())
        .environment(LocationManager())
        .environment(AppSettings())
        .preferredColorScheme(.dark)
}
