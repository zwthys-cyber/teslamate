import SwiftUI

struct ConnectionView: View {
    @Environment(AppSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var serverURL = ""
    @State private var token = ""
    @State private var isConnecting = false

    var body: some View {
        NavigationStack {
            Form {
                Section("TeslaMate 服务器") {
                    TextField("http://100.88.30.82:4000/", text: $serverURL)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                    SecureField("访问令牌", text: $token)
                        .textInputAutocapitalization(.never)
                }
                Section {
                    Button {
                        Task {
                            isConnecting = true
                            session.save(serverURL: serverURL, token: token)
                            await session.refresh()
                            isConnecting = false
                            if session.errorMessage == nil { dismiss() }
                        }
                    } label: {
                        HStack {
                            if isConnecting { ProgressView() }
                            Text(isConnecting ? "正在连接…" : "保存并连接")
                        }
                    }
                    .disabled(serverURL.isEmpty || token.isEmpty || isConnecting)
                } footer: {
                    Text("请先打开 Tailscale。访问令牌只保存在本机钥匙串中。")
                }
                if let error = session.errorMessage {
                    Section { Text(error).foregroundStyle(.red) }
                }
            }
            .navigationTitle("连接设置")
            .onAppear {
                serverURL = session.serverURL
                token = session.token
            }
        }
    }
}
