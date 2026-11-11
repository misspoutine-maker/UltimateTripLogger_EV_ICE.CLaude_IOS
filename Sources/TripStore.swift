import Foundation

final class TripStore: ObservableObject {
    @Published private(set) var trips: [Trip] = []
    private let dir: URL
    private let io = DispatchQueue(label: "trip.io", qos: .utility)

    init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        dir = docs.appendingPathComponent("Trips", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        load()
    }

    private func fileURL(_ id: UUID) -> URL {
        return dir.appendingPathComponent("\(id.uuidString).json")
    }

    private func load() {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        var list: [Trip] = []
        for f in files where f.pathExtension == "json" {
            guard let data = try? Data(contentsOf: f),
                  var trip = try? decoder.decode(Trip.self, from: data) else { continue }
            if trip.isOngoing {
                // Trajet interrompu (app fermée) : on le clôture pour ne rien perdre
                trip.isOngoing = false
                trip.endTime = trip.points.last?.time ?? trip.startTime
                write(trip)
            }
            list.append(trip)
        }
        trips = list.sorted { $0.startTime > $1.startTime }
    }

    private func write(_ trip: Trip) {
        let url = fileURL(trip.id)
        io.async {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            if let data = try? encoder.encode(trip) {
                try? data.write(to: url, options: .atomic)
            }
        }
    }

    func save(_ trip: Trip) {
        write(trip)
        if let i = trips.firstIndex(where: { $0.id == trip.id }) {
            trips[i] = trip
        } else {
            trips.insert(trip, at: 0)
        }
    }

    func mutate(_ tripId: UUID, _ change: (inout Trip) -> Void) {
        guard let i = trips.firstIndex(where: { $0.id == tripId }) else { return }
        var t = trips[i]
        change(&t)
        t.recomputeTimes()
        save(t)
    }

    func delete(_ trip: Trip) {
        try? FileManager.default.removeItem(at: fileURL(trip.id))
        trips.removeAll { $0.id == trip.id }
    }
}

enum CsvExporter {
    private static func esc(_ s: String) -> String {
        return "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    private static func num(_ v: Double, _ digits: Int = 1) -> String {
        return String(format: "%.\(digits)f", locale: Locale(identifier: "en_US"), v)
    }

    private static func soc(_ v: Int?) -> String {
        if let v = v { return "\(v)" }
        return ""
    }

    private static func write(_ text: String, name: String) -> URL? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        let bom = "\u{FEFF}"
        do {
            try (bom + text).write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            return nil
        }
    }

    static func tripCSV(_ trip: Trip) -> URL? {
        var lines: [String] = []
        let header = ["Type", "Lieu", "Adresse", "Arrivée", "Départ", "Durée (min)",
                      "Distance depuis précédent (km)", "Depuis dernière recharge (km)",
                      "kWh", "Carburant (L)", "Coût", "Réseau", "SOC début (%)", "SOC fin (%)", "Notes"]
        lines.append(header.map { esc(tr($0)) }.joined(separator: ","))
        for s in trip.stages {
            let cols: [String] = [
                esc(s.type.label), esc(s.placeName), esc(s.address),
                esc(Fmt.dateTime(s.arrival)), esc(Fmt.dateTime(s.departure)),
                num(Double(s.durationSeconds) / 60.0, 0),
                num(s.distanceFromPrevMeters / 1000.0),
                num(s.distanceSinceLastChargeMeters / 1000.0),
                num(s.energyKwh), num(s.fuelLiters ?? 0), num(s.cost, 2), esc(s.network),
                soc(s.startSoc), soc(s.endSoc), esc(s.notes)
            ]
            lines.append(cols.joined(separator: ","))
        }
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd_HHmm"
        return write(lines.joined(separator: "\n"), name: "Trajet_\(df.string(from: trip.startTime)).csv")
    }

    static func allTripsCSV(_ trips: [Trip]) -> URL? {
        var lines: [String] = []
        let header = ["Date", "Départ", "Arrivée", "Distance (km)", "Durée conduite (min)",
                      "Recharge (min)", "Repas (min)", "Autre (min)", "Vitesse moy. (km/h)",
                      "Vitesse max (km/h)", "Dénivelé + (m)", "SOC départ (%)", "SOC arrivée (%)"]
        lines.append(header.map { esc(tr($0)) }.joined(separator: ","))
        for t in trips where !t.isOngoing {
            let cols: [String] = [
                esc(Fmt.dateTime(t.startTime)), esc(t.startPlace), esc(t.endPlace),
                num(t.totalDistanceMeters / 1000.0),
                num(Double(t.drivingSeconds) / 60.0, 0),
                num(Double(t.chargingSeconds) / 60.0, 0),
                num(Double(t.mealSeconds) / 60.0, 0),
                num(Double(t.otherSeconds) / 60.0, 0),
                num(t.avgSpeedKmh), num(t.maxSpeedKmh), num(t.elevationGainMeters, 0),
                soc(t.startSoc), soc(t.endSoc)
            ]
            lines.append(cols.joined(separator: ","))
        }
        return write(lines.joined(separator: "\n"), name: "Tous_les_trajets.csv")
    }
}
