//
//  Mission.swift
//  Mission Planning Software
//
//  In-memory representation of a complete mission. Serialized to / from KML
//  on disk (see KMLCodec / MissionStore).
//

import Foundation

nonisolated struct Mission: Identifiable {
    var id = UUID()
    var name: String
    var waypoints: [Waypoint]
    var areas: [TLSArea] = []
    var markers: [MapMarker] = []
    var currentActiveWaypointIndex: Int = 0
}
