import Foundation

public struct HTTPReply: Sendable {
    public let data: Data
    public let status: Int
    public let retryAfter: String?
    public init(data: Data, status: Int, retryAfter: String? = nil) {
        self.data = data; self.status = status; self.retryAfter = retryAfter
    }
}

public protocol ManagedTransport: Sendable {
    func api(path: String, method: String, body: Data?, key: String) async throws -> HTTPReply
    func upload(file: URL, to url: URL) async throws -> HTTPReply
}

public enum ManagedFailure: String, Error, Sendable {
    case consentRequired, busy, invalidResponse, invalidURL, missingKey, unsafePath
    case sourceChanged, partialResult, existingRun, localStorage, audioTooLong
}

final class RejectRedirects: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

public struct PyannoteTransport: ManagedTransport {
    private let apiSession: URLSession
    private let uploadSession: URLSession
    public init() {
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil
        config.urlCredentialStorage = nil
        config.urlCache = nil
        config.timeoutIntervalForRequest = 60
        apiSession = URLSession(configuration: config, delegate: RejectRedirects(), delegateQueue: nil)
        let upload = URLSessionConfiguration.ephemeral
        upload.httpCookieStorage = nil
        upload.urlCredentialStorage = nil
        upload.urlCache = nil
        upload.timeoutIntervalForRequest = 60
        upload.timeoutIntervalForResource = 3600
        uploadSession = URLSession(configuration: upload, delegate: RejectRedirects(), delegateQueue: nil)
    }
    init(apiSession: URLSession, uploadSession: URLSession) { self.apiSession = apiSession; self.uploadSession = uploadSession }

    static func apiRequest(path: String, method: String, body: Data?, key: String) throws -> URLRequest {
        guard path == "/v1/media/input" || path == "/v1/diarize" || path.hasPrefix("/v1/jobs/"),
              !path.contains("?"), !path.contains("#"), !path.contains(".."),
              !key.isEmpty, !key.contains("\n"), !key.contains("\r"),
              let url = URL(string: "https://api.pyannote.ai" + path) else { throw ManagedFailure.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        request.setValue("Bearer " + key, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return request
    }
    static func uploadRequest(_ url: URL) throws -> URLRequest {
        guard url.scheme == "https", let host = url.host, !host.isEmpty,
              url.user == nil, url.password == nil, url.fragment == nil else { throw ManagedFailure.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        return request
    }
    public func api(path: String, method: String, body: Data?, key: String) async throws -> HTTPReply {
        let request = try Self.apiRequest(path: path, method: method, body: body, key: key)
        let (data, response) = try await apiSession.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw ManagedFailure.invalidResponse }
        return HTTPReply(data: data, status: response.statusCode, retryAfter: response.value(forHTTPHeaderField: "Retry-After"))
    }
    public func upload(file: URL, to url: URL) async throws -> HTTPReply {
        let (data, response) = try await uploadSession.upload(for: Self.uploadRequest(url), fromFile: file)
        guard let response = response as? HTTPURLResponse else { throw ManagedFailure.invalidResponse }
        return HTTPReply(data: data, status: response.statusCode, retryAfter: response.value(forHTTPHeaderField: "Retry-After"))
    }
}

public enum PollDelay {
    public static func seconds(retryAfter: String?, attempt: Int, now: Date = Date(), jitter: Double = 1) -> Double {
        if let retryAfter {
            if let seconds = Double(retryAfter), seconds.isFinite, seconds >= 0 { return seconds }
            let parser = DateFormatter()
            parser.locale = Locale(identifier: "en_US_POSIX")
            parser.timeZone = TimeZone(secondsFromGMT: 0)
            parser.dateFormat = "EEE, dd MMM yyyy HH:mm:ss z"
            if let date = parser.date(from: retryAfter) { return max(0, date.timeIntervalSince(now)) }
        }
        return min(60, 10 * pow(2, Double(min(3, max(0, attempt))))) * min(1.2, max(0.8, jitter))
    }
}
