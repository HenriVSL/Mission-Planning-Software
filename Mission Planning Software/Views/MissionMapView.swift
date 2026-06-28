//
//  MissionMapView.swift
//  Mission Planning Software
//
//  Full-screen navigation map: tracks the user, draws the baseline route and
//  the highlighted active leg, and overlays the targeting arrow + HUD.
//

import MapKit
import SwiftUI

struct MissionMapView: View {
    @Environment(MissionManager.self) private var mission
    @Environment(LocationManager.self) private var location

    /// Camera follows the user's location; falls back to the route region
    /// until the first GPS fix arrives.
    @State private var camera: MapCameraPosition = .userLocation(fallback: .automatic)

    /// Geographic coordinate currently under the screen center — the drop point
    /// for new waypoints in Edit Mode. Kept in sync via `onMapCameraChange`.
    @State private var mapCenter = CLLocationCoordinate2D(latitude: 61.677, longitude: 24.356)

    /// Whether the mission menu sheet is presented.
    @State private var showingMenu = false

    /// Whether the waypoint list editor sheet is presented.
    @State private var showingList = false

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
                mapContent
                radiusContent(proxy)
            }
            .mapStyle(.standard(elevation: .realistic, pointsOfInterest: .excludingAll))
            .mapControls {
                MapUserLocationButton()
                MapCompass()
                MapScaleView()
            }
            .onMapCameraChange(frequency: .continuous) { context in
                mapCenter = context.region.center
            }
            // Edit Mode reticle, pinned to the screen center.
            .overlay {
                if isEditing { CrosshairView() }
            }
            .overlay(alignment: .top) { topBanner }
            .overlay(alignment: .bottom) { bottomBar }
            .ignoresSafeArea(edges: .bottom)
            .onAppear { location.start() }
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
                WaypointListView(onLocate: locate(_:))
            }
        }
    }

    /// Navigation Mode shows telemetry; Edit Mode shows the authoring controls,
    /// with a selected-waypoint action bar stacked above when applicable.
    @ViewBuilder
    private var bottomBar: some View {
        if isEditing {
            VStack(spacing: 8) {
                if let selected = mission.selectedWaypoint,
                   let index = mission.index(of: selected.id) {
                    SelectedWaypointBar(
                        index: index,
                        waypoint: selected,
                        onEdit: { showingList = true }
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

    // MARK: - Map content

    @MapContentBuilder
    private var mapContent: some MapContent {
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

        // Waypoint markers (active one highlighted; tap to select in Edit Mode).
        ForEach(Array(mission.waypoints.enumerated()), id: \.element.id) { index, waypoint in
            Annotation("", coordinate: waypoint.coordinate, anchor: .center) {
                WaypointMarkerView(
                    index: index,
                    isActive: index == mission.currentActiveWaypointIndex,
                    isSelected: isEditing && mission.selectedWaypointID == waypoint.id
                )
                .onTapGesture {
                    if isEditing { mission.select(waypoint.id) }
                }
            }
        }

        // Active waypoint's activation radius — a subtle trigger ring shown in
        // Navigation Mode so the auto-advance zone is visible.
        if !isEditing, let active = mission.activeWaypoint {
            MapCircle(center: active.coordinate, radius: active.activationRadius)
                .foregroundStyle(.green.opacity(0.08))
                .stroke(.green.opacity(0.6), style: StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
        }

        // Targeting arrow pinned at the user's current location (navigation only).
        if !isEditing, let user = location.userLocation {
            Annotation("", coordinate: user, anchor: .center) {
                TargetingArrowView(bearing: bearingToActive)
            }
        }
    }

    // MARK: - Radius editing (Edit Mode)

    /// The selected waypoint's activation-radius circle plus a draggable handle
    /// on its circumference. Only present in Edit Mode with a selection.
    @MapContentBuilder
    private func radiusContent(_ proxy: MapProxy) -> some MapContent {
        if isEditing,
           let selected = mission.selectedWaypoint {
            MapCircle(center: selected.coordinate, radius: selected.activationRadius)
                .foregroundStyle(.yellow.opacity(0.12))
                .stroke(.yellow, style: StrokeStyle(lineWidth: 2))

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

    // MARK: - Top banner

    private var topBanner: some View {
        let index = mission.currentActiveWaypointIndex
        let name = mission.activeWaypoint?.displayName(index: index) ?? "No Target"
        return HStack(spacing: 8) {
            Image(systemName: isEditing ? "pencil.and.outline" : "scope")
                .foregroundStyle(.green)
            Text(isEditing ? "EDIT MODE — PAN TO POSITION" : "WP \(index): \(name.uppercased())")
                .font(.system(.headline, design: .rounded).bold())
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().stroke(.white.opacity(0.12), lineWidth: 1))
        .shadow(color: .black.opacity(0.4), radius: 6, y: 2)
        .padding(.top, 4)
    }
}

#Preview {
    MissionMapView()
        .environment(MissionManager())
        .environment(LocationManager())
        .preferredColorScheme(.dark)
}
