import Foundation
import HTTPTypes
import OpenAPIRuntime

/// Keeps generated response decoding while following Apple's opaque pagination links.
struct AppStoreConnectPageMiddleware: ClientMiddleware {
    var nextPageURL: String?

    func intercept(
        _ request: HTTPRequest,
        body: HTTPBody?,
        baseURL: URL,
        operationID: String,
        next: @concurrent @Sendable (HTTPRequest, HTTPBody?, URL) async throws -> (HTTPResponse, HTTPBody?)
    ) async throws -> (HTTPResponse, HTTPBody?) {
        guard let nextPageURL else {
            return try await next(request, body, baseURL)
        }

        guard
            request.method == .get,
            let target = URLComponents(string: nextPageURL),
            let origin = URLComponents(url: baseURL, resolvingAgainstBaseURL: true),
            let original = URLComponents(string: request.path ?? ""),
            target.scheme == origin.scheme,
            target.host == origin.host,
            target.port == origin.port,
            target.user == nil, target.password == nil, target.fragment == nil,
            target.percentEncodedPath == original.percentEncodedPath,
            (original.queryItems ?? []).filter({ item in
                item.name.hasPrefix("filter[") || item.name == "include"
            }).allSatisfy({ item in
                target.queryItems?.contains(item) == true
            })
        else {
            throw ApogeeError.unexpectedAPIResponse("An unsafe or out-of-scope pagination link was returned.")
        }

        var request = request
        request.path = target.percentEncodedPath + (target.percentEncodedQuery.map { "?\($0)" } ?? "")
        return try await next(request, body, baseURL)
    }
}
