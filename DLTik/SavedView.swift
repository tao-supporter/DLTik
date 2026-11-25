import SwiftUI
import AVKit
import Photos

struct SavedView: View {
    @State private var files: [URL] = []
    @State private var selected: URL?
    @State private var notice = ""

    var body: some View {
        NavigationStack {
            Group {
                if files.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "folder").font(.largeTitle).foregroundStyle(.secondary)
                        Text("保存した動画・画像はまだありません").font(.subheadline).foregroundStyle(.secondary)
                    }
                } else {
                    List {
                        ForEach(files, id: \.path) { url in
                            Button { selected = url } label: {
                                HStack(spacing: 12) {
                                    ThumbView(url: url)
                                        .frame(width: 52, height: 52)
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(url.lastPathComponent).font(.caption).lineLimit(2)
                                        Text(fileInfo(url)).font(.caption2).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: isVideo(url) ? "play.circle.fill" : "photo")
                                        .foregroundStyle(.cyan)
                                }
                            }
                            .swipeActions {
                                Button(role: .destructive) { delete(url) } label: { Label("削除", systemImage: "trash") }
                                ShareLink(item: url) { Label("共有", systemImage: "square.and.arrow.up") }
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("保存済み")
            .navigationBarTitleDisplayMode(.inline)
            .background(Color(red: 0.04, green: 0.05, blue: 0.07).ignoresSafeArea())
            .onAppear(perform: reload)
            .sheet(item: Binding(get: { selected.map { FileRef(url: $0) } }, set: { selected = $0?.url })) { ref in
                FilePreview(url: ref.url)
            }
            .alert(notice, isPresented: Binding(get: { !notice.isEmpty }, set: { if !$0 { notice = "" } })) {
                Button("OK") { notice = "" }
            }
        }
    }

    private func reload() {
        let urls = (try? FileManager.default.contentsOfDirectory(at: Downloader.folder, includingPropertiesForKeys: [.creationDateKey])) ?? []
        files = urls.sorted {
            let a = (try? $0.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? nil
            let b = (try? $1.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? nil
            return (a ?? .distantPast) > (b ?? .distantPast)
        }
    }

    private func delete(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
        reload()
    }

    private func fileInfo(_ url: URL) -> String {
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        let size = attrs?[.size] as? Int64 ?? 0
        return formatBytes(size)
    }
}

func isVideo(_ url: URL) -> Bool {
    ["mp4", "mov", "m4v"].contains(url.pathExtension.lowercased())
}

private struct FileRef: Identifiable {
    var url: URL
    var id: String { url.path }
}

struct FilePreview: View {
    var url: URL
    @Environment(\.dismiss) private var dismiss
    @State private var notice = ""

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                if isVideo(url) {
                    VideoPlayer(player: AVPlayer(url: url))
                        .ignoresSafeArea(edges: .bottom)
                } else if let img = UIImage(contentsOfFile: url.path) {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFit()
                } else {
                    Text("プレビューできません").foregroundStyle(.white)
                }
            }
            .navigationTitle(url.lastPathComponent)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }
                }
                ToolbarItemGroup(placement: .primaryAction) {
                    ShareLink(item: url) { Image(systemName: "square.and.arrow.up") }
                    Button { saveToPhotos() } label: { Image(systemName: "photo.badge.plus") }
                }
            }
            .alert(notice, isPresented: Binding(get: { !notice.isEmpty }, set: { if !$0 { notice = "" } })) {
                Button("OK") { notice = "" }
            }
        }
    }

    private func saveToPhotos() {
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else {
                DispatchQueue.main.async { notice = "写真への保存が許可されていません" }
                return
            }
            PHPhotoLibrary.shared().performChanges {
                if isVideo(url) { PHAssetCreationRequest.forAsset().addResource(with: .video, fileURL: url, options: nil) }
                else { PHAssetCreationRequest.forAsset().addResource(with: .photo, fileURL: url, options: nil) }
            } completionHandler: { ok, _ in
                DispatchQueue.main.async { notice = ok ? "写真に保存しました" : "保存に失敗しました" }
            }
        }
    }
}

private struct ThumbView: View {
    var url: URL
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            Color.white.opacity(0.07)
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Image(systemName: isVideo(url) ? "film" : "photo").foregroundStyle(.secondary)
            }
        }
        .task {
            if isVideo(url) {
                let asset = AVURLAsset(url: url)
                let gen = AVAssetImageGenerator(asset: asset)
                gen.appliesPreferredTrackTransform = true
                gen.maximumSize = CGSize(width: 160, height: 160)
                if let cg = try? gen.copyCGImage(at: CMTime(seconds: 0.5, preferredTimescale: 600), actualTime: nil) {
                    image = UIImage(cgImage: cg)
                }
            } else {
                image = UIImage(contentsOfFile: url.path)
            }
        }
    }
}
