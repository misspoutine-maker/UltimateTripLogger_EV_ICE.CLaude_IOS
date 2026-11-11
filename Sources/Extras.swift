import SwiftUI
import UIKit
import MapKit

enum AppInfo {
    static var versionString: String {
        let info = Bundle.main.infoDictionary
        let v = info?["CFBundleShortVersionString"] as? String ?? "?"
        let b = info?["CFBundleVersion"] as? String ?? "?"
        return tr("Version") + " \(v) (build \(b))"
    }
}

struct AltitudeProfileView: View {
    let points: [GpsPoint]

    private var alts: [Double] {
        let valid = points.filter { $0.alt != 0 }.map { $0.alt }
        if valid.count <= 200 { return valid }
        let step = Double(valid.count) / 200.0
        var out: [Double] = []
        var i = 0.0
        while Int(i) < valid.count {
            out.append(valid[Int(i)])
            i += step
        }
        return out
    }

    var body: some View {
        let a = alts
        let lo = a.min() ?? 0
        let hi = a.max() ?? 0
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Profil d'altitude")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Theme.textSecondary)
                Spacer()
                Text("\(Int(lo)) m – \(Int(hi)) m")
                    .font(.system(size: 12))
                    .foregroundColor(Theme.blue)
            }
            GeometryReader { geo in
                let range = max(hi - lo, 1)
                let w = geo.size.width
                let h = geo.size.height
                ZStack {
                    Path { p in
                        guard a.count >= 2 else { return }
                        p.move(to: CGPoint(x: 0, y: h))
                        for (i, v) in a.enumerated() {
                            let x = w * CGFloat(i) / CGFloat(a.count - 1)
                            let y = h - h * CGFloat((v - lo) / range)
                            p.addLine(to: CGPoint(x: x, y: y))
                        }
                        p.addLine(to: CGPoint(x: w, y: h))
                        p.closeSubpath()
                    }
                    .fill(Theme.blue.opacity(0.25))
                    Path { p in
                        guard a.count >= 2 else { return }
                        for (i, v) in a.enumerated() {
                            let x = w * CGFloat(i) / CGFloat(a.count - 1)
                            let y = h - h * CGFloat((v - lo) / range)
                            if i == 0 { p.move(to: CGPoint(x: x, y: y)) } else { p.addLine(to: CGPoint(x: x, y: y)) }
                        }
                    }
                    .stroke(Theme.blue, lineWidth: 2)
                }
            }
            .frame(height: 110)
        }
        .padding(14)
        .background(Theme.surface)
        .cornerRadius(14)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.border, lineWidth: 1))
    }
}

enum PdfExporter {
    static func tripPDF(_ trip: Trip, completion: @escaping (URL?) -> Void) {
        var lines: [(String, Bool)] = []
        lines.append(("\(trip.startPlace) → \(trip.endPlace.isEmpty ? "…" : trip.endPlace)", true))
        lines.append((Fmt.dateTime(trip.startTime), false))
        lines.append(("", false))
        lines.append((tr("Distance :") + " \(Fmt.km(trip.totalDistanceMeters))", false))
        lines.append((tr("Conduite :") + " \(Fmt.human(trip.drivingSeconds))   " + tr("Recharge :") + " \(Fmt.human(trip.chargingSeconds))   " + tr("Repas :") + " \(Fmt.human(trip.mealSeconds))", false))
        lines.append((tr("Vitesse moy. :") + " \(Fmt.speed(trip.avgSpeedKmh))   max : \(Fmt.speed(trip.maxSpeedKmh))   " + tr("Dénivelé + :") + " \(Fmt.meters(trip.elevationGainMeters))", false))
        if trip.startSoc != nil || trip.endSoc != nil {
            let a = trip.startSoc.map { "\($0)" } ?? "–"
            let b = trip.endSoc.map { "\($0)" } ?? "–"
            lines.append((tr("Batterie :") + " \(a) % → \(b) %", false))
        }
        lines.append(("", false))
        lines.append((tr("Étapes"), true))
        for s in trip.stages {
            var l = "\(Fmt.time(s.arrival))  \(s.type.label)"
            if !s.placeName.isEmpty { l += " – \(s.placeName)" }
            if s.durationSeconds > 0 { l += " (\(Fmt.human(s.durationSeconds)))" }
            lines.append((l, false))
            var d = "      +\(Fmt.km(s.distanceFromPrevMeters))"
            if s.energyKwh > 0 { d += String(format: " • %.1f kWh", s.energyKwh) }
            if let f = s.fuelLiters, f > 0 { d += " • " + Fmt.fuel(f) }
            if s.cost > 0 { d += String(format: " • %.2f $", s.cost) }
            if !s.network.isEmpty { d += " • \(s.network)" }
            lines.append((d, false))
        }

        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd_HHmm"
        let name = "Trajet_\(df.string(from: trip.startTime)).pdf"
        mapImage(points: trip.points, stages: trip.stages, size: CGSize(width: 515, height: 300)) { image in
            completion(render(lines, name: name, image: image))
        }
    }

    static func mapImage(points: [GpsPoint], stages: [Stage], size: CGSize, completion: @escaping (UIImage?) -> Void) {
        let step = max(1, points.count / 2000)
        var coords: [CLLocationCoordinate2D] = []
        var i = 0
        while i < points.count {
            coords.append(CLLocationCoordinate2D(latitude: points[i].lat, longitude: points[i].lng))
            i += step
        }
        guard coords.count >= 2 else {
            completion(nil)
            return
        }
        let rect = MKPolyline(coordinates: coords, count: coords.count).boundingMapRect
        let options = MKMapSnapshotter.Options()
        options.mapRect = rect.insetBy(dx: -rect.size.width * 0.15 - 500, dy: -rect.size.height * 0.15 - 500)
        options.size = size
        MKMapSnapshotter(options: options).start { snapshot, _ in
            guard let snap = snapshot else {
                completion(nil)
                return
            }
            let image = UIGraphicsImageRenderer(size: size).image { _ in
                snap.image.draw(at: .zero)
                let path = UIBezierPath()
                for (n, c) in coords.enumerated() {
                    let pt = snap.point(for: c)
                    if n == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
                }
                path.lineWidth = 4
                path.lineJoinStyle = .round
                UIColor(red: 0, green: 0.55, blue: 1, alpha: 1).setStroke()
                path.stroke()
                for st in stages where st.lat != 0 || st.lng != 0 {
                    let pt = snap.point(for: CLLocationCoordinate2D(latitude: st.lat, longitude: st.lng))
                    let color: UIColor
                    switch st.type {
                    case .charging, .chargingMeal: color = .systemGreen
                    case .refuel: color = .systemOrange
                    case .meal: color = .systemYellow
                    case .other: color = .systemPurple
                    default: color = .systemRed
                    }
                    color.setFill()
                    UIColor.white.setStroke()
                    let dot = UIBezierPath(ovalIn: CGRect(x: pt.x - 6, y: pt.y - 6, width: 12, height: 12))
                    dot.lineWidth = 2
                    dot.fill()
                    dot.stroke()
                }
            }
            completion(image)
        }
    }

    static func dayPDF(_ day: DayRecap) -> URL? {
        var lines: [(String, Bool)] = []
        lines.append((tr("Récap du") + " \(Fmt.day(day.id))", true))
        lines.append(("", false))
        lines.append((tr("Trajets :") + " \(day.trips.count)   " + tr("Distance :") + " \(Fmt.km(day.distance))   " + tr("Conduite :") + " \(Fmt.human(day.driving))", false))
        lines.append((tr("Vitesse moy. :") + " \(Fmt.speed(day.avgSpeed))   max : \(Fmt.speed(day.maxSpeed))   " + tr("Dénivelé + :") + " \(Fmt.meters(day.gain))", false))
        lines.append((tr("Énergie :") + String(format: " %.1f kWh   ", day.kwh) + tr("Coût :") + String(format: " %.2f $   ", day.cost) + tr("Recharges :") + " \(day.chargeCount)", false))
        lines.append((tr("Recharge :") + " \(Fmt.human(day.charging))   " + tr("Repas :") + " \(Fmt.human(day.meal))", false))
        for trip in day.trips {
            lines.append(("", false))
            lines.append(("\(trip.startPlace) → \(trip.endPlace.isEmpty ? "…" : trip.endPlace)", true))
            lines.append(("\(Fmt.time(trip.startTime))  •  \(Fmt.km(trip.totalDistanceMeters))  •  \(Fmt.human(trip.drivingSeconds))", false))
            for s in trip.stages where s.type != .departure && s.type != .arrival {
                var l = "      \(Fmt.time(s.arrival))  \(s.type.label)"
                if !s.placeName.isEmpty { l += " – \(s.placeName)" }
                if s.durationSeconds > 0 { l += " (\(Fmt.human(s.durationSeconds)))" }
                if s.energyKwh > 0 { l += String(format: " • %.1f kWh", s.energyKwh) }
                if let f = s.fuelLiters, f > 0 { l += " • " + Fmt.fuel(f) }
                if s.cost > 0 { l += String(format: " • %.2f $", s.cost) }
                lines.append((l, false))
            }
        }
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        return render(lines, name: "Recap_\(df.string(from: day.id)).pdf")
    }

    private static func render(_ lines: [(String, Bool)], name: String, image: UIImage? = nil) -> URL? {
        let pageRect = CGRect(x: 0, y: 0, width: 595, height: 842)
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)
        let normal: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 11)]
        let bold: [NSAttributedString.Key: Any] = [.font: UIFont.boldSystemFont(ofSize: 15)]
        let data = renderer.pdfData { ctx in
            ctx.beginPage()
            var y: CGFloat = 40
            if let img = image {
                img.draw(in: CGRect(x: 40, y: 40, width: 515, height: 300))
                y = 356
            }
            for (text, isBold) in lines {
                if y > 790 {
                    ctx.beginPage()
                    y = 40
                }
                (text as NSString).draw(at: CGPoint(x: 40, y: y), withAttributes: isBold ? bold : normal)
                y += isBold ? 24 : 16
            }
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        do {
            try data.write(to: url)
            return url
        } catch {
            return nil
        }
    }
}

enum SheetsExport {
    private static func clean(_ s: String) -> String {
        return s.replacingOccurrences(of: "\t", with: " ").replacingOccurrences(of: "\n", with: " ")
    }

    // Texte tabulé : se colle directement dans Google Sheets
    static func tsv(_ trips: [Trip]) -> String {
        let header = ["Date", "Départ", "Arrivée", "Type", "Lieu", "Arrivée à", "Durée (min)",
                      "Distance étape (km)", "Depuis recharge (km)", "kWh", "Carburant (L)", "Coût", "Réseau",
                      "SOC début", "SOC fin", "Notes"]
        var rows: [String] = [header.map { tr($0) }.joined(separator: "\t")]
        let us = Locale(identifier: "en_US")
        for t in trips.sorted(by: { $0.startTime < $1.startTime }) where !t.isOngoing {
            for s in t.stages {
                let cols: [String] = [
                    Fmt.dateTime(t.startTime), clean(t.startPlace), clean(t.endPlace),
                    s.type.label, clean(s.placeName), Fmt.dateTime(s.arrival),
                    String(format: "%.0f", locale: us, Double(s.durationSeconds) / 60.0),
                    String(format: "%.1f", locale: us, s.distanceFromPrevMeters / 1000.0),
                    String(format: "%.1f", locale: us, s.distanceSinceLastChargeMeters / 1000.0),
                    String(format: "%.1f", locale: us, s.energyKwh),
                    String(format: "%.1f", locale: us, s.fuelLiters ?? 0),
                    String(format: "%.2f", locale: us, s.cost), clean(s.network),
                    s.startSoc.map { "\($0)" } ?? "", s.endSoc.map { "\($0)" } ?? "", clean(s.notes)
                ]
                rows.append(cols.joined(separator: "\t"))
            }
        }
        return rows.joined(separator: "\n")
    }

    static func copy(_ trips: [Trip]) {
        UIPasteboard.general.string = tsv(trips)
    }
}
