//
//  AppSettings.swift
//  Mission Planning Software
//
//  App-level display preferences (not part of a mission): map style and
//  keep-screen-awake.
//

import Observation

/// Selectable MapKit base styles.
enum MapStyleOption: String, CaseIterable, Identifiable {
    case standard
    case hybrid
    case satellite

    var id: String { rawValue }

    var label: String {
        switch self {
        case .standard: return "Standard"
        case .hybrid: return "Hybrid"
        case .satellite: return "Satellite"
        }
    }

    var systemImage: String {
        switch self {
        case .standard: return "map"
        case .hybrid: return "map.fill"
        case .satellite: return "globe.americas.fill"
        }
    }
}

@Observable
final class AppSettings {
    var mapStyle: MapStyleOption = .standard
    /// Render the map with a dark appearance (overrides the system appearance,
    /// which MapKit otherwise follows). Affects Standard/Hybrid, not Satellite.
    var mapDark: Bool = true
    /// Prevent the screen from auto-locking (useful while navigating).
    var keepAwake: Bool = false
}
