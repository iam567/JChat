import SwiftUI
import PhotosUI

private let teal = Color(uiColor: UIColor { traits in
    traits.userInterfaceStyle == .dark
        ? UIColor(red: 0.40, green: 0.86, blue: 0.81, alpha: 1)
        : UIColor(red: 0.06, green: 0.39, blue: 0.43, alpha: 1)
})
private let canvas = Color(uiColor: .systemGroupedBackground)
private let card = Color(uiColor: .secondarySystemGroupedBackground)
private let surface = Color(uiColor: .systemBackground)

struct ContentView: View {
    @StateObject private var chat = ChatModel()
    @AppStorage("myLanguage") private var own = "zh"
    @AppStorage("targetLanguage") private var target = "ja"
    @AppStorage("tone") private var tone = "auto"
    @AppStorage("openAIModel") private var model = "gpt-6.1-sol"
    @State private var settings = false
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var clearAll = false
    @State private var newChat = false

    var effectiveOwn: String { chat.current?.myLanguage ?? own }
    var effectiveTarget: String { chat.current?.targetLanguage ?? target }
    func l(_ zh: String, _ ja: String, _ en: String) -> String {
        switch own { case "ja": return ja; case "en": return en; default: return zh }
    }

    var body: some View {
        TabView(selection: $chat.tab) {
            NavigationStack {
                VStack(spacing: 0) {
                    controls
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 20) {
                                if chat.current == nil { welcome }
                                ForEach(chat.current?.turns ?? []) { turn in
                                    TurnCard(turn: turn, own: effectiveOwn)
                                }
                                if chat.busy {
                                    HStack(spacing: 10) { ProgressView(); Text(chat.progress).font(.subheadline).foregroundStyle(.secondary) }
                                        .padding().frame(maxWidth: .infinity, alignment: .leading).background(card, in: RoundedRectangle(cornerRadius: 18))
                                }
                                if !chat.busy, chat.pendingText != nil || chat.pendingImage != nil {
                                    Button { Task { await retry() } } label: { Label(l("重试上次翻译", "もう一度翻訳", "Retry translation"), systemImage: "arrow.clockwise") }
                                }
                                Color.clear.frame(height: 1).id("bottom")
                            }.padding(18)
                        }
                        .onChange(of: chat.current?.turns.count) { _, _ in withAnimation { proxy.scrollTo("bottom", anchor: .bottom) } }
                        .onChange(of: chat.busy) { _, _ in withAnimation { proxy.scrollTo("bottom", anchor: .bottom) } }
                        .scrollDismissesKeyboard(.interactively)
                    }
                    composer
                }
                .background(canvas)
                .navigationTitle("JChat")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button { if chat.current == nil { chat.startNew() } else { newChat = true } } label: { Image(systemName: "square.and.pencil") }
                            .accessibilityLabel(l("新对话", "新しい会話", "New conversation")).disabled(chat.busy)
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { settings = true } label: { Image(systemName: "gearshape") }
                            .accessibilityLabel(l("设置", "設定", "Settings")).disabled(chat.busy)
                    }
                }
            }
            .tabItem { Label(l("直接翻译", "翻訳", "Translate"), systemImage: "bubble.left.and.text.bubble.right") }.tag(0)

            NavigationStack {
                Group {
                    if chat.histories.isEmpty {
                        ContentUnavailableView(l("还没有翻译历史", "履歴はありません", "No translation history"), systemImage: "clock.arrow.circlepath", description: Text(l("翻译过的对话会自动保存在这里", "翻訳した会話はここに自動保存されます", "Your translations are saved here automatically")))
                    } else {
                        List {
                            ForEach(chat.histories) { item in
                                Button { chat.open(item) } label: {
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text(item.title).font(.headline).foregroundStyle(.primary).lineLimit(2)
                                        HStack {
                                            Text("\(AppLanguage.name(item.myLanguage)) ↔ \(AppLanguage.name(item.targetLanguage))")
                                            Spacer()
                                            Text(item.createdAt, format: .dateTime.month().day().hour().minute())
                                        }.font(.caption).foregroundStyle(.secondary)
                                    }.padding(.vertical, 5)
                                }.disabled(chat.busy)
                            }.onDelete { offsets in chat.remove(Set(offsets.map { chat.histories[$0].id })) }
                        }
                    }
                }
                .navigationTitle(l("翻译历史", "翻訳履歴", "History"))
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(role: .destructive) { clearAll = true } label: { Image(systemName: "trash") }.disabled(chat.busy || chat.histories.isEmpty)
                    }
                }
            }
            .tabItem { Label(l("翻译历史", "履歴", "History"), systemImage: "clock.arrow.circlepath") }.tag(1)
        }
        .tint(teal)
        .sheet(isPresented: $settings) { SettingsView(own: $own, target: $target, model: $model) }
        .onChange(of: selectedPhoto) { _, item in
            guard let item else { return }
            Task {
                do {
                    guard let data = try await item.loadTransferable(type: Data.self) else { throw ChatError(message: "无法读取这张图片") }
                    await chat.screenshot(data, own: effectiveOwn, target: effectiveTarget, tone: tone, model: model)
                } catch { chat.error = error.localizedDescription }
                selectedPhoto = nil
            }
        }
        .alert(l("提示", "お知らせ", "Notice"), isPresented: Binding(get: { chat.error != nil }, set: { if !$0 { chat.error = nil } })) {
            Button(l("知道了", "OK", "OK"), role: .cancel) { chat.error = nil }
        } message: { Text(chat.error ?? "") }
        .confirmationDialog(l("清空所有翻译历史？", "すべての履歴を削除しますか？", "Delete all history?"), isPresented: $clearAll, titleVisibility: .visible) {
            Button(l("全部删除", "すべて削除", "Delete all"), role: .destructive) { chat.remove(Set(chat.histories.map(\.id))) }
        }
        .confirmationDialog(l("开启新对话？当前内容已保存到历史。", "新しい会話を開始しますか？現在の会話は保存されています。", "Start a new conversation? This one is saved."), isPresented: $newChat, titleVisibility: .visible) {
            Button(l("新对话", "新しい会話", "New conversation")) { chat.startNew() }
        }
    }

    private var controls: some View {
        VStack(spacing: 10) {
            HStack {
                Text(AppLanguage.name(effectiveOwn)).fontWeight(.semibold)
                Image(systemName: "arrow.left.arrow.right").font(.caption).foregroundStyle(.secondary)
                Menu {
                    ForEach(AppLanguage.all) { language in
                        Button(language.name) {
                            target = language.id
                            if chat.current != nil {
                                chat.current?.targetLanguage = language.id
                            }
                        }
                    }
                } label: { Text(AppLanguage.name(effectiveTarget)); Image(systemName: "chevron.down").font(.caption2) }
                Spacer()
                Menu {
                    ForEach(Tone.all) { item in Button(item.name) { tone = item.id } }
                } label: { Text(Tone.all.first { $0.id == tone }?.name ?? "AI 自动判断").font(.subheadline); Image(systemName: "chevron.down").font(.caption2) }
            }
            if chat.current != nil, chat.current?.myLanguage != own {
                Text(l("这段历史使用原来的语言设置；新对话会使用你的新设置", "この会話は元の言語設定を使用します", "This conversation keeps its original language settings")).font(.caption).foregroundStyle(.secondary)
            }
        }.padding(.horizontal, 18).padding(.vertical, 12).background(surface).disabled(chat.busy)
    }

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 18) {
            Image(systemName: "bubble.left.and.text.bubble.right.fill").font(.system(size: 40)).foregroundStyle(teal)
            Text(l("看懂对方，自然回复", "相手を理解して、自然に返信", "Understand them. Reply naturally.")).font(.title2.bold())
            Text(l("截取 LINE 对话后，点一下「翻译最新截图」。也可以粘贴对方说的话，或直接输入你想回复的内容。", "LINEをスクリーンショットして「最新のスクショを翻訳」をタップ。相手の文章を貼り付けたり、返信したい内容を入力することもできます。", "Take a LINE screenshot and tap Translate latest screenshot. You can also paste their message or type your reply."))
                .font(.subheadline).foregroundStyle(.secondary).lineSpacing(5)
            Label(l("新对话自动保存到翻译历史", "会話は履歴に自動保存", "Conversations are saved to history"), systemImage: "clock").font(.caption).foregroundStyle(teal)
        }.padding(24).frame(maxWidth: .infinity, alignment: .leading).background(card, in: RoundedRectangle(cornerRadius: 24)).padding(.top, 16)
    }

    private var composer: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                Button { Task { await chat.latest(own: effectiveOwn, target: effectiveTarget, tone: tone, model: model) } } label: {
                    Label(l("翻译最新截图", "最新のスクショを翻訳", "Latest screenshot"), systemImage: "camera.viewfinder").font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity).padding(.vertical, 12)
                }.background(teal.opacity(0.14), in: RoundedRectangle(cornerRadius: 14))
                PhotosPicker(selection: $selectedPhoto, matching: .images, photoLibrary: .shared()) {
                    Image(systemName: "photo.on.rectangle").font(.title3).frame(width: 48, height: 44).background(teal.opacity(0.14), in: RoundedRectangle(cornerRadius: 14))
                }.accessibilityLabel(l("从相册选图", "写真から選ぶ", "Choose photo"))
            }
            Picker("方向", selection: $chat.incoming) {
                Text(l("我要回复", "返信する", "My reply")).tag(false)
                Text(l("对方说", "相手の発言", "Their message")).tag(true)
            }.pickerStyle(.segmented)
            HStack(alignment: .bottom, spacing: 10) {
                TextField("", text: $chat.draft, prompt: Text(chat.incoming ? l("粘贴对方说的话，翻译成", "相手の文章を貼り付け →", "Paste their message →") + AppLanguage.name(effectiveOwn) : l("输入想回复的话 → ", "返信したい内容 → ", "Type your reply → ") + AppLanguage.name(effectiveTarget)).foregroundStyle(.secondary), axis: .vertical)
                    .lineLimit(1...5).foregroundStyle(.primary).padding(12).background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
                Button { Task { await chat.send(own: effectiveOwn, target: effectiveTarget, tone: tone, model: model) } } label: {
                    Image(systemName: "arrow.up").font(.title3.bold()).foregroundStyle(surface).frame(width: 46, height: 46).background(teal, in: RoundedRectangle(cornerRadius: 15))
                }.disabled(chat.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty).accessibilityLabel(l("发送", "送信", "Send"))
            }
        }.padding(14).background(surface).disabled(chat.busy)
    }

    private func retry() async { await chat.retry(own: effectiveOwn, target: effectiveTarget, tone: tone, model: model) }
}

struct TurnCard: View {
    let turn: Turn
    let own: String
    func l(_ zh: String, _ ja: String, _ en: String) -> String { own == "ja" ? ja : (own == "en" ? en : zh) }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label(turn.kind == "outgoing" ? l("我要回复", "返信する", "My reply") : l("对方说", "相手の発言", "Their message"), systemImage: turn.kind == "outgoing" ? "arrow.up.right" : "arrow.down.left").font(.caption.weight(.semibold)).foregroundStyle(teal)
                Spacer()
                Text(turn.createdAt, style: .time).font(.caption2).foregroundStyle(.secondary)
            }
            if let data = turn.thumbnail, let image = UIImage(data: data) {
                Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 180).clipShape(RoundedRectangle(cornerRadius: 12))
                DisclosureGroup(l("识别出的原文", "認識した原文", "Recognized text")) { Text(turn.original).font(.caption).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }.font(.caption).foregroundStyle(.secondary)
            } else {
                Text(turn.original).font(.subheadline).textSelection(.enabled)
            }
            if turn.kind != "outgoing" {
                Divider()
                Text(turn.result.translation).lineSpacing(5).textSelection(.enabled)
            }
            if !turn.result.summary.isEmpty {
                Text(turn.result.summary).font(.subheadline).foregroundStyle(.secondary).lineSpacing(4)
            }
            ForEach(Array(turn.result.replies.enumerated()), id: \.offset) { _, reply in ReplyCard(reply: reply, own: own) }
        }.padding(18).frame(maxWidth: .infinity, alignment: .leading).background(card, in: RoundedRectangle(cornerRadius: 20))
    }
}

struct ReplyCard: View {
    let reply: Reply
    let own: String
    @State private var edited: String
    @State private var copied = false
    init(reply: Reply, own: String) { self.reply = reply; self.own = own; _edited = State(initialValue: reply.text) }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("", text: $edited, axis: .vertical).lineLimit(2...12).lineSpacing(4)
            Text(reply.note).font(.caption).foregroundStyle(.secondary).lineSpacing(3)
            Button {
                UIPasteboard.general.string = edited
                copied = true
                Task { try? await Task.sleep(for: .seconds(1.5)); copied = false }
            } label: {
                Label(copied ? (own == "ja" ? "コピーしました" : "已复制") : (own == "ja" ? "返信をコピー" : (own == "en" ? "Copy reply" : "复制这条回复")), systemImage: copied ? "checkmark" : "doc.on.doc").font(.subheadline.weight(.semibold))
            }.disabled(edited.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }.padding(15).background(teal.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
    }
}
