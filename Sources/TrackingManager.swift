import Foundation
import CoreLocation
import UIKit

final class TrackingManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let placeholderCity = "Détection GPS…"

    let store = TripStore()
    private let lm = CLLocationManager()
    private let geocoder = CLGeocoder()

    // État affiché
    @Published var isTracking = false
    @Published var speedKmh = 0.0
    @Published var avgSpeedKmh = 0.0
    @Published var distanceMeters = 0.0
    @Published var tripSeconds = 0
    @Published var drivingSeconds = 0
    @Published var city = TrackingManager.placeholderCity
    @Published var address = ""
    @Published var altitude = 0.0
    @Published var elevationGain = 0.0
    @Published var activeStop: StageType?
    @Published var activeStopSeconds = 0
    @Published var activeStopStartSoc: Int?
    @Published var sinceChargeMeters = 0.0
    @Published var authStatus: CLAuthorizationStatus = .notDetermined

    // État interne
    private var trip: Trip?
    private var lastLocation: CLLocation?
    private var lastLat = 0.0
    private var lastLng = 0.0
    private var timer: Timer?
    private var stopStart: Date?
    private var stoppedBefore = 0
    private var chargeAnchor = 0.0
    private var stageAnchor = 0.0
    private var maxSpeed = 0.0
    private var minAlt = Double.greatestFiniteMagnitude
    private var maxAlt = -Double.greatestFiniteMagnitude
    private var lastSave = Date()
    private var departureNeedsPlace = false

    // Frontières
    private var confirmedState = ""
    private var confirmedCountry = ""
    private var pendingState = ""
    private var pendingCountry = ""
    private var pendingHits = 0
    private var distanceAtLastBorder = 0.0

    // Géocodage limité (CLGeocoder est plafonné par Apple)
    private var lastGeocodeDate: Date?
    private var lastGeocodeLocation: CLLocation?
    private var geocoding = false

    override init() {
        super.init()
        lm.delegate = self
        lm.desiredAccuracy = kCLLocationAccuracyBest
        lm.distanceFilter = 1
        lm.activityType = .automotiveNavigation
        lm.pausesLocationUpdatesAutomatically = false
        authStatus = lm.authorizationStatus
    }

    var currentCoordinate: (Double, Double) { return (lastLat, lastLng) }

    // MARK: Permissions et GPS

    func startGPS() {
        if lm.authorizationStatus == .notDetermined {
            lm.requestWhenInUseAuthorization()
        } else {
            lm.startUpdatingLocation()
        }
    }

    func appBackgrounded() {
        if isTracking {
            if var t = trip {
                applyTotals(&t)
                store.save(t)
            }
        } else {
            lm.stopUpdatingLocation()
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authStatus = manager.authorizationStatus
        switch manager.authorizationStatus {
        case .authorizedWhenInUse:
            manager.startUpdatingLocation()
            manager.requestAlwaysAuthorization()
        case .authorizedAlways:
            manager.startUpdatingLocation()
        default:
            break
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        for loc in locations { handle(loc) }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}

    // MARK: Traitement des positions

    private func handle(_ loc: CLLocation) {
        // Ignore les positions imprécises (> 30 m)
        guard loc.horizontalAccuracy >= 0, loc.horizontalAccuracy <= 30 else { return }

        let spd = loc.speed >= 0 ? loc.speed * 3.6 : 0.0
        let alt = loc.verticalAccuracy >= 0 ? loc.altitude : 0.0

        if isTracking && trip != nil {
            if let prev = lastLocation, activeStop == nil {
                let dist = loc.distance(from: prev)
                let dt = loc.timestamp.timeIntervalSince(prev.timestamp)
                if dt > 0 && dt <= 0.4 { return }

                let implied = dt > 0 ? dist / dt : 0.0
                let teleport = implied > 60.0 && dist > 50.0
                let moving = (spd >= 2.5 || loc.speed >= 0.7) && dist >= 3.0
                let significant = dist >= 10.0

                if !teleport && (moving || significant) {
                    distanceMeters += dist
                    if prev.verticalAccuracy >= 0 && loc.verticalAccuracy >= 0 {
                        let diff = loc.altitude - prev.altitude
                        if diff >= 0.5 && diff <= 100.0 { elevationGain += diff }
                    }
                }
            }
            if spd > maxSpeed { maxSpeed = spd }
            trip?.points.append(GpsPoint(lat: loc.coordinate.latitude, lng: loc.coordinate.longitude,
                                         alt: alt, speedKmh: spd, time: Date()))
        }

        lastLocation = loc
        lastLat = loc.coordinate.latitude
        lastLng = loc.coordinate.longitude
        speedKmh = spd
        if alt != 0 {
            altitude = alt
            if alt < minAlt { minAlt = alt }
            if alt > maxAlt { maxAlt = alt }
        }
        if isTracking {
            avgSpeedKmh = computeAvg()
        } else {
            avgSpeedKmh = spd
        }
        geocodeIfNeeded(loc)
    }

    private func computeAvg() -> Double {
        if drivingSeconds > 0 {
            return (distanceMeters / 1000.0) / (Double(drivingSeconds) / 3600.0)
        }
        return 0
    }

    // MARK: Géocodage et frontières

    private func geocodeIfNeeded(_ loc: CLLocation) {
        if geocoding { return }
        var due = false
        if let last = lastGeocodeDate {
            let elapsed = Date().timeIntervalSince(last)
            let moved = lastGeocodeLocation.map { loc.distance(from: $0) } ?? 1000
            due = (elapsed >= 12 && moved >= 150) || elapsed >= 90
        } else {
            due = true
        }
        if !due { return }
        geocoding = true
        geocoder.reverseGeocodeLocation(loc) { [weak self] marks, _ in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.geocoding = false
                self.lastGeocodeDate = Date()
                self.lastGeocodeLocation = loc
                if let pm = marks?.first { self.applyPlacemark(pm) }
            }
        }
    }

    private func applyPlacemark(_ pm: CLPlacemark) {
        let newCity = pm.locality ?? pm.subAdministrativeArea ?? pm.administrativeArea ?? ""
        let state = pm.administrativeArea ?? ""
        let country = pm.country ?? ""
        let street = [pm.subThoroughfare, pm.thoroughfare].compactMap { $0 }.joined(separator: " ")
        let parts: [String] = [street, pm.locality ?? "", state, country].filter { !$0.isEmpty }
        let addr = parts.joined(separator: ", ")

        if !newCity.isEmpty { city = newCity }
        if !addr.isEmpty { address = addr }

        guard isTracking, trip != nil else { return }

        if departureNeedsPlace, !newCity.isEmpty {
            departureNeedsPlace = false
            trip?.startPlace = newCity
            trip?.startAddress = addr
            if let i = trip?.stages.firstIndex(where: { $0.type == .departure }) {
                trip?.stages[i].placeName = newCity
                trip?.stages[i].address = addr
            }
        }
        checkBorder(state: state, country: country)
    }

    private func checkBorder(state: String, country: String) {
        let cState = TrackingManager.normalizeRegion(state)
        let cCountry = TrackingManager.normalizeRegion(country)
        if cState.isEmpty || cCountry.isEmpty { return }

        if confirmedState.isEmpty || confirmedCountry.isEmpty {
            confirmedState = cState
            confirmedCountry = cCountry
            return
        }

        let countryChanged = cCountry != confirmedCountry
        let stateChanged = cState != confirmedState

        if !(countryChanged || stateChanged) {
            pendingHits = 0
            pendingState = ""
            pendingCountry = ""
            return
        }

        if cState == pendingState && cCountry == pendingCountry {
            pendingHits += 1
        } else {
            pendingState = cState
            pendingCountry = cCountry
            pendingHits = 1
        }

        let sinceBorder = distanceMeters - distanceAtLastBorder
        if pendingHits >= 2 && sinceBorder >= 2500.0 {
            let title: String
            if countryChanged {
                title = country.isEmpty ? tr("Poste frontalier") : tr("Douanes / Frontière :") + " \(country)"
            } else {
                title = state.isEmpty ? tr("Passage frontière") : tr("Frontière État :") + " \(state)"
            }
            let info = [state, country].filter { !$0.isEmpty }.joined(separator: ", ")
            let now = Date()
            var stage = Stage(type: .border)
            stage.placeName = title
            stage.address = info
            stage.arrival = now
            stage.departure = now
            stage.country = country
            stage.stateProvince = state
            stage.lat = lastLat
            stage.lng = lastLng
            stage.altitude = altitude
            stage.distanceFromPrevMeters = max(0, distanceMeters - stageAnchor)
            stage.distanceSinceLastChargeMeters = max(0, distanceMeters - chargeAnchor)
            trip?.stages.append(stage)

            confirmedState = cState
            confirmedCountry = cCountry
            distanceAtLastBorder = distanceMeters
            stageAnchor = distanceMeters
            pendingHits = 0
            pendingState = ""
            pendingCountry = ""
        }
    }

    private static let regionAliases: [(names: [String], canonical: String)] = [
        (["QC", "QUE", "QUEBEC"], "QUEBEC"),
        (["ON", "ONT", "ONTARIO"], "ONTARIO"),
        (["NB", "NOUVEAU BRUNSWICK", "NEW BRUNSWICK"], "NEW BRUNSWICK"),
        (["NS", "NOUVELLE ECOSSE", "NOVA SCOTIA"], "NOVA SCOTIA"),
        (["PE", "ILE DU PRINCE EDOUARD", "PRINCE EDWARD ISLAND"], "PRINCE EDWARD ISLAND"),
        (["NL", "TERRE NEUVE ET LABRADOR", "NEWFOUNDLAND", "NEWFOUNDLAND AND LABRADOR"], "NEWFOUNDLAND"),
        (["MB", "MANITOBA"], "MANITOBA"),
        (["SK", "SASKATCHEWAN"], "SASKATCHEWAN"),
        (["AB", "ALBERTA"], "ALBERTA"),
        (["BC", "COLOMBIE BRITANNIQUE", "BRITISH COLUMBIA"], "BRITISH COLUMBIA"),
        (["YT", "YUKON"], "YUKON"),
        (["NT", "TERRITOIRES DU NORD OUEST", "NORTHWEST TERRITORIES"], "NORTHWEST TERRITORIES"),
        (["NU", "NUNAVUT"], "NUNAVUT"),
        (["NY", "NEW YORK"], "NEW YORK"),
        (["VT", "VERMONT"], "VERMONT"),
        (["NH", "NEW HAMPSHIRE"], "NEW HAMPSHIRE"),
        (["ME", "MAINE"], "MAINE"),
        (["MA", "MASSACHUSETTS"], "MASSACHUSETTS"),
        (["CT", "CONNECTICUT"], "CONNECTICUT"),
        (["RI", "RHODE ISLAND"], "RHODE ISLAND"),
        (["NJ", "NEW JERSEY"], "NEW JERSEY"),
        (["PA", "PENNSYLVANIA"], "PENNSYLVANIA"),
        (["DE", "DELAWARE"], "DELAWARE"),
        (["MD", "MARYLAND"], "MARYLAND"),
        (["DC", "DISTRICT OF COLUMBIA"], "DISTRICT OF COLUMBIA"),
        (["VA", "VIRGINIA"], "VIRGINIA"),
        (["NC", "NORTH CAROLINA", "CAROLINE DU NORD"], "NORTH CAROLINA"),
        (["SC", "SOUTH CAROLINA", "CAROLINE DU SUD"], "SOUTH CAROLINA"),
        (["GA", "GEORGIA", "GEORGIE"], "GEORGIA"),
        (["FL", "FLORIDA", "FLORIDE"], "FLORIDA"),
        (["CA", "CAN", "CANADA"], "CANADA"),
        (["US", "USA", "UNITED STATES", "UNITED STATES OF AMERICA", "ETATS UNIS"], "UNITED STATES")
    ]

    static func normalizeRegion(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "" }
        let folded = trimmed.folding(options: .diacriticInsensitive, locale: Locale(identifier: "en_US")).uppercased()
        var chars: [Character] = []
        for c in folded {
            if c.isASCII && (c.isLetter || c.isNumber) { chars.append(c) } else { chars.append(" ") }
        }
        let clean = String(chars).split(separator: " ").joined(separator: " ")
        for entry in regionAliases where entry.names.contains(clean) {
            return entry.canonical
        }
        return clean
    }

    // MARK: Trajet

    func startTrip(place: String, soc: Int?) {
        guard !isTracking else { return }
        let now = Date()
        let hasCity = city != TrackingManager.placeholderCity
        let startPlace = !place.isEmpty ? place : (hasCity ? city : tr("Départ"))
        departureNeedsPlace = place.isEmpty && !hasCity

        var t = Trip()
        t.startTime = now
        t.startPlace = startPlace
        t.startAddress = address
        t.startLat = lastLat
        t.startLng = lastLng
        t.startSoc = soc
        t.isOngoing = true

        var dep = Stage(type: .departure)
        dep.placeName = startPlace
        dep.address = address
        dep.arrival = now
        dep.departure = now
        dep.lat = lastLat
        dep.lng = lastLng
        dep.altitude = altitude
        dep.startSoc = soc
        dep.endSoc = soc
        t.stages = [dep]

        trip = t
        distanceMeters = 0
        elevationGain = 0
        tripSeconds = 0
        drivingSeconds = 0
        activeStop = nil
        activeStopSeconds = 0
        stopStart = nil
        stoppedBefore = 0
        chargeAnchor = 0
        stageAnchor = 0
        maxSpeed = 0
        sinceChargeMeters = 0
        confirmedState = ""
        confirmedCountry = ""
        pendingState = ""
        pendingCountry = ""
        pendingHits = 0
        distanceAtLastBorder = 0
        lastLocation = nil
        lastSave = now

        isTracking = true
        UIApplication.shared.isIdleTimerDisabled = true
        lm.allowsBackgroundLocationUpdates = true
        lm.showsBackgroundLocationIndicator = true
        lm.startUpdatingLocation()
        startTimer()
        store.save(t)
    }

    private func startTimer() {
        timer?.invalidate()
        let tm = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(tm, forMode: .common)
        timer = tm
    }

    private func tick() {
        guard isTracking, let t = trip else { return }
        let now = Date()
        tripSeconds = Int(now.timeIntervalSince(t.startTime))
        activeStopSeconds = stopStart.map { Int(now.timeIntervalSince($0)) } ?? 0
        drivingSeconds = max(0, tripSeconds - stoppedBefore - activeStopSeconds)
        avgSpeedKmh = computeAvg()
        sinceChargeMeters = max(0, distanceMeters - chargeAnchor)

        if now.timeIntervalSince(lastSave) >= 30 {
            lastSave = now
            var snap = t
            applyTotals(&snap)
            store.save(snap)
        }
    }

    private func applyTotals(_ t: inout Trip) {
        t.totalDistanceMeters = distanceMeters
        t.drivingSeconds = drivingSeconds
        t.avgSpeedKmh = computeAvg()
        t.maxSpeedKmh = maxSpeed
        t.elevationGainMeters = elevationGain
        t.endLat = lastLat
        t.endLng = lastLng
        if let local = trip { t.stages = local.stages; t.points = local.points }
    }

    func beginStop(_ type: StageType, startSoc: Int? = nil) {
        guard isTracking, activeStop == nil else { return }
        activeStop = type
        activeStopStartSoc = startSoc
        stopStart = Date()
        activeStopSeconds = 0
    }

    func finishStop(place: String, kwh: Double, cost: Double, network: String,
                    notes: String, startSoc: Int?, endSoc: Int?, fuelLiters: Double? = nil) {
        guard let type = activeStop, let start = stopStart else { return }
        let now = Date()
        let duration = max(0, Int(now.timeIntervalSince(start)))

        var stage = Stage(type: type)
        stage.placeName = place.isEmpty ? (city == TrackingManager.placeholderCity ? "" : city) : place
        stage.address = address
        stage.arrival = start
        stage.departure = now
        stage.durationSeconds = duration
        stage.energyKwh = kwh
        stage.cost = cost
        stage.network = network
        stage.notes = notes
        stage.lat = lastLat
        stage.lng = lastLng
        stage.altitude = altitude
        stage.distanceFromPrevMeters = max(0, distanceMeters - stageAnchor)
        stage.distanceSinceLastChargeMeters = max(0, distanceMeters - chargeAnchor)
        stage.startSoc = startSoc
        stage.endSoc = endSoc
        stage.fuelLiters = fuelLiters
        trip?.stages.append(stage)

        stoppedBefore += duration
        if type.isCharging || type.isRefuel { chargeAnchor = distanceMeters }
        stageAnchor = distanceMeters
        activeStop = nil
        activeStopStartSoc = nil
        stopStart = nil
        activeStopSeconds = 0

        if var t = trip {
            applyTotals(&t)
            store.save(t)
        }
    }

    func endTrip(endSoc: Int?) {
        guard isTracking, var t = trip else { return }
        if activeStop != nil {
            finishStop(place: "", kwh: 0, cost: 0, network: "", notes: "", startSoc: nil, endSoc: nil)
            t = trip ?? t
        }
        let now = Date()
        var arrival = Stage(type: .arrival)
        arrival.placeName = city == TrackingManager.placeholderCity ? tr("Arrivée") : city
        arrival.address = address
        arrival.arrival = now
        arrival.departure = now
        arrival.lat = lastLat
        arrival.lng = lastLng
        arrival.altitude = altitude
        arrival.distanceFromPrevMeters = max(0, distanceMeters - stageAnchor)
        arrival.distanceSinceLastChargeMeters = max(0, distanceMeters - chargeAnchor)
        arrival.endSoc = endSoc
        trip?.stages.append(arrival)

        t = trip ?? t
        applyTotals(&t)
        t.endTime = now
        t.endPlace = arrival.placeName
        t.endAddress = address
        t.endSoc = endSoc
        t.isOngoing = false
        t.recomputeTimes()
        store.save(t)

        timer?.invalidate()
        timer = nil
        trip = nil
        isTracking = false
        activeStop = nil
        distanceMeters = 0
        elevationGain = 0
        tripSeconds = 0
        drivingSeconds = 0
        sinceChargeMeters = 0
        avgSpeedKmh = speedKmh
        UIApplication.shared.isIdleTimerDisabled = false
        lm.allowsBackgroundLocationUpdates = false
        lm.showsBackgroundLocationIndicator = false
    }
}
