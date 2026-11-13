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
