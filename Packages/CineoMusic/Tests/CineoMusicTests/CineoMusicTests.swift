import Foundation
import XCTest
@testable import CineoMusic

final class CineoMusicTests: XCTestCase {
    func testManualConfigurationCompilesIntoRealAceRequest() throws {
        let plan = CineoMusicSettings(caption: "Minimal synth instrumental", bpm: 112,
                                      duration: 42, keyscale: "A minor", seed: 7,
                                      volume: 0.3, offset: 2, fadeIn: 0.5, fadeOut: 2)
        let data = try plan.aceRequest()
        let dict = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(dict["caption"] as? String, "Minimal synth instrumental")
        XCTAssertEqual(dict["lyrics"] as? String, "[Instrumental]")
        XCTAssertEqual(dict["bpm"] as? Int, 112)
        XCTAssertEqual(dict["duration"] as? Double, 42)
        XCTAssertEqual(dict["seed"] as? Int64, 7)
        XCTAssertEqual(dict["output_format"] as? String, "wav16")
        XCTAssertEqual(dict["use_cot_caption"] as? Bool, false)
    }

    func testRejectInvalidConfigurationsAndUnsafeAssetNames() {
        XCTAssertThrowsError(try CineoMusicSettings(caption: "").validate())
        XCTAssertThrowsError(try CineoMusicSettings(bpm: 500).validate())
        XCTAssertThrowsError(try CineoMusicSettings(duration: 9).validate())
        XCTAssertThrowsError(try CineoMusicSettings(offset: 12).validate(videoDuration: 8))
        XCTAssertThrowsError(try CineoMusicAsset(fileName: "../escape.wav",
                  settings: CineoMusicSettings()).validate())
    }

    func testACEClientOnlyAllowsLoopback() {
        XCTAssertNoThrow(try CineoACEClient(baseURL: URL(string: "http://127.0.0.1:8080")!))
        XCTAssertThrowsError(try CineoACEClient(baseURL: URL(string: "https://music.example.com")!))
        XCTAssertThrowsError(try CineoACEClient(baseURL: URL(string: "http://10.0.0.1:8080")!))
    }

    func testExtractActualWavFromMultipartNotLatent() throws {
        let wav = Data("RIFF1234WAVEdata".utf8)
        let boundary = "ace-batch-boundary"
        var response = Data(("--" + boundary + "\r\nContent-Type: audio/wav\r\n\r\n").utf8)
        response.append(wav)
        response.append(Data(("\r\n--" + boundary + "\r\nContent-Type: application/octet-stream\r\n\r\n").utf8))
        response.append(Data([0, 1, 2, 3]))
        response.append(Data(("\r\n--" + boundary + "--\r\n").utf8))
        let extracted = try CineoACEClient.wavPayload(response,
                            contentType: "multipart/mixed; boundary=ace-batch-boundary")
        XCTAssertEqual(extracted, wav)
    }
}
