import SwiftUI

enum Fmt {
    static func hms(_ s: Int) -> String {
        let v = max(0, s)
        return String(format: "%02d:%02d:%02d", v / 3600, (v % 3600) / 60, v % 60)
    }

    static func human(_ s: Int) -> String {
        let v = max(0, s)
        let h = v / 3600
        let m = (v % 3600) / 60
        if h > 0 { return "\(h)h \(m)m" }
        if m > 0 { return "\(m)m" }
        return "\(v)s"
    }

    static func km(_ meters: Double) -> String {
        return String(format: "%.1f km", meters / 1000.0)
    }

    static func speed(_ kmh: Double) -> String {
        return "\(Int(kmh)) km/h"
    }

    static func meters(_ m: Double) -> String {
        return "\(Int(m)) m"
    }

    private static let dtFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f
    }()

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    static func day(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Lang.locale
        f.dateStyle = .long
        return f.string(from: d)
    }

    static var fuelUnitIsGallons: Bool {
        return (UserDefaults.standard.string(forKey: "fuelUnit") ?? "l") == "gal"
    }

    static func fuel(_ liters: Double) -> String {
        if fuelUnitIsGallons { return String(format: "%.1f gal", liters * 0.264172) }
        return String(format: "%.1f L", liters)
    }

    static func displayToLiters(_ value: Double) -> Double {
        return fuelUnitIsGallons ? value / 0.264172 : value
    }

    static func litersToDisplay(_ liters: Double) -> Double {
        return fuelUnitIsGallons ? liters * 0.264172 : liters
    }

    static func consumption(liters: Double, meters: Double) -> String {
        if liters <= 0 || meters <= 0 { return "–" }
        if fuelUnitIsGallons {
            let mpg = (meters / 1609.344) / (liters * 0.264172)
            return String(format: "%.1f mpg", mpg)
        }
        return String(format: "%.1f L/100 km", liters / (meters / 1000.0) * 100.0)
    }

    static func dateTime(_ d: Date) -> String { dtFormatter.string(from: d) }
    static func time(_ d: Date) -> String { timeFormatter.string(from: d) }
}

enum Theme {
    static let background = Color(hex: 0x0B132B)
    static let surface = Color(hex: 0x141E3A)
    static let card = Color(hex: 0x1C2541)
    static let border = Color(hex: 0x2E3E69)
    static let blue = Color(hex: 0x00D2FF)
    static let green = Color(hex: 0x00E676)
    static let amber = Color(hex: 0xFFB703)
    static let purple = Color(hex: 0xBD66FF)
    static let orange = Color(hex: 0xFF7A00)
    static let gold = Color(hex: 0xFFD166)
    static let red = Color(hex: 0xFF4B5C)
    static let textPrimary = Color(hex: 0xF2F6FA)
    static let textSecondary = Color(hex: 0xA0AEC0)

    static func color(for type: StageType) -> Color {
        switch type {
        case .departure: return blue
        case .charging: return green
        case .refuel: return orange
        case .meal: return amber
        case .chargingMeal: return green
        case .other: return purple
        case .border: return gold
        case .arrival: return blue
        }
    }
}

extension Color {
    init(hex: UInt32) {
        let r = Double((hex >> 16) & 0xFF) / 255.0
        let g = Double((hex >> 8) & 0xFF) / 255.0
        let b = Double(hex & 0xFF) / 255.0
        self.init(red: r, green: g, blue: b)
    }
}
