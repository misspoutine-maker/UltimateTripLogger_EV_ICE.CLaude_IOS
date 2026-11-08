import SwiftUI

@main
struct UltimateTripLoggerApp: App {
    @StateObject private var tracker = TrackingManager()
    @Environment(\.scenePhase) private var phase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(tracker)
                .preferredColorScheme(.dark)
                .onAppear { tracker.startGPS() }
                .onChange(of: phase) { newPhase in
                    if newPhase == .active {
                        tracker.startGPS()
                    } else if newPhase == .background {
                        tracker.appBackgrounded()
                    }
                }
        }
    }
}

struct RootView: View {
    @EnvironmentObject var tracker: TrackingManager

    var body: some View {
        TabView {
            LiveTripView()
                .tabItem { Label("Trajet", systemImage: "speedometer") }
            HistoryView(store: tracker.store)
                .tabItem { Label("Historique", systemImage: "clock.arrow.circlepath") }
        }
        .accentColor(Theme.blue)
    }
}

struct ShareItem: Identifiable {
    let id = UUID()
    let url: URL
}

struct ShareSheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        return UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

struct MetricCard: View {
    let label: String
    let value: String

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundColor(Theme.textPrimary)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Theme.surface)
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border, lineWidth: 1))
    }
}

struct LabeledField: View {
    let label: String
    let placeholder: String
    @Binding var text: String
    var keyboard: UIKeyboardType = .default

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundColor(Theme.textSecondary)
            TextField(placeholder, text: $text)
                .keyboardType(keyboard)
                .textFieldStyle(.roundedBorder)
        }
    }
}

func parseDouble(_ s: String) -> Double {
    return Double(s.replacingOccurrences(of: ",", with: ".")) ?? 0
}

func parseSoc(_ s: String) -> Int? {
    guard let v = Int(s.trimmingCharacters(in: .whitespaces)), v >= 0, v <= 100 else { return nil }
    return v
}
