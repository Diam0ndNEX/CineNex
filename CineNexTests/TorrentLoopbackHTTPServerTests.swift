import XCTest
@testable import CineNex

final class TorrentLoopbackHTTPServerTests: XCTestCase {
    private actor MemoryReader: TorrentByteReader {
        private let bytes: Data

        init(_ bytes: Data) {
            self.bytes = bytes
        }

        func read(offset: Int64, length: Int) async throws -> Data {
            guard offset >= 0, length >= 0, offset <= Int64(bytes.count),
                  offset + Int64(length) <= Int64(bytes.count) else {
                throw TorrentStreamingError.invalidRead
            }
            let start = Int(offset)
            return bytes.subdata(in: start..<(start + length))
        }
    }

    private struct FakeEngine: TorrentPlaybackEngine {
        let file: TorrentPreparedFile

        func prepareFiles(for request: PlaybackSourceRequest) async throws -> [TorrentPreparedFile] {
            [file]
        }

        func stop() async {}
    }

    func testProviderReturnsLoopbackURLAndServesPartialBytes() async throws {
        let expected = Data("0123456789abcdefghijklmnopqrstuvwxyz".utf8)
        let file = TorrentPreparedFile(
            id: "movie-file",
            title: "Test Movie",
            fileName: "movie.mp4",
            length: Int64(expected.count),
            contentType: "video/mp4",
            reader: MemoryReader(expected)
        )
        let server = TorrentLoopbackHTTPServer()
        let provider = TorrentPlaybackProvider(engine: FakeEngine(file: file), server: server)
        defer { server.stop() }

        let request = PlaybackSourceRequest(title: "Test Movie", mediaKind: .movie, tmdbID: 123)
        let sources = try await provider.findSources(for: request)
        XCTAssertEqual(sources.count, 1)
        let source = try XCTUnwrap(sources.first)
        XCTAssertEqual(source.url.scheme, "http")
        XCTAssertEqual(source.url.host, "127.0.0.1")

        var urlRequest = URLRequest(url: source.url)
        urlRequest.setValue("bytes=5-12", forHTTPHeaderField: "Range")
        let (data, response) = try await URLSession.shared.data(for: urlRequest)
        let http = try XCTUnwrap(response as? HTTPURLResponse)
        XCTAssertEqual(http.statusCode, 206)
        XCTAssertEqual(http.value(forHTTPHeaderField: "Content-Range"), "bytes 5-12/36")
        XCTAssertEqual(data, expected.subdata(in: 5..<13))
    }

    func testHeadRequestReturnsMetadataWithoutBody() async throws {
        let expected = Data("sample-video".utf8)
        let file = TorrentPreparedFile(
            id: "head-file",
            title: "HEAD Test",
            fileName: "head.mp4",
            length: Int64(expected.count),
            contentType: "video/mp4",
            reader: MemoryReader(expected)
        )
        let server = TorrentLoopbackHTTPServer()
        let provider = TorrentPlaybackProvider(engine: FakeEngine(file: file), server: server)
        defer { server.stop() }
        let sources = try await provider.findSources(for: PlaybackSourceRequest(title: "HEAD Test", mediaKind: .movie))
        let source = try XCTUnwrap(sources.first)
        var request = URLRequest(url: source.url)
        request.httpMethod = "HEAD"
        request.setValue("bytes=2-4", forHTTPHeaderField: "Range")
        let (data, response) = try await URLSession.shared.data(for: request)
        let http = try XCTUnwrap(response as? HTTPURLResponse)
        XCTAssertEqual(http.statusCode, 200)
        XCTAssertEqual(http.value(forHTTPHeaderField: "Content-Length"), String(expected.count))
        XCTAssertTrue(data.isEmpty)
    }

    func testInvalidBearerTokenDoesNotExposeFile() async throws {
        let expected = Data("private".utf8)
        let file = TorrentPreparedFile(
            id: "private-file",
            title: "Private",
            fileName: "private.mp4",
            length: Int64(expected.count),
            contentType: "video/mp4",
            reader: MemoryReader(expected)
        )
        let server = TorrentLoopbackHTTPServer()
        let provider = TorrentPlaybackProvider(engine: FakeEngine(file: file), server: server)
        defer { server.stop() }
        let sources = try await provider.findSources(for: PlaybackSourceRequest(title: "Private", mediaKind: .movie))
        let source = try XCTUnwrap(sources.first)
        var components = try XCTUnwrap(URLComponents(url: source.url, resolvingAgainstBaseURL: false))
        components.path = "/v1/invalid-token/private-file"
        let invalidURL = try XCTUnwrap(components.url)
        let (_, response) = try await URLSession.shared.data(from: invalidURL)
        let http = try XCTUnwrap(response as? HTTPURLResponse)
        XCTAssertEqual(http.statusCode, 404)
    }
}
