import LinkKit
import SwiftUI

struct ConnectBankView: View {
    private let onLinked: @MainActor () -> Void
    @State private var model: ConnectBankModel
    @State private var linkSession: PlaidLinkSession?
    @State private var isPresentingLink = false
    @State private var openWhenReady = false

    init(api: any DropletAPI, onLinked: @escaping @MainActor () -> Void) {
        self.onLinked = onLinked
        _model = State(initialValue: ConnectBankModel(api: api))
    }

    var body: some View {
        @Bindable var model = model
        VStack(spacing: Theme.Spacing.xxl) {
            Spacer(minLength: Theme.Spacing.l)
            explainer
            Spacer(minLength: Theme.Spacing.l)
            VStack(spacing: Theme.Spacing.m) {
                connectButton
                Text("Sandbox login: user_good / pass_good")
                    .font(.footnote.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
        .padding(.horizontal, Theme.Spacing.xl)
        .padding(.bottom, Theme.Spacing.l)
        .frame(maxWidth: 440)
        .frame(maxWidth: .infinity)
        .errorBanner($model.error, retry: connect)
        .sensoryFeedback(.error, trigger: model.error) { _, new in new != nil }
        .sheet(isPresented: $isPresentingLink) {
            if let linkSession {
                linkSession.sheet()
            }
        }
        .task {
            if model.phase == .idle { await model.prepare() }
        }
        .onChange(of: model.phase) { _, phase in handle(phase) }
        .animation(Theme.spring, value: model.phase)
    }

    private var explainer: some View {
        VStack(spacing: Theme.Spacing.xl) {
            ZStack {
                Circle()
                    .fill(Theme.accent.opacity(0.12))
                    .frame(width: 112, height: 112)
                DropShape()
                    .fill(Theme.accent.gradient)
                    .frame(width: 40, height: 52)
            }
            .accessibilityHidden(true)
            VStack(spacing: Theme.Spacing.s) {
                Text("Connect your bank")
                    .font(.largeTitle.weight(.bold))
                    .tracking(-0.7)
                Text("We round up every purchase. Your spare change becomes drops.")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.center)
            Card(padding: Theme.Spacing.l) {
                VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                    step("arrow.up.circle.fill", "Card purchases round up to the next dollar.")
                    step("drop.fill", "When your drops reach the threshold, they're invested.")
                    step("testtube.2", "Trades are simulated in this build.")
                }
            }
        }
    }

    private func step(_ symbol: String, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.m) {
            Image(systemName: symbol)
                .foregroundStyle(Theme.accent)
                .frame(width: 24)
                .accessibilityHidden(true)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.primary)
        }
    }

    private var connectButton: some View {
        Button(action: connect) {
            HStack(spacing: Theme.Spacing.s) {
                if isBusy {
                    ProgressView()
                }
                Text(buttonTitle)
            }
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding(.vertical, Theme.Spacing.xs)
        }
        .buttonStyle(.glassProminent)
        .controlSize(.large)
        .disabled(!canConnect)
    }

    private var buttonTitle: String {
        switch model.phase {
        case .idle, .ready: "Connect bank"
        case .fetchingToken: "Preparing…"
        case .exchanging: "Linking your bank…"
        case .done: "Connected"
        }
    }

    private var isBusy: Bool {
        model.phase == .fetchingToken || model.phase == .exchanging
    }

    private var canConnect: Bool {
        switch model.phase {
        case .idle: true
        case .ready: linkSession != nil
        case .fetchingToken, .exchanging, .done: false
        }
    }

    private func connect() {
        switch model.phase {
        case .ready where linkSession != nil:
            isPresentingLink = true
        case .idle:
            openWhenReady = true
            Task { await model.prepare() }
        default:
            break
        }
    }

    private func handle(_ phase: ConnectBankModel.Phase) {
        switch phase {
        case .ready(let token):
            linkSession = makeSession(token: token)
            if openWhenReady, linkSession != nil {
                openWhenReady = false
                isPresentingLink = true
            }
        case .idle:
            // Link exited or a step failed. A Link session is single-use: the next attempt fetches a fresh token.
            isPresentingLink = false
            linkSession = nil
            openWhenReady = false
        case .exchanging:
            isPresentingLink = false
        case .done:
            onLinked()
        case .fetchingToken:
            break
        }
    }

    /// Creating the session preloads Link. Callbacks hop to the main actor and only touch the model.
    private func makeSession(token: String) -> PlaidLinkSession? {
        let model = model
        let configuration = LinkTokenConfiguration(
            token: token,
            onSuccess: { @Sendable success in
                let publicToken = success.publicToken
                let institutionName = success.metadata.institution.name
                Task { @MainActor in
                    await model.handleSuccess(publicToken: publicToken, institutionName: institutionName)
                }
            },
            onExit: { @Sendable exit in
                let message = exit.error?.displayMessage ?? exit.error?.errorMessage
                Task { @MainActor in
                    model.handleExit(errorMessage: message)
                }
            },
            onEvent: nil,
            onLoad: nil
        )
        do {
            return try Plaid.createPlaidLinkSession(configuration: configuration)
        } catch {
            model.handleExit(errorMessage: error.localizedDescription)
            return nil
        }
    }
}

#Preview("Connect bank") {
    ConnectBankView(api: PreviewDropletAPI(hasBank: false), onLinked: {})
}
