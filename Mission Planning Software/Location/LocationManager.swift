//
//  LocationManager.swift
//  Mission Planning Software
//
//  CoreLocation wrapper exposing the user's live position as observable state.
//

import CoreLocation
import Observation

@Observable
final class LocationManager: NSObject, CLLocationManagerDelegate {

    /// Most recent fix as a raw coordinate (convenient for MapKit content).
    var userLocation: CLLocationCoordinate2D?
    /// Full location object, kept for speed / course / accuracy telemetry.
    var currentLocation: CLLocation?
    var authorizationStatus: CLAuthorizationStatus

    @ObservationIgnored private let manager = CLLocationManager()

    override init() {
        authorizationStatus = manager.authorizationStatus
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        manager.distanceFilter = kCLDistanceFilterNone
        manager.activityType = .fitness
    }

    /// Request "When In Use" access and begin streaming updates. Safe to call
    /// repeatedly; CoreLocation coalesces redundant requests.
    func start() {
        manager.requestWhenInUseAuthorization()
        manager.startUpdatingLocation()
    }

    var groundSpeed: CLLocationSpeed? {
        guard let speed = currentLocation?.speed, speed >= 0 else { return nil }
        return speed
    }

    // MARK: - CLLocationManagerDelegate
    //
    // Callbacks are delivered on the run loop the manager was created on (main),
    // so we synchronously assume MainActor isolation to mutate observable state.

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        MainActor.assumeIsolated {
            self.currentLocation = location
            self.userLocation = location.coordinate
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        MainActor.assumeIsolated {
            self.authorizationStatus = status
            if status == .authorizedWhenInUse || status == .authorizedAlways {
                manager.startUpdatingLocation()
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Transient errors (e.g. no fix yet) are expected; ignore for Phase 1.
    }
}
