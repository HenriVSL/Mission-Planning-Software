# Mission Planning Software

A waypoint navigation and map-annotation app for iPhone, iPad and Mac, built
with SwiftUI and MapKit. Plan a route of waypoints, mark areas and points of
interest on the map, then follow the route in the field with a targeting
arrow, live distance and ETA. Missions are stored as standard KML files.

## Features

### Navigation mode

| | |
|---|---|
| **Live tracking** | Full-screen map that follows your GPS position, with user-location, compass and scale controls |
| **Route** | Dashed white lines join the waypoints in order. The leg you are currently on is drawn solid green |
| **Targeting arrow** | Points from your position to the active waypoint and takes the map's rotation into account |
| **Telemetry HUD** | Straight-line distance and estimated time to the active waypoint, based on your current speed |
| **Prev / Next** | Step to the previous or next waypoint manually |
| **Auto-advance** | When you enter the active waypoint's activation radius, the next waypoint becomes active. The radius is shown as a dashed ring |
| **Mission menu** | Tap the HUD for active-target details (name, distance, coordinate, radius), edit mode, the mission library and display settings |

### Edit mode

Edit mode has three layers: **Waypoints**, **Areas** and **Markers**. New
items are placed at a fixed crosshair in the centre of the screen, so you pan
the map rather than tap a point.

| | |
|---|---|
| **Waypoints** | Drop at the crosshair, select, delete, rename, and set the activation radius (2 to 3000 m) by dragging a handle on the circle |
| **Areas** | Draw polygons point by point (add, undo, finish). Set colour, outline or translucent fill, and a name. Edit the shape by dragging corners, tapping a **+** on an edge to add a corner, or double-tapping a corner to remove it. Optionally show an area's name in navigation mode |
| **Markers** | Place any emoji on the map with an optional name and a coloured background chip. Markers scale with the zoom level and hide when you zoom out past about 150 km |
| **Moving items** | **Move on map** pins a waypoint or marker to the crosshair while you pan, with Cancel or Drop Here. When the lock button is unlocked, you can also press, hold and drag items directly |
| **List editors** | Each layer has a list with swipe-to-delete and **Show on map**. Waypoints and markers can be given exact latitude / longitude there (plus radius for waypoints). Areas can be renamed, recoloured and filled |
| **Quick save** | A save button in the edit-mode control panel writes the mission to its file |

### Missions and files

| | |
|---|---|
| **Mission library** | Save, load, rename (save under a new name) and delete missions. You are asked before an existing mission is replaced |
| **KML storage** | Each mission is a `.kml` file in the app's Documents folder. Waypoints and markers are `<Point>` placemarks, areas are `<Polygon>` placemarks, grouped in `Waypoints`, `TLS` and `Markers` folders |
| **Import** | Import a `.kml` file from Files. It is checked for readable waypoints and added to the library under a unique name |
| **Export / share** | Share the current mission, including unsaved edits, as a `.kml` file through AirDrop, Mail, Files and so on |
| **Resume** | On launch, the app reopens the mission you last used |

### Display

- Map type: Standard, Hybrid or Satellite
- Dark or light map (the app itself always uses dark mode)
- Keep the screen awake while navigating (iOS and iPadOS only)

## How it works

- `MissionManager` (`@Observable`) holds the mission, the current mode and
  layer, and all editing actions. `LocationManager` wraps `CLLocationManager`
  for navigation-accuracy fixes.
- Bearings and distances are calculated in
  [`Utilities/GeoMath.swift`](Mission%20Planning%20Software/Utilities/GeoMath.swift).
- `KMLCodec` reads and writes KML with Foundation's `XMLParser`. App-specific
  values (activation radius, area colour and fill, marker emoji and
  background, label settings) are stored in `<ExtendedData>`, so they survive
  a round trip. Areas also get a standard KML `<Style>`, so other KML viewers
  show them with the right colour. Markers appear as plain pins in other
  tools.
- iOS and macOS build from the same target. Platform differences (sheets,
  keyboards, edit buttons, overlay materials) are handled in
  [`Utilities/View+Platform.swift`](Mission%20Planning%20Software/Utilities/View+Platform.swift).

[`Design_Document.md`](Design_Document.md) contains the development notes.
Items it lists as remaining or later, such as KMZ support and per-area line
width, are **planned** and not implemented.

## Requirements

- iOS / iPadOS 26.0 or later, or macOS 14.0 or later (build from source for Mac)
- Location access ("When In Use") for tracking, distance and the targeting
  arrow. Planning and editing work without it.
- A device with GPS for field navigation

## Install

1. Download the unsigned `.ipa` from the
   [latest release](https://github.com/HenriVSL/Mission-Planning-Software/releases/latest).
2. Sideload it with a tool that re-signs it with your own Apple ID, such as
   [AltStore](https://altstore.io), [SideStore](https://sidestore.io) or
   [Sideloadly](https://sideloadly.io).

Apps signed with a free Apple ID expire after 7 days and need to be re-signed.

The `.ipa` is for iPhone and iPad. For the Mac version, build from source.

## Build from source

1. Open `Mission Planning Software.xcodeproj` in Xcode 26 or later.
2. Select your team under **Signing & Capabilities** for the
   `Mission Planning Software` target. Change the bundle identifier
   (`henril.Mission-Planning-Software`) if Xcode reports a conflict.
3. Choose an iOS device, the Simulator or **My Mac** as the destination, and
   run.

The macOS build is native (not Mac Catalyst) and unsandboxed. If it crashes
inside Metal when run from Xcode, turn off **Edit Scheme > Run > Diagnostics >
Metal API Validation**. The validation layer trips over MapKit's rendering,
and the app runs normally without it.

## Third-party components

None. The app uses only Apple frameworks (SwiftUI, MapKit, CoreLocation,
Foundation).

## License

MIT, see [LICENSE](LICENSE).
