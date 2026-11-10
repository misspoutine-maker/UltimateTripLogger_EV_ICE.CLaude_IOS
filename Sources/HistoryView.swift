import SwiftUI

struct HistoryView: View {
    @ObservedObject var store: TripStore
    @State private var share: ShareItem?

    var body: some View {
        NavigationView {
            ZStack {
                Theme.background.ignoresSafeArea()
                if store.trips.isEmpty {
                    Text("Aucun trajet enregistré")
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
            .navigationTitle("Historique")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        if let url = CsvExporter.allTripsCSV(store.trips) { share = ShareItem(url: url) }
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .disabled(store.trips.isEmpty)
                }
            }
        }
        .navigationViewStyle(StackNavigationViewStyle())
        .sheet(item: $share) { item in ShareSheet(url: item.url) }
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
                    Text("● En cours")
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

struct TripDetailView: View {
    @ObservedObject var store: TripStore
    let tripId: UUID
    @Environment(\.presentationMode) var presentation
    @State private var share: ShareItem?
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
                            StageRow(stage: stage)
                        }
                        Button {
                            confirmDelete = true
                        } label: {
                            Text("Supprimer ce trajet")
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
                Text("Trajet introuvable").foregroundColor(Theme.textSecondary)
            }
        }
        .navigationTitle("Détails")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button("Exporter en CSV") {
                        if let trip = trip, let url = CsvExporter.tripCSV(trip) { share = ShareItem(url: url) }
                    }
                    Button("Exporter en PDF") {
                        if let trip = trip, let url = PdfExporter.tripPDF(trip) { share = ShareItem(url: url) }
                    }
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
            }
        }
        .sheet(item: $share) { item in ShareSheet(url: item.url) }
        .alert(isPresented: $confirmDelete) {
            Alert(title: Text("Supprimer ce trajet ?"),
                  message: Text("Cette action est définitive."),
                  primaryButton: .destructive(Text("Supprimer")) {
                      if let trip = trip { store.delete(trip) }
                      presentation.wrappedValue.dismiss()
                  },
                  secondaryButton: .cancel(Text("Annuler")))
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
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func stats(_ trip: Trip) -> some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                MetricCard(label: "Distance", value: Fmt.km(trip.totalDistanceMeters))
                MetricCard(label: "Conduite", value: Fmt.human(trip.drivingSeconds))
                MetricCard(label: "Vitesse moy.", value: Fmt.speed(trip.avgSpeedKmh))
            }
            HStack(spacing: 8) {
                MetricCard(label: "Vitesse max", value: Fmt.speed(trip.maxSpeedKmh))
                MetricCard(label: "Recharge", value: Fmt.human(trip.chargingSeconds))
                MetricCard(label: "Dénivelé +", value: Fmt.meters(trip.elevationGainMeters))
            }
            if trip.startSoc != nil || trip.endSoc != nil {
                HStack(spacing: 8) {
                    MetricCard(label: "Batterie départ", value: trip.startSoc.map { "\($0) %" } ?? "–")
                    MetricCard(label: "Batterie arrivée", value: trip.endSoc.map { "\($0) %" } ?? "–")
                }
            }
        }
    }
}

struct StageRow: View {
    let stage: Stage

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: stage.type.icon)
                .foregroundColor(Theme.color(for: stage.type))
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(Theme.textPrimary)
                Text(Fmt.time(stage.arrival) + (stage.durationSeconds > 0 ? " • \(Fmt.human(stage.durationSeconds))" : ""))
                    .font(.system(size: 12))
                    .foregroundColor(Theme.textSecondary)
                if stage.type != .departure {
                    Text("+\(Fmt.km(stage.distanceFromPrevMeters)) depuis l'étape précédente")
                        .font(.system(size: 12))
                        .foregroundColor(Theme.textSecondary)
                }
                if stage.energyKwh > 0 || stage.cost > 0 {
                    Text(String(format: "%.1f kWh • %.2f $", stage.energyKwh, stage.cost) +
                         (stage.network.isEmpty ? "" : " • \(stage.network)"))
                        .font(.system(size: 12))
                        .foregroundColor(Theme.green)
                }
                if stage.startSoc != nil || stage.endSoc != nil {
                    let a = stage.startSoc.map { "\($0)" } ?? "–"
                    let b = stage.endSoc.map { "\($0)" } ?? "–"
                    Text("Batterie : \(a) % → \(b) %")
                        .font(.system(size: 12))
                        .foregroundColor(Theme.blue)
                }
                if !stage.notes.isEmpty {
                    Text(stage.notes)
                        .font(.system(size: 12))
                        .foregroundColor(Theme.textSecondary)
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
