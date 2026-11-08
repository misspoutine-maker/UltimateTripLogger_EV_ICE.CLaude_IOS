import SwiftUI

enum LiveSheet: Identifiable {
    case start, endStop, endTrip
    var id: Int {
        switch self {
        case .start: return 0
        case .endStop: return 1
        case .endTrip: return 2
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
                Text("km/h")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Theme.textSecondary)
            }
        }
        .frame(width: 210, height: 210)
    }
}

struct LiveTripView: View {
    @EnvironmentObject var t: TrackingManager
    @State private var sheet: LiveSheet?

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 14) {
                    locationBanner
                    SpeedGauge(speed: t.speedKmh)
                    metrics
                    actions
                }
                .padding(16)
            }
        }
        .sheet(item: $sheet) { which in
            switch which {
            case .start: StartSheet().environmentObject(t)
            case .endStop: EndStopSheet().environmentObject(t)
            case .endTrip: EndTripSheet().environmentObject(t)
            }
        }
    }

    private var locationBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "location.fill").foregroundColor(Theme.blue)
            VStack(alignment: .leading, spacing: 2) {
                Text(t.city)
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
                Text("● REC")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(Theme.red)
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
                MetricCard(label: "Vitesse moy.", value: Fmt.speed(t.avgSpeedKmh))
                MetricCard(label: "Distance", value: Fmt.km(t.distanceMeters))
                MetricCard(label: "Durée", value: Fmt.hms(t.tripSeconds))
            }
            if t.altitude != 0 || t.elevationGain > 0 {
                HStack(spacing: 8) {
                    MetricCard(label: "Altitude", value: Fmt.meters(t.altitude))
                    MetricCard(label: "Dénivelé +", value: Fmt.meters(t.elevationGain))
                }
            }
            if t.isTracking {
                HStack {
                    Image(systemName: "bolt.fill").foregroundColor(Theme.blue)
                    Text("Depuis la dernière recharge")
                        .font(.system(size: 12))
                        .foregroundColor(Theme.textSecondary)
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
                Text("\(stop.label) en cours")
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
                HStack(spacing: 10) {
                    stopButton(.charging)
                    stopButton(.chargingMeal)
                }
                HStack(spacing: 10) {
                    stopButton(.meal)
                    stopButton(.other)
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
                Text(title).font(.system(size: 17, weight: .heavy))
            }
            .foregroundColor(Theme.background)
            .frame(maxWidth: .infinity)
            .frame(height: 60)
            .background(color)
            .cornerRadius(16)
        }
    }
}

struct StartSheet: View {
    @EnvironmentObject var t: TrackingManager
    @Environment(\.presentationMode) var presentation
    @State private var place = ""
    @State private var soc = ""

    var body: some View {
        NavigationView {
            ZStack {
                Theme.background.ignoresSafeArea()
                VStack(spacing: 16) {
                    LabeledField(label: "Lieu de départ (optionnel)", placeholder: t.city, text: $place)
                    LabeledField(label: "Batterie au départ en % (optionnel)", placeholder: "ex. 90", text: $soc, keyboard: .numberPad)
                    Button {
                        t.startTrip(place: place.trimmingCharacters(in: .whitespaces), soc: parseSoc(soc))
                        presentation.wrappedValue.dismiss()
                    } label: {
                        Text("Démarrer")
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
            .navigationTitle("Nouveau trajet")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { presentation.wrappedValue.dismiss() }
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
    @State private var cost = ""
    @State private var network = ""
    @State private var startSoc = ""
    @State private var endSoc = ""
    @State private var notes = ""

    private var isCharging: Bool { t.activeStop?.isCharging ?? false }

    var body: some View {
        NavigationView {
            ZStack {
                Theme.background.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 14) {
                        LabeledField(label: "Lieu", placeholder: t.city, text: $place)
                        if isCharging {
                            LabeledField(label: "Énergie (kWh)", placeholder: "0", text: $kwh, keyboard: .decimalPad)
                            LabeledField(label: "Coût ($)", placeholder: "0", text: $cost, keyboard: .decimalPad)
                            LabeledField(label: "Réseau", placeholder: "Tesla, IONNA, Electrify America…", text: $network)
                            LabeledField(label: "Batterie début (%)", placeholder: "", text: $startSoc, keyboard: .numberPad)
                            LabeledField(label: "Batterie fin (%)", placeholder: "", text: $endSoc, keyboard: .numberPad)
                        }
                        LabeledField(label: "Notes", placeholder: "", text: $notes)
                        Button {
                            t.finishStop(place: place.trimmingCharacters(in: .whitespaces),
                                         kwh: parseDouble(kwh), cost: parseDouble(cost),
                                         network: network, notes: notes,
                                         startSoc: parseSoc(startSoc), endSoc: parseSoc(endSoc))
                            presentation.wrappedValue.dismiss()
                        } label: {
                            Text("Enregistrer l'arrêt")
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
            .navigationTitle(t.activeStop?.label ?? "Arrêt")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { presentation.wrappedValue.dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

struct EndTripSheet: View {
    @EnvironmentObject var t: TrackingManager
    @Environment(\.presentationMode) var presentation
    @State private var soc = ""

    var body: some View {
        NavigationView {
            ZStack {
                Theme.background.ignoresSafeArea()
                VStack(spacing: 16) {
                    Text("\(Fmt.km(t.distanceMeters)) • \(Fmt.human(t.tripSeconds))")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(Theme.textPrimary)
                    LabeledField(label: "Batterie à l'arrivée en % (optionnel)", placeholder: "ex. 35", text: $soc, keyboard: .numberPad)
                    Button {
                        t.endTrip(endSoc: parseSoc(soc))
                        presentation.wrappedValue.dismiss()
                    } label: {
                        Text("Terminer et enregistrer")
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
            .navigationTitle("Fin du trajet")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { presentation.wrappedValue.dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}
