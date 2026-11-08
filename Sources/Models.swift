import Foundation

enum StageType: String, Codable, CaseIterable {
    case departure, charging, meal, chargingMeal, other, border, arrival

    var label: String {
        switch self {
        case .departure: return "Départ"
        case .charging: return "Recharge"
        case .meal: return "Repas"
        case .chargingMeal: return "Recharge + repas"
        case .other: return "Autre arrêt"
        case .border: return "Frontière"
        case .arrival: return "Arrivée"
        }
    }

    var icon: String {
        switch self {
        case .departure: return "flag.fill"
        case .charging: return "bolt.fill"
        case .meal: return "fork.knife"
        case .chargingMeal: return "bolt.fill"
        case .other: return "mappin.and.ellipse"
        case .border: return "arrow.left.arrow.right"
        case .arrival: return "flag.checkered"
        }
    }

    var isCharging: Bool { self == .charging || self == .chargingMeal }
}

struct Stage: Codable, Identifiable {
    var id = UUID()
    var type: StageType
    var placeName = ""
    var address = ""
    var arrival = Date()
    var departure = Date()
    var durationSeconds = 0
    var energyKwh = 0.0
    var cost = 0.0
    var network = ""
    var notes = ""
    var country = ""
    var stateProvince = ""
    var lat = 0.0
    var lng = 0.0
    var altitude = 0.0
    var distanceFromPrevMeters = 0.0
    var distanceSinceLastChargeMeters = 0.0
    var startSoc: Int?
    var endSoc: Int?
}

struct GpsPoint: Codable {
    var lat: Double
    var lng: Double
    var alt: Double
    var speedKmh: Double
    var time: Date
}

struct Trip: Codable, Identifiable {
    var id = UUID()
    var startTime = Date()
    var endTime: Date?
    var startPlace = "Départ"
    var startAddress = ""
    var startLat = 0.0
    var startLng = 0.0
    var endPlace = ""
    var endAddress = ""
    var endLat = 0.0
    var endLng = 0.0
    var totalDistanceMeters = 0.0
    var drivingSeconds = 0
    var chargingSeconds = 0
    var mealSeconds = 0
    var otherSeconds = 0
    var avgSpeedKmh = 0.0
    var maxSpeedKmh = 0.0
    var elevationGainMeters = 0.0
    var isOngoing = false
    var startSoc: Int?
    var endSoc: Int?
    var stages: [Stage] = []
    var points: [GpsPoint] = []
}
