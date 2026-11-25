import Foundation

enum LinkKind {
    case video, image, audio
}

struct FoundLink: Identifiable, Hashable {
    var url: URL
    var label: String
    var kind: LinkKind
    var id: String { url.absoluteString + label }
}

struct PostInfo {
    var cover: URL?
    var title = ""
    var author = ""
    var links: [FoundLink] = []
    var videos: [FoundLink] { links.filter { $0.kind == .video } }
    var images: [FoundLink] { links.filter { $0.kind == .image } }
    var audios: [FoundLink] { links.filter { $0.kind == .audio } }
}

enum ClientError: LocalizedError {
    case badURL, notFound
    var errorDescription: String? {
        switch self {
        case .badURL: return "TikTok / Douyin のURLが見つかりませんでした"
        case .notFound: return "取得できませんでした。リンクを確認してもう一度試してください"
        }
    }
}

struct TikTokClient {
    private let ua = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Safari/605.1.15"
    private let fallbackDomains = ["savetik.co", "tikdownloader.io", "snaptik.net", "tikvideo.app"]

    static func firstURL(in text: String) -> String? {
        guard let m = text.range(of: #"https?://[^\s"]+"#, options: .regularExpression) else { return nil }
        var s = String(text[m])
        while let last = s.last, "。、,)）".contains(last) { s.removeLast() }
        return s
    }

    func fetch(_ input: String) async throws -> PostInfo {
        guard input.contains("tiktok.com") || input.contains("douyin.com") else { throw ClientError.badURL }
        var post = try await viaAjaxSearch(input)
        if post.images.isEmpty {
            if let extra = try? await viaTikwm(input) {
                post.links.append(contentsOf: extra.images)
                if post.cover == nil { post.cover = extra.cover }
                if post.title.isEmpty { post.title = extra.title }
                if post.author.isEmpty { post.author = extra.author }
            }
        }
        if post.links.isEmpty { throw ClientError.notFound }
        return post
    }

    private func viaAjaxSearch(_ input: String) async throws -> PostInfo {
        let domains = await configDomains().shuffled()
        for domain in domains {
            if let post = try? await ajaxSearch(domain: domain, input: input), !post.links.isEmpty {
                return post
            }
        }
        if let post = try? await viaTikwm(input) { return post }
        throw ClientError.notFound
    }

    private func configDomains() async -> [String] {
        for urlString in ["https://www.moody0100.com/file/242/", "https://m-r.pw/242"] {
            guard let url = URL(string: urlString),
                  let (data, _) = try? await URLSession.shared.data(from: url),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tik = obj["tik"] as? [String], !tik.isEmpty else { continue }
            return tik
        }
        return fallbackDomains
    }

    private func ajaxSearch(domain: String, input: String) async throws -> PostInfo {
        var req = URLRequest(url: URL(string: "https://\(domain)/api/ajaxSearch")!)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.setValue(ua, forHTTPHeaderField: "User-Agent")
        req.timeoutInterval = 25
        let form = ["url": input, "q": input, "URLz": input, "lang": "en", "lang_code": "en"]
        req.httpBody = form.map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? $0.value)" }
            .joined(separator: "&").data(using: .utf8)
        let (data, _) = try await URLSession.shared.data(for: req)
        guard let text = String(data: data, encoding: .utf8) else { return PostInfo() }
        var html = text
        if let jsonData = text.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
           let d = obj["data"] as? String { html = d }
        return parse(html: html)
    }

    private func parse(html: String) -> PostInfo {
        var post = PostInfo()
        var seen = Set<String>()
        let anchorPattern = #"<a[^>]+href="([^"]+)"[^>]*>(.*?)</a>"#
        for m in matches(anchorPattern, in: html) {
            guard m.count == 3 else { continue }
            let href = m[1].replacingOccurrences(of: "&amp;", with: "&")
            let label = stripTags(m[2])
            guard href.hasPrefix("http"), label.lowercased().contains("download"), let url = URL(string: href) else { continue }
            let lower = label.lowercased()
            let kind: LinkKind
            if lower.contains("mp3") || lower.contains("music") { kind = .audio }
            else if lower.contains("image") || lower.contains("photo") || ["jpg", "jpeg", "png", "webp"].contains(url.pathExtension.lowercased()) { kind = .image }
            else { kind = .video }
            if seen.insert(href).inserted { post.links.append(FoundLink(url: url, label: label, kind: kind)) }
        }
        let imgPattern = #"<img[^>]+src="([^"]+)""#
        let imgs = matches(imgPattern, in: html).compactMap { $0.count == 2 ? $0[1].replacingOccurrences(of: "&amp;", with: "&") : nil }
        if post.cover == nil, let first = imgs.first { post.cover = URL(string: first) }
        if post.images.isEmpty {
            for src in imgs where src.contains("tiktokcdn") || src.contains("ibyteimg") {
                guard let url = URL(string: src), seen.insert(src).inserted else { continue }
                if url == post.cover && imgs.count > 1 { continue }
                post.links.append(FoundLink(url: url, label: "Image \(post.images.count + 1)", kind: .image))
            }
        }
        if let h = matches(#"<h3[^>]*>(.*?)</h3>"#, in: html).first, h.count == 2 { post.title = stripTags(h[1]) }
        return post
    }

    private struct TikwmResponse: Decodable {
        struct DataPart: Decodable {
            var play: String?
            var hdplay: String?
            var cover: String?
            var title: String?
            var images: [String]?
            var author: Author?
        }
        struct Author: Decodable { var nickname: String? }
        var data: DataPart?
    }

    private func viaTikwm(_ input: String) async throws -> PostInfo {
        let enc = input.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? input
        var req = URLRequest(url: URL(string: "https://www.tikwm.com/api/?url=\(enc)&hd=1")!)
        req.setValue(ua, forHTTPHeaderField: "User-Agent")
        req.timeoutInterval = 25
        let (data, _) = try await URLSession.shared.data(for: req)
        let res = try JSONDecoder().decode(TikwmResponse.self, from: data)
        guard let d = res.data else { throw ClientError.notFound }
        var post = PostInfo()
        post.title = d.title ?? ""
        post.author = d.author?.nickname ?? ""
        if let cover = d.cover { post.cover = URL(string: cover) }
        if let hd = d.hdplay, let u = URL(string: hd) { post.links.append(FoundLink(url: u, label: "Download HD", kind: .video)) }
        if let play = d.play, let u = URL(string: play), u.absoluteString != d.hdplay { post.links.append(FoundLink(url: u, label: "Download MP4", kind: .video)) }
        for (i, src) in (d.images ?? []).enumerated() {
            if let u = URL(string: src) { post.links.append(FoundLink(url: u, label: "Image \(i + 1)", kind: .image)) }
        }
        return post
    }

    private func matches(_ pattern: String, in text: String) -> [[String]] {
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators, .caseInsensitive]) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return re.matches(in: text, range: range).map { m in
            (0..<m.numberOfRanges).map { i in
                guard let r = Range(m.range(at: i), in: text) else { return "" }
                return String(text[r])
            }
        }
    }

    private func stripTags(_ s: String) -> String {
        var t = s.replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
        for (a, b) in [("&amp;", "&"), ("&quot;", "\""), ("&#39;", "'"), ("&nbsp;", " ")] { t = t.replacingOccurrences(of: a, with: b) }
        return t.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ")
    }
}
