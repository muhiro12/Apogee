import Foundation

/// Keeps asset requests isolated from API authorization and refuses redirects.
private final class ScreenshotAssetDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

enum ScreenshotUploadValidation {
    static func validate(_ operations: [ScreenshotUploadOperation], byteCount: Int) throws {
        guard !operations.isEmpty, operations.count <= 1_000 else {
            throw ScreenshotError.unsafeUpload
        }
        var offset = 0
        for operation in operations.sorted(by: { $0.offset < $1.offset }) {
            guard operation.offset == offset, operation.length > 0,
                  operation.length <= byteCount - offset else {
                throw ScreenshotError.unsafeUpload
            }
            try validateExpiry(operation)
            offset += operation.length
        }
        guard offset == byteCount else {
            throw ScreenshotError.unsafeUpload
        }
    }

    static func validateExpiry(_ operation: ScreenshotUploadOperation, now: Date = .now) throws {
        guard operation.method == "PUT", operation.url.utf8.count < 16_384,
              let url = URLComponents(string: operation.url), url.scheme == "https",
              let host = url.host?.lowercased(), host.hasSuffix(".apple.com"),
              url.user == nil, url.password == nil, url.fragment == nil,
              url.port == nil || url.port == 443,
              let expirations = url.queryItems?.filter({ $0.name == "Expires" }), expirations.count == 1,
              let text = expirations.first?.value, let expires = TimeInterval(text), expires.isFinite,
              expires > now.timeIntervalSince1970,
              operation.headers.count <= 64 else {
            throw ScreenshotError.unsafeUpload
        }
        let forbidden = ["authorization", "cookie", "host", "content-length", "transfer-encoding"]
        for (name, value) in operation.headers {
            guard !name.isEmpty, name.utf8.count < 128, value.utf8.count < 8_192,
                  !forbidden.contains(name.lowercased()),
                  name.unicodeScalars.allSatisfy({ $0.value > 32 && $0.value < 127 && $0 != ":" }),
                  !value.contains("\r"), !value.contains("\n") else {
                throw ScreenshotError.unsafeUpload
            }
        }
    }

    static func send(_ data: Data, operation: ScreenshotUploadOperation) async throws {
        try Task.checkCancellation()
        try validateExpiry(operation)
        guard data.count == operation.length, let url = URL(string: operation.url) else {
            throw ScreenshotError.unsafeUpload
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 120
        let session = URLSession(configuration: configuration, delegate: ScreenshotAssetDelegate(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.allHTTPHeaderFields = operation.headers
        do {
            let (_, response) = try await session.upload(for: request, from: data)
            guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode) else {
                throw ScreenshotError.unsafeUpload
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch {
            throw ScreenshotError.unsafeUpload
        }
    }
}
