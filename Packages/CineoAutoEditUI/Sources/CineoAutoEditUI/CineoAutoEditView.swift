#if canImport(SwiftUI)
import SwiftUI

/// UI shell intentionally separated from the recording app / renderer.
/// The parent application supplies *real* preview, render and progress state.
public struct CineoAutoEditView: View {
    public struct Proposal: Identifiable, Sendable, Equatable {
        public let id: UUID
        public let title: String
        public let sourceSecond: Double
        public let reason: String

        public init(id: UUID, title: String, sourceSecond: Double, reason: String) {
            self.id = id; self.title = title
            self.sourceSecond = sourceSecond; self.reason = reason
        }
    }

    public enum Mode: String, CaseIterable, Identifiable, Sendable {
        case auto = "Auto"
        case assisted = "Assistito"
        case studio = "Studio"
        public var id: String { rawValue }
    }

    public let filename: String
    public let proposals: [Proposal]
    public let exportAvailable: Bool
    public let progress: Double?
    public let onExport: () -> Void
    public let onChangeAcceptance: (UUID, Bool) -> Void

    @State private var mode: Mode = .assisted
    @State private var acceptedIDs: Set<UUID> = []

    public init(filename: String, proposals: [Proposal],
                exportAvailable: Bool, progress: Double? = nil,
                onExport: @escaping () -> Void,
                onChangeAcceptance: @escaping (UUID, Bool) -> Void) {
        self.filename = filename
        self.proposals = proposals
        self.exportAvailable = exportAvailable
        self.progress = progress
        self.onExport = onExport
        self.onChangeAcceptance = onChangeAcceptance
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Cineo Studio").font(.title2.weight(.semibold))
                    Text(filename).foregroundStyle(.secondary)
                }
                Spacer()
                Picker("Editing", selection: $mode) {
                    ForEach(Mode.allCases) { choice in Text(choice.rawValue).tag(choice) }
                }.pickerStyle(.segmented).frame(maxWidth: 320)
            }
            GroupBox("Anteprima") {
                ContentUnavailableView("Anteprima non collegata",
                                       systemImage: "film",
                                       description: Text("La preview reale verrà fornita dal renderer condiviso; non viene mostrato un video simulato."))
                    .frame(maxWidth: .infinity, minHeight: 160)
            }
            if mode != .studio {
                Text("Interventi proposti").font(.headline)
                if proposals.isEmpty {
                    Text("Nessun evento disponibile: styling e zoom manuale rimangono utilizzabili.")
                        .foregroundStyle(.secondary)
                }
                ForEach(proposals) { proposal in
                    Toggle(isOn: Binding(
                        get: { acceptedIDs.contains(proposal.id) },
                        set: { isOn in
                            if isOn { acceptedIDs.insert(proposal.id) }
                            else { acceptedIDs.remove(proposal.id) }
                            onChangeAcceptance(proposal.id, isOn)
                        }
                    )) {
                        VStack(alignment: .leading) {
                            Text(proposal.title)
                            Text(String(format: "%0.1f s · %@", proposal.sourceSecond, proposal.reason))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            Spacer(minLength: 4)
            HStack {
                if let progress {
                    ProgressView(value: min(max(progress, 0), 1))
                        .frame(maxWidth: 250)
                        .accessibilityLabel("Esportazione in corso")
                }
                Spacer()
                Button("Esporta MP4") { onExport() }
                    .disabled(!exportAvailable || progress != nil)
                    .keyboardShortcut("e", modifiers: [.command])
            }
        }
        .padding(24)
        .frame(minWidth: 620, minHeight: 480)
    }
}
#endif
