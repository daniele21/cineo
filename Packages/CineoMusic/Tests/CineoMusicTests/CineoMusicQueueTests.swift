import Foundation
import XCTest
@testable import CineoMusic

final class CineoMusicQueueTests: XCTestCase {
    let settings = CineoMusicSettings()

    func testRecoveredOutputCanCompleteInterruptedQuit() throws {
        var job = try CineoMusicQueueJob(kind: .generation,
            originVideoPath: "/tmp/video.mp4", title: "test",
            settings: CineoMusicSettings(), destinationPath: "/tmp/result.wav")
        job.phase = .interrupted
        job.recoverAfterAppRestart(outputExists: true)
        XCTAssertEqual(job.phase, .ready)
        XCTAssertNil(job.checkpoint)
    }

    func testCheckpointMustNotBeAutomaticallyReusedAfterAppRestart() throws {
        var job = try CineoMusicQueueJob(kind: .generation,
            originVideoPath: "/tmp/video.mp4", title: "test",
            settings: CineoMusicSettings(), destinationPath: "/tmp/result.wav")
        job.phase = .running
        job.checkpoint = try CineoACEJobCheckpoint(stage: .synth, remoteID: "abc123")
        job.recoverAfterAppRestart(outputExists: false)
        job.invalidateUnverifiedRemoteCheckpoint()
        XCTAssertEqual(job.phase, .interrupted)
        XCTAssertNil(job.checkpoint)
    }

    func testQueueJobsRoundTripAndResumeKnownServerJob() throws {
        var job = try CineoMusicQueueJob(
            kind: .generation, originVideoPath: "/tmp/video.mp4",
            title: "Demo", settings: settings, destinationPath: "/tmp/job.wav")
        job.phase = .running
        job.checkpoint = try CineoACEJobCheckpoint(stage: .synth, remoteID: "123")
        let json = try JSONEncoder().encode([job])
        var recovered = try XCTUnwrap(JSONDecoder().decode([CineoMusicQueueJob].self, from: json).first)
        recovered.recoverAfterAppRestart(outputExists: false)
        XCTAssertEqual(recovered.phase, .queued)
        XCTAssertEqual(recovered.checkpoint?.remoteID, "123")
    }

    func testUnknownSubmissionMustNotAutomaticallyDuplicateRequest() throws {
        var job = try CineoMusicQueueJob(
            kind: .generation, originVideoPath: "/tmp/video.mp4",
            title: "Demo", settings: settings, destinationPath: "/tmp/new.wav")
        job.phase = .running
        job.recoverAfterAppRestart(outputExists: false)
        XCTAssertEqual(job.phase, .interrupted)
    }

    func testCompletedFileIsNeverLostSilently() throws {
        var job = try CineoMusicQueueJob(
            kind: .generation, originVideoPath: "/tmp/video.mp4",
            title: "Demo", settings: settings, destinationPath: "/tmp/new.wav")
        job.phase = .ready
        job.recoverAfterAppRestart(outputExists: false)
        XCTAssertEqual(job.phase, .failed)
    }

    func testUnsafeJobIDsRejected() {
        XCTAssertThrowsError(try CineoACEJobCheckpoint(stage: .synth, remoteID: "hello/world"))
        XCTAssertThrowsError(try CineoACEJobCheckpoint(stage: .synth, remoteID: ""))
    }
}
