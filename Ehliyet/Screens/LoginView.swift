import SwiftUI
import AuthenticationServices

struct LoginView: View {
    @Environment(AuthStore.self) private var auth
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme

    @State private var mode: Mode = .login
    @State private var email = ""
    @State private var password = ""
    @State private var name = ""
    @State private var error: String?
    @FocusState private var focus: Field?

    enum Mode { case login, register }
    enum Field { case name, email, password }

    var reason: String? = nil

    private var canSubmit: Bool { email.contains("@") && password.count >= (mode == .register ? 8 : 1) && !auth.isLoading }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                VStack(spacing: 8) {
                    IconTile(systemName: "car.fill", color: Palette.tint, size: 64)
                    Text(mode == .login ? "Giriş Yap" : "Hesap Oluştur").font(.system(size: 28, weight: .bold))
                    Text(reason ?? "İlerlemen ve satın alımların tüm cihazlarında seninle olsun.")
                        .font(.system(size: 15)).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
                .padding(.top, 24)

                SignInWithAppleButton(.continue) { req in
                    req.requestedScopes = [.fullName, .email]
                } onCompletion: { result in
                    Task { await handleApple(result) }
                }
                .signInWithAppleButtonStyle(scheme == .dark ? .white : .black)
                .frame(height: 52)
                .clipShape(Capsule())

                HStack {
                    Rectangle().fill(Color(.separator)).frame(height: 0.5)
                    Text("veya").font(.system(size: 13)).foregroundStyle(.secondary)
                    Rectangle().fill(Color(.separator)).frame(height: 0.5)
                }

                Card {
                    if mode == .register {
                        field("Ad", text: $name, field: .name).textContentType(.name)
                        RowDivider(leading: 18)
                    }
                    field("E-posta", text: $email, field: .email)
                        .textContentType(.emailAddress).keyboardType(.emailAddress).textInputAutocapitalization(.never)
                    RowDivider(leading: 18)
                    SecureField(mode == .register ? "Şifre (en az 8 karakter)" : "Şifre", text: $password)
                        .textContentType(mode == .register ? .newPassword : .password)
                        .focused($focus, equals: .password)
                        .submitLabel(.go)
                        .onSubmit { Task { await submit() } }
                        .padding(.horizontal, 18).frame(minHeight: 50)
                }

                if let error {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 14)).foregroundStyle(Palette.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                PrimaryButton(title: auth.isLoading ? "Bekleyin…" : (mode == .login ? "Giriş Yap" : "Kayıt Ol")) {
                    Task { await submit() }
                }
                .disabled(!canSubmit)
                .opacity(canSubmit ? 1 : 0.5)

                Button(mode == .login ? "Hesabın yok mu? Kayıt ol" : "Zaten hesabın var mı? Giriş yap") {
                    withAnimation(.snappy) { mode = mode == .login ? .register : .login; error = nil }
                }
                .font(.system(size: 15, weight: .semibold))
            }
            .padding(.horizontal, 20)
            .padding(.top, 50)
            .padding(.bottom, 30)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Color(.systemGroupedBackground))
        .overlay(alignment: .topTrailing) {
            GlassIconButton(systemName: "xmark", label: "Kapat") { dismiss() }
                .padding(16)
        }
    }

    private func field(_ title: String, text: Binding<String>, field: Field) -> some View {
        TextField(title, text: text)
            .focused($focus, equals: field)
            .autocorrectionDisabled()
            .padding(.horizontal, 18).frame(minHeight: 50)
    }

    private func submit() async {
        guard canSubmit else { return }
        error = nil
        do {
            if mode == .login { try await auth.login(email: email, password: password) }
            else { try await auth.register(email: email, password: password, name: name) }
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func handleApple(_ result: Result<ASAuthorization, Error>) async {
        switch result {
        case .success(let authorization):
            guard let cred = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let tokenData = cred.identityToken, let token = String(data: tokenData, encoding: .utf8) else {
                error = "Apple kimliği alınamadı"; return
            }
            let fullName = [cred.fullName?.givenName, cred.fullName?.familyName].compactMap { $0 }.joined(separator: " ")
            do { try await auth.signInWithApple(identityToken: token, name: fullName) }
            catch { self.error = error.localizedDescription }
        case .failure(let err):
            if (err as? ASAuthorizationError)?.code != .canceled { error = err.localizedDescription }
        }
    }
}
