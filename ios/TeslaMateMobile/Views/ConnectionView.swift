import SwiftUI

struct ConnectionView: View {
    @Environment(AppSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var serverURL = ""
    @State private var token = ""
    @State private var errorMessage: String?
    @State private var connectionTask: Task<Void, Never>?

    var body: some View {
        Form {
            Section("TeslaMate 服务器") {
                TextField("https://your-server.example/", text: $serverURL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                SecureField("访问令牌", text: $token)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
            .disabled(session.isConnecting)
            Section {
                Button {
                    connectionTask = Task {
                        errorMessage = nil
                        do {
                            try await session.connect(serverURL: serverURL, token: token)
                            dismiss()
                        } catch is CancellationError {
                        } catch {
                            errorMessage = error.localizedDescription
                        }
                    }
                } label: {
                    HStack {
                        if session.isConnecting { ProgressView() }
                        Text(session.isConnecting ? "正在验证连接…" : "验证并保存")
                    }
                }
                .disabled(serverURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                          token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || session.isConnecting)
            } footer: {
                Text("推荐使用 HTTPS。若使用 Tailscale 私网地址，请先连接 Tailscale。验证成功后才会替换当前连接，令牌保存在本机钥匙串中。")
            }
            if let error = errorMessage ?? session.errorMessage {
                Section { Text(error).foregroundStyle(.red) }
            }
            if session.isConfigured {
                Section {
                    Button("断开连接并清除凭据", role: .destructive) {
                        do {
                            try session.disconnect()
                            dismiss()
                        } catch { errorMessage = error.localizedDescription }
                    }
                    .disabled(session.isConnecting)
                }
            }
        }
        .navigationTitle("连接设置")
        .interactiveDismissDisabled(session.isConnecting)
        .onAppear {
            serverURL = session.serverURL
            token = session.token
        }
        .onDisappear { connectionTask?.cancel() }
    }
}
