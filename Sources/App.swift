import SwiftUI
import MessageUI

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
    @AppStorage("lang") private var lang = "auto"

    var body: some View {
        TabView {
            LiveTripView()
                .tabItem { Label(tr("Trajet"), systemImage: "speedometer") }
            RecapView(store: tracker.store)
                .tabItem { Label(tr("Récap"), systemImage: "chart.bar.fill") }
            HistoryView(store: tracker.store)
                .tabItem { Label(tr("Historique"), systemImage: "clock.arrow.circlepath") }
        }
        .accentColor(Theme.blue)
        .id(lang)
    }
}

struct ShareItem: Identifiable {
    let id = UUID()
    let url: URL
}

struct MailItem: Identifiable {
    let id = UUID()
    let url: URL
    let subject: String
}

struct MailComposer: UIViewControllerRepresentable {
    let item: MailItem
    @Environment(\.presentationMode) var presentation

    static var canSend: Bool { MFMailComposeViewController.canSendMail() }

    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let vc = MFMailComposeViewController()
        vc.mailComposeDelegate = context.coordinator
        vc.setSubject(item.subject)
        let to = UserDefaults.standard.string(forKey: "mailTo") ?? ""
        if !to.isEmpty { vc.setToRecipients([to]) }
        vc.setMessageBody(item.subject, isHTML: false)
        if let data = try? Data(contentsOf: item.url) {
            vc.addAttachmentData(data, mimeType: "text/csv", fileName: item.url.lastPathComponent)
        }
        return vc
    }

    func updateUIViewController(_ uiViewController: MFMailComposeViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(presentation: $presentation) }

    final class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        let presentation: Binding<PresentationMode>

        init(presentation: Binding<PresentationMode>) {
            self.presentation = presentation
        }

        func mailComposeController(_ controller: MFMailComposeViewController,
                                   didFinishWith result: MFMailComposeResult, error: Error?) {
            presentation.wrappedValue.dismiss()
        }
    }
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
                .autocapitalization(keyboard == .emailAddress ? .none : .sentences)
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
