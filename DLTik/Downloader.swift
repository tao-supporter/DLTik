import Foundation

struct DLItem: Identifiable {
    enum State { case downloading, done, failed }
    var id = UUID()
    var url: URL
    var label: String
    var kind: LinkKind
    var filename: String
    var fraction = 0.0
    var written: Int64 = 0
    var total: Int64 = 0
    var state: State = .downloading
    var localURL: URL?
}

final class Downloader: NSObject, ObservableObject {
    @Published var items: [DLItem] = []

    private lazy var session: URLSession = {
        let conf = URLSessionConfiguration.default
        conf.httpMaximumConnectionsPerHost = 6
        conf.timeoutIntervalForRequest = 60
        return URLSession(configuration: conf, delegate: self, delegateQueue: nil)
    }()

    static var folder: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("DLTik", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func start(_ link: FoundLink) {
        var item = DLItem(url: link.url, label: link.label, kind: link.kind, filename: "")
        item.filename = baseName(for: link)
        items.insert(item, at: 0)
        var req = URLRequest(url: link.url)
        req.setValue("https://www.tiktok.com/", forHTTPHeaderField: "Referer")
        req.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Mobile/15E148 Safari/604.1", forHTTPHeaderField: "User-Agent")
        let task = session.downloadTask(with: req)
        task.taskDescription = item.id.uuidString
        task.resume()
    }

    func remove(_ item: DLItem) {
        items.removeAll { $0.id == item.id }
    }

    private func baseName(for link: FoundLink) -> String {
        let ext: String
        let fromURL = link.url.pathExtension.lowercased()
        if ["mp4", "mov", "jpg", "jpeg", "png", "webp", "mp3", "m4a"].contains(fromURL) { ext = fromURL }
        else { ext = link.kind == .image ? "jpg" : link.kind == .audio ? "mp3" : "mp4" }
        let stamp = DateFormatter()
        stamp.dateFormat = "yyyyMMdd-HHmmss"
        let label = link.label.replacingOccurrences(of: "Download", with: "").replacingOccurrences(of: "/", with: "-").trimmingCharacters(in: .whitespaces)
        return "tiktok-\(stamp.string(from: Date()))\(label.isEmpty ? "" : "-\(label)").\(ext)"
    }

    private func uniqueURL(for name: String) -> URL {
        var url = Self.folder.appendingPathComponent(name)
        var n = 2
        while FileManager.default.fileExists(atPath: url.path) {
            let base = (name as NSString).deletingPathExtension
            let ext = (name as NSString).pathExtension
            url = Self.folder.appendingPathComponent("\(base) \(n).\(ext)")
            n += 1
        }
        return url
    }

    private func update(id: String, _ change: @escaping (inout DLItem) -> Void) {
        DispatchQueue.main.async {
            guard let i = self.items.firstIndex(where: { $0.id.uuidString == id }) else { return }
            change(&self.items[i])
        }
    }
}

extension Downloader: URLSessionDownloadDelegate {
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard let id = downloadTask.taskDescription else { return }
        update(id: id) { item in
            item.written = totalBytesWritten
            item.total = totalBytesExpectedToWrite
            if totalBytesExpectedToWrite > 0 { item.fraction = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite) }
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let id = downloadTask.taskDescription else { return }
        var dest: URL?
        DispatchQueue.main.sync {
            if let item = self.items.first(where: { $0.id.uuidString == id }) { dest = self.uniqueURL(for: item.filename) }
        }
        guard let dest else { return }
        do {
            try FileManager.default.moveItem(at: location, to: dest)
            update(id: id) { item in
                item.localURL = dest
                item.fraction = 1
                item.state = .done
                if item.total <= 0, let size = try? FileManager.default.attributesOfItem(atPath: dest.path)[.size] as? Int64 {
                    item.written = size; item.total = size
                }
            }
        } catch {
            update(id: id) { $0.state = .failed }
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let id = task.taskDescription, error != nil else { return }
        update(id: id) { if $0.state == .downloading { $0.state = .failed } }
    }
}

func formatBytes(_ bytes: Int64) -> String {
    if bytes <= 0 { return "0 MB" }
    let mb = Double(bytes) / 1_000_000
    return mb >= 100 ? String(format: "%.0f MB", mb) : String(format: "%.1f MB", mb)
}
