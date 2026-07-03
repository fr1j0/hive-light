import Foundation

public enum SessionStatus: String, Codable, Sendable {
    case running
    case waiting
    case attention
    case handoff
    case idle
    case error
    case done
}

public struct Session: Codable, Sendable, Equatable {
    public let sessionID: String
    public var status: SessionStatus
    public var project: String
    public var cwd: String
    public var updatedAt: Date
    public var transcriptPath: String?
    // Hosting-terminal identity, for focusing the session on click (#22, #62).
    public var termProgram: String?
    public var tty: String?
    public var termSessionId: String?
    public var focusURL: String?

    public init(sessionID: String, status: SessionStatus, project: String, cwd: String,
                updatedAt: Date, transcriptPath: String? = nil,
                termProgram: String? = nil, tty: String? = nil, termSessionId: String? = nil,
                focusURL: String? = nil) {
        self.sessionID = sessionID
        self.status = status
        self.project = project
        self.cwd = cwd
        self.updatedAt = updatedAt
        self.transcriptPath = transcriptPath
        self.termProgram = termProgram
        self.tty = tty
        self.termSessionId = termSessionId
        self.focusURL = focusURL
    }

    enum CodingKeys: String, CodingKey {
        case sessionID = "session_id"
        case status
        case project
        case cwd
        case updatedAt = "updated_at"
        case transcriptPath = "transcript_path"
        case termProgram = "term_program"
        case tty
        case termSessionId = "term_session_id"
        case focusURL = "focus_url"
    }
}

public enum ClaudeLightJSON {
    public static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.withoutEscapingSlashes]
        return e
    }()

    public static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}
