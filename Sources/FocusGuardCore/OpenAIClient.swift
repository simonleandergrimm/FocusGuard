import Foundation

public enum OpenAIClientError: LocalizedError {
    case invalidResponse
    case refusal(String)
    case api(String)

    public var errorDescription: String? {
        switch self {
        case .invalidResponse: "The model returned an unreadable plan."
        case .refusal(let message): message
        case .api(let message): message
        }
    }
}

public struct OpenAIClient: Sendable {
    private static let maximumRequestAttempts = 3

    public let apiKey: String
    public let model: String

    public init(apiKey: String, model: String = "gpt-5.6-terra") {
        self.apiKey = apiKey
        self.model = model
    }

    public func draftPlan(
        from prompt: String,
        mode: PlanDraftMode = .oneTime,
        defaultStrictness: Strictness = .locked,
        now: Date = Date(),
        timeZone: TimeZone = .current
    ) async throws -> LLMBlockDraft {
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/responses")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 60

        let systemPrompt = Self.systemPrompt(
            mode: mode,
            defaultStrictness: defaultStrictness,
            now: now,
            timeZone: timeZone
        )
        var body: [String: Any] = [
            "model": model,
            "input": [
                [
                    "role": "system",
                    "content": [["type": "input_text", "text": systemPrompt]],
                ],
                [
                    "role": "user",
                    "content": [["type": "input_text", "text": prompt]],
                ],
            ],
            "text": [
                "format": [
                    "type": "json_schema",
                    "name": "focus_guard_plan",
                    "strict": true,
                    "schema": Self.responseSchema(mode: mode),
                ],
            ],
            "max_output_tokens": 3_000,
        ]
        if model.hasPrefix("gpt-5") {
            body["reasoning"] = ["effort": "medium"]
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let session = Self.makeSession()
        defer { session.invalidateAndCancel() }
        let (data, response) = try await Self.dataWithRetry(for: request, session: session)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenAIClientError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            if let envelope = try? JSONDecoder().decode(APIErrorEnvelope.self, from: data) {
                throw OpenAIClientError.api(envelope.error.message)
            }
            throw OpenAIClientError.api("OpenAI returned HTTP \(httpResponse.statusCode).")
        }

        let envelope = try JSONDecoder().decode(ResponseEnvelope.self, from: data)
        if let refusal = envelope.output.compactMap({ $0.content }).flatMap({ $0 }).first(where: { $0.type == "refusal" })?.refusal {
            throw OpenAIClientError.refusal(refusal)
        }

        guard let text = envelope.output
            .compactMap({ $0.content })
            .flatMap({ $0 })
            .first(where: { $0.type == "output_text" })?
            .text?
            .data(using: .utf8)
        else {
            if envelope.status == "incomplete" {
                let reason = envelope.incompleteDetails?.reason ?? "an unknown reason"
                throw OpenAIClientError.api("The model stopped before completing the plan (\(reason)). Please try again.")
            }
            throw OpenAIClientError.invalidResponse
        }

        return try JSONDecoder().decode(LLMBlockDraft.self, from: text)
    }

    private static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.waitsForConnectivity = true
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 90
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        return URLSession(configuration: configuration)
    }

    private static func dataWithRetry(
        for request: URLRequest,
        session: URLSession
    ) async throws -> (Data, URLResponse) {
        for attempt in 1...maximumRequestAttempts {
            do {
                let result = try await session.data(for: request)
                if let response = result.1 as? HTTPURLResponse,
                   OpenAIRetryPolicy.shouldRetry(statusCode: response.statusCode),
                   attempt < maximumRequestAttempts {
                    let delay = OpenAIRetryPolicy.delay(
                        afterAttempt: attempt,
                        retryAfter: response.value(forHTTPHeaderField: "Retry-After")
                    )
                    try await Task.sleep(for: .seconds(delay))
                    continue
                }
                return result
            } catch is CancellationError {
                throw CancellationError()
            } catch let error as URLError {
                guard error.code != .cancelled else { throw error }
                guard OpenAIRetryPolicy.shouldRetry(urlErrorCode: error.code) else {
                    throw OpenAIClientError.api(OpenAIRetryPolicy.message(for: error.code, exhausted: false))
                }
                guard attempt < maximumRequestAttempts else {
                    throw OpenAIClientError.api(OpenAIRetryPolicy.message(for: error.code, exhausted: true))
                }
                let delay = OpenAIRetryPolicy.delay(afterAttempt: attempt, retryAfter: nil)
                try await Task.sleep(for: .seconds(delay))
            }
        }

        throw OpenAIClientError.api("FocusGuard couldn't reach OpenAI. Please try again.")
    }

    private static func systemPrompt(
        mode: PlanDraftMode,
        defaultStrictness: Strictness,
        now: Date,
        timeZone: TimeZone
    ) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let nowString = formatter.string(from: now)
        let localFormatter = DateFormatter()
        localFormatter.calendar = Calendar(identifier: .gregorian)
        localFormatter.locale = Locale(identifier: "en_US_POSIX")
        localFormatter.timeZone = timeZone
        localFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let localNowString = localFormatter.string(from: now)

        return """
        You translate a person's natural-language focus request into one FocusGuard block plan.

        Current instant: \(nowString)
        Current local date and time: \(localNowString)
        Time zone: \(timeZone.identifier)

        Outcome:
        Produce a complete, reviewable plan that captures the requested targets, timing, and strictness without inventing unrelated targets. If one essential detail truly cannot be inferred from the defaults below, return a concise clarification question instead of a partial plan.

        Target rules:
        - Include every website or application the person explicitly names.
        - A named category, language, country, or geography (for example "major UK news sites") authorizes you to expand only that category into 5–12 representative websites. Do not expand beyond the requested category.
        - Domains must be bare canonical hostnames, without scheme, path, or wildcard.
        - Applications must be ordinary macOS application display names, not process names or system services.
        - Prefer well-known root domains. Do not manufacture plausible-looking domains.
        \(TargetPresetCatalog.modelGuidance)

        Timing and strictness rules:
        - Convert requested start times to nonnegative whole minutes from the current time.
        - Durations must be between 1 minute and 10080 minutes.
        - If a one-time duration is omitted, use 60 minutes.
        - "locked", "strict", "hard mode", or "no early exit" means locked.
        - "focused" or "focus mode" means focused.
        - "flexible", "gentle", or "easy to stop" means flexible.
        - If strictness is omitted, use \(defaultStrictness.rawValue). This selected default is authoritative.

        Explanation rules:
        - The summary is one short sentence confirming what will happen.
        - The interpretation is one short sentence naming any category expansion or default you applied. It must be specific enough for the person to catch a misunderstanding before activation.
        - For a workable request, set needs_clarification to false and clarification_question to an empty string.
        - Set needs_clarification to true only when the target or schedule would otherwise be materially ambiguous. Ask one smallest useful question in clarification_question; the other fields must still satisfy the schema.

        Mode rules:
        - The requested plan mode is \(mode.rawValue).
        - For oneTime mode, kind must be one_time, recurrence_days must be empty, and recurrence time fields must be 0.
        - For recurring mode, kind must be recurring and recurrence_days must contain every day on which the plan repeats.
        - Interpret "daily" as all seven days, "weekdays" as Monday through Friday, and "weekends" as Saturday and Sunday.
        - Recurring start time fields use local 24-hour clock time in the stated time zone.
        - For recurring mode, start_delay_minutes must be 0. Calculate duration across midnight when the user gives an end time.
        - If a recurring duration is omitted, use 60 minutes. If its start time is omitted, use the current local clock time.

        Before returning, verify that the plan has at least one concrete target unless clarification is required, all timing values are within the schema, category targets stay within the requested category, and the interpretation describes every non-obvious inference.
        """
    }

    private static func responseSchema(mode: PlanDraftMode) -> [String: Any] {
        let isRecurring = mode == .recurring
        return [
            "type": "object",
            "additionalProperties": false,
            "properties": [
                "kind": [
                    "type": "string",
                    "enum": [isRecurring ? LLMPlanKind.recurring.rawValue : LLMPlanKind.oneTime.rawValue],
                ],
                "title": ["type": "string"],
                "domains": [
                    "type": "array",
                    "items": ["type": "string"],
                ],
                "applications": [
                    "type": "array",
                    "items": ["type": "string"],
                ],
                "start_delay_minutes": [
                    "type": "integer",
                    "minimum": 0,
                    "maximum": isRecurring ? 0 : 10080,
                ],
                "duration_minutes": [
                    "type": "integer",
                    "minimum": 1,
                    "maximum": 10080,
                ],
                "strictness": [
                    "type": "string",
                    "enum": Strictness.allCases.map(\.rawValue),
                ],
                "summary": ["type": "string"],
                "interpretation": ["type": "string"],
                "needs_clarification": ["type": "boolean"],
                "clarification_question": ["type": "string"],
                "recurrence_days": [
                    "type": "array",
                    "items": [
                        "type": "string",
                        "enum": Weekday.allCases.map(\.rawValue),
                    ],
                    "minItems": isRecurring ? 1 : 0,
                    "maxItems": isRecurring ? 7 : 0,
                ],
                "recurrence_start_hour": [
                    "type": "integer",
                    "minimum": 0,
                    "maximum": isRecurring ? 23 : 0,
                ],
                "recurrence_start_minute": [
                    "type": "integer",
                    "minimum": 0,
                    "maximum": isRecurring ? 59 : 0,
                ],
            ],
            "required": [
                "kind",
                "title",
                "domains",
                "applications",
                "start_delay_minutes",
                "duration_minutes",
                "strictness",
                "summary",
                "interpretation",
                "needs_clarification",
                "clarification_question",
                "recurrence_days",
                "recurrence_start_hour",
                "recurrence_start_minute",
            ],
        ]
    }
}

enum OpenAIRetryPolicy {
    static func shouldRetry(statusCode: Int) -> Bool {
        switch statusCode {
        case 408, 429, 500, 502, 503, 504:
            true
        default:
            false
        }
    }

    static func shouldRetry(urlErrorCode: URLError.Code) -> Bool {
        switch urlErrorCode {
        case .timedOut,
             .cannotFindHost,
             .cannotConnectToHost,
             .dnsLookupFailed,
             .networkConnectionLost,
             .notConnectedToInternet,
             .resourceUnavailable,
             .secureConnectionFailed:
            true
        default:
            false
        }
    }

    static func delay(afterAttempt attempt: Int, retryAfter: String?) -> TimeInterval {
        if let retryAfter,
           let serverDelay = TimeInterval(retryAfter.trimmingCharacters(in: .whitespacesAndNewlines)) {
            return min(max(serverDelay, 0.25), 8)
        }
        return min(pow(2, Double(max(attempt - 1, 0))), 4)
    }

    static func message(for code: URLError.Code, exhausted: Bool) -> String {
        let suffix = exhausted ? " after three attempts" : ""
        switch code {
        case .notConnectedToInternet:
            return "No internet connection is available. Active FocusGuard blocks are unaffected; reconnect and draft again."
        case .cannotFindHost, .dnsLookupFailed:
            return "FocusGuard couldn't resolve the OpenAI service\(suffix). Active blocks are unaffected; check your connection and try again."
        case .timedOut:
            return "The OpenAI request timed out\(suffix). Active blocks are unaffected; please try drafting again."
        default:
            return "FocusGuard couldn't reach OpenAI\(suffix). Active blocks are unaffected; check your connection and try again."
        }
    }
}

private struct ResponseEnvelope: Decodable {
    let status: String?
    let incompleteDetails: IncompleteDetails?
    let output: [Output]

    enum CodingKeys: String, CodingKey {
        case status
        case incompleteDetails = "incomplete_details"
        case output
    }

    struct IncompleteDetails: Decodable {
        let reason: String?
    }

    struct Output: Decodable {
        let content: [Content]?
    }

    struct Content: Decodable {
        let type: String
        let text: String?
        let refusal: String?
    }
}

private struct APIErrorEnvelope: Decodable {
    let error: APIError

    struct APIError: Decodable {
        let message: String
    }
}
