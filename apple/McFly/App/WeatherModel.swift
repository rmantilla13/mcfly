import CoreLocation
import McFlyKit
import Observation

/// Home's weather: today's, where the phone is (`Weather`, from Open-Meteo). The
/// location is asked for only when the person taps the tile, at reduced accuracy
/// (a few kilometres), and only to get the forecast and the place's name.
@MainActor
@Observable
final class WeatherModel: NSObject {
    enum State: Equatable {
        /// Location never asked for: the tile offers to.
        case off
        /// Location refused or restricted: the tile says where to change it.
        case denied
        case loading
        case ready(Weather, place: String?)
        case failed(String)
    }

    private(set) var state: State = .off
    @ObservationIgnored private let manager = CLLocationManager()
    @ObservationIgnored private var loadedAt: Date?
    @ObservationIgnored private let isDemo: Bool

    /// Fresh enough for a glance; the forecast itself moves hourly.
    static let maxAge: TimeInterval = 30 * 60

    init(isDemo: Bool) {
        self.isDemo = isDemo
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyReduced
        if isDemo {
            state = .ready(Weather(temperature: 72, high: 78, low: 61, code: 2), place: "Austin")
        } else {
            state = Self.state(for: manager.authorizationStatus)
        }
    }

    /// Refreshes if it's been a while, and only if location is already allowed.
    func refreshIfStale() {
        guard !isDemo, manager.authorizationStatus.isAllowed else { return }
        if let loadedAt, Date.now.timeIntervalSince(loadedAt) < Self.maxAge, case .ready = state { return }
        manager.requestLocation()
        if case .ready = state {} else { state = .loading }
    }

    /// The tile's tap: ask for location the first time, else refresh.
    func turnOn() {
        guard !isDemo else { return }
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        default:
            loadedAt = nil
            refreshIfStale()
        }
    }

    private static func state(for status: CLAuthorizationStatus) -> State {
        switch status {
        case .notDetermined: return .off
        case .denied, .restricted: return .denied
        default: return .loading
        }
    }

    private func load(_ location: CLLocation) async {
        let unit = Weather.unit()
        let url = Weather.url(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude, unit: unit)
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
            let weather = try Weather.decode(data, unit: unit)
            let place = try? await CLGeocoder().reverseGeocodeLocation(location).first?.locality
            state = .ready(weather, place: place)
            loadedAt = .now
        } catch {
            if case .ready = state { return }   // keep the last forecast over an error
            state = .failed("Weather couldn't be reached.")
        }
    }
}

extension WeatherModel: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            // A new manager reports the status straight away; the demo keeps its weather.
            guard !self.isDemo else { return }
            self.state = Self.state(for: status)
            if status.isAllowed { self.refreshIfStale() }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { @MainActor in await self.load(location) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            if case .ready = self.state { return }
            self.state = .failed("This phone's location isn't available.")
        }
    }
}

private extension CLAuthorizationStatus {
    var isAllowed: Bool {
        #if os(iOS)
        return self == .authorizedWhenInUse || self == .authorizedAlways
        #else
        return self == .authorizedAlways
        #endif
    }
}
