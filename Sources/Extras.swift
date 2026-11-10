import SwiftUI
import UIKit

enum AppInfo {
    static var versionString: String {
        let info = Bundle.main.infoDictionary
        let v = info?["CFBundleShortVersionString"] as? String ?? "?"
        let b = info?["CFBundleVersion"] as? String ?? "?"
        return "Version \(v) (build \(b))"
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
    static func tripPDF(_ trip: Trip) -> URL? {
        var lines: [(String, Bool)] = []
        lines.append(("\(trip.startPlace) → \(trip.endPlace.isEmpty ? "…" : trip.endPlace)", true))
        lines.append((Fmt.dateTime(trip.startTime), false))
        lines.append(("", false))
        lines.append(("Distance : \(Fmt.km(trip.totalDistanceMeters))", false))
        lines.append(("Conduite : \(Fmt.human(trip.drivingSeconds))   Recharge : \(Fmt.human(trip.chargingSeconds))   Repas : \(Fmt.human(trip.mealSeconds))", false))
        lines.append(("Vitesse moy. : \(Fmt.speed(trip.avgSpeedKmh))   max : \(Fmt.speed(trip.maxSpeedKmh))   Dénivelé + : \(Fmt.meters(trip.elevationGainMeters))", false))
        if trip.startSoc != nil || trip.endSoc != nil {
            let a = trip.startSoc.map { "\($0)" } ?? "–"
            let b = trip.endSoc.map { "\($0)" } ?? "–"
            lines.append(("Batterie : \(a) % → \(b) %", false))
        }
        lines.append(("", false))
        lines.append(("Étapes", true))
        for s in trip.stages {
            var l = "\(Fmt.time(s.arrival))  \(s.type.label)"
            if !s.placeName.isEmpty { l += " – \(s.placeName)" }
            if s.durationSeconds > 0 { l += " (\(Fmt.human(s.durationSeconds)))" }
            lines.append((l, false))
            var d = "      +\(Fmt.km(s.distanceFromPrevMeters))"
            if s.energyKwh > 0 || s.cost > 0 {
                d += String(format: " • %.1f kWh • %.2f $", s.energyKwh, s.cost)
            }
            if !s.network.isEmpty { d += " • \(s.network)" }
            lines.append((d, false))
        }

        let pageRect = CGRect(x: 0, y: 0, width: 595, height: 842)
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)
        let normal: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 11)]
        let bold: [NSAttributedString.Key: Any] = [.font: UIFont.boldSystemFont(ofSize: 15)]

        let data = renderer.pdfData { ctx in
            ctx.beginPage()
            var y: CGFloat = 40
            for (text, isBold) in lines {
                if y > 790 {
                    ctx.beginPage()
                    y = 40
                }
                (text as NSString).draw(at: CGPoint(x: 40, y: y), withAttributes: isBold ? bold : normal)
                y += isBold ? 24 : 16
            }
        }

        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd_HHmm"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Trajet_\(df.string(from: trip.startTime)).pdf")
        do {
            try data.write(to: url)
            return url
        } catch {
            return nil
        }
    }
}
