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

### Phase 2D — ✅ Moving waypoints (two mechanisms)

* **Lock-gated press-and-hold drag** (tablet-friendly): off by default. A lock button (top-leading in Edit Mode, `MissionManager.isDragUnlocked`) unlocks it. When unlocked, a `LongPressGesture(0.25s).sequenced(before: DragGesture(.global))` on a marker repositions it via `MapProxy.convert` → `moveWaypoint(id:to:)`. The gesture is only attached when unlocked so a locked map pans normally.
* **Reticle "Move on map"** (phone-friendly): from `SelectedWaypointBar` or a waypoint list row. `beginMovingOnMap(id:)` centers the camera on the waypoint so it sits under the crosshair; `onMapCameraChange(.continuous)` then pins the waypoint to the map center as you pan. The bottom bar swaps to `MoveModeBar` (**Cancel** restores the original coordinate, **Drop Here** confirms at center). Top banner shows "MOVING WP N".
* **Model:** `isDragUnlocked`/`toggleDragLock`, `moveWaypoint(id:to:)`, `movingWaypointID` + `movingWaypoint`/`isMovingOnMap`, `beginMovingOnMap`/`confirmMovingOnMap`/`cancelMovingOnMap` (stores original coordinate for cancel). `exitEditMode` cancels any in-progress move and re-locks dragging.

**Phase 2 (Mission Editor) is complete.** Next: Phase 3 (Persistence, KML/KMZ import/export, mission library).

### Field-test fixes (post-Phase 2)

* **Targeting arrow vs. map rotation:** the arrow rotation is now `bearingToActive − mapHeading` (map heading captured from `context.camera.heading` in `onMapCameraChange`). Previously it used the raw true bearing, so it pointed wrong in heading-up tracking or after a two-finger rotate. North-up (heading 0) is unchanged.
* **Radius handle vs. drag-to-move:** the yellow radius drag handle is hidden while `isDragUnlocked` is true, so it can't be grabbed by accident when press-and-hold-dragging a waypoint. The radius circle still shows.
* **Arrow 0°/360° spin:** `TargetingArrowView` now animates an accumulated `displayedAngle`, advancing by the shortest signed delta (`−180…180°`) per update instead of animating the raw bearing. Fixes the near-full backward spin when crossing north.

---

## 6. Phase 3 — Persistence, Import/Export & Library

**Storage decision:** missions are stored **as KML files** in the app's Documents directory (one format end-to-end). `activationRadius` round-trips via `<ExtendedData><Data name="activationRadius">`. KML parsing uses Foundation's built-in `XMLParser` (no AEXML dependency).

### Phase 3A — ✅ Mission persistence + Library

* **Models:** `Mission` (id, name, waypoints, activeIndex) and `Waypoint` are `nonisolated` value types (no actor isolation, so the parser can build them off the main actor cleanly).
* **`KMLCodec`:** `encode(_:)` → KML string (XML-escaped names, `lon,lat,alt` coordinate order, radius in ExtendedData); `decode(_:fallbackName:)` via a `nonisolated` `XMLParser` delegate that reads Placemark name/coordinates and the `activationRadius` Data value. Round-trip verified offline (coords, radius, escaping).
* **`MissionStore`:** lists `*.kml` in Documents (newest first, as `MissionFile`), `save(_:fileName:)`, `load(_:)`, `delete(_:)`, name sanitization. Library uses the file name as the mission's display name.
* **`MissionManager`:** `currentMission` snapshot, `load(_:from:)`, `markSaved(as:url:)`, `newMission()` (clears + enters Edit Mode), and a `currentFileURL` for the backing file.
* **`MissionLibraryView`** (pushed from the menu's `MissionLibrary` link): Current-mission section with an **editable name `TextField`** (the name is the file name), **Save Mission**, and **New Mission**; Saved-missions section with load (tap), delete (swipe / EditButton), modified date, and a check on the active file.
* **Save semantics (revised):** saving to an **existing** name shows a "Replace Mission?" confirmation before overwriting; a **new** name just saves a separate mission (never auto-deletes). Renaming = save under the new name, then delete the old one. (`MissionStore.exists(name:)` / `url(forName:)`.)

### Phase 3B — ✅ Export / Share

* **`Export / Share (KML)`** in the Library's Current-mission section: a `ShareLink` over a temp `.kml` file written from the live `currentMission` (so it reflects unsaved edits and the current name). `refreshExport()` regenerates it on appear, on name change, and after Save/New; the temp file is named `<mission name>.kml` for a sensible share filename. Hidden when the mission has no waypoints. Gives AirDrop / Save to Files / Mail / etc.

### Phase 3C — ✅ KML import

* **`Import KML…`** in the Library opens a `.fileImporter`. KML has no system UTType, so the allowed type is `UTType(filenameExtension: "kml")` (a dynamic, extension-matched type).
* `importFile(_:)` wraps the read in `startAccessingSecurityScopedResource()` / `stop…` (files come from outside the sandbox), validates by parsing with `KMLCodec.decode` (clear error if it has no readable waypoints), then saves a normalized copy into the library under a **non-colliding** name via `MissionStore.uniqueName(base:)` (" 2", " 3", …). The imported mission appears at the top of the Saved list (tap to load).
* Full external round-trip now works: Export a `.kml` → reimport it.

### Phase 3 remaining (planned)

* **3D — KMZ:** add ZIPFoundation (the one external dependency + Xcode project change); unzip `.kmz` → parse `doc.kml`; optional `.kmz` export.

---

## 7. TLS — Tactical Layer Symbols (drawn areas)

**Concept:** alongside navigation waypoints, the user draws enclosed **areas** ("TLS"). Each area has a colour and is **outline-only by default**, with an optional translucent **fill** (e.g. a red no-go zone).

**Storage decision (settled):** a **single KML** holds both — `<Point>` placemarks for waypoints, `<Polygon>` placemarks for TLS — grouped in named `<Folder>` layers (`Waypoints`, `TLS`). This is standard and interoperable (areas render as polygons in Google Earth/ATAK). KMZ stays an optional packaging wrapper (3D), not a requirement. Rejected alternatives: KMZ-with-multiple-KMLs (readers usually only load `doc.kml`) and "specially-named waypoint sequences" (non-standard; other tools just see points).

### TLS-A — ✅ Model + KML storage + rendering

* **`TLSArea`** (`nonisolated`): id, name, `vertices: [CLLocationCoordinate2D]` (open ring), `colorHex`, `filled`. `TLSPalette` holds preset RGB hex colours. `Color(hex:)` helper bridges to SwiftUI.
* **Model wiring:** `Mission.areas` + `MissionManager.areas` (with mock "Op Area" outline + "No-Go" filled), threaded through `currentMission` / `load` / `newMission`.
* **KML codec:** encodes a `TLS` folder of `<Polygon>` placemarks, each with a `<Style>` (LineStyle + PolyStyle, KML `aabbggrr` colour, `<fill>` flag) for interop **and** `<ExtendedData>` (`color`, `filled`) for exact in-app round-trip; coordinate ring is auto-closed. Decoder tracks geometry (`<Point>` → waypoint, `<Polygon>` → area), reads multi-tuple ring coordinates, strips the duplicate closing vertex, and reads colour/fill from ExtendedData. Round-trip verified offline (vertices, colour, fill, byte order).
* **Rendering:** `MapPolygon` per area (beneath route/markers, both modes) — translucent fill when `filled`, otherwise clear with a coloured stroke.

### TLS-B — ✅ Draw mode + area editing

* **Layer toggle:** a segmented `Waypoints / Areas` picker at the top of Edit Mode (`MissionManager.editLayer`, switched via `setEditLayer` which clears selections / in-progress draws). The lock button, radius handle, and waypoint tap/drag are gated to the waypoints layer.
* **Drawing:** "Draw Area" starts a vertex-by-vertex draw using the same center crosshair as waypoint dropping. `DrawAreaBar` = Cancel / Undo / **Add** (drops a vertex at the crosshair) / **Finish** (commits when ≥ 3 vertices, then selects it). Live draft = dashed yellow polyline + vertex dots; banner shows the running point count. State: `isDrawingArea`, `draftVertices`, `beginDrawingArea`/`addDraftVertex`/`undoDraftVertex`/`finishDrawingArea`/`cancelDrawingArea`.
* **Selection & styling:** each area shows a tappable centroid label (`AreaMarkerView`); selected area gets a thicker outline. `SelectedAreaBar` gives a colour swatch row (`ColorSwatchRow` / `TLSPalette`), a fill toggle, edit (opens list), delete, deselect. `AreaListView` (sheet) edits name / colour / fill, swipe-deletes, and "Show on map" recenters. Model: `selectedArea`, `selectArea`/`deselectArea`, `setAreaColor`, `toggleAreaFilled`, `deleteArea`/`deleteSelectedArea`/`deleteAreas(atOffsets:)`, `indexOfArea`, `TLSArea.center`.
* **Save/load:** unchanged codec path — areas persist through KML save/load (round-trip verified). `newMission`/`exitEditMode` reset layer + area state.

### TLS-C — ✅ Vertex editing + nav label toggle

* **Vertex editing:** the selected-area bar's **Edit Shape** (`hand.draw`) enters `isEditingAreaShape`. Each vertex shows a white handle — **press-and-hold then drag** to move (`LongPressGesture.sequenced(before: DragGesture(minimumDistance: 0, .global))` → `moveAreaVertex` via `MapProxy.convert`); **double-tap** → `removeAreaVertex` (min 3). A plain `minimumDistance: 0` drag would claim the touch and break double-tap delete, and a `minimumDistance > 0` drag lets the map pan win — so the hold-then-drag pattern (same as waypoint move) is used. Each edge midpoint shows a green **+** handle (tap → `insertAreaVertex`). `ShapeEditBar` = Done + hint; layer picker / centroid labels hidden while shaping. Handles built as a single `ForEach` of uniquely-id'd `ShapeHandle`s to avoid annotation-identity clashes.
* **Nav label toggle:** `TLSArea.showLabel` (round-tripped via `<ExtendedData>`), toggled per-area from the selected-area bar (`tag`/`tag.fill`) and the area list. Areas with `showLabel` render their label in Navigation Mode (non-interactive); edit-mode labels are unchanged.

### TLS — planned tweaks (later)

* Per-area line width; richer KML import (read `<Style>` colour when our `<ExtendedData>` is absent, e.g. third-party files); tap-empty-map to add a vertex while drawing.

---

## 8. Display / field features

* **`AppSettings`** (`@Observable`, injected in the App): `mapStyle: MapStyleOption {standard, hybrid, satellite}` and `keepAwake: Bool`.
* **Map type:** switched from the navigation menu's **Display** section and from an **Edit-mode control island** (top-right). `MissionMapView.mapStyle` maps the option to `.standard` / `.hybrid(elevation:)` / `.imagery(elevation:)`.
* **Control island:** in Edit Mode (top-trailing, `!isMoving`), a small material "island" groups the **map-type** menu, a **quick-save** button (overwrites the current mission's file — or creates it under the current name — with a brief checkmark), and (waypoints/markers layers) the **drag lock** toggle, as equal-size 40pt icons. No floating button in Navigation Mode.
* **Crosshair vs keyboard:** the reticle uses `.ignoresSafeArea(.keyboard)` so it stays at the map's true centre (the drop point) when the emoji keyboard pushes other content up — otherwise drops landed at screen-centre instead of the reticle.
* **Keep screen awake:** Toggle in the menu's Display section; applied via `UIApplication.shared.isIdleTimerDisabled` (onAppear + onChange).
* **Menu detent:** the navigation menu opens at `.fraction(0.7)` first (was `.medium`), so the actions/footer show without dragging to full.
* **Startup mission:** the hardcoded "Orivesi Recon" mock is removed. `MissionManager` starts empty and `loadLastMissionIfAvailable()` (called from `onAppear`) loads the last-used mission — tracked by file *name* in `UserDefaults` (`lastMissionFileName`, since the sandbox path can change between launches), persisted on every `load`/`markSaved` — falling back to the newest saved mission, else staying empty.

KMZ (old 3D) deprioritized — not needed for now.

---

## 10. macOS support (Tier 2 — native, shared code)

Goal: edit mission files on a Mac (incl. Intel, so native macOS — not "Designed for iPad"). Both iOS and macOS build clean from one target.

* **Project:** the app target gained `SUPPORTED_PLATFORMS = "iphoneos iphonesimulator macosx"`, `SDKROOT = auto`, `MACOSX_DEPLOYMENT_TARGET = 14.0`, `SUPPORTS_MACCATALYST = NO` (native AppKit-backed, not Catalyst). iOS deployment stays 26.0. **Unsandboxed** (no macOS entitlements added) so the file importer, `~/Documents` library, and location (with the usage-description Info.plist key) work without extra setup.
* **`Utilities/View+Platform.swift`:** cross-platform wrappers keep view code clean — `inlineNavTitle()`, `numericKeyboard()`, `wordsCapitalization()`, `editorSheet()`/`menuSheet()` (detents on iOS, window sizing on macOS), `PlatformEditButton` / `editButtonToolbar` (iOS `EditButton`, no-op on macOS). Toolbar `Done` buttons moved from `.topBarTrailing` to cross-platform `.confirmationAction`.
* **Code fixes:** `LocationManager.isAuthorized(_:)` handles `.authorizedWhenInUse` (iOS) vs `.authorizedAlways` (macOS); `import UIKit` + `isIdleTimerDisabled` (keep-awake) guarded with `#if os(iOS)` (`applyKeepAwake` is a no-op on macOS for now).
* **Models / `KMLCodec` / `MissionStore` / GeoMath:** zero changes — already pure Foundation/CoreLocation.
* **Window sizing:** the macOS `WindowGroup` sets `.defaultSize(1000×720)` + `.frame(minWidth:700, minHeight:500)` (removes a transient zero-size Metal drawable at launch). macOS map uses `.flat` elevation (2D, better for editing).
* **⚠️ Metal API Validation gotcha:** running from Xcode with **Metal API Validation** enabled (the Run-scheme default) crashes inside the validation layer while it validates MapKit / SwiftUI blur-material (`.ultraThinMaterial`) rendering on macOS (`MTLDebugRenderCommandEncoder` sampleCount assert, then a `MetalTools`/`CoreImageOld` segfault). This is a MapKit/validation-layer bug, **not app code** — the app runs fine when launched normally (Release, `open`, or with validation off). **Fix for debugging:** Edit Scheme → Run → Diagnostics → uncheck **Metal API Validation**.
* **macOS control-island width:** a `Menu` with a custom icon label renders as a full-width pop-up button on macOS (stretched the island). Fixed with `.menuIndicator(.hidden).menuStyle(.button).buttonStyle(.plain).fixedSize()` so it hugs the icon.
* **Performance — blur materials:** `.ultraThinMaterial` (9 overlay backgrounds) is very costly over the live map on integrated GPUs. New `ShapeStyle.panel` (in `View+Platform.swift`) is the material on iOS and a cheap solid (`black 0.62`) on macOS; all overlays use `.panel`. (MapKit itself is GPU/Metal; satellite/hybrid imagery is heaviest. For real perf, test a **Release** build — Debug is `-Onone`.)
* **Performance — per-pan re-render storm:** `onMapCameraChange(.continuous)` was writing `mapCenter`/`mapHeading`/`mapDistance` `@State` every camera tick, invalidating the whole view + rebuilding all map content dozens of times/sec while panning (CPU pegged). Fixed: `mapCenter` now lives in a plain `CenterBox` reference (read imperatively at drop/move time, never rendered → no invalidation), and `mapHeading`/`mapDistance` are only assigned when they meaningfully change (they don't during a plain pan). So a plain pan triggers **no** SwiftUI re-render; heading/distance still update on rotate/zoom, and the reticle-follow still updates while moving a feature.
* **Not done (Tier 3, later):** mouse/keyboard-native UX (the touch flows — crosshair-drop, press-hold-drag — work but aren't Mac-idiomatic), further window-friendly layout, macOS keep-awake, and optional sandboxing/entitlements for distribution.

---

## 9. Markers (emoji icons)

**Concept:** free-form emoji icons placed on the map (e.g. 🚑 here), separate from navigation waypoints — a third edit layer (**Waypoints / Areas / Markers**).

* **`MapMarker`** (`nonisolated`): id, `emoji` (single grapheme), `name?`, coordinate, `showLabel`. `Mission.markers` + `MissionManager.markers`, threaded through `currentMission`/`load`/`newMission`.
* **Storage:** KML `<Point>` placemarks in a `Markers` folder, tagged `featureType=marker` with `emoji` + `showLabel` in `<ExtendedData>`. The decoder discriminates points by `featureType` (`marker` → `MapMarker`, else `Waypoint`). Emoji are UTF-8, so they round-trip cleanly (verified offline). Other tools show a plain pin (KML icons must be image files, not glyphs) — acceptable per the interop stance.
* **Input:** free emoji via `EmojiField` (a `TextField` that keeps the last grapheme; uses the system emoji keyboard). No curated palette — any emoji. The drop bar also remembers a **current background colour** (`MissionManager.currentBackground`) alongside `currentEmoji`, so new markers inherit the last-chosen emoji + background.
* **Rendering (`MarkerView`):** emoji on a translucent rounded chip whose **colour is per-marker** (`MapMarker.backgroundHex`, default black; `MarkerPalette.backgrounds` = black/white/red/orange/yellow/green/blue/purple — useful for friendly/hostile/etc. coding). Optional name label below (per-marker `showLabel` toggle). **Hidden past a camera-distance threshold** (`markerVisibilityMaxDistance = 150 km`) when zoomed far out — except while editing the markers layer. Background round-trips via `<ExtendedData>`. Picked from a `ColorSwatchRow` (now takes a `colors:` param) in `SelectedMarkerBar` and `MarkerListView`.
* **Zoom scaling:** a `markerScale` derived from camera distance (`scaleEffect`) makes emoji grow/shrink with the map like ground features. Tunables: `markerReferenceDistance` (scale 1.0 point, 4 km), `markerMinScale` (0.35), `markerMaxScale` (1.6, caps the zoomed-in size). Emoji base size 22 in `MarkerView`.
* **Editing:** markers layer → `MarkerEditBar` (Done / List / current-emoji field / **Drop** at crosshair). Tap a marker to select → `SelectedMarkerBar` (move, change emoji, label toggle, delete, deselect). `MarkerListView` edits emoji / name / lat-lon / label, locate, swipe-delete.
* **Moving (both methods, mirroring waypoints):** reticle **move** button on `SelectedMarkerBar` (`beginMovingMarkerOnMap` → `MoveModeBar`; `movingMarkerID`, `confirm`/`cancel`), and lock-gated **press-and-hold drag** (`markerAnnotation`; the lock toggle now shows on the markers layer too). `isMovingOnMap` and `cancelAnyMoveOnMap` cover both feature types; `onMapCameraChange` / `confirmMove` handle whichever is active.
* **Top-overlay layout fix:** banner text shortened (`EDIT MODE`, `MOVING — PAN & DROP`, etc. — the picker already shows the layer) and the banner + layer picker capped at `maxWidth 240` with `lineLimit(1).minimumScaleFactor`, so they no longer slide under the top-right compass / control island.

Build notes:
* Project uses a **synchronized root group** — new Swift files dropped into the folder are auto-added to the target (no `.pbxproj` edits needed for sources).
* Location-usage string added via build setting `INFOPLIST_KEY_NSLocationWhenInUseUsageDescription` (Info.plist is generated).
* **Dev environment:** test on the **iOS 26.0** simulator; the 26.3.1 simulator runs pathologically slowly. For a pure compile check use `-destination 'generic/platform=iOS Simulator'`.
