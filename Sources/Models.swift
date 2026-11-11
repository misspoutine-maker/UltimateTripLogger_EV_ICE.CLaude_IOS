import Foundation

enum StageType: String, Codable, CaseIterable {
    case departure, charging, refuel, meal, chargingMeal, other, border, arrival

    var label: String {
        switch self {
        case .departure: return tr("Départ")
        case .charging: return tr("Recharge")
        case .refuel: return tr("Carburant")
        case .meal: return tr("Repas")
        case .chargingMeal: return tr("Recharge + repas")
        case .other: return tr("Autre arrêt")
        case .border: return tr("Frontière")
        case .arrival: return tr("Arrivée")
        }
    }

    var icon: String {
        switch self {
        case .departure: return "flag.fill"
        case .charging: return "bolt.fill"
        case .refuel: return "fuelpump.fill"
        case .meal: return "fork.knife"
        case .chargingMeal: return "bolt.fill"
        case .other: return "mappin.and.ellipse"
        case .border: return "arrow.left.arrow.right"
        case .arrival: return "flag.checkered"
        }
    }

    var isCharging: Bool { self == .charging || self == .chargingMeal }
    var isRefuel: Bool { self == .refuel }
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
    var fuelLiters: Double?
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
    var refuelSeconds: Int?
    var avgSpeedKmh = 0.0
    var maxSpeedKmh = 0.0
    var elevationGainMeters = 0.0
    var isOngoing = false
    var startSoc: Int?
    var endSoc: Int?
    var stages: [Stage] = []
    var points: [GpsPoint] = []
}

extension Trip {
    mutating func recomputeTimes() {
        chargingSeconds = stages.filter { $0.type.isCharging }.reduce(0) { $0 + $1.durationSeconds }
        mealSeconds = stages.filter { $0.type == .meal }.reduce(0) { $0 + $1.durationSeconds }
        otherSeconds = stages.filter { $0.type == .other }.reduce(0) { $0 + $1.durationSeconds }
        refuelSeconds = stages.filter { $0.type.isRefuel }.reduce(0) { $0 + $1.durationSeconds }
    }

    var totalKwh: Double { stages.reduce(0) { $0 + $1.energyKwh } }
    var totalFuelLiters: Double { stages.reduce(0) { $0 + ($1.fuelLiters ?? 0) } }
    var totalCost: Double { stages.reduce(0) { $0 + $1.cost } }
}
