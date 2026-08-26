import Foundation

/// Thin Anthropic Messages API client. Uses Haiku for cost, with hard local
/// rate limits so a stuck quiz loop can't burn the key.
actor ClaudeClient {
    static let shared = ClaudeClient()

    enum ClientError: Error, Equatable {
        case missingKey
        case rateLimited(retryAfter: TimeInterval)
        case dailyCapReached
        case badResponse(status: Int)
        case decodeFailed
    }

    /// Cheapest generally-available chat model. Override via Secrets if needed.
    /// Model IDs are complete without a date suffix — the dated form is a
    /// snapshot alias, not the canonical id.
    private var model: String { Secrets.claudeModel ?? "claude-haiku-4-5" }
    private let host = "https://api.anthropic.com/v1/messages"
    private let session: URLSession

    /// At most one call every 20s, 15 calls per rolling calendar day.
    private var lastCallAt: Date = .distantPast
    private var dayKey: String = ""
    private var callsToday: Int = 0
    private let minInterval: TimeInterval = 20
    private let dailyCap = 15

    init(session: URLSession = .shared) {
        self.session = session
    }

    func interpretGoals(text: String, profile: UserProfile) async throws -> TrainingBrief {
        guard Secrets.hasClaude else { throw ClientError.missingKey }
        try reserveSlot()

        let system = """
        You help LockIn, a personal training + nutrition iOS app, turn a short free-text \
        goal into a compact coaching brief. Reply with ONLY valid JSON (no markdown) matching:
        {
          "summary": "1-2 sentences",
          "priorities": ["...", "..."],
          "sessionEmphases": ["short cue for today's training", "..."],
          "mappedGoalHints": ["fastBowling" and/or "hikingBackpacking" and/or "fatLoss" if relevant],
          "cautions": ["optional safety notes"]
        }
        Be concrete and evidence-minded. Do not invent medical advice. Keep arrays short (≤4).
        """

        let user = """
        Name: \(profile.name.isEmpty ? "athlete" : profile.name)
        Body: \(profile.sex.rawValue), \(profile.age)y, \(Int(profile.heightInches))in, \(Int(profile.currentWeightLbs))→\(Int(profile.goalWeightLbs)) lb, \(profile.goalDirection.rawValue)
        Equipment: \(profile.equipment.map(\.rawValue).joined(separator: ", "))
        Assets: \(profile.gymAssets.map(\.rawValue).sorted().joined(separator: ", "))
        Already selected sports: \(profile.fitnessGoals.map(\.rawValue).joined(separator: ", "))
        Free-text goal:
        \(text)
        """

        let payload: [String: Any] = [
            "model": model,
            "max_tokens": 500,
            "system": system,
            "messages": [["role": "user", "content": user]]
        ]

        var request = URLRequest(url: URL(string: host)!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue(Secrets.claudeAPIKey!, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ClientError.badResponse(status: -1) }
        guard (200..<300).contains(http.statusCode) else { throw ClientError.badResponse(status: http.statusCode) }

        let envelope = try JSONDecoder().decode(AnthropicMessage.self, from: data)
        let textOut = envelope.content.compactMap(\.text).joined()
        guard let jsonData = extractJSON(from: textOut).data(using: .utf8),
              let parsed = try? JSONDecoder().decode(BriefDTO.self, from: jsonData)
        else { throw ClientError.decodeFailed }

        return TrainingBrief(
            summary: parsed.summary,
            priorities: parsed.priorities ?? [],
            sessionEmphases: parsed.sessionEmphases ?? [],
            mappedGoalHints: parsed.mappedGoalHints ?? [],
            cautions: parsed.cautions ?? [],
            generatedAt: Date()
        )
    }

    /// Admission control: the slot is *reserved* here, before the request goes
    /// out, not recorded after it comes back.
    ///
    /// This actor suspends at `await session.data`, so a second caller can run
    /// `checkRateLimit` while the first is still in flight. Booking the call on
    /// the way in is what makes "one every 20s, 15 a day" actually true rather
    /// than "15 concurrent calls, then a limit".
    private func reserveSlot() throws {
        let now = Date()
        let key = dayStamp(now)
        if key != dayKey {
            dayKey = key
            callsToday = 0
        }
        if callsToday >= dailyCap { throw ClientError.dailyCapReached }
        let wait = minInterval - now.timeIntervalSince(lastCallAt)
        if wait > 0 { throw ClientError.rateLimited(retryAfter: wait) }
        lastCallAt = now
        callsToday += 1
    }

    private func dayStamp(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    private func extractJSON(from text: String) -> String {
        if let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}") {
            return String(text[start...end])
        }
        return text
    }
}

private struct AnthropicMessage: Decodable {
    struct Block: Decodable {
        let type: String?
        let text: String?
    }
    let content: [Block]
}

private struct BriefDTO: Decodable {
    let summary: String
    let priorities: [String]?
    let sessionEmphases: [String]?
    let mappedGoalHints: [String]?
    let cautions: [String]?
}
