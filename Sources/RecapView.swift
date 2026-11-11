import SwiftUI

struct DayRecap: Identifiable {
    let id: Date
    let trips: [Trip]

    var distance: Double { trips.reduce(0) { $0 + $1.totalDistanceMeters } }
    var driving: Int { trips.reduce(0) { $0 + $1.drivingSeconds } }
    var charging: Int { trips.reduce(0) { $0 + $1.chargingSeconds } }
    var meal: Int { trips.reduce(0) { $0 + $1.mealSeconds } }
    var kwh: Double { trips.flatMap { $0.stages }.reduce(0) { $0 + $1.energyKwh } }
    var cost: Double { trips.flatMap { $0.stages }.reduce(0) { $0 + $1.cost } }
    var chargeCount: Int { trips.flatMap { $0.stages }.filter { $0.type.isCharging }.count }
    var maxSpeed: Double { trips.map { $0.maxSpeedKmh }.max() ?? 0 }
    var avgSpeed: Double {
        let h = Double(driving) / 3600.0
        return h > 0 ? (distance / 1000.0) / h : 0
    }
    var gain: Double { trips.reduce(0) { $0 + $1.elevationGainMeters } }
    var kwhPer100: Double { distance > 0 ? kwh / (distance / 1000.0) * 100.0 : 0 }
}

struct RecapView: View {
    @ObservedObject var store: TripStore

    private var days: [DayRecap] {
        let cal = Calendar.current
        let done = store.trips.filter { !$0.isOngoing }
        let grouped = Dictionary(grouping: done) { cal.startOfDay(for: $0.startTime) }
        return grouped.map { DayRecap(id: $0.key, trips: $0.value.sorted { $0.startTime < $1.startTime }) }
            .sorted { $0.id > $1.id }
    }

    var body: some View {
        NavigationView {
            ZStack {
                Theme.background.ignoresSafeArea()
                if days.isEmpty {
                    Text("Aucun récap disponible")
                        .foregroundColor(Theme.textSecondary)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 10) {
                            totalsCard
                            ForEach(days) { day in
                                NavigationLink(destination: DayDetailView(store: store, day: day)) {
                                    DayCard(day: day)
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                        }
                        .padding(16)
                    }
                }
            }
            .navigationTitle("Récap")
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }

    private var totalsCard: some View {
        let all = DayRecap(id: Date(), trips: days.flatMap { $0.trips })
        return VStack(spacing: 8) {
            Text("Total • \(days.count) jour(s)")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Theme.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 8) {
                MetricCard(label: "Distance", value: Fmt.km(all.distance))
                MetricCard(label: "Conduite", value: Fmt.human(all.driving))
                MetricCard(label: "Énergie", value: String(format: "%.0f kWh", all.kwh))
            }
            HStack(spacing: 8) {
                MetricCard(label: "Coût total", value: String(format: "%.2f $", all.cost))
                MetricCard(label: "kWh/100 km", value: String(format: "%.1f", all.kwhPer100))
                MetricCard(label: "Recharges", value: "\(all.chargeCount)")
            }
        }
    }
}

struct DayCard: View {
    let day: DayRecap

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(Fmt.day(day.id))
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(Theme.textPrimary)
                Spacer()
                Text("\(day.trips.count) trajet(s)")
                    .font(.system(size: 12))
                    .foregroundColor(Theme.textSecondary)
            }
            HStack(spacing: 14) {
                Label(Fmt.km(day.distance), systemImage: "map")
                Label(Fmt.human(day.driving), systemImage: "clock")
                if day.chargeCount > 0 {
                    Label("\(day.chargeCount)", systemImage: "bolt.fill")
                }
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
}

struct DayDetailView: View {
    @ObservedObject var store: TripStore
    let day: DayRecap
    @State private var share: ShareItem?
    @State private var copied = false

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 10) {
                    HStack(spacing: 8) {
                        MetricCard(label: "Distance", value: Fmt.km(day.distance))
                        MetricCard(label: "Conduite", value: Fmt.human(day.driving))
                        MetricCard(label: "Vitesse moy.", value: Fmt.speed(day.avgSpeed))
                    }
                    HStack(spacing: 8) {
                        MetricCard(label: "Vitesse max", value: Fmt.speed(day.maxSpeed))
                        MetricCard(label: "Recharge", value: Fmt.human(day.charging))
                        MetricCard(label: "Repas", value: Fmt.human(day.meal))
                    }
                    HStack(spacing: 8) {
                        MetricCard(label: "Énergie", value: String(format: "%.1f kWh", day.kwh))
                        MetricCard(label: "Coût", value: String(format: "%.2f $", day.cost))
                        MetricCard(label: "Dénivelé +", value: Fmt.meters(day.gain))
                    }
                    ForEach(day.trips) { trip in
                        NavigationLink(destination: TripDetailView(store: store, tripId: trip.id)) {
                            TripRow(trip: trip)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                .padding(16)
            }
        }
        .navigationTitle(Fmt.day(day.id))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button("Exporter en PDF") {
                        if let url = PdfExporter.dayPDF(day) { share = ShareItem(url: url) }
                    }
                    Button("Copier pour Google Sheets") {
                        SheetsExport.copy(day.trips)
                        copied = true
                    }
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
            }
        }
        .sheet(item: $share) { item in ShareSheet(url: item.url) }
        .alert(isPresented: $copied) { copiedAlert }
    }
}
