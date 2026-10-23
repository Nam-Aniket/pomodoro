import Foundation
import PomodoroCore

// `tomo`: talk to Pomodoro from a terminal, a script, or an AI tool (MCP over stdio). Local only: it posts the
// focus notification and reads Pomodoro's files read-only; nothing leaves the Mac.
//
//   tomo start "Writing report" [--app NAME]   start (or retag) a session; NAME = a profile or contract app, default Other
//   tomo end ["Writing report"] [--app NAME]
//   tomo activity [--app NAME]                 proof of work, keeps the not-working check quiet
//   tomo idea "Make the chart zoomable"        park an idea in the inbox
//   tomo status                                what Tomo is doing now
//   tomo today                                 today's sessions
//   tomo mcp                                   run as an MCP server on stdio (for Claude Desktop, Claude Code, others)

let root = ProcessInfo.processInfo.environment["POMODORO_HOME"].map { URL(fileURLWithPath: $0) }
    ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Pomodoro")
let channel = ProcessInfo.processInfo.environment["POMODORO_EVENT_NAME"] ?? FocusEvent.publicName

func post(_ phase: String, task: String, app: String) {
    var info = ["app": app, "phase": phase, "task": task, "at": ISO8601DateFormatter().string(from: Date())]
    if task.isEmpty { info.removeValue(forKey: "task") }
    DistributedNotificationCenter.default().postNotificationName(.init(channel), object: nil, userInfo: info, deliverImmediately: true)
    RunLoop.main.run(until: Date().addingTimeInterval(0.2))
}

func status() -> [String: Any] {
    let s = Store(root: root).load(now: Date())
    let d = Durations()
    return ["phase": s.phase.rawValue, "profile": s.appName ?? s.app ?? "", "task": s.task ?? "", "paused": s.isPaused,
            "activeMinutes": Int(s.active / 60), "minutesLeft": Int(s.remaining(d) / 60), "tomatoesToday": (s.harvest(d) * 10).rounded() / 10,
            "note": "Saved state; Pomodoro writes it every 15 s, so it can be up to 15 s old."]
}

func today() -> [[String: Any]] {
    let day = DayState.dayKey(Date())
    return SessionDB(url: root.appendingPathComponent("sessions.sqlite")).sessions(from: day, to: day).map {
        ["profile": $0.app, "task": $0.task, "activeMinutes": Int($0.active / 60), "elapsedMinutes": Int($0.elapsed / 60), "completed": $0.completed]
    }
}

func park(_ idea: String, app: String?) throws -> String {
    try ParkingLot().park(idea, app: app, task: nil, now: Date()).path
}

func json(_ v: Any) -> String {
    (try? JSONSerialization.data(withJSONObject: v, options: [.sortedKeys, .prettyPrinted])).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
}

// MARK: MCP (JSON-RPC 2.0 over stdio, one message per line)

let tools: [[String: Any]] = [
    ["name": "get_status", "description": "What Tomo (Pomodoro) is doing now: phase, profile, task, active minutes, minutes left.",
     "inputSchema": ["type": "object", "properties": [String: Any]()]],
    ["name": "start_session", "description": "Start a focus session, or move the running one to a new task. Use for work Pomodoro cannot see, such as tailoring a CV in a chat.",
     "inputSchema": ["type": "object", "properties": ["task": ["type": "string"], "profile": ["type": "string", "description": "A profile or contract app name; default Other"]], "required": ["task"]]],
    ["name": "end_session", "description": "Mark the current task done.",
     "inputSchema": ["type": "object", "properties": ["task": ["type": "string"], "profile": ["type": "string"]]]],
    ["name": "park_idea", "description": "Save an idea to the ideas inbox without leaving the task.",
     "inputSchema": ["type": "object", "properties": ["idea": ["type": "string"], "profile": ["type": "string"]], "required": ["idea"]]],
    ["name": "today_summary", "description": "Today's focus sessions: profile, task, active and elapsed minutes.",
     "inputSchema": ["type": "object", "properties": [String: Any]()]],
]

func reply(_ id: Any, _ result: [String: Any]) {
    print(json(["jsonrpc": "2.0", "id": id, "result": result]).replacingOccurrences(of: "\n", with: ""))
    fflush(stdout)
}

func text(_ s: String) -> [String: Any] { ["content": [["type": "text", "text": s]]] }

func mcp() {
    while let line = readLine() {
        guard let msg = (try? JSONSerialization.jsonObject(with: Data(line.utf8))) as? [String: Any], let method = msg["method"] as? String else { continue }
        guard let id = msg["id"] else { continue }   // notifications need no answer
        let params = msg["params"] as? [String: Any] ?? [:]
        switch method {
        case "initialize":
            reply(id, ["protocolVersion": (params["protocolVersion"] as? String) ?? "2025-06-18", "capabilities": ["tools": [String: Any]()],
                       "serverInfo": ["name": "pomodoro", "version": "0.4.0"]])
        case "tools/list": reply(id, ["tools": tools])
        case "tools/call":
            let name = params["name"] as? String ?? "", a = params["arguments"] as? [String: Any] ?? [:]
            let app = (a["profile"] as? String) ?? "Other"
            switch name {
            case "get_status": reply(id, text(json(status())))
            case "today_summary": reply(id, text(json(today())))
            case "start_session": post("start", task: a["task"] as? String ?? "", app: app); reply(id, text("Started: \(a["task"] as? String ?? "")"))
            case "end_session": post("end", task: a["task"] as? String ?? "", app: app); reply(id, text("Ended."))
            case "park_idea":
                do { reply(id, text("Parked in \(try park(a["idea"] as? String ?? "", app: a["profile"] as? String))")) }
                catch { reply(id, ["content": [["type": "text", "text": "Could not park: \(error)"]], "isError": true]) }
            default: print(json(["jsonrpc": "2.0", "id": id, "error": ["code": -32601, "message": "Unknown tool \(name)"]]).replacingOccurrences(of: "\n", with: "")); fflush(stdout)
            }
        case "ping": reply(id, [:])
        default: print(json(["jsonrpc": "2.0", "id": id, "error": ["code": -32601, "message": "Method not found"]]).replacingOccurrences(of: "\n", with: "")); fflush(stdout)
        }
    }
}

// MARK: command line

var args = Array(CommandLine.arguments.dropFirst())
var app = "Other"
if let i = args.firstIndex(of: "--app"), i + 1 < args.count { app = args[i + 1]; args.removeSubrange(i...(i + 1)) }
switch args.first {
case "start": post("start", task: args.dropFirst().joined(separator: " "), app: app); print("Started.")
case "end": post("end", task: args.dropFirst().joined(separator: " "), app: app); print("Ended.")
case "activity": post("activity", task: "", app: app)
case "idea": do { print("Parked in \(try park(args.dropFirst().joined(separator: " "), app: nil))") } catch { print("Could not park: \(error)"); exit(1) }
case "status": print(json(status()))
case "today": print(json(today()))
case "mcp": mcp()
default:
    print("usage: tomo start \"task\" [--app NAME] | end | activity | idea \"text\" | status | today | mcp")
    exit(args.isEmpty ? 0 : 1)
}
