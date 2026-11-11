import SwiftUI

var copiedAlert: Alert {
    return Alert(title: Text(tr("Copié")),
                        message: Text(tr("Ouvre Google Sheets, appui long sur une cellule → Coller.")),
                 dismissButton: .default(Text(tr("OK"))))
}

struct HistoryView: View {
    @ObservedObject var store: TripStore
    @State private var share: ShareItem?
    @State private var copied = false

    var body: some View {
        NavigationView {
            ZStack {
                Theme.background.ignoresSafeArea()
                if store.trips.isEmpty {
                    Text(tr("Aucun trajet enregistré"))
                        .foregroundColor(Theme.textSecondary)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 10) {
                            ForEach(store.trips) { trip in
                                NavigationLink(destination: TripDetailView(store: store, tripId: trip.id)) {
                                    TripRow(trip: trip)
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                        }
                        .padding(16)
                    }
                }
            }
            .navigationTitle(tr("Historique"))
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button(tr("Exporter tout en CSV")) {
                            if let url = CsvExporter.allTripsCSV(store.trips) { share = ShareItem(url: url) }
                        }
                        Button(tr("Copier pour Google Sheets")) {
                            SheetsExport.copy(store.trips)
                            copied = true
                        }
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .disabled(store.trips.isEmpty)
                }
            }
        }
        .navigationViewStyle(StackNavigationViewStyle())
        .sheet(item: $share) { item in ShareSheet(url: item.url) }
        .alert(isPresented: $copied) { copiedAlert }
    }
}

struct TripRow: View {
    let trip: Trip

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(Fmt.day(trip.startTime))
                    .font(.system(size: 13))
                    .foregroundColor(Theme.textSecondary)
                Spacer()
                if trip.isOngoing {
                    Text(tr("● En cours"))
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(Theme.red)
                }
            }
            Text(route)
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(Theme.textPrimary)
            HStack(spacing: 14) {
                Label(Fmt.km(trip.totalDistanceMeters), systemImage: "map")
                Label(Fmt.human(durationSeconds), systemImage: "clock")
                Label(Fmt.speed(trip.avgSpeedKmh), systemImage: "speedometer")
            }
            .font(.system(size: 12))
            .foregroundColor(Theme.blue)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface)
        .cornerRadius(14)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.border, lineWidth: 1))
    }

    private var route: String {
        let end = trip.endPlace.isEmpty ? "…" : trip.endPlace
        return "\(trip.startPlace) → \(end)"
    }

    private var durationSeconds: Int {
        guard let end = trip.endTime else { return trip.drivingSeconds }
        return Int(end.timeIntervalSince(trip.startTime))
    }
}

enum DetailSheet: Identifiable {
    case share(ShareItem)
    case editTrip
    case editStage(UUID)

    var id: String {
        switch self {
        case .share(let item): return "s-\(item.id.uuidString)"
        case .editTrip: return "trip"
        case .editStage(let u): return "e-\(u.uuidString)"
        }
    }
}

struct TripDetailView: View {
    @ObservedObject var store: TripStore
    let tripId: UUID
    @Environment(\.presentationMode) var presentation
    @State private var sheet: DetailSheet?
    @State private var confirmDelete = false

    private var trip: Trip? { store.trips.first { $0.id == tripId } }

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            if let trip = trip {
                ScrollView {
                    VStack(spacing: 14) {
                        header(trip)
                        if trip.points.count >= 2 || !trip.stages.isEmpty {
                            RouteMapView(points: trip.points, stages: trip.stages)
                                .frame(height: 260)
                                .cornerRadius(14)
                        }
                        stats(trip)
                        if trip.points.filter({ $0.alt != 0 }).count >= 2 {
                            AltitudeProfileView(points: trip.points)
                        }
                        ForEach(trip.stages) { stage in
                            Button {
                                guard !trip.isOngoing else { return }
                                if stage.type == .departure || stage.type == .arrival {
                                    sheet = .editTrip
                                } else {
                                    sheet = .editStage(stage.id)
                                }
                            } label: {
                                StageRow(stage: stage)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                        Button {
                            confirmDelete = true
                        } label: {
                            Text(tr("Supprimer ce trajet"))
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(Theme.red)
                                .frame(maxWidth: .infinity)
                                .frame(height: 46)
                                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.red.opacity(0.5), lineWidth: 1))
                        }
                    }
                    .padding(16)
                }
            } else {
                Text(tr("Trajet introuvable")).foregroundColor(Theme.textSecondary)
            }
        }
        .navigationTitle(tr("Détails"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button(tr("Modifier le trajet")) { sheet = .editTrip }
                    Button(tr("Exporter en CSV")) {
                        if let trip = trip, let url = CsvExporter.tripCSV(trip) { sheet = .share(ShareItem(url: url)) }
                    }
                    Button(tr("Exporter en PDF (avec carte)")) {
                        if let trip = trip {
                            PdfExporter.tripPDF(trip) { url in
                                if let url = url { sheet = .share(ShareItem(url: url)) }
                            }
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(item: $sheet) { which in
            switch which {
            case .share(let item): ShareSheet(url: item.url)
            case .editTrip: TripEditSheet(store: store, tripId: tripId)
            case .editStage(let id): StageEditSheet(store: store, tripId: tripId, stageId: id)
            }
        }
        .alert(isPresented: $confirmDelete) {
            Alert(title: Text(tr("Supprimer ce trajet ?")),
                  message: Text(tr("Cette action est définitive.")),
                  primaryButton: .destructive(Text(tr("Supprimer"))) {
                      if let trip = trip { store.delete(trip) }
                      presentation.wrappedValue.dismiss()
                  },
                  secondaryButton: .cancel(Text(tr("Annuler"))))
        }
    }

    private func header(_ trip: Trip) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(trip.startPlace) → \(trip.endPlace.isEmpty ? "…" : trip.endPlace)")
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(Theme.textPrimary)
            Text(Fmt.dateTime(trip.startTime))
                .font(.system(size: 13))
                .foregroundColor(Theme.textSecondary)
            if !trip.isOngoing {
                Text(tr("Touchez une étape pour la modifier"))
                    .font(.system(size: 11))
                    .foregroundColor(Theme.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func stats(_ trip: Trip) -> some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                MetricCard(label: tr("Distance"), value: Fmt.km(trip.totalDistanceMeters))
                MetricCard(label: tr("Conduite"), value: Fmt.human(trip.drivingSeconds))
                MetricCard(label: tr("Vitesse moy."), value: Fmt.speed(trip.avgSpeedKmh))
            }
            HStack(spacing: 8) {
                MetricCard(label: tr("Vitesse max"), value: Fmt.speed(trip.maxSpeedKmh))
                MetricCard(label: tr("Recharge"), value: Fmt.human(trip.chargingSeconds))
                MetricCard(label: tr("Dénivelé +"), value: Fmt.meters(trip.elevationGainMeters))
            }
            if trip.totalKwh > 0 || trip.totalFuelLiters > 0 || trip.totalCost > 0 {
                HStack(spacing: 8) {
                    if trip.totalKwh > 0 {
                        MetricCard(label: tr("Énergie"), value: String(format: "%.1f kWh", trip.totalKwh))
                    }
                    if trip.totalFuelLiters > 0 {
                        MetricCard(label: tr("Carburant"), value: Fmt.fuel(trip.totalFuelLiters))
                        MetricCard(label: tr("Conso"), value: Fmt.consumption(liters: trip.totalFuelLiters, meters: trip.totalDistanceMeters))
                    }
                    MetricCard(label: tr("Coût"), value: String(format: "%.2f $", trip.totalCost))
                }
            }
            if trip.startSoc != nil || trip.endSoc != nil {
                HStack(spacing: 8) {
                    MetricCard(label: tr("Batterie départ"), value: trip.startSoc.map { "\($0) %" } ?? "–")
                    MetricCard(label: tr("Batterie arrivée"), value: trip.endSoc.map { "\($0) %" } ?? "–")
                }
            }
        }
    }
}

struct StageRow: View {
    let stage: Stage

    private var detailLine: String {
        var parts: [String] = []
        if stage.energyKwh > 0 { parts.append(String(format: "%.1f kWh", stage.energyKwh)) }
        if let f = stage.fuelLiters, f > 0 { parts.append(Fmt.fuel(f)) }
        if stage.cost > 0 { parts.append(String(format: "%.2f $", stage.cost)) }
        if !stage.network.isEmpty { parts.append(stage.network) }
        return parts.joined(separator: " • ")
    }

    private var socLine: String? {
        if stage.startSoc == nil && stage.endSoc == nil { return nil }
        let a = stage.startSoc.map { "\($0)" } ?? "–"
        let b = stage.endSoc.map { "\($0)" } ?? "–"
        return tr("Batterie :") + " \(a) % → \(b) %"
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: stage.type.icon)
                .foregroundColor(Theme.color(for: stage.type))
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(Theme.textPrimary)
                    .multilineTextAlignment(.leading)
                Text(Fmt.time(stage.arrival) + (stage.durationSeconds > 0 ? " • \(Fmt.human(stage.durationSeconds))" : ""))
                    .font(.system(size: 12))
                    .foregroundColor(Theme.textSecondary)
                if stage.type != .departure {
                    Text("+\(Fmt.km(stage.distanceFromPrevMeters)) " + tr("depuis l'étape précédente"))
                        .font(.system(size: 12))
                        .foregroundColor(Theme.textSecondary)
                }
                if !detailLine.isEmpty {
                    Text(detailLine)
                        .font(.system(size: 12))
                        .foregroundColor(Theme.green)
                        .multilineTextAlignment(.leading)
                }
                if let soc = socLine {
                    Text(soc)
                        .font(.system(size: 12))
                        .foregroundColor(Theme.blue)
                }
                if !stage.notes.isEmpty {
                    Text(stage.notes)
                        .font(.system(size: 12))
                        .foregroundColor(Theme.textSecondary)
                        .multilineTextAlignment(.leading)
                }
            }
            Spacer()
        }
        .padding(12)
        .background(Theme.surface)
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border, lineWidth: 1))
    }

    private var title: String {
        if stage.placeName.isEmpty { return stage.type.label }
        if stage.type == .border { return stage.placeName }
        return "\(stage.type.label) – \(stage.placeName)"
    }
}

struct StageEditSheet: View {
    @ObservedObject var store: TripStore
    let tripId: UUID
    let stageId: UUID
    @Environment(\.presentationMode) var presentation
    @AppStorage("fuelUnit") private var fuelUnit = "l"
    @State private var loaded = false
    @State private var type: StageType = .other
    @State private var place = ""
    @State private var cost = ""
    @State private var kwh = ""
    @State private var fuel = ""
    @State private var network = ""
    @State private var notes = ""
    @State private var startSoc = ""
    @State private var endSoc = ""
    @State private var confirmDelete = false

    private func load() {
        guard !loaded,
              let trip = store.trips.first(where: { $0.id == tripId }),
              let s = trip.stages.first(where: { $0.id == stageId }) else { return }
        loaded = true
        type = s.type
        place = s.placeName
        cost = s.cost > 0 ? String(format: "%.2f", s.cost) : ""
        kwh = s.energyKwh > 0 ? String(format: "%.1f", s.energyKwh) : ""
        if let f = s.fuelLiters, f > 0 { fuel = String(format: "%.1f", Fmt.litersToDisplay(f)) }
        network = s.network
        notes = s.notes
        startSoc = s.startSoc.map { "\($0)" } ?? ""
        endSoc = s.endSoc.map { "\($0)" } ?? ""
    }

    private func save() {
        let newFuel: Double? = type.isRefuel ? Fmt.displayToLiters(parseDouble(fuel)) : nil
        store.mutate(tripId) { trip in
            guard let i = trip.stages.firstIndex(where: { $0.id == stageId }) else { return }
            trip.stages[i].placeName = place.trimmingCharacters(in: .whitespaces)
            trip.stages[i].cost = parseDouble(cost)
            trip.stages[i].energyKwh = type.isCharging ? parseDouble(kwh) : 0
            trip.stages[i].fuelLiters = newFuel
            trip.stages[i].network = network
            trip.stages[i].notes = notes
            trip.stages[i].startSoc = parseSoc(startSoc)
            trip.stages[i].endSoc = parseSoc(endSoc)
        }
    }

    var body: some View {
        NavigationView {
            ZStack {
                Theme.background.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 14) {
                        LabeledField(label: tr("Lieu"), placeholder: tr(""), text: $place)
                        LabeledField(label: tr("Coût ($)"), placeholder: tr("0"), text: $cost, keyboard: .decimalPad)
                        if type.isCharging {
                            LabeledField(label: tr("Énergie (kWh)"), placeholder: tr("0"), text: $kwh, keyboard: .decimalPad)
                        }
                        if type.isRefuel {
                            LabeledField(label: fuelUnit == "gal" ? tr("Volume (gallons)") : tr("Volume (litres)"),
                                         placeholder: tr("0"), text: $fuel, keyboard: .decimalPad)
                        }
                        if type.isCharging || type.isRefuel {
                            LabeledField(label: type.isRefuel ? tr("Station / fournisseur") : tr("Réseau"),
                                         placeholder: tr(""), text: $network)
                        }
                        if type.isCharging {
                            LabeledField(label: tr("Batterie début (%)"), placeholder: tr(""), text: $startSoc, keyboard: .numberPad)
                            LabeledField(label: tr("Batterie fin (%)"), placeholder: tr(""), text: $endSoc, keyboard: .numberPad)
                        }
                        LabeledField(label: tr("Notes"), placeholder: tr(""), text: $notes)
                        Button {
                            save()
                            presentation.wrappedValue.dismiss()
                        } label: {
                            Text(tr("Enregistrer"))
                                .font(.system(size: 17, weight: .heavy))
                                .foregroundColor(Theme.background)
                                .frame(maxWidth: .infinity)
                                .frame(height: 54)
                                .background(Theme.green)
                                .cornerRadius(14)
                        }
                        Button {
                            confirmDelete = true
                        } label: {
                            Text(tr("Supprimer cette étape"))
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(Theme.red)
                                .frame(maxWidth: .infinity)
                                .frame(height: 46)
                                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.red.opacity(0.5), lineWidth: 1))
                        }
                    }
                    .padding(16)
                }
            }
            .onAppear { load() }
            .navigationTitle(type.label)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(tr("Annuler")) { presentation.wrappedValue.dismiss() }
                }
            }
            .alert(isPresented: $confirmDelete) {
                Alert(title: Text(tr("Supprimer cette étape ?")),
                      message: Text(tr("Cette action est définitive.")),
                      primaryButton: .destructive(Text(tr("Supprimer"))) {
                          store.mutate(tripId) { $0.stages.removeAll { $0.id == stageId } }
                          presentation.wrappedValue.dismiss()
                      },
                      secondaryButton: .cancel(Text(tr("Annuler"))))
            }
        }
        .preferredColorScheme(.dark)
    }
}

struct TripEditSheet: View {
    @ObservedObject var store: TripStore
    let tripId: UUID
    @Environment(\.presentationMode) var presentation
    @State private var loaded = false
    @State private var startPlace = ""
    @State private var endPlace = ""
    @State private var startSoc = ""
    @State private var endSoc = ""

    private func load() {
        guard !loaded, let t = store.trips.first(where: { $0.id == tripId }) else { return }
        loaded = true
        startPlace = t.startPlace
        endPlace = t.endPlace
        startSoc = t.startSoc.map { "\($0)" } ?? ""
        endSoc = t.endSoc.map { "\($0)" } ?? ""
    }

    private func save() {
        store.mutate(tripId) { t in
            t.startPlace = startPlace.trimmingCharacters(in: .whitespaces)
            t.endPlace = endPlace.trimmingCharacters(in: .whitespaces)
            t.startSoc = parseSoc(startSoc)
            t.endSoc = parseSoc(endSoc)
            if let i = t.stages.firstIndex(where: { $0.type == .departure }) {
                t.stages[i].placeName = t.startPlace
                t.stages[i].startSoc = t.startSoc
                t.stages[i].endSoc = t.startSoc
            }
            if let i = t.stages.lastIndex(where: { $0.type == .arrival }) {
                t.stages[i].placeName = t.endPlace
                t.stages[i].endSoc = t.endSoc
            }
        }
    }

    var body: some View {
        NavigationView {
            ZStack {
                Theme.background.ignoresSafeArea()
                VStack(spacing: 14) {
                    LabeledField(label: tr("Lieu de départ"), placeholder: tr(""), text: $startPlace)
                    LabeledField(label: tr("Lieu d'arrivée"), placeholder: tr(""), text: $endPlace)
                    LabeledField(label: tr("Batterie au départ (%)"), placeholder: tr(""), text: $startSoc, keyboard: .numberPad)
                    LabeledField(label: tr("Batterie à l'arrivée (%)"), placeholder: tr(""), text: $endSoc, keyboard: .numberPad)
                    Button {
                        save()
                        presentation.wrappedValue.dismiss()
                    } label: {
                        Text(tr("Enregistrer"))
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
            .onAppear { load() }
            .navigationTitle(tr("Modifier le trajet"))
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
