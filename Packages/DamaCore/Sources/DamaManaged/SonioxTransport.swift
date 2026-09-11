import Foundation

public protocol SonioxTransporting: Sendable {
    func api(path: String, method: String, body: Data?, key: String) async throws -> HTTPReply
    func upload(file: URL, key: String) async throws -> HTTPReply
}

public struct SonioxTransport: SonioxTransporting {
    private let session: URLSession
    public init() {
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil; config.urlCredentialStorage = nil; config.urlCache = nil
        config.timeoutIntervalForRequest = 60; config.timeoutIntervalForResource = 3600
        session = URLSession(configuration: config, delegate: RejectRedirects(), delegateQueue: nil)
    }
    init(session: URLSession) { self.session = session }
    static func request(path: String, method: String, body: Data?, key: String) throws -> URLRequest {
        let parts = path.split(separator: "/", omittingEmptySubsequences: false)
        let validGet = parts.count >= 4 && parts[0] == "" && parts[1] == "v1" && parts[2] == "transcriptions" &&
            UUID(uuidString: String(parts[3])) != nil && (parts.count == 4 || (parts.count == 5 && parts[4] == "transcript"))
        guard (method == "POST" && ["/v1/files", "/v1/transcriptions"].contains(path)) || (method == "GET" && validGet),
              !key.isEmpty, !key.contains("\n"), !key.contains("\r"),
              let url = URL(string: "https://api.soniox.com" + path) else { throw ManagedFailure.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = method; request.httpBody = body
        request.setValue("Bearer " + key, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return request
    }
    private func reply(_ data: Data, _ response: URLResponse) throws -> HTTPReply {
        guard let response = response as? HTTPURLResponse else { throw ManagedFailure.invalidResponse }
        return HTTPReply(data: data, status: response.statusCode, retryAfter: response.value(forHTTPHeaderField: "Retry-After"))
    }
    public func api(path: String, method: String, body: Data?, key: String) async throws -> HTTPReply {
        let (data, response) = try await session.data(for: Self.request(path: path, method: method, body: body, key: key))
        return try reply(data, response)
    }
    // Stream the multipart body to a private temporary file; never load an hours-long recording into RAM.
    static func multipart(file: URL, destination: URL, boundary: String) throws {
        guard file.isFileURL, file.resolvingSymlinksInPath().path == file.path else { throw ManagedFailure.unsafePath }
        guard FileManager.default.createFile(atPath: destination.path, contents: nil, attributes: [.posixPermissions: 0o600]) else {
            throw ManagedFailure.localStorage
        }
        let output = try FileHandle(forWritingTo: destination)
        defer { try? output.close() }
        let input = try FileHandle(forReadingFrom: file)
        defer { try? input.close() }
        try output.write(contentsOf: Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"analysis.wav\"\r\nContent-Type: audio/wav\r\n\r\n".utf8))
        while let chunk = try input.read(upToCount: 1_048_576), !chunk.isEmpty {
            try Task.checkCancellation()
            try output.write(contentsOf: chunk)
        }
        try output.write(contentsOf: Data("\r\n--\(boundary)--\r\n".utf8))
    }
    public func upload(file: URL, key: String) async throws -> HTTPReply {
        var request = try Self.request(path: "/v1/files", method: "POST", body: nil, key: key)
        let boundary = "DAMA-\(UUID().uuidString)"
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("dama-upload-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: directory) }
        let body = directory.appendingPathComponent("multipart")
        try Self.multipart(file: file, destination: body, boundary: boundary)
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        let (data, response) = try await session.upload(for: request, fromFile: body)
        return try reply(data, response)
    }
}
