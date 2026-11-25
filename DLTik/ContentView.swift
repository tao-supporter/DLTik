import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            DownloadView()
                .tabItem { Label("ダウンロード", systemImage: "arrow.down.circle.fill") }
            SavedView()
                .tabItem { Label("保存済み", systemImage: "folder.fill") }
        }
        .tint(Color(red: 0.15, green: 0.95, blue: 0.85))
    }
}

private struct DownloadView: View {
    @EnvironmentObject private var downloader: Downloader
    @State private var input = ""
    @State private var loading = false
    @State private var status = ""
    @State private var post: PostInfo?
    @State private var errorText = ""
    @State private var preview: DLItem?
    private let client = TikTokClient()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    header
                    inputCard
                    if loading || !status.isEmpty { statusRow }
                    if !errorText.isEmpty { errorCard }
                    if let post { resultCard(post) }
                    if !downloader.items.isEmpty { downloadsCard }
                }
                .padding(16)
            }
            .background(Color(red: 0.04, green: 0.05, blue: 0.07).ignoresSafeArea())
            .navigationTitle("DLTik")
            .navigationBarTitleDisplayMode(.inline)
            .onTapGesture { hideKeyboard() }
            .sheet(item: $preview) { item in
                if let url = item.localURL { FilePreview(url: url) }
            }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(LinearGradient(colors: [.cyan, .pink], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 48, height: 48)
                Image(systemName: "music.note")
                    .font(.title2.bold())
                    .foregroundStyle(.black)
                Image(systemName: "arrow.down")
                    .font(.system(size: 13, weight: .black))
                    .foregroundStyle(.white)
                    .offset(x: 11, y: 11)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("TikTok ダウンローダー")
                    .font(.headline)
                Text("動画も画像投稿も、リンクを貼るだけ")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private var inputCard: some View {
        VStack(spacing: 12) {
            TextField("https://www.tiktok.com/@user/video/...", text: $input, axis: .vertical)
                .lineLimit(2...4)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
                .padding(12)
                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
            HStack(spacing: 10) {
                Button {
                    if let s = UIPasteboard.general.string { input = s }
                } label: {
                    Label("貼り付け", systemImage: "doc.on.clipboard")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                Button(role: .destructive) { input = ""; post = nil; errorText = "" } label: {
                    Label("消す", systemImage: "xmark")
                }
                .buttonStyle(.bordered)
            }
            Button {
                Task { await fetch() }
            } label: {
                HStack {
                    if loading { ProgressView().tint(.black) }
                    Text(loading ? "取得中…" : "取得する")
                        .fontWeight(.bold)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color(red: 0.0, green: 0.85, blue: 0.72))
            .foregroundStyle(.black)
            .disabled(loading || input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(16)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.white.opacity(0.08)))
    }

    private var statusRow: some View {
        HStack(spacing: 8) {
            if loading { ProgressView() }
            Text(status)
                .font(.footnote)
                .foregroundStyle(.secondary)
            Spacer()
        }
    }

    private var errorCard: some View {
        Text(errorText)
            .font(.footnote)
            .foregroundStyle(.red)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(Color.red.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
    }

    private func resultCard(_ post: PostInfo) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            if let cover = post.cover {
                AsyncImage(url: cover) { img in
                    img.resizable().scaledToFill()
                } placeholder: {
                    Color.white.opacity(0.06)
                }
                .frame(height: 210)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            if !post.author.isEmpty {
                Text("@\(post.author)").font(.subheadline.bold())
            }
            if !post.title.isEmpty {
                Text(post.title).font(.footnote).foregroundStyle(.secondary).lineLimit(3)
            }
            ForEach(post.videos) { link in
                Button { downloader.start(link) } label: {
                    Label(link.label, systemImage: "arrow.down.circle.fill")
                        .fontWeight(.bold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 5)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color(red: 0.0, green: 0.85, blue: 0.72))
                .foregroundStyle(.black)
            }
            if !post.images.isEmpty {
                Text("画像 \(post.images.count)枚").font(.subheadline.bold())
                ForEach(post.images) { link in
                    Button { downloader.start(link) } label: {
                        Label(link.label, systemImage: "photo")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 3)
                    }
                    .buttonStyle(.bordered)
                }
                Button { post.images.forEach { downloader.start($0) } } label: {
                    Label("画像を全部ダウンロード", systemImage: "square.grid.2x2")
                        .fontWeight(.bold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 3)
                }
                .buttonStyle(.bordered)
                .tint(.cyan)
            }
            ForEach(post.audios) { link in
                Button { downloader.start(link) } label: {
                    Label(link.label, systemImage: "music.note")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(16)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.white.opacity(0.08)))
    }

    private var downloadsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("ダウンロード状況").font(.subheadline.bold())
            ForEach(downloader.items) { item in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Image(systemName: item.kind == .image ? "photo" : item.kind == .audio ? "music.note" : "film")
                            .foregroundStyle(.cyan)
                        Text(item.filename).font(.caption).lineLimit(1)
                        Spacer()
                        switch item.state {
                        case .downloading:
                            Text("\(Int(item.fraction * 100))%").font(.caption.bold()).monospacedDigit()
                        case .done:
                            Text("完了").font(.caption.bold()).foregroundStyle(.green)
                        case .failed:
                            Text("失敗").font(.caption.bold()).foregroundStyle(.red)
                        }
                    }
                    ProgressView(value: item.fraction)
                        .tint(item.state == .failed ? .red : Color(red: 0.0, green: 0.85, blue: 0.72))
                    HStack {
                        Text(item.total > 0 ? "\(formatBytes(item.written)) / \(formatBytes(item.total))" : formatBytes(item.written))
                            .font(.caption2).foregroundStyle(.secondary).monospacedDigit()
                        Spacer()
                        if item.state == .done, item.localURL != nil {
                            Button(item.kind == .image ? "表示" : "再生") { preview = item }
                                .font(.caption.bold())
                            ShareLink(item: item.localURL!) { Text("共有") }.font(.caption.bold())
                        }
                        Button(role: .destructive) { downloader.remove(item) } label: {
                            Image(systemName: "trash").font(.caption)
                        }
                    }
                }
                .padding(10)
                .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .padding(16)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.white.opacity(0.08)))
    }

    private func fetch() async {
        guard let url = TikTokClient.firstURL(in: input) else {
            errorText = "TikTok / Douyin のURLが見つかりませんでした"; return
        }
        input = url
        loading = true; errorText = ""; post = nil
        status = "送信先を取得中…"
        do {
            let found = try await client.fetch(url)
            post = found
            status = "取得完了"
        } catch {
            errorText = error.localizedDescription
            status = ""
        }
        loading = false
    }

    private func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}
