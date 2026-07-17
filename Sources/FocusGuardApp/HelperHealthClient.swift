import Foundation

struct HelperRuntimeHealth: Decodable, Equatable, Sendable {
    let ok: Bool
    let version: Int
    let activePlans: Int
    let blockedDomains: Int
    let blockedApplications: Int

    enum CodingKeys: String, CodingKey {
        case ok
        case version
        case activePlans = "active_plans"
        case blockedDomains = "blocked_domains"
        case blockedApplications = "blocked_applications"
    }
}

enum HelperHealthClient {
    static func fetch() async -> HelperRuntimeHealth? {
        guard let url = URL(string: "http://127.0.0.1:8765/health") else { return nil }
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.timeoutInterval = 2

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200
            else { return nil }
            return try JSONDecoder().decode(HelperRuntimeHealth.self, from: data)
        } catch {
            return nil
        }
    }
}
