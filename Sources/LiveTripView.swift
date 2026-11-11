import SwiftUI

enum LiveSheet: Identifiable {
    case start, endStop, endTrip, settings
    var id: Int {
        switch self {
        case .start: return 0
        case .endStop: return 1
        case .endTrip: return 2
        case .settings: return 3
        }
    }
}

struct SpeedGauge: View {
    let speed: Double
    private let maxSpeed = 160.0

    var body: some View {
        let frac = min(max(speed / maxSpeed, 0), 1)
        ZStack {
            Circle()
                .trim(from: 0, to: 0.75)
                .stroke(Theme.card, style: StrokeStyle(lineWidth: 16, lineCap: .round))
                .rotationEffect(.degrees(135))
            Circle()
                .trim(from: 0, to: 0.75 * frac)
                .stroke(Theme.blue, style: StrokeStyle(lineWidth: 16, lineCap: .round))
                .rotationEffect(.degrees(135))
                .animation(.easeOut(duration: 0.3), value: frac)
            VStack(spacing: 0) {
                Text("\(Int(speed))")
                    .font(.system(size: 64, weight: .heavy, design: .rounded))
                    .foregroundColor(Theme.textPrimary)
                Text(tr("km/h"))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Theme.textSecondary)
            }
        }
        .frame(width: 210, height: 210)
    }
}

struct LiveTripView: View {
    @EnvironmentObject var t: TrackingManager
    @AppStorage("vehicle") private var vehicle = "ev"
    @State private var sheet: LiveSheet?

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
                    SpeedGauge(speed: t.speedKmh)
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
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.border, lineWidth: 1))
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
            bigButton("DÉMARRER LE TRAJET", icon: "play.fill", color: Theme.blue) {
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
            t.beginStop(type)
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
    @AppStorage("fuelUnit") private var fuelUnit = "l"
    @Environment(\.presentationMode) var presentation

    var body: some View {
        NavigationView {
            ZStack {
                Theme.background.ignoresSafeArea()
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(tr("Type de véhicule")).font(.caption).foregroundColor(Theme.textSecondary)
                        Picker("", selection: $vehicle) {
                            Text(tr("Électrique")).tag("ev")
                            Text(tr("Essence")).tag("ice")
                            Text(tr("Hybride")).tag("hybrid")
                        }
                        .pickerStyle(SegmentedPickerStyle())
                    }
                    if vehicle != "ev" {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(tr("Unité de carburant")).font(.caption).foregroundColor(Theme.textSecondary)
                            Picker("", selection: $fuelUnit) {
                                Text(tr("Litres (L)")).tag("l")
                                Text(tr("Gallons (gal)")).tag("gal")
                            }
                            .pickerStyle(SegmentedPickerStyle())
                        }
                    }
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
    @AppStorage("fuelUnit") private var fuelUnit = "l"
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
                            LabeledField(label: fuelUnit == "gal" ? tr("Volume (gallons)") : tr("Volume (litres)"),
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
