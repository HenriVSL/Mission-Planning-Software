# System Design Document: Tactical Orienteering & Mission Planning App

## 1. Project Overview
A localized, user-controlled navigation and mission planning tool designed for precise, tactical-style routing (walking, driving, orienteering). Unlike standard turn-by-turn navigation apps, this software prioritizes strict waypoint adherence, manual mission progression, and precise telemetry over automated route snapping. 

**Default Styling & Behavior:**
* The application must default to **Dark Mode** for optimal field visibility.
* The application launches immediately into the active Map View (Navigation Mode).

## 2. Technology Stack
* **UI Framework:** SwiftUI (Targeting iOS 17+)
* **Mapping Engine:** MapKit (Native Apple)
* **Telemetry & GPS:** CoreLocation
* **Data Serialization:** KML / KMZ parsing via lightweight Swift Packages (e.g., `AEXML` for KML XML parsing, `ZIPFoundation` for KMZ archive extraction).
* **Architecture:** Observation framework (`@Observable`) for global state management.

## 3. Core Data Models
* **`Waypoint`**: Represents a single target.
    * `id`: UUID
    * `name`: String (Optional)
    * `coordinate`: CLLocationCoordinate2D
    * `activationRadius`: Double (Measured in meters)
* **`Mission`**: Represents a complete route.
    * `id`: UUID
    * `missionName`: String
    * `waypoints`: Array of `Waypoint` objects
    * `currentActiveWaypointIndex`: Integer tracking the active objective.
* **`MissionFile`**: Lightweight struct for the Mission Library.
    * `fileName`, `fileURL`, `creationDate`.

---

## 4. Phased Implementation Strategy

To ensure stability and manage context effectively, development is strictly divided into three phases.

### Phase 1: Map Engine & Execution HUD (Foundation)
**Goal:** Establish tracking, telemetry, and the baseline UI using hardcoded mock data.

* **Mock Initialization:** Initialize the `MissionManager` with 4-5 hardcoded waypoints located near Orivesi, Pirkanmaa (approx. coordinates 61.677, 24.356) to allow for immediate field testing of the map routing and GPS tracking.
* **Camera & Tracking:** The MapKit view must continuously track and center on the user's current GPS location.
* **Route Rendering (MapPolylines):**
    * *Baseline Route:* A continuous white, dashed line connecting all waypoints (0 to N).
    * *Active Leg:* A thick, solid green line connecting the user's current location to the active waypoint. This is rendered *underneath* the white dashed line to act as a highly visible highlight.
* **Targeting Arrow:**
    * A custom user annotation on the map.
    * Must calculate the true bearing (using the Haversine formula) from the user's coordinate to the active waypoint's coordinate.
    * The bearing is applied as a `.rotationEffect()` so the arrow constantly points directly at the target, regardless of the user's physical device heading.
* **Telemetry HUD:**
    * Top banner displaying the active waypoint: "WP [Index]: [Name]".
    * Bottom overlay displaying straight-line Distance to Target and Time to Target (calculated via current speed).
    * Manual overrides: `[ < Prev ]` and `[ Next > ]` buttons to manually shift the `currentActiveWaypointIndex`.

### Phase 2: The Mission Editor
**Goal:** Allow users to create, move, and modify waypoints on the device.

* **Mode Toggle:** Switch between Navigation Mode and Edit Mode.
* **Crosshair Targeting:** In Edit Mode, a static crosshair remains in the exact center of the screen. Panning the map moves the map beneath the crosshair. A "Drop Waypoint" button saves the coordinate at the crosshair's center.
* **Map Gestures:**
    * *Double Tap:* Delete the selected waypoint.
    * *Long Press & Drag:* Move an existing waypoint to a new coordinate.
* **Radius Manipulation:**
    * When a waypoint is selected, a `MapCircle` visually represents its `activationRadius`.
    * A draggable dot on the circumference of the circle allows the user to dynamically increase/decrease the radius size, updating a text label (in meters) in real-time.
* **Waypoint List View:**
    * A SwiftUI `List` of all waypoints.
    * Tapping expands the row to reveal text fields for manual entry of Name, Latitude, Longitude, and Radius.

### Phase 3: Persistence, Import/Export, & Library
**Goal:** Implement KML/KMZ file support and a local sandbox library.

* **Mission Library UI:** A separate screen listing all saved `MissionFile` objects stored in the app's iOS Documents Directory. Users can select a mission to load it or swipe to delete.
* **Importing:** * A `.fileImporter` restricted to `.kml` and `.kmz` UTTypes.
    * Copies selected files from outside sources into the app's secure Documents Directory.
* **Parsing Logic (KML/KMZ):**
    * Extract coordinates and names from standard `<Placemark>` tags.
    * *Custom Data:* Utilize the KML `<ExtendedData>` tag to save and extract the custom `activationRadius` values so they persist across exports/imports.
    * For `.kmz`, use `ZIPFoundation` to unzip the archive to a temp directory and parse the enclosed `doc.kml`.
* **Exporting:** Generate a KML string from the current `Mission` state and utilize `ShareLink` or `UIActivityViewController` to share the file.

---

## 5. Implementation Log

### Phase 1 — ✅ Complete (compiles clean, iOS 26 SDK)

File layout (under `Mission Planning Software/`):

* `Models/Waypoint.swift` — `Waypoint` struct (id, name, coordinate, activationRadius).
* `Models/MissionManager.swift` — `@Observable` global state + 5 hardcoded Orivesi mock waypoints, `activeWaypoint`, `advance()`/`retreat()` with `canAdvance`/`canRetreat` bounds.
* `Location/LocationManager.swift` — `@Observable` `CLLocationManagerDelegate`; delegate callbacks are `nonisolated` + `MainActor.assumeIsolated` (project defaults to `MainActor` actor isolation). Exposes `userLocation`, `currentLocation`, `groundSpeed`, `authorizationStatus`.
* `Utilities/GeoMath.swift` — `CLLocationCoordinate2D.bearing(to:)` (forward azimuth) and `.distance(to:)`, plus `Telemetry` distance/ETA string formatters.
* `Views/MissionMapView.swift` — full-screen `Map`, camera `.userLocation(fallback: .automatic)`, per-leg route rendering, waypoint markers, targeting arrow, top banner.
    * **Route rendering:** each leg is drawn as its own `MapPolyline`, exactly once — the **active leg is solid green**, every other leg is **white dashed**. We deliberately avoid overlapping two polylines on the same path (MapKit's draw order for overlapping overlays is undefined). The first leg (user → WP0) is solid green only while WP0 is the target.
* `Views/TargetingArrowView.swift`, `WaypointMarkerView.swift`, `TelemetryHUDView.swift` — overlays/annotations.
* `ContentView` hosts `MissionMapView`; app forces `.preferredColorScheme(.dark)` and injects both managers via `.environment`.

### Phase 2A — ✅ Edit Mode foundation + Drop Waypoint

* `MissionManager` gained `AppMode { navigation, edit }` + `mode`, a `selectedWaypointID` (for later sub-phases), and editing methods: `enterEditMode()` / `exitEditMode()`, `addWaypoint(at:radius:)`, `deleteWaypoint(id:)`, and a private `clampActiveIndex()` that keeps `currentActiveWaypointIndex` valid after edits.
* **Menu entry point:** tapping the central readout of the telemetry HUD opens `MissionMenuView` (a sheet). For now it shows active-target info (name, distance, coordinate, radius) and an **Edit Mission** button; this is the home for future per-waypoint info / mission actions.
* **Edit Mode UI:** a fixed center `CrosshairView`, the bottom bar swaps to `EditModeBar` (Drop Waypoint / Done), the top banner shows an EDIT MODE indicator, and the targeting arrow is hidden. `onMapCameraChange(.continuous)` tracks the screen-center coordinate (`mapCenter`); **Drop Waypoint** appends a waypoint there. Returning to Navigation Mode re-centers/follows the user.

### Phase 2B — ✅ Waypoint selection, list editor & deletion

* **On-map selection (Edit Mode):** tapping a waypoint marker selects it (`onTapGesture` → `mission.select`); selected marker shows a yellow halo (`WaypointMarkerView.isSelected`).
* **Selected-waypoint action bar** (`SelectedWaypointBar`): stacked above `EditModeBar` when something is selected — edit details, **delete** (trash), or deselect.
* **Waypoint list editor** (`WaypointListView`, opened via the new **List** button in `EditModeBar`): `List` of `DisclosureGroup` rows; expand to edit **Name / Latitude / Longitude / Radius** (live two-way bindings via `@Bindable`); **swipe-to-delete** + `EditButton`; **Show on map** recenters the camera (`MissionMapView.locate`). Opening the list auto-scrolls to / expands the selected waypoint.
* **Model:** `MissionManager` gained `selectedWaypoint`, `index(of:)`, `select`/`deselect`, `deleteSelectedWaypoint`, `deleteWaypoints(atOffsets:)`. (Model stays SwiftUI-free — offset deletion done manually, not via SwiftUI's `remove(atOffsets:)`.)

### Phase 2C — ✅ Activation radius (behavior + editing)

* **Auto-advance behavior:** `MissionManager.evaluateArrival(at:)` advances the active waypoint whenever the user is within the active waypoint's `activationRadius` (loops so multiple close waypoints clear in one fix; only ever moves forward; final waypoint stays active). Driven by `LocationManager.updateCount` (an Equatable signal incremented per GPS fix; `CLLocationCoordinate2D` isn't Equatable) via `onChange` in `MissionMapView`, gated to Navigation Mode. Toggle: `MissionManager.autoAdvanceEnabled` (no UI yet). *Known nuance: manual Prev can be immediately re-advanced if still inside the radius.*
* **Radius visualization:** Navigation Mode draws a subtle green dashed trigger ring around the **active** waypoint (`MapCircle`); Edit Mode draws a solid yellow editable circle around the **selected** waypoint.
* **Draggable handle:** placed due-east on the circle via `CLLocationCoordinate2D.coordinate(bearingDegrees:distanceMeters:)`. Dragging converts the touch to a coordinate through `MapReader`/`MapProxy.convert(_:from: .global)`, sets radius = distance(center, touch) via `setRadius` (clamped 2–3000 m), with a live meters label on the handle and in `SelectedWaypointBar`.

### Phase 2 remaining (planned)

* **2D — On-map gestures (move):** long-press-drag to move a waypoint — highest MapKit risk; approach may be adapted. (Delete is already covered by 2B.)

Build notes:
* Project uses a **synchronized root group** — new Swift files dropped into the folder are auto-added to the target (no `.pbxproj` edits needed for sources).
* Location-usage string added via build setting `INFOPLIST_KEY_NSLocationWhenInUseUsageDescription` (Info.plist is generated).
* **Dev environment:** test on the **iOS 26.0** simulator; the 26.3.1 simulator runs pathologically slowly. For a pure compile check use `-destination 'generic/platform=iOS Simulator'`.
