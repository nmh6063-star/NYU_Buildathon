import SwiftUI

struct AuthView: View {
    @State private var model: AuthModel
    @FocusState private var focus: Field?

    private enum Field: Hashable { case name, email, password }

    init(api: any DropletAPI) {
        _model = State(initialValue: AuthModel(api: api))
    }

    var body: some View {
        @Bindable var model = model
        ScrollView {
            VStack(spacing: Theme.Spacing.xxl) {
                wordmark
                VStack(spacing: Theme.Spacing.m) {
                    if model.mode == .signUp {
                        field {
                            TextField("Name", text: $model.name)
                                .textContentType(.name)
                                .submitLabel(.next)
                                .focused($focus, equals: .name)
                                .onSubmit { focus = .email }
                        }
                        .transition(.opacity)
                    }
                    field {
                        TextField("Email", text: $model.email)
                            .textContentType(.emailAddress)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .submitLabel(.next)
                            .focused($focus, equals: .email)
                            .onSubmit { focus = .password }
                    }
                    field {
                        SecureField("Password", text: $model.password)
                            .textContentType(.password)
                            .submitLabel(.go)
                            .focused($focus, equals: .password)
                            .onSubmit(submit)
                    }
                    hints
                }
                VStack(spacing: Theme.Spacing.l) {
                    Button(action: submit) {
                        ZStack {
                            Text(model.mode == .signUp ? "Create account" : "Sign in")
                                .opacity(model.isSubmitting ? 0 : 1)
                            if model.isSubmitting {
                                ProgressView()
                            }
                        }
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Theme.Spacing.xs)
                    }
                    .buttonStyle(.glassProminent)
                    .controlSize(.large)
                    .disabled(!model.canSubmit)

                    Button(action: toggleMode) {
                        Text(model.mode == .signUp ? "Already have an account? Sign in" : "New to Droplet? Create an account")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(Theme.accent)
                    }
                    .buttonStyle(.pressable)
                }
            }
            .padding(.horizontal, Theme.Spacing.xl)
            .padding(.top, 72)
            .padding(.bottom, Theme.Spacing.xxl)
            .frame(maxWidth: 440)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .animation(Theme.spring, value: model.mode)
        .animation(Theme.spring, value: model.error)
        .sensoryFeedback(.error, trigger: model.error) { _, new in new != nil }
    }

    private var wordmark: some View {
        VStack(spacing: Theme.Spacing.m) {
            DropShape()
                .fill(Theme.accent.gradient)
                .frame(width: 44, height: 57)
                .accessibilityHidden(true)
            Text("Droplet")
                .font(.largeTitle.weight(.bold))
                .tracking(-0.7)
            Text("Spare change, invested.")
                .font(.body)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private func field<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .font(.body)
            .padding(.horizontal, Theme.Spacing.l)
            .frame(minHeight: 52)
            .background(.background.secondary, in: .rect(cornerRadius: 14))
    }

    @ViewBuilder private var hints: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            if !model.email.isEmpty && !model.email.contains("@") {
                Text("Enter a valid email address.")
                    .foregroundStyle(.secondary)
            }
            if !model.password.isEmpty && model.password.count < 6 {
                Text("Use at least 6 characters.")
                    .foregroundStyle(.secondary)
            }
            if let error = model.error {
                Label(error.message, systemImage: "exclamationmark.circle.fill")
                    .foregroundStyle(.red)
            }
        }
        .font(.footnote)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Theme.Spacing.xs)
    }

    private func submit() {
        guard model.canSubmit else { return }
        focus = nil
        Task { await model.submit() }
    }

    private func toggleMode() {
        model.mode = model.mode == .signUp ? .signIn : .signUp
        model.error = nil
    }
}

#Preview("Sign up") {
    AuthView(api: PreviewDropletAPI(signedIn: false))
}
