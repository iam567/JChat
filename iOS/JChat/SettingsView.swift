import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var own: String
    @Binding var target: String
    @Binding var model: String
    @State private var key = KeyStore.read()
    @State private var testing = false
    @State private var notice: String?
    @State private var showKey = false
    func l(_ zh: String, _ ja: String, _ en: String) -> String { own == "ja" ? ja : (own == "en" ? en : zh) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker(l("我的语言", "自分の言語", "My language"), selection: $own) {
                        ForEach(AppLanguage.all) { language in Text(language.name).tag(language.id) }
                    }
                    Picker(l("对方语言", "相手の言語", "Their language"), selection: $target) {
                        ForEach(AppLanguage.all) { language in Text(language.name).tag(language.id) }
                    }
                } header: { Text(l("语言设置", "言語設定", "Languages")) } footer: {
                    Text(l("「我要回复」翻成对方语言；「对方说」和截图翻成我的语言。已有历史保留原来的语言，新对话使用这里的设置。", "返信は相手の言語へ、相手の発言とスクショは自分の言語へ翻訳します。設定は新しい会話に適用されます。", "Your replies use their language. Their messages and screenshots use yours. Changes apply to new conversations."))
                }
                Section {
                    HStack {
                        Group {
                            if showKey { TextField("sk-…", text: $key) }
                            else { SecureField("sk-…", text: $key) }
                        }.textInputAutocapitalization(.never).autocorrectionDisabled().textContentType(.password)
                        Button { showKey.toggle() } label: { Image(systemName: showKey ? "eye.slash" : "eye") }.buttonStyle(.borderless)
                    }
                    Menu {
                        Button("GPT-6.1 Sol") { model = "gpt-6.1-sol" }
                        Button("GPT-6 Astra") { model = "gpt-6-astra" }
                        Button("GPT-6 Luna") { model = "gpt-6-luna" }
                    } label: {
                        HStack { Text(l("选择模型", "モデルを選択", "Choose model")); Spacer(); Text(model).foregroundStyle(.secondary) }
                    }
                    TextField(l("模型 ID（可手动修改）", "モデルID（編集可）", "Model ID (editable)"), text: $model)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    Button {
                        testing = true
                        Task {
                            do {
                                try await OpenAIClient(key: key.trimmingCharacters(in: .whitespacesAndNewlines), model: model.trimmingCharacters(in: .whitespacesAndNewlines)).verify()
                                notice = l("连接成功，API Key 和模型访问权限正常", "接続成功。APIキーとモデルへのアクセスを確認しました", "Connected. API key and model access verified.")
                            } catch { notice = error.localizedDescription }
                            testing = false
                        }
                    } label: {
                        HStack { Text(l("验证 Key 和模型", "キーとモデルを確認", "Verify key and model")); if testing { Spacer(); ProgressView() } }
                    }.disabled(testing || key.isEmpty || model.isEmpty)
                } header: { Text("OpenAI API") } footer: {
                    Text(l("密钥加密保存在这台 iPhone 的钥匙串里。翻译直接连接 OpenAI。模型默认 GPT-6.1 Sol，可按账号权限调整。", "キーはこのiPhoneのキーチェーンに保存されます。翻訳はOpenAIに直接接続します。初期モデルはGPT-6.1 Solです。", "Your key is stored in this iPhone’s Keychain. Translation connects directly to OpenAI. Default model: GPT-6.1 Sol."))
                }
                Section {
                    Button(l("打开照片权限设置", "写真のアクセス設定を開く", "Open photo permissions")) {
                        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                    }
                } footer: {
                    Text(l("「翻译最新截图」需要照片完整访问权限；不想授权全部照片，也可以用相册按钮手动选图。截图文字在手机上识别，再发送文字进行翻译。", "最新のスクショを取得するには写真へのフルアクセスが必要です。写真ピッカーで個別選択もできます。文字認識は端末内で行います。", "Latest screenshot requires full Photos access. You can also choose images individually. Text recognition runs on your phone."))
                }
                Section {
                    Text("JChat · 1.0").foregroundStyle(.secondary)
                    Text(l("对话自动保存在手机上，可在翻译历史中删除。", "会話は端末に保存され、履歴から削除できます。", "Conversations are saved on your phone and can be deleted from History.")).font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle(l("设置", "設定", "Settings"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(l("保存", "保存", "Save")) {
                        let cleanModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !cleanModel.isEmpty else { notice = "请填写模型 ID"; return }
                        do {
                            try KeyStore.save(key.trimmingCharacters(in: .whitespacesAndNewlines))
                            model = cleanModel
                            dismiss()
                        } catch { notice = error.localizedDescription }
                    }.disabled(testing)
                }
            }
            .interactiveDismissDisabled(testing)
            .alert(l("连接设置", "接続設定", "Connection settings"), isPresented: Binding(get: { notice != nil }, set: { if !$0 { notice = nil } })) {
                Button("OK", role: .cancel) { notice = nil }
            } message: { Text(notice ?? "") }
        }
    }
}
