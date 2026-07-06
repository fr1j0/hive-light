import Foundation

public struct HookPayload: Codable, Sendable {
    public let sessionID: String
    public let hookEventName: String
    public let cwd: String?
    public let message: String?
    public let transcriptPath: String?

    public init(sessionID: String, hookEventName: String, cwd: String?, message: String?, transcriptPath: String? = nil) {
        self.sessionID = sessionID
        self.hookEventName = hookEventName
        self.cwd = cwd
        self.message = message
        self.transcriptPath = transcriptPath
    }

    enum CodingKeys: String, CodingKey {
        case sessionID = "session_id"
        case hookEventName = "hook_event_name"
        case cwd
        case message
        case transcriptPath = "transcript_path"
    }
}
