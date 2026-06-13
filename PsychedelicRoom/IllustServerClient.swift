import Foundation

// MARK: - DTOs

struct IllustServerAsset: Codable, Identifiable, Sendable, Hashable {
    let hash: String
    let mediaType: String
    let ext: String
    let width: Int?
    let height: Int?
    let fileSize: Int
    let title: String?
    let postedAt: Int?
    let addedAt: Int
    let rating: String
    let durationSeconds: Double?
    let frameCount: Int?
    let codec: String?
    let posterHash: String?
    let sourceType: String?
    let sourceId: String?
    let sourceUserId: String?
    let sourceUserName: String?
    /// このアセットに登録されたタグ ("namespace:name" 文字列の配列)。
    /// サーバが /api/search のレスポンスに "tags" を含めた場合のみ入る (未対応サーバでは nil)。
    let tags: [String]?

    var id: String { hash }

    /// 表示用ラベル: 「作者名：ファイル名」形式。
    /// 作者名 (`sourceUserName`) と title が両方あれば連結。
    /// 片方しか無ければ単独で。どちらも空なら hash 12 桁の短縮形。
    var displayName: String {
        let userTrimmed = (sourceUserName ?? "").trimmingCharacters(in: .whitespaces)
        let titleTrimmed = (title ?? "").trimmingCharacters(in: .whitespaces)
        let hasUser = !userTrimmed.isEmpty
        let hasTitle = !titleTrimmed.isEmpty
        if hasUser, hasTitle { return "\(userTrimmed)：\(titleTrimmed)" }
        if hasTitle { return titleTrimmed }
        if hasUser { return userTrimmed }
        return String(hash.prefix(12))
    }

    enum CodingKeys: String, CodingKey {
        case hash
        case mediaType = "media_type"
        case ext, width, height
        case fileSize = "file_size"
        case title
        case postedAt = "posted_at"
        case addedAt = "added_at"
        case rating
        case durationSeconds = "duration_seconds"
        case frameCount = "frame_count"
        case codec
        case posterHash = "poster_hash"
        case sourceType = "source_type"
        case sourceId = "source_id"
        case sourceUserId = "source_user_id"
        case sourceUserName = "source_user_name"
        case tags
    }
}

struct IllustServerPage: Codable, Sendable {
    let total: Int
    let limit: Int
    let offset: Int
    let hasMore: Bool

    enum CodingKeys: String, CodingKey {
        case total, limit, offset
        case hasMore = "has_more"
    }
}

struct IllustServerSearchResponse: Codable, Sendable {
    let items: [IllustServerAsset]
    let page: IllustServerPage
}

struct IllustServerTag: Codable, Identifiable, Sendable, Hashable {
    let id: Int
    let namespace: String
    let name: String
    let nameJa: String?
    let count: Int

    enum CodingKeys: String, CodingKey {
        case id, namespace, name, count
        case nameJa = "name_ja"
    }
}

struct IllustServerHealth: Codable, Sendable {
    let status: String
    let dbOk: Bool
    let journalMode: String
    let libRootExists: Bool
    let version: String?

    enum CodingKeys: String, CodingKey {
        case status, version
        case dbOk = "db_ok"
        case journalMode = "journal_mode"
        case libRootExists = "lib_root_exists"
    }
}

// MARK: - Errors

enum IllustServerError: LocalizedError {
    case invalidHost
    case requestFailed(Int)
    case decodingFailed(Error)
    case transportError(Error)

    var errorDescription: String? {
        switch self {
        case .invalidHost:
            return "サーバ URL が無効です"
        case .requestFailed(let code):
            return "サーバエラー (HTTP \(code))"
        case .decodingFailed(let err):
            return "レスポンス解析失敗: \(err.localizedDescription)"
        case .transportError(let err):
            return "通信失敗: \(err.localizedDescription)"
        }
    }
}

// MARK: - Client

final class IllustServerClient: Sendable {
    let baseURL: URL
    private let session: URLSession

    init(baseURL: URL) {
        self.baseURL = baseURL
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 20
        config.timeoutIntervalForResource = 60
        config.waitsForConnectivity = false
        self.session = URLSession(configuration: config)
    }

    /// `"http://100.64.0.5:8080"` のようなホスト文字列からクライアントを構築。
    /// scheme なしの `"100.64.0.5:8080"` も `http://` 補完して受け付ける。
    /// 末尾 `/` および末尾の `/api` パスは正規化して除去する。
    static func from(host: String) -> IllustServerClient? {
        var trimmed = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // scheme 補完
        if !trimmed.lowercased().hasPrefix("http://") && !trimmed.lowercased().hasPrefix("https://") {
            trimmed = "http://" + trimmed
        }

        // 末尾の余計なパス・スラッシュを掃除
        while trimmed.hasSuffix("/") { trimmed.removeLast() }
        if trimmed.lowercased().hasSuffix("/api") { trimmed.removeLast(4) }

        guard let url = URL(string: trimmed),
              let scheme = url.scheme, (scheme == "http" || scheme == "https"),
              url.host != nil
        else { return nil }
        return IllustServerClient(baseURL: url)
    }

    // MARK: URL helpers (生メディア配信は URL 直構築で十分)

    func mediaURL(hash: String) -> URL {
        url(forPath: "/media/\(hash)", query: nil) ?? baseURL
    }

    func thumbURL(hash: String) -> URL {
        url(forPath: "/thumb/\(hash)", query: nil) ?? baseURL
    }

    // MARK: Endpoints

    func health() async throws -> IllustServerHealth {
        try await getJSON(path: "api/health")
    }

    /// タグ AND 検索。`tag` は `"namespace:name"` または `"name"`。
    /// `after` / `before` は unix epoch (秒)、`sort` は `"posted_at_desc" | "posted_at_asc" | "added_at_desc"`。
    func search(
        tags: [String] = [],
        ratings: [String] = [],
        mediaType: String? = nil,
        after: Int? = nil,
        before: Int? = nil,
        sort: String? = nil,
        limit: Int = 60,
        offset: Int = 0
    ) async throws -> IllustServerSearchResponse {
        var items: [URLQueryItem] = []
        for t in tags {
            items.append(URLQueryItem(name: "tag", value: t))
        }
        for r in ratings {
            items.append(URLQueryItem(name: "rating", value: r))
        }
        if let mt = mediaType {
            items.append(URLQueryItem(name: "media_type", value: mt))
        }
        if let after = after {
            items.append(URLQueryItem(name: "after", value: String(after)))
        }
        if let before = before {
            items.append(URLQueryItem(name: "before", value: String(before)))
        }
        if let sort = sort {
            items.append(URLQueryItem(name: "sort", value: sort))
        }
        items.append(URLQueryItem(name: "limit", value: String(limit)))
        items.append(URLQueryItem(name: "offset", value: String(offset)))
        return try await getJSON(path: "api/search", query: items)
    }

    func suggestTags(query: String, limit: Int = 20) async throws -> [IllustServerTag] {
        let items: [URLQueryItem] = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "limit", value: String(limit)),
        ]
        return try await getJSON(path: "api/tags/suggest", query: items)
    }

    func popularTags(namespace: String? = nil, limit: Int = 50) async throws -> [IllustServerTag] {
        var items: [URLQueryItem] = [
            URLQueryItem(name: "limit", value: String(limit)),
        ]
        if let ns = namespace {
            items.append(URLQueryItem(name: "namespace", value: ns))
        }
        return try await getJSON(path: "api/tags/popular", query: items)
    }

    // MARK: Private

    /// baseURL + path を URLComponents 経由で安全に結合する。
    /// path は先頭 `/` 必須 (relative path 扱いの曖昧さを排除)。
    private func url(forPath path: String, query: [URLQueryItem]?) -> URL? {
        guard var comps = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            return nil
        }
        let basePath = comps.path.hasSuffix("/") ? String(comps.path.dropLast()) : comps.path
        let suffix = path.hasPrefix("/") ? path : "/" + path
        comps.path = basePath + suffix
        if let q = query, !q.isEmpty {
            comps.queryItems = q
        }
        return comps.url
    }

    private func getJSON<T: Decodable>(path: String, query: [URLQueryItem]? = nil) async throws -> T {
        guard let requestURL = url(forPath: path, query: query) else {
            throw IllustServerError.invalidHost
        }
        do {
            let (data, response) = try await session.data(from: requestURL)
            guard let http = response as? HTTPURLResponse else {
                print("[IllustServerClient] non-HTTP response from \(requestURL)")
                throw IllustServerError.requestFailed(-1)
            }
            guard (200..<300).contains(http.statusCode) else {
                print("[IllustServerClient] HTTP \(http.statusCode) from \(requestURL)")
                throw IllustServerError.requestFailed(http.statusCode)
            }
            do {
                return try JSONDecoder().decode(T.self, from: data)
            } catch {
                print("[IllustServerClient] decode error from \(requestURL): \(error)")
                throw IllustServerError.decodingFailed(error)
            }
        } catch let e as IllustServerError {
            throw e
        } catch {
            print("[IllustServerClient] transport error from \(requestURL): \(error)")
            throw IllustServerError.transportError(error)
        }
    }
}
