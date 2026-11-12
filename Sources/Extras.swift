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

enum PdfItem {
    case line(String, Bool)
    case image(UIImage, CGFloat)
}

enum PdfExporter {
    // MARK: PDF d'un trajet (avec carte)

    static func tripPDF(_ trip: Trip, completion: @escaping (URL?) -> Void) {
        let head: [PdfItem] = [
            .line("\(trip.startPlace) → \(trip.endPlace.isEmpty ? "…" : trip.endPlace)", true),
            .line(Fmt.dateTime(trip.startTime), false),
            .line("", false)
        ]
        var body: [PdfItem] = []
        body.append(.line("", false))
        body.append(.line(tr("Distance :") + " \(Fmt.km(trip.totalDistanceMeters))", false))
        body.append(.line(tr("Conduite :") + " \(Fmt.human(trip.drivingSeconds))   " + tr("Recharge :") + " \(Fmt.human(trip.chargingSeconds))   " + tr("Repas :") + " \(Fmt.human(trip.mealSeconds))", false))
        body.append(.line(tr("Vitesse moy. :") + " \(Fmt.speed(trip.avgSpeedKmh))   max : \(Fmt.speed(trip.maxSpeedKmh))   " + tr("Dénivelé + :") + " \(Fmt.meters(trip.elevationGainMeters))", false))
        if trip.startSoc != nil || trip.endSoc != nil {
            let a = trip.startSoc.map { "\($0)" } ?? "–"
            let b = trip.endSoc.map { "\($0)" } ?? "–"
            body.append(.line(tr("Batterie :") + " \(a) % → \(b) %", false))
        }
        body.append(.line("", false))
        body.append(.line(tr("Étapes"), true))
        for s in trip.stages {
            body.append(contentsOf: stageLines(s, indent: ""))
        }

        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd_HHmm"
        let name = "Trajet_\(df.string(from: trip.startTime)).pdf"
        mapImage(points: trip.points, stages: trip.stages, size: CGSize(width: 515, height: 300)) { image in
            var items = head
            if let image = image { items.append(.image(image, 300)) }
            items.append(contentsOf: body)
            completion(render(items, name: name))
        }
    }

    // MARK: PDF d'un jour (une carte par trajet)

    static func dayPDF(_ day: DayRecap, completion: @escaping (URL?) -> Void) {
        let head: [PdfItem] = [
            .line(tr("Récap du") + " \(Fmt.day(day.id))", true),
            .line("", false),
            .line(tr("Trajets :") + " \(day.trips.count)   " + tr("Distance :") + " \(Fmt.km(day.distance))   " + tr("Conduite :") + " \(Fmt.human(day.driving))", false),
            .line(tr("Vitesse moy. :") + " \(Fmt.speed(day.avgSpeed))   max : \(Fmt.speed(day.maxSpeed))   " + tr("Dénivelé + :") + " \(Fmt.meters(day.gain))", false),
            .line(tr("Énergie :") + String(format: " %.1f kWh   ", day.kwh) + tr("Coût :") + String(format: " %.2f $   ", day.cost) + tr("Recharges :") + " \(day.chargeCount)", false),
            .line(tr("Recharge :") + " \(Fmt.human(day.charging))   " + tr("Repas :") + " \(Fmt.human(day.meal))", false)
        ]
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        let name = "Recap_\(df.string(from: day.id)).pdf"

        loadMaps(day.trips, 0, [:]) { maps in
            var items = head
            for trip in day.trips {
                items.append(.line("", false))
                items.append(.line("\(trip.startPlace) → \(trip.endPlace.isEmpty ? "…" : trip.endPlace)", true))
                items.append(.line("\(Fmt.time(trip.startTime))  •  \(Fmt.km(trip.totalDistanceMeters))  •  \(Fmt.human(trip.drivingSeconds))", false))
                if let img = maps[trip.id] { items.append(.image(img, 220)) }
                for s in trip.stages where s.type != .departure && s.type != .arrival {
                    items.append(contentsOf: stageLines(s, indent: "      "))
                }
            }
            completion(render(items, name: name))
        }
    }

    private static func loadMaps(_ trips: [Trip], _ index: Int, _ acc: [UUID: UIImage],
                                 _ done: @escaping ([UUID: UIImage]) -> Void) {
        if index >= trips.count {
            done(acc)
            return
        }
        let t = trips[index]
        mapImage(points: t.points, stages: t.stages, size: CGSize(width: 515, height: 220)) { img in
            var next = acc
            if let img = img { next[t.id] = img }
            loadMaps(trips, index + 1, next, done)
        }
    }

    private static func stageLines(_ s: Stage, indent: String) -> [PdfItem] {
        var l = "\(indent)\(Fmt.time(s.arrival))  \(s.type.label)"
        if !s.placeName.isEmpty { l += " – \(s.placeName)" }
        if s.durationSeconds > 0 { l += " (\(Fmt.human(s.durationSeconds)))" }
        var d = "\(indent)      +\(Fmt.km(s.distanceFromPrevMeters))"
        if s.energyKwh > 0 { d += String(format: " • %.1f kWh", s.energyKwh) }
        if let f = s.fuelLiters, f > 0 { d += " • " + Fmt.fuel(f) }
        if s.cost > 0 { d += String(format: " • %.2f $", s.cost) }
        if !s.network.isEmpty { d += " • \(s.network)" }
        return [.line(l, false), .line(d, false)]
    }

    // MARK: Carte (tuiles Apple Plans, sinon tracé seul)

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

        let snapshotter = MKMapSnapshotter(options: options)
        snapshotter.start { snapshot, _ in
            _ = snapshotter // garde le snapshotter en vie jusqu'à la fin
            guard let snap = snapshot else {
                completion(fallbackImage(coords: coords, stages: stages, size: size))
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
                    drawDot(at: pt, type: st.type)
                }
            }
            completion(image)
        }
    }

    private static func drawDot(at pt: CGPoint, type: StageType) {
        let color: UIColor
        switch type {
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

    // Plan B quand les tuiles ne se chargent pas (hors-ligne) : le tracé sur fond uni
    private static func fallbackImage(coords: [CLLocationCoordinate2D], stages: [Stage], size: CGSize) -> UIImage {
        let lats = coords.map { $0.latitude }
        let lngs = coords.map { $0.longitude }
        let minLat = lats.min() ?? 0
        let maxLat = lats.max() ?? 0
        let minLng = lngs.min() ?? 0
        let maxLng = lngs.max() ?? 0
        let midLat = (minLat + maxLat) / 2.0
        let kx = cos(midLat * Double.pi / 180.0)
        let spanX = max((maxLng - minLng) * kx, 0.0001)
        let spanY = max(maxLat - minLat, 0.0001)
        let margin: CGFloat = 20
        let scale = min((size.width - 2 * margin) / CGFloat(spanX), (size.height - 2 * margin) / CGFloat(spanY))
        let offX = (size.width - CGFloat(spanX) * scale) / 2.0
        let offY = (size.height - CGFloat(spanY) * scale) / 2.0

        func project(_ lat: Double, _ lng: Double) -> CGPoint {
            let x = offX + CGFloat((lng - minLng) * kx) * scale
            let y = size.height - (offY + CGFloat(lat - minLat) * scale)
            return CGPoint(x: x, y: y)
        }

        return UIGraphicsImageRenderer(size: size).image { _ in
            UIColor(red: 0.93, green: 0.95, blue: 0.97, alpha: 1).setFill()
            UIBezierPath(rect: CGRect(origin: .zero, size: size)).fill()
            let path = UIBezierPath()
            for (n, c) in coords.enumerated() {
                let pt = project(c.latitude, c.longitude)
                if n == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
            }
            path.lineWidth = 4
            path.lineJoinStyle = .round
            UIColor(red: 0, green: 0.55, blue: 1, alpha: 1).setStroke()
            path.stroke()
            for st in stages where st.lat != 0 || st.lng != 0 {
                drawDot(at: project(st.lat, st.lng), type: st.type)
            }
        }
    }

    // MARK: Rendu PDF

    private static func render(_ items: [PdfItem], name: String) -> URL? {
        let pageRect = CGRect(x: 0, y: 0, width: 595, height: 842)
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)
        let normal: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 11)]
        let bold: [NSAttributedString.Key: Any] = [.font: UIFont.boldSystemFont(ofSize: 15)]
        let data = renderer.pdfData { ctx in
            ctx.beginPage()
            var y: CGFloat = 40
            for item in items {
                switch item {
                case .line(let text, let isBold):
                    if y > 790 {
                        ctx.beginPage()
                        y = 40
                    }
                    let h: CGFloat = isBold ? 22 : 15
                    (text as NSString).draw(in: CGRect(x: 40, y: y, width: 515, height: h), withAttributes: isBold ? bold : normal)
                    y += isBold ? 24 : 16
                case .image(let img, let h):
                    if y + h > 800 {
                        ctx.beginPage()
                        y = 40
                    }
                    img.draw(in: CGRect(x: 40, y: y, width: 515, height: h))
                    y += h + 12
                }
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

// MARK: Export Excel (.xlsx), s'ouvre dans Google Sheets

enum XCell {
    case text(String)
    case number(Double)
}

enum XlsxExporter {
    private static func r(_ v: Double, _ d: Int = 1) -> Double {
        let m = pow(10.0, Double(d))
        return (v * m).rounded() / m
    }

    private static func soc(_ v: Int?) -> XCell {
        if let v = v { return .number(Double(v)) }
        return .text("")
    }

    static func workbook(trips: [Trip], name: String) -> URL? {
        let done = trips.filter { !$0.isOngoing }.sorted { $0.startTime < $1.startTime }
        if done.isEmpty { return nil }
        let dayFmt = DateFormatter()
        dayFmt.dateFormat = "yyyy-MM-dd"

        // Feuille 1 : résumé par jour
        var daily: [[XCell]] = [headerRow(["Date", "Trajets", "Distance (km)", "Conduite (min)", "Recharge (min)",
                                            "Repas (min)", "Énergie (kWh)", "Carburant (L)", "Coût",
                                            "Recharges / pleins", "Vitesse moy. (km/h)", "Vitesse max (km/h)",
                                            "Dénivelé + (m)"])]
        for d in DayRecap.group(done).sorted(by: { $0.id < $1.id }) {
            daily.append([
                .text(dayFmt.string(from: d.id)), .number(Double(d.trips.count)),
                .number(r(d.distance / 1000.0)), .number(r(Double(d.driving) / 60.0, 0)),
                .number(r(Double(d.charging) / 60.0, 0)), .number(r(Double(d.meal) / 60.0, 0)),
                .number(r(d.kwh)), .number(r(d.fuelLiters)), .number(r(d.cost, 2)),
                .number(Double(d.chargeCount)), .number(r(d.avgSpeed)), .number(r(d.maxSpeed)),
                .number(r(d.gain, 0))
            ])
        }

        // Feuille 2 : trajets
        var tripRows: [[XCell]] = [headerRow(["Date", "Départ", "Arrivée", "Distance (km)", "Conduite (min)",
                                              "Recharge (min)", "Repas (min)", "Autre (min)", "Vitesse moy. (km/h)",
                                              "Vitesse max (km/h)", "Dénivelé + (m)", "SOC départ (%)",
                                              "SOC arrivée (%)", "Énergie (kWh)", "Carburant (L)", "Coût"])]
        for t in done {
            tripRows.append([
                .text(Fmt.dateTime(t.startTime)), .text(t.startPlace), .text(t.endPlace),
                .number(r(t.totalDistanceMeters / 1000.0)), .number(r(Double(t.drivingSeconds) / 60.0, 0)),
                .number(r(Double(t.chargingSeconds) / 60.0, 0)), .number(r(Double(t.mealSeconds) / 60.0, 0)),
                .number(r(Double(t.otherSeconds) / 60.0, 0)), .number(r(t.avgSpeedKmh)), .number(r(t.maxSpeedKmh)),
                .number(r(t.elevationGainMeters, 0)), soc(t.startSoc), soc(t.endSoc),
                .number(r(t.totalKwh)), .number(r(t.totalFuelLiters)), .number(r(t.totalCost, 2))
            ])
        }

        // Feuille 3 : étapes
        var stageRows: [[XCell]] = [headerRow(["Date", "Type", "Lieu", "Arrivée à", "Durée (min)",
                                               "Distance étape (km)", "Depuis recharge (km)", "Énergie (kWh)",
                                               "Carburant (L)", "Coût", "Réseau", "SOC début (%)", "SOC fin (%)",
                                               "Notes"])]
        for t in done {
            for s in t.stages {
                stageRows.append([
                    .text(Fmt.dateTime(t.startTime)), .text(s.type.label), .text(s.placeName),
                    .text(Fmt.dateTime(s.arrival)), .number(r(Double(s.durationSeconds) / 60.0, 0)),
                    .number(r(s.distanceFromPrevMeters / 1000.0)), .number(r(s.distanceSinceLastChargeMeters / 1000.0)),
                    .number(r(s.energyKwh)), .number(r(s.fuelLiters ?? 0)), .number(r(s.cost, 2)),
                    .text(s.network), soc(s.startSoc), soc(s.endSoc), .text(s.notes)
                ])
            }
        }

        let sheets: [(String, [[XCell]])] = [(tr("Résumés"), daily), (tr("Trajets"), tripRows), (tr("Étapes"), stageRows)]
        let data = build(sheets)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        do {
            try data.write(to: url)
            return url
        } catch {
            return nil
        }
    }

    private static func headerRow(_ titles: [String]) -> [XCell] {
        return titles.map { XCell.text("#H#" + tr($0)) }
    }

    private static func esc(_ s: String) -> String {
        return s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    private static func colName(_ index: Int) -> String {
        var n = index
        var s = ""
        repeat {
            s = String(Character(UnicodeScalar(UInt8(65 + n % 26)))) + s
            n = n / 26 - 1
        } while n >= 0
        return s
    }

    private static func sheetXML(_ rows: [[XCell]]) -> String {
        let colCount = rows.map { $0.count }.max() ?? 1
        var xml = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>"
        xml += "<worksheet xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\">"
        xml += "<cols><col min=\"1\" max=\"\(colCount)\" width=\"20\" customWidth=\"1\"/></cols><sheetData>"
        for (ri, row) in rows.enumerated() {
            xml += "<row r=\"\(ri + 1)\">"
            for (ci, cell) in row.enumerated() {
                let ref = "\(colName(ci))\(ri + 1)"
                switch cell {
                case .number(let v):
                    let value = v.isFinite ? v : 0
                    xml += "<c r=\"\(ref)\"><v>\(value)</v></c>"
                case .text(let t):
                    if t.isEmpty { continue }
                    if t.hasPrefix("#H#") {
                        xml += "<c r=\"\(ref)\" t=\"inlineStr\" s=\"1\"><is><t>\(esc(String(t.dropFirst(3))))</t></is></c>"
                    } else {
                        xml += "<c r=\"\(ref)\" t=\"inlineStr\"><is><t>\(esc(t))</t></is></c>"
                    }
                }
            }
            xml += "</row>"
        }
        xml += "</sheetData></worksheet>"
        return xml
    }

    private static func build(_ sheets: [(String, [[XCell]])]) -> Data {
        let head = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>"
        var files: [(String, Data)] = []

        var types = head + "<Types xmlns=\"http://schemas.openxmlformats.org/package/2006/content-types\">"
        types += "<Default Extension=\"rels\" ContentType=\"application/vnd.openxmlformats-package.relationships+xml\"/>"
        types += "<Default Extension=\"xml\" ContentType=\"application/xml\"/>"
        types += "<Override PartName=\"/xl/workbook.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml\"/>"
        types += "<Override PartName=\"/xl/styles.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml\"/>"
        for n in 1...sheets.count {
            types += "<Override PartName=\"/xl/worksheets/sheet\(n).xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml\"/>"
        }
        types += "</Types>"
        files.append(("[Content_Types].xml", Data(types.utf8)))

        let rels = head + "<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\"><Relationship Id=\"rId1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument\" Target=\"xl/workbook.xml\"/></Relationships>"
        files.append(("_rels/.rels", Data(rels.utf8)))

        var wb = head + "<workbook xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\" xmlns:r=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships\"><sheets>"
        var wbRels = head + "<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\">"
        for (i, sheet) in sheets.enumerated() {
            let n = i + 1
            wb += "<sheet name=\"\(esc(sheet.0))\" sheetId=\"\(n)\" r:id=\"rId\(n)\"/>"
            wbRels += "<Relationship Id=\"rId\(n)\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet\" Target=\"worksheets/sheet\(n).xml\"/>"
            files.append(("xl/worksheets/sheet\(n).xml", Data(sheetXML(sheet.1).utf8)))
        }
        wb += "</sheets></workbook>"
        wbRels += "<Relationship Id=\"rId\(sheets.count + 1)\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles\" Target=\"styles.xml\"/></Relationships>"
        files.append(("xl/workbook.xml", Data(wb.utf8)))
        files.append(("xl/_rels/workbook.xml.rels", Data(wbRels.utf8)))

        let styles = head + "<styleSheet xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\"><fonts count=\"2\"><font><sz val=\"11\"/><name val=\"Calibri\"/></font><font><b/><sz val=\"11\"/><name val=\"Calibri\"/></font></fonts><fills count=\"2\"><fill><patternFill patternType=\"none\"/></fill><fill><patternFill patternType=\"gray125\"/></fill></fills><borders count=\"1\"><border><left/><right/><top/><bottom/><diagonal/></border></borders><cellStyleXfs count=\"1\"><xf numFmtId=\"0\" fontId=\"0\" fillId=\"0\" borderId=\"0\"/></cellStyleXfs><cellXfs count=\"2\"><xf numFmtId=\"0\" fontId=\"0\" fillId=\"0\" borderId=\"0\" xfId=\"0\"/><xf numFmtId=\"0\" fontId=\"1\" fillId=\"0\" borderId=\"0\" xfId=\"0\" applyFont=\"1\"/></cellXfs><cellStyles count=\"1\"><cellStyle name=\"Normal\" xfId=\"0\" builtinId=\"0\"/></cellStyles></styleSheet>"
        files.append(("xl/styles.xml", Data(styles.utf8)))

        return zip(files)
    }

    // MARK: ZIP minimal (sans compression)

    private static let crcTable: [UInt32] = (0..<256).map { (i: Int) -> UInt32 in
        var c = UInt32(i)
        for _ in 0..<8 {
            c = (c & 1) != 0 ? (0xEDB88320 ^ (c >> 1)) : (c >> 1)
        }
        return c
    }

    private static func crc32(_ data: Data) -> UInt32 {
        var c: UInt32 = 0xFFFFFFFF
        for b in data {
            c = crcTable[Int((c ^ UInt32(b)) & 0xFF)] ^ (c >> 8)
        }
        return ~c
    }

    private static func le16(_ v: UInt16) -> Data {
        var x = v.littleEndian
        return withUnsafeBytes(of: &x) { Data($0) }
    }

    private static func le32(_ v: UInt32) -> Data {
        var x = v.littleEndian
        return withUnsafeBytes(of: &x) { Data($0) }
    }

    private static func zip(_ files: [(String, Data)]) -> Data {
        var out = Data()
        var central = Data()
        for (name, data) in files {
            let nameData = Data(name.utf8)
            let crc = crc32(data)
            let size = UInt32(data.count)
            let offset = UInt32(out.count)

            out.append(le32(0x04034b50))
            out.append(le16(20)); out.append(le16(0)); out.append(le16(0))
            out.append(le16(0)); out.append(le16(0x21))
            out.append(le32(crc)); out.append(le32(size)); out.append(le32(size))
            out.append(le16(UInt16(nameData.count))); out.append(le16(0))
            out.append(nameData)
            out.append(data)

            central.append(le32(0x02014b50))
            central.append(le16(20)); central.append(le16(20)); central.append(le16(0)); central.append(le16(0))
            central.append(le16(0)); central.append(le16(0x21))
            central.append(le32(crc)); central.append(le32(size)); central.append(le32(size))
            central.append(le16(UInt16(nameData.count)))
            central.append(le16(0)); central.append(le16(0)); central.append(le16(0)); central.append(le16(0))
            central.append(le32(0)); central.append(le32(offset))
            central.append(nameData)
        }
        let cdOffset = UInt32(out.count)
        out.append(central)
        out.append(le32(0x06054b50))
        out.append(le16(0)); out.append(le16(0))
        out.append(le16(UInt16(files.count))); out.append(le16(UInt16(files.count)))
        out.append(le32(UInt32(central.count))); out.append(le32(cdOffset))
        out.append(le16(0))
        return out
    }
}
