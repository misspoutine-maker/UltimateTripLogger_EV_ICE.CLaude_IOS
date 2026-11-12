import SwiftUI

enum LiveSheet: Identifiable {
    case start, endStop, endTrip, settings, stopSoc
    var id: Int {
        switch self {
        case .start: return 0
        case .endStop: return 1
        case .endTrip: return 2
        case .settings: return 3
        case .stopSoc: return 4
        }
    }
}

struct SpeedGauge: View {
    let speed: Double
    let maxSpeed: Double
    let unit: String
    let color: Color
    var size: CGFloat = 165

    var body: some View {
        let frac = min(max(speed / maxSpeed, 0), 1)
        ZStack {
            Circle()
                .trim(from: 0, to: 0.75)
                .stroke(Theme.card, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                .rotationEffect(.degrees(135))
            Circle()
                .trim(from: 0, to: 0.75 * frac)
                .stroke(color, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                .rotationEffect(.degrees(135))
                .animation(.easeOut(duration: 0.3), value: frac)
            VStack(spacing: 0) {
                Text("\(Int(speed))")
                    .font(.system(size: 46, weight: .heavy, design: .rounded))
                    .foregroundColor(Theme.textPrimary)
                Text(unit)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Theme.textSecondary)
            }
        }
        .frame(width: size, height: size)
    }
}

struct LiveTripView: View {
    @EnvironmentObject var t: TrackingManager
    @AppStorage("vehicle") private var vehicle = "ev"
    @AppStorage("units") private var units = "metric"
    @State private var sheet: LiveSheet?
    @State private var pendingStop: StageType = .charging

    private var modeColor: Color { return Theme.mode(vehicle) }

    private var cityText: String {
        return t.city == TrackingManager.placeholderCity ? tr("Détection GPS…") : t.city
    }

    private var stopTypes: [StageType] {
        switch vehicle {
        case "ice": return [.refuel, .meal, .other]
        case "hybrid": return [.charging, .refuel, .chargingMeal, .meal, .other]
        default: return [.charging, .chargingMeal, .meal, .other]
        }
    }

    private var sinceLabel: String {
        switch vehicle {
        case "ice": return "Depuis le dernier plein"
        case "hybrid": return "Depuis la dernière recharge / le dernier plein"
        default: return "Depuis la dernière recharge"
        }
    }

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 14) {
                    locationBanner
                    HStack(spacing: 8) {
                        SpeedGauge(speed: t.speedKmh, maxSpeed: 160, unit: "km/h", color: modeColor)
                        SpeedGauge(speed: t.speedKmh * 0.621371, maxSpeed: 100, unit: "mph", color: Theme.gold)
                    }
                    metrics
                    actions
                    Text(AppInfo.versionString)
                        .font(.system(size: 11))
                        .foregroundColor(Theme.textSecondary)
                        .padding(.top, 6)
                }
                .padding(16)
            }
        }
        .sheet(item: $sheet) { which in
            switch which {
            case .start: StartSheet().environmentObject(t)
            case .endStop: EndStopSheet().environmentObject(t)
            case .endTrip: EndTripSheet().environmentObject(t)
            case .settings: SettingsSheet()
            case .stopSoc: StopSocSheet(type: pendingStop).environmentObject(t)
            }
        }
    }

    private var locationBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "location.fill").foregroundColor(Theme.blue)
            VStack(alignment: .leading, spacing: 2) {
                Text(cityText)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(Theme.textPrimary)
                if !t.address.isEmpty {
                    Text(t.address)
                        .font(.system(size: 12))
                        .foregroundColor(Theme.textSecondary)
                        .lineLimit(2)
                }
            }
            Spacer()
            if t.isTracking {
                Text(tr("● REC"))
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(Theme.red)
            }
            ModeBadge(mode: vehicle)
            Button {
                units = (units == "imperial") ? "metric" : "imperial"
            } label: {
                Text(units == "imperial" ? "mi" : "km")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(Theme.textPrimary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.border, lineWidth: 1))
            }
            Button {
                sheet = .settings
            } label: {
                Image(systemName: "gearshape.fill")
                    .foregroundColor(Theme.textSecondary)
                    .padding(6)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .background(Theme.surface)
        .cornerRadius(14)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(modeColor.opacity(0.7), lineWidth: 1.5))
    }

    private var metrics: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                MetricCard(label: tr("Vitesse moy."), value: Fmt.speed(t.avgSpeedKmh))
                MetricCard(label: tr("Distance"), value: Fmt.km(t.distanceMeters))
                MetricCard(label: tr("Durée"), value: Fmt.hms(t.tripSeconds))
            }
            if t.altitude != 0 || t.elevationGain > 0 {
                HStack(spacing: 8) {
                    MetricCard(label: tr("Altitude"), value: Fmt.meters(t.altitude))
                    MetricCard(label: tr("Dénivelé +"), value: Fmt.meters(t.elevationGain))
                }
            }
            if t.isTracking {
                HStack {
                    Image(systemName: vehicle == "ice" ? "fuelpump.fill" : "bolt.fill").foregroundColor(Theme.blue)
                    Text(tr(sinceLabel))
                        .font(.system(size: 12))
                        .foregroundColor(Theme.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Spacer()
                    Text(Fmt.km(t.sinceChargeMeters))
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(Theme.textPrimary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Theme.surface)
                .cornerRadius(12)
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border, lineWidth: 1))
            }
        }
    }

    @ViewBuilder
    private var actions: some View {
        if !t.isTracking {
            bigButton("DÉMARRER LE TRAJET", icon: "play.fill", color: modeColor) {
                sheet = .start
            }
        } else if let stop = t.activeStop {
            VStack(spacing: 10) {
                Text(stop.label + " " + tr("en cours"))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(Theme.color(for: stop))
                Text(Fmt.hms(t.activeStopSeconds))
                    .font(.system(size: 40, weight: .heavy, design: .rounded))
                    .foregroundColor(Theme.textPrimary)
                bigButton("TERMINER L'ARRÊT", icon: "stop.fill", color: Theme.color(for: stop)) {
                    sheet = .endStop
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity)
            .background(Theme.surface)
            .cornerRadius(14)
        } else {
            VStack(spacing: 10) {
                let types = stopTypes
                let rows = stride(from: 0, to: types.count, by: 2).map { Array(types[$0 ..< min($0 + 2, types.count)]) }
                ForEach(0..<rows.count, id: \.self) { i in
                    HStack(spacing: 10) {
                        ForEach(rows[i], id: \.self) { type in
                            stopButton(type)
                        }
                    }
                }
                bigButton("TERMINER LE TRAJET", icon: "flag.checkered", color: Theme.red) {
                    sheet = .endTrip
                }
            }
        }
    }

    private func stopButton(_ type: StageType) -> some View {
        Button {
            if type.isCharging {
                pendingStop = type
                sheet = .stopSoc
            } else {
                t.beginStop(type)
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: type.icon)
                Text(type.label)
                    .font(.system(size: 14, weight: .semibold))
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
            }
            .foregroundColor(Theme.color(for: type))
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(Theme.surface)
            .cornerRadius(14)
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.color(for: type).opacity(0.5), lineWidth: 1))
        }
    }

    private func bigButton(_ title: String, icon: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                Text(tr(title)).font(.system(size: 17, weight: .heavy))
            }
            .foregroundColor(Theme.background)
            .frame(maxWidth: .infinity)
            .frame(height: 60)
            .background(color)
            .cornerRadius(16)
        }
    }
}

struct SettingsSheet: View {
    @AppStorage("lang") private var lang = "auto"
    @AppStorage("vehicle") private var vehicle = "ev"
    @AppStorage("units") private var units = "metric"
    @AppStorage("mailTo") private var mailTo = ""
    @Environment(\.presentationMode) var presentation

    var body: some View {
        NavigationView {
            ZStack {
                Theme.background.ignoresSafeArea()
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(tr("Type de véhicule")).font(.caption).foregroundColor(Theme.textSecondary)
                        Picker("", selection: $vehicle) {
                            Text(tr("EV")).tag("ev")
                            Text(tr("ICE")).tag("ice")
                            Text(tr("PHEV")).tag("hybrid")
                        }
                        .pickerStyle(SegmentedPickerStyle())
                        HStack(spacing: 14) {
                            Text(tr("● EV")).foregroundColor(Theme.blue)
                            Text(tr("● ICE")).foregroundColor(Theme.red)
                            Text(tr("● PHEV")).foregroundColor(Theme.green)
                        }
                        .font(.system(size: 12, weight: .semibold))
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text(tr("Unités")).font(.caption).foregroundColor(Theme.textSecondary)
                        Picker("", selection: $units) {
                            Text(tr("Métrique (km, L)")).tag("metric")
                            Text(tr("Impérial (mi, gal)")).tag("imperial")
                        }
                        .pickerStyle(SegmentedPickerStyle())
                    }
                    LabeledField(label: tr("Adresse e-mail par défaut (envoi du CSV)"), placeholder: "nom@exemple.com", text: $mailTo, keyboard: .emailAddress)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(tr("Langue")).font(.caption).foregroundColor(Theme.textSecondary)
                        Picker("", selection: $lang) {
                            Text(tr("Auto")).tag("auto")
                            Text(tr("Français")).tag("fr")
                            Text(tr("English")).tag("en")
                        }
                        .pickerStyle(SegmentedPickerStyle())
                    }
                    Spacer()
                    Text(AppInfo.versionString)
                        .font(.system(size: 12))
                        .foregroundColor(Theme.textSecondary)
                        .frame(maxWidth: .infinity)
                }
                .padding(16)
            }
            .navigationTitle(tr("Réglages"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(tr("OK")) { presentation.wrappedValue.dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

struct StartSheet: View {
    @EnvironmentObject var t: TrackingManager
    @Environment(\.presentationMode) var presentation
    @State private var place = ""
    @State private var soc = ""
    @AppStorage("vehicle") private var vehicle = "ev"

    var body: some View {
        NavigationView {
            ZStack {
                Theme.background.ignoresSafeArea()
                VStack(spacing: 16) {
                    LabeledField(label: tr("Lieu de départ (optionnel)"), placeholder: t.city == TrackingManager.placeholderCity ? tr("Détection GPS…") : t.city, text: $place)
                    if vehicle != "ice" {
                        LabeledField(label: tr("Batterie au départ en % (optionnel)"), placeholder: tr("ex. 90"), text: $soc, keyboard: .numberPad)
                    }
                    Button {
                        t.startTrip(place: place.trimmingCharacters(in: .whitespaces), soc: parseSoc(soc))
                        presentation.wrappedValue.dismiss()
                    } label: {
                        Text(tr("Démarrer"))
                            .font(.system(size: 17, weight: .heavy))
                            .foregroundColor(Theme.background)
                            .frame(maxWidth: .infinity)
                            .frame(height: 54)
                            .background(Theme.blue)
                            .cornerRadius(14)
                    }
                    Spacer()
                }
                .padding(16)
            }
            .navigationTitle(tr("Nouveau trajet"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(tr("Annuler")) { presentation.wrappedValue.dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

struct EndStopSheet: View {
    @EnvironmentObject var t: TrackingManager
    @Environment(\.presentationMode) var presentation
    @State private var place = ""
    @State private var kwh = ""
    @State private var fuel = ""
    @State private var cost = ""
    @State private var network = ""
    @State private var startSoc = ""
    @State private var endSoc = ""
    @State private var notes = ""
    @State private var pois: [Poi] = []

    private var isCharging: Bool { t.activeStop?.isCharging ?? false }
    private var isRefuel: Bool { t.activeStop?.isRefuel ?? false }

    private var placeholderPlace: String {
        return t.city == TrackingManager.placeholderCity ? tr("Détection GPS…") : t.city
    }

    private var poiList: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(tr("À proximité"))
                .font(.caption)
                .foregroundColor(Theme.textSecondary)
            ForEach(pois) { poi in
                Button {
                    place = poi.name
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(poi.name)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(Theme.textPrimary)
                            Text(tr(poi.category) + " • " + Fmt.meters(poi.distance))
                                .font(.system(size: 11))
                                .foregroundColor(Theme.textSecondary)
                        }
                        Spacer()
                        if place == poi.name {
                            Image(systemName: "checkmark.circle.fill").foregroundColor(Theme.green)
                        }
                    }
                    .padding(10)
                    .background(Theme.surface)
                    .cornerRadius(10)
                }
            }
        }
    }

    var body: some View {
        NavigationView {
            ZStack {
                Theme.background.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 14) {
                        LabeledField(label: tr("Lieu"), placeholder: placeholderPlace, text: $place)
                        if !pois.isEmpty { poiList }
                        LabeledField(label: tr("Coût ($)"), placeholder: tr("0"), text: $cost, keyboard: .decimalPad)
                        if isCharging {
                            LabeledField(label: tr("Énergie (kWh)"), placeholder: tr("0"), text: $kwh, keyboard: .decimalPad)
                        }
                        if isRefuel {
                            LabeledField(label: Fmt.isImperial ? tr("Volume (gallons)") : tr("Volume (litres)"),
                                         placeholder: tr("0"), text: $fuel, keyboard: .decimalPad)
                        }
                        if isCharging || isRefuel {
                            LabeledField(label: isRefuel ? tr("Station / fournisseur") : tr("Réseau"),
                                         placeholder: isRefuel ? "Shell, Petro-Canada…" : "Tesla, IONNA, Electrify America…",
                                         text: $network)
                        }
                        if isCharging {
                            LabeledField(label: tr("Batterie début (%)"), placeholder: tr(""), text: $startSoc, keyboard: .numberPad)
                            LabeledField(label: tr("Batterie fin (%)"), placeholder: tr(""), text: $endSoc, keyboard: .numberPad)
                        }
                        LabeledField(label: tr("Notes"), placeholder: tr(""), text: $notes)
                        Button {
                            t.finishStop(place: place.trimmingCharacters(in: .whitespaces),
                                         kwh: parseDouble(kwh), cost: parseDouble(cost),
                                         network: network, notes: notes,
                                         startSoc: parseSoc(startSoc), endSoc: parseSoc(endSoc),
                                         fuelLiters: isRefuel ? Fmt.displayToLiters(parseDouble(fuel)) : nil)
                            presentation.wrappedValue.dismiss()
                        } label: {
                            Text(tr("Enregistrer l'arrêt"))
                                .font(.system(size: 17, weight: .heavy))
                                .foregroundColor(Theme.background)
                                .frame(maxWidth: .infinity)
                                .frame(height: 54)
                                .background(Theme.green)
                                .cornerRadius(14)
                        }
                    }
                    .padding(16)
                }
            }
            .onAppear {
                startSoc = t.activeStopStartSoc.map { "\($0)" } ?? ""
                let c = t.currentCoordinate
                PoiFinder.find(lat: c.0, lng: c.1, type: t.activeStop) { pois = $0 }
            }
            .navigationTitle(t.activeStop?.label ?? tr("Arrêt"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(tr("Annuler")) { presentation.wrappedValue.dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

struct EndTripSheet: View {
    @EnvironmentObject var t: TrackingManager
    @Environment(\.presentationMode) var presentation
    @AppStorage("vehicle") private var vehicle = "ev"
    @State private var soc = ""

    var body: some View {
        NavigationView {
            ZStack {
                Theme.background.ignoresSafeArea()
                VStack(spacing: 16) {
                    Text("\(Fmt.km(t.distanceMeters)) • \(Fmt.human(t.tripSeconds))")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(Theme.textPrimary)
                    if vehicle != "ice" {
                        LabeledField(label: tr("Batterie à l'arrivée en % (optionnel)"), placeholder: tr("ex. 35"), text: $soc, keyboard: .numberPad)
                    }
                    Button {
                        t.endTrip(endSoc: parseSoc(soc))
                        presentation.wrappedValue.dismiss()
                    } label: {
                        Text(tr("Terminer et enregistrer"))
                            .font(.system(size: 17, weight: .heavy))
                            .foregroundColor(Theme.background)
                            .frame(maxWidth: .infinity)
                            .frame(height: 54)
                            .background(Theme.red)
                            .cornerRadius(14)
                    }
                    Spacer()
                }
                .padding(16)
            }
            .navigationTitle(tr("Fin du trajet"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(tr("Annuler")) { presentation.wrappedValue.dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

struct StopSocSheet: View {
    let type: StageType
    @EnvironmentObject var t: TrackingManager
    @Environment(\.presentationMode) var presentation
    @State private var soc = ""

    var body: some View {
        NavigationView {
            ZStack {
                Theme.background.ignoresSafeArea()
                VStack(spacing: 16) {
                    Text(type.label)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(Theme.color(for: type))
                    LabeledField(label: tr("Batterie actuelle (%)"), placeholder: "ex. 20", text: $soc, keyboard: .numberPad)
                    Button {
                        t.beginStop(type, startSoc: parseSoc(soc))
                        presentation.wrappedValue.dismiss()
                    } label: {
                        Text(tr("Démarrer l'arrêt"))
                            .font(.system(size: 17, weight: .heavy))
                            .foregroundColor(Theme.background)
                            .frame(maxWidth: .infinity)
                            .frame(height: 54)
                            .background(Theme.color(for: type))
                            .cornerRadius(14)
                    }
                    Button {
                        t.beginStop(type, startSoc: nil)
                        presentation.wrappedValue.dismiss()
                    } label: {
                        Text(tr("Passer"))
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(Theme.textSecondary)
                    }
                    Spacer()
                }
                .padding(16)
            }
            .navigationTitle(tr("Début de l'arrêt"))
            .navigationBarTitleDisplayMode(.inline)
        }
        .preferredColorScheme(.dark)
    }
}
