import Foundation
import MapKit

struct Poi: Identifiable {
    let id = UUID()
    let name: String
    let category: String
    let distance: Double
}

enum PoiFinder {
    static func find(lat: Double, lng: Double, type: StageType?, completion: @escaping ([Poi]) -> Void) {
        if lat == 0 && lng == 0 {
            completion([])
            return
        }
        let queries: [(String, String)]
        switch type {
        case .some(.charging):
            queries = [("EV charging station", "Recharge"), ("Supercharger", "Recharge")]
        case .some(.chargingMeal):
            queries = [("EV charging station", "Recharge"), ("Restaurant", "Restaurant")]
        case .some(.meal):
            queries = [("Restaurant", "Restaurant"), ("Café", "Café")]
        default:
            queries = [("Station-service", "Essence"), ("Hôtel", "Hôtel"), ("Dépanneur", "Commerce")]
        }

        let origin = CLLocation(latitude: lat, longitude: lng)
        let region = MKCoordinateRegion(center: origin.coordinate, latitudinalMeters: 4000, longitudinalMeters: 4000)
        let group = DispatchGroup()
        var found: [Poi] = []

        for (query, category) in queries {
            group.enter()
            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = query
            request.region = region
            MKLocalSearch(request: request).start { response, _ in
                DispatchQueue.main.async {
                    for item in response?.mapItems ?? [] {
                        guard let name = item.name, let loc = item.placemark.location else { continue }
                        found.append(Poi(name: name, category: category, distance: loc.distance(from: origin)))
                    }
                    group.leave()
                }
            }
        }

        group.notify(queue: .main) {
            var seen = Set<String>()
            let unique = found.sorted { $0.distance < $1.distance }.filter { seen.insert($0.name).inserted }
            completion(Array(unique.prefix(8)))
        }
    }
}
