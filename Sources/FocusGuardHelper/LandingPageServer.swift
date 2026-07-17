import Darwin
import FocusGuardCore
import Foundation
import Network

private final class LandingPagePolicy: @unchecked Sendable {
    private let lock = NSLock()
    private var document = BlockScheduleDocument()

    func update(activePlans: [BlockPlan]) {
        lock.lock()
        document = BlockScheduleDocument(plans: activePlans)
        lock.unlock()
    }

    func block(for host: String) -> WebsiteBlockContext? {
        lock.lock()
        let snapshot = document
        lock.unlock()
        return snapshot.activeWebsiteBlock(for: host)
    }

    func healthSnapshot() -> LandingPageHealthSnapshot {
        lock.lock()
        let snapshot = document
        lock.unlock()
        return LandingPageHealthSnapshot(
            activePlans: snapshot.plans.count,
            blockedDomains: Set(snapshot.plans.flatMap(\.domains)).count,
            blockedApplications: Set(snapshot.plans.flatMap(\.applications).map(\.bundleIdentifier)).count
        )
    }
}

private struct LandingPageHealthSnapshot {
    let activePlans: Int
    let blockedDomains: Int
    let blockedApplications: Int
}

final class LandingPageServer: @unchecked Sendable {
    private let policy = LandingPagePolicy()
    private let queue = DispatchQueue(label: "FocusGuard.LandingPageServer", qos: .utility)
    private let helperVersion: Int
    private var listeners: [UInt16: NWListener] = [:]

    init(helperVersion: Int = FocusGuardHelperProtocol.currentVersion) {
        self.helperVersion = helperVersion
    }

    func update(activePlans: [BlockPlan]) {
        policy.update(activePlans: activePlans)
    }

    func start() {
        queue.async { [weak self] in
            self?.startListener(port: 80)
            self?.startListener(port: 8_765)
        }
    }

    private func startListener(port: UInt16) {
        guard listeners[port] == nil else { return }
        do {
            let parameters = NWParameters.tcp
            parameters.allowLocalEndpointReuse = true
            parameters.requiredLocalEndpoint = .hostPort(
                host: "127.0.0.1",
                port: NWEndpoint.Port(rawValue: port)!
            )

            let listener = try NWListener(using: parameters)
            listener.stateUpdateHandler = { [weak self, weak listener] state in
                switch state {
                case .ready:
                    Self.log("landing page listening on 127.0.0.1:\(port)")
                case .failed(let error):
                    Self.log("landing page port \(port) failed: \(error)")
                    guard let self,
                          let listener,
                          let currentListener = self.listeners[port],
                          currentListener === listener
                    else { return }
                    self.listeners[port] = nil
                    self.queue.asyncAfter(deadline: .now() + 2) { [weak self] in
                        self?.startListener(port: port)
                    }
                default:
                    break
                }
            }
            listener.newConnectionHandler = { [weak self] connection in
                self?.handle(connection, listenerPort: port)
            }
            listeners[port] = listener
            listener.start(queue: queue)
        } catch {
            Self.log("could not start landing page port \(port): \(error.localizedDescription)")
            queue.asyncAfter(deadline: .now() + 2) { [weak self] in
                self?.startListener(port: port)
            }
        }
    }

    private func handle(_ connection: NWConnection, listenerPort: UInt16) {
        connection.start(queue: queue)
        receiveRequest(on: connection, listenerPort: listenerPort, accumulated: Data())
    }

    private func receiveRequest(
        on connection: NWConnection,
        listenerPort: UInt16,
        accumulated: Data
    ) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { [weak self] data, _, isComplete, error in
            guard let self else {
                connection.cancel()
                return
            }

            var requestData = accumulated
            if let data {
                requestData.append(data)
            }

            let headersComplete = requestData.range(of: Data("\r\n\r\n".utf8)) != nil
            if headersComplete || isComplete || error != nil || requestData.count >= 32_768 {
                let response = self.response(for: requestData, listenerPort: listenerPort)
                connection.send(content: response, completion: .contentProcessed { _ in
                    connection.cancel()
                })
            } else {
                self.receiveRequest(on: connection, listenerPort: listenerPort, accumulated: requestData)
            }
        }
    }

    private func response(for requestData: Data, listenerPort: UInt16) -> Data {
        guard let request = String(data: requestData, encoding: .utf8) else {
            return httpResponse(status: "400 Bad Request", contentType: "text/plain; charset=utf-8", body: Data("Bad request".utf8))
        }

        let lines = request.components(separatedBy: "\r\n")
        let requestParts = lines.first?.split(separator: " ") ?? []
        guard requestParts.count >= 2 else {
            return httpResponse(status: "400 Bad Request", contentType: "text/plain; charset=utf-8", body: Data("Bad request".utf8))
        }

        let target = String(requestParts[1])
        let components = URLComponents(string: "http://focusguard.local\(target)")
        let queryHost = components?.queryItems?.first(where: { $0.name == "host" })?.value

        if target.hasPrefix("/api/check") {
            return checkResponse(host: queryHost ?? "")
        }

        if target.hasPrefix("/health") {
            let snapshot = policy.healthSnapshot()
            return jsonResponse([
                "ok": true,
                "version": helperVersion,
                "active_plans": snapshot.activePlans,
                "blocked_domains": snapshot.blockedDomains,
                "blocked_applications": snapshot.blockedApplications,
            ])
        }

        let requestedHost: String
        if let queryHost, !queryHost.isEmpty {
            requestedHost = queryHost
        } else {
            requestedHost = hostHeader(from: lines) ?? ""
        }

        let block = policy.block(for: requestedHost)
        let html = LandingPageHTML.render(host: requestedHost, block: block)
        return httpResponse(
            status: "200 OK",
            contentType: "text/html; charset=utf-8",
            body: Data(html.utf8),
            additionalHeaders: [
                "Content-Security-Policy": "default-src 'none'; style-src 'unsafe-inline'; script-src 'unsafe-inline'; base-uri 'none'; form-action 'none'",
                "Referrer-Policy": "no-referrer",
            ]
        )
    }

    private func checkResponse(host: String) -> Data {
        guard let block = policy.block(for: host) else {
            return jsonResponse(["blocked": false])
        }

        return jsonResponse([
            "blocked": true,
            "host": block.host,
            "title": block.title,
            "ends_at_ms": Int(block.endsAt.timeIntervalSince1970 * 1_000),
        ])
    }

    private func hostHeader(from lines: [String]) -> String? {
        guard let line = lines.first(where: { $0.lowercased().hasPrefix("host:") }) else { return nil }
        let value = line.dropFirst(5).trimmingCharacters(in: .whitespacesAndNewlines)
        return value.split(separator: ":", maxSplits: 1).first.map(String.init)
    }

    private func jsonResponse(_ object: [String: Any]) -> Data {
        let body = (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])) ?? Data("{}".utf8)
        return httpResponse(
            status: "200 OK",
            contentType: "application/json; charset=utf-8",
            body: body,
            additionalHeaders: ["Access-Control-Allow-Origin": "*"]
        )
    }

    private func httpResponse(
        status: String,
        contentType: String,
        body: Data,
        additionalHeaders: [String: String] = [:]
    ) -> Data {
        var headers = [
            "HTTP/1.1 \(status)",
            "Content-Type: \(contentType)",
            "Content-Length: \(body.count)",
            "Cache-Control: no-store, no-cache, must-revalidate",
            "Connection: close",
            "X-Content-Type-Options: nosniff",
        ]
        for (name, value) in additionalHeaders.sorted(by: { $0.key < $1.key }) {
            headers.append("\(name): \(value)")
        }
        headers.append("")
        headers.append("")

        var response = Data(headers.joined(separator: "\r\n").utf8)
        response.append(body)
        return response
    }

    private static func log(_ message: String) {
        print("[FocusGuardHelper] \(ISO8601DateFormatter().string(from: Date())) \(message)")
        fflush(stdout)
    }
}

private enum LandingPageHTML {
    static func render(host: String, block: WebsiteBlockContext?) -> String {
        let safeHost = escape(host.isEmpty ? "this site" : host)
        let safeTitle = escape(block?.title ?? "FocusGuard commitment")
        let endMilliseconds = Int((block?.endsAt ?? Date()).timeIntervalSince1970 * 1_000)
        let isActive = block != nil

        return """
        <!doctype html>
        <html lang="en">
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <title>FocusGuard · Pause</title>
          <style>
            :root { color-scheme:light; --ink:#1b202a; --muted:#68707d; --line:#e5e7eb; --blue:#1b74e6; --ground:#fff; }
            * { box-sizing:border-box; }
            html, body { min-height:100%; margin:0; }
            body { display:grid; place-items:center; padding:28px; background:var(--ground); color:var(--ink); font-family:-apple-system,BlinkMacSystemFont,"SF Pro Text","Helvetica Neue",sans-serif; }
            main { width:min(92vw,580px); }
            header { display:flex; align-items:center; justify-content:space-between; gap:20px; }
            .brand { display:flex; align-items:center; gap:10px; color:var(--blue); font-size:12px; font-weight:800; letter-spacing:.16em; }
            .shield { width:23px; height:23px; display:grid; place-items:center; color:var(--blue); }
            .shield svg { display:block; width:100%; height:100%; }
            .state { color:var(--muted); font-size:13px; }
            body[data-active="true"] .state { color:var(--blue); }
            .content { margin-top:clamp(68px,11vh,112px); }
            .site { margin:0 0 12px; color:var(--muted); font-size:15px; }
            h1 { margin:0; font-size:clamp(38px,6vw,52px); font-weight:700; line-height:1.05; letter-spacing:-.035em; }
            .message { margin:14px 0 0; color:var(--muted); font-size:19px; line-height:1.5; }
            .details { margin-top:42px; border-top:1px solid var(--line); }
            .detail { display:flex; justify-content:space-between; gap:28px; padding:17px 0; border-bottom:1px solid var(--line); font-size:15px; line-height:1.4; }
            .label { color:var(--muted); }
            .title { max-width:65%; text-align:right; font-weight:600; }
            .countdown { color:var(--ink); font:600 15px ui-monospace,SFMono-Regular,Menlo,monospace; white-space:nowrap; }
            .actions { display:flex; align-items:center; gap:16px; margin-top:28px; }
            button { appearance:none; border:0; border-radius:10px; padding:12px 16px; background:var(--ink); color:#fff; font:650 14px inherit; cursor:pointer; transition:background .16s ease; }
            button:hover { background:#2b3341; }
            button:focus-visible { outline:3px solid rgba(27,116,230,.28); outline-offset:3px; }
            .hint { color:var(--muted); font:11px ui-monospace,SFMono-Regular,Menlo,monospace; }
            .pixel-note { position:fixed; right:clamp(36px,8vw,128px); top:52%; width:72px; height:72px; color:var(--blue); opacity:.88; animation:pixel-float 7s ease-in-out infinite; pointer-events:none; }
            .pixel-note svg { display:block; width:100%; height:100%; shape-rendering:crispEdges; image-rendering:pixelated; filter:drop-shadow(8px 10px 0 rgba(27,32,42,.06)); }
            @keyframes pixel-float { 0%,100% { transform:translate(0,-50%) rotate(-2deg); } 50% { transform:translate(-9px,calc(-50% - 13px)) rotate(2deg); } }
            @media (prefers-reduced-motion:reduce) { .pixel-note { animation:none; transform:translateY(-50%); } }
            @media (max-width:900px) { .pixel-note { display:none; } }
            @media (max-width:520px) { body { display:block; padding:28px 22px; } main { width:100%; } .content { margin-top:76px; } .detail { align-items:flex-start; } .title { max-width:60%; } }
          </style>
        </head>
        <body data-active="\(isActive)" data-end-ms="\(endMilliseconds)">
          <main>
            <header>
              <div class="brand"><span class="shield" aria-hidden="true"><svg viewBox="0 0 24 24" role="img"><path d="M12 3 5 5.7v5.15c0 4.32 2.86 8.3 7 9.65 4.14-1.35 7-5.33 7-9.65V5.7L12 3Z" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linejoin="round"/><path d="M12 4.9v13.62c-3.13-1.31-5.2-4.45-5.2-7.67V6.94L12 4.9Z" fill="currentColor"/></svg></span> FOCUSGUARD</div>
              <div class="state" id="status">\(isActive ? "Active" : "Complete")</div>
            </header>
            <section class="content">
              <p class="site">\(safeHost) is blocked</p>
              <h1>You can visit later.</h1>
              <p class="message">Take a note if you need to.</p>
              <div class="details">
                <div class="detail"><span class="label">Block</span><span class="title">\(safeTitle)</span></div>
                <div class="detail"><span class="label">Remaining</span><span class="countdown" id="countdown">—</span></div>
              </div>
              <div class="actions"><button id="leave">Close tab</button><span class="hint">⌘W</span></div>
            </section>
          </main>
          <div class="pixel-note" aria-hidden="true">
            <svg viewBox="0 0 72 72" role="presentation">
              <rect x="16" y="8" width="36" height="4" fill="currentColor"/>
              <rect x="12" y="12" width="4" height="44" fill="currentColor"/>
              <rect x="16" y="56" width="36" height="4" fill="currentColor"/>
              <rect x="52" y="12" width="4" height="44" fill="currentColor"/>
              <rect x="16" y="12" width="36" height="44" fill="#f3f7ff"/>
              <rect x="22" y="22" width="24" height="4" fill="currentColor"/>
              <rect x="22" y="32" width="18" height="4" fill="#9abdf1"/>
              <rect x="22" y="42" width="22" height="4" fill="#9abdf1"/>
              <rect x="4" y="20" width="4" height="4" fill="currentColor"/>
              <rect x="62" y="10" width="4" height="4" fill="#9abdf1"/>
              <rect x="60" y="58" width="4" height="4" fill="currentColor"/>
            </svg>
          </div>
          <script>
            const body = document.body;
            const countdown = document.getElementById('countdown');
            function updateTime() {
              if (body.dataset.active !== 'true') { countdown.textContent = 'Complete'; return; }
              const seconds = Math.max(0, Math.ceil((Number(body.dataset.endMs) - Date.now()) / 1000));
              if (seconds === 0) { countdown.textContent = 'Complete'; document.getElementById('status').textContent = 'Complete'; return; }
              const hours = Math.floor(seconds / 3600);
              const minutes = Math.floor((seconds % 3600) / 60);
              const secs = seconds % 60;
              countdown.textContent = hours ? `${hours}h ${String(minutes).padStart(2,'0')}m` : `${minutes}m ${String(secs).padStart(2,'0')}s`;
            }
            document.getElementById('leave').addEventListener('click', () => { window.close(); setTimeout(() => location.replace('about:blank'), 80); });
            updateTime(); setInterval(updateTime, 1000);
          </script>
        </body>
        </html>
        """
    }

    private static func escape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }
}
