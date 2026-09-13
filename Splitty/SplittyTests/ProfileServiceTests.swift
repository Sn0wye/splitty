import Foundation
import Testing
@testable import Splitty

struct ProfileServiceTests {
    @Test func storageUploadUsesOnlyThePinnedContentType() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [UploadURLProtocol.self]
        let service = ProfileService(uploadSession: URLSession(configuration: configuration))
        let slot = AvatarUpload(
            key: "avatars/1/photo.jpg",
            uploadURL: URL(string: "https://storage.example/upload")!,
            contentType: "image/jpeg",
            maxBytes: 100
        )

        try await service.uploadAvatar(Data([1, 2, 3]), to: slot)

        let request = try #require(UploadURLProtocol.lastRequest)
        #expect(request.httpMethod == "PUT")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "image/jpeg")
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
    }
}

private final class UploadURLProtocol: URLProtocol, @unchecked Sendable {
    static var lastRequest: URLRequest?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lastRequest = request
        client?.urlProtocol(
            self,
            didReceive: HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!,
            cacheStoragePolicy: .notAllowed
        )
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
