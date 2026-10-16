import CoreLocation
import Foundation

/// The time zone where this device is, for Settings' "Use my location": one
/// position at reduced accuracy (a few kilometres, as Home's weather asks for),
/// turned into its zone by the system geocoder. Location is asked for the first
/// time if it never was; the saved setting is written only when the person
/// saves, so a glance at Settings on a trip can't move the display's clock.
@MainActor
final class LocationTimeZone: NSObject {
    enum Failure: LocalizedError {
        case denied, unavailable, unknown

        var errorDescription: String? {
            switch self {
            case .denied: return "Location is off for McFly. Turn it on in Settings → McFly → Location, or type the zone."
            case .unavailable: return "This device's location isn't available. Type the zone instead."
            case .unknown: return "No time zone is known for where you are. Type it instead."
            }
        }
    }

    private let manager = CLLocationManager()
    private var waiting: CheckedContinuation<CLLocation, Error>?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyReduced
    }

    /// The zone here, or why it couldn't be found.
    func current() async throws -> TimeZone {
        let location = try await position()
        let places = try await CLGeocoder().reverseGeocodeLocation(location)
        guard let zone = places.first?.timeZone else { throw Failure.unknown }
        return zone
    }

    private func position() async throws -> CLLocation {
        try await withCheckedThrowingContinuation { continuation in
            waiting = continuation
            switch manager.authorizationStatus {
            case .notDetermined: manager.requestWhenInUseAuthorization()   // the answer arrives below
            case .denied, .restricted: finish(.failure(Failure.denied))
            default: manager.requestLocation()
            }
        }
    }

    private func finish(_ result: Result<CLLocation, Error>) {
        guard let waiting else { return }
        self.waiting = nil
        waiting.resume(with: result)
    }
}

extension LocationTimeZone: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            // A new manager reports its status straight away; only a pending ask acts on it.
            guard self.waiting != nil else { return }
            switch status {
            case .notDetermined: break
            case .denied, .restricted: self.finish(.failure(Failure.denied))
            default: self.manager.requestLocation()
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { @MainActor in self.finish(.success(location)) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in self.finish(.failure(Failure.unavailable)) }
    }
}
