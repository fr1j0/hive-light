import Foundation

public enum SessionStatus: String, Codable, Sendable {
    case running
    case waiting
    case attention
    case handoff
    case idle
    case error
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
    /// What the session is blocked on, for notification bodies — the pending
    /// question / ask sentence / permission message (#80). Set by the hook
    /// only for needs-you statuses; ≤140 chars.
    public var detail: String?
    /// Context-window usage 0...1 measured at the last Stop (#96): the last
    /// assistant entry's usage tokens over the model's window. Persists
    /// across transcript-less events; nil until first measured.
    public var contextFraction: Double?
    /// Git branch of the session's cwd at the last hook event (#82); nil for
    /// non-repos, detached HEAD, and sessions written by older hooks.
    public var branch: String?
    /// Model id of the session's last assistant turn (#105); nil until a
    /// transcript-bearing event, and for sessions written by older hooks.
    public var model: String?
    /// When the session's first hook event was seen — the stable sort key for
    /// the panel (rows hold terminal-tab order; status never moves them). Set
    /// once by the hook, sticky across all later writes; nil for sessions
    /// written by older hooks (sort falls back to updatedAt).
    public var startedAt: Date?

    public init(sessionID: String, status: SessionStatus, project: String, cwd: String,
                updatedAt: Date, transcriptPath: String? = nil,
                termProgram: String? = nil, tty: String? = nil, termSessionId: String? = nil,
                focusURL: String? = nil, detail: String? = nil, contextFraction: Double? = nil, branch: String? = nil, model: String? = nil,
                startedAt: Date? = nil) {
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
        self.detail = detail
        self.contextFraction = contextFraction
        self.branch = branch
        self.model = model
        self.startedAt = startedAt
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
        case detail
        case contextFraction = "context_fraction"
        case branch
        case model
        case startedAt = "started_at"
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
