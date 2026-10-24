import SwiftUI

/// Cross-fades between the four routes `AppModel` decides.
struct RootView: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        ZStack {
            switch appModel.route {
            case .launching:
                LaunchView()
                    .transition(.opacity)
            case .auth:
                AuthView(api: appModel.api)
                    .transition(.opacity)
            case .connectBank:
                ConnectBankView(api: appModel.api, onLinked: appModel.bankLinked)
                    .transition(.opacity)
            case .main:
                MainTabs()
                    .transition(.opacity)
            }
        }
        .animation(Theme.spring, value: appModel.route)
    }
}

private struct LaunchView: View {
    var body: some View {
        VStack(spacing: Theme.Spacing.l) {
            DropShape()
                .fill(Theme.accent.gradient)
                .frame(width: 44, height: 57)
                .accessibilityHidden(true)
            ProgressView()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading")
    }
}

#Preview("Root, signed out") {
    let api = PreviewDropletAPI(signedIn: false)
    let appModel = AppModel(api: api)
    RootView()
        .environment(appModel)
        .environment(DropletStore(api: api))
        .task { await appModel.start() }
}

#Preview("Root, signed in") {
    let api = PreviewDropletAPI()
    let appModel = AppModel(api: api)
    RootView()
        .environment(appModel)
        .environment(DropletStore(api: api))
        .task { await appModel.start() }
}
