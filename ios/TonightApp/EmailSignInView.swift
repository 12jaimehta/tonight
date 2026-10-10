import AuthKit
import SwiftUI

/// Email OTP against the configured Supabase host. Sign in with Apple stays compiled out.
struct EmailSignInView: View {
    var client: EmailOTPClient
    @State private var email = ""
    @State private var code = ""
    @State private var phase: Phase = .email
    @State private var notice = ""

    private enum Phase {
        case email
        case code
        case signedIn
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Continue with email")
                .font(.largeTitle)
                .accessibilityIdentifier("signin.email")
            #if SIGN_IN_WITH_APPLE
            Button("Sign in with Apple") {}
                .accessibilityIdentifier("signin.apple")
            #endif
            if phase == .signedIn {
                Text("Signed in")
                    .accessibilityIdentifier("signin.notice")
            } else if phase == .email {
                TextField("Email", text: $email)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("signin.address")
                Button("Send code") { Task { await send() } }
                    .accessibilityIdentifier("signin.send")
            } else {
                TextField("Code", text: $code)
                    .keyboardType(.numberPad)
                    .textContentType(.oneTimeCode)
                    .accessibilityIdentifier("signin.code")
                Button("Verify") { Task { await verify() } }
                    .accessibilityIdentifier("signin.verify")
            }
            if !notice.isEmpty {
                Text(notice)
                    .accessibilityIdentifier("signin.notice")
            }
        }
        .padding(24)
    }

    private func send() async {
        do {
            try await client.requestCode(email: email)
            phase = .code
            notice = ""
        } catch {
            notice = "Check the email address and try again."
        }
    }

    private func verify() async {
        do {
            _ = try await client.verify(email: email, code: code)
            phase = .signedIn
            notice = ""
        } catch {
            notice = "That code didn't work. Check the latest email."
        }
    }
}
