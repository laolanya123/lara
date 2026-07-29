//
//  WebRelayModel.swift
//  lara
//
//  Web relay tab model: relay session creation (HTTP POST), WebSocket
//  connection with auto-reconnect and the 10Hz push loop that streams
//  KRW radar frames (krw_engine) to the relay server.
//

import Foundation
import Combine

enum WebRelayConnState: String {
    case disconnected = "未连接"
    case connecting = "连接中"
    case connected = "已连接"
    case reconnecting = "重连中"
}

final class WebRelayModel: ObservableObject {
    @Published var connState: WebRelayConnState = .disconnected
    @Published var sessionCode = ""
    @Published var sessionURL = ""
    @Published private(set) var pushing = false
    @Published var framesPerSecond = 0
    @Published var lastActors = 0
    @Published var lastLoots = 0
    @Published var inGame = false
    @Published var lastError: String?
    @Published var attachedPid: Int32 = 0
    @Published var attachedName = ""
    @Published var attachedBase: UInt64 = 0

    var attached: Bool { attachedPid != 0 }

    private let queue = DispatchQueue(label: "lara.webrelay", qos: .userInitiated)
    private var wsSession: URLSession?
    private var wsTask: URLSessionWebSocketTask?
    private var serverAddress = ""
    private var wantConnected = false
    private var wsReady = false
    private var pushTimer: DispatchSourceTimer?
    private var fpsTimer: DispatchSourceTimer?
    private var framesInWindow = 0

    // MARK: - game process binding (KRW engine)

    func attach(pid: Int32, name: String) {
        lastError = nil
        queue.async {
            var base: UInt64 = 0
            let ok = krw_engine_attach(pid, &base)
            DispatchQueue.main.async {
                if ok {
                    self.attachedPid = pid
                    self.attachedName = name
                    self.attachedBase = base
                } else {
                    self.attachedPid = 0
                    self.attachedName = ""
                    self.attachedBase = 0
                    self.lastError = "绑定失败：无法获取进程 vm_map 或主 Mach-O 基址（游戏可能未在运行，或 KRW 未就绪）。"
                }
            }
        }
    }

    func detach() {
        setPushing(false)
        queue.async {
            krw_engine_detach()
            DispatchQueue.main.async {
                self.attachedPid = 0
                self.attachedName = ""
                self.attachedBase = 0
                self.inGame = false
                self.lastActors = 0
                self.lastLoots = 0
            }
        }
    }

    // Re-sync local state with the engine (e.g. tab re-opened after attach).
    func refreshAttachState() {
        queue.async {
            let ok = krw_engine_is_attached()
            let pid = krw_engine_attached_pid()
            let base = krw_engine_main_base()
            DispatchQueue.main.async {
                if ok && pid != 0 {
                    if self.attachedPid == 0 {
                        self.attachedPid = pid
                        self.attachedBase = base
                        if self.attachedName.isEmpty {
                            self.attachedName = "pid \(pid)"
                        }
                    }
                } else if self.attachedPid != 0 {
                    self.attachedPid = 0
                    self.attachedName = ""
                    self.attachedBase = 0
                }
            }
        }
    }

    // MARK: - relay session

    func connect(server raw: String) {
        var addr = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if addr.isEmpty {
            lastError = "请输入服务器地址。"
            return
        }
        if !addr.hasPrefix("http://") && !addr.hasPrefix("https://") {
            addr = "http://" + addr
        }
        while addr.hasSuffix("/") { addr.removeLast() }
        guard let url = URL(string: addr + "/session/create") else {
            lastError = "服务器地址无效。"
            return
        }
        serverAddress = addr
        wantConnected = true
        lastError = nil
        DispatchQueue.main.async { self.connState = .connecting }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 10
        URLSession.shared.dataTask(with: req) { [weak self] data, _, err in
            guard let self else { return }
            var code = ""
            var page = ""
            var ws = ""
            if let data,
               let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                code = obj["code"] as? String ?? ""
                page = obj["url"] as? String ?? ""
                ws = obj["ws_client"] as? String ?? ""
            }
            if err != nil || code.isEmpty || ws.isEmpty {
                let msg = err?.localizedDescription ?? "服务器返回无效会话。"
                DispatchQueue.main.async {
                    self.connState = .disconnected
                    self.lastError = "创建会话失败：\(msg)"
                }
                self.queue.async { self.scheduleReconnectLocked() }
                return
            }
            DispatchQueue.main.async {
                self.sessionCode = code
                self.sessionURL = page
            }
            self.queue.async { self.openWSLocked(ws) }
        }.resume()
    }

    func disconnect() {
        wantConnected = false
        queue.async {
            self.tearDownWSLocked()
            DispatchQueue.main.async {
                self.connState = .disconnected
                self.sessionCode = ""
                self.sessionURL = ""
                self.framesPerSecond = 0
            }
        }
    }

    // MARK: - websocket (everything below runs on `queue` unless noted)

    private func openWSLocked(_ wsString: String) {
        tearDownWSLocked()
        guard let u = URL(string: wsString) else {
            scheduleReconnectLocked()
            return
        }
        let session = URLSession(configuration: .default)
        let task = session.webSocketTask(with: u)
        wsSession = session
        wsTask = task
        task.resume()
        wsReady = true
        DispatchQueue.main.async { self.connState = .connected }
        receiveLoop(task)
    }

    private func receiveLoop(_ task: URLSessionWebSocketTask) {
        task.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .failure:
                self.queue.async { self.handleDropLocked(task) }
            case .success:
                // 单向推送，收到的内容直接丢弃，继续挂着监听关闭/错误事件。
                self.receiveLoop(task)
            }
        }
    }

    private func handleDropLocked(_ task: URLSessionWebSocketTask) {
        guard task === wsTask else { return }
        wsReady = false
        scheduleReconnectLocked()
    }

    private func scheduleReconnectLocked() {
        guard wantConnected else {
            DispatchQueue.main.async { self.connState = .disconnected }
            return
        }
        DispatchQueue.main.async { self.connState = .reconnecting }
        let server = serverAddress
        queue.asyncAfter(deadline: .now() + 5) { [weak self] in
            guard let self, self.wantConnected, !self.wsReady else { return }
            // 重新走一遍建会话流程，顺带处理会话过期。
            self.connect(server: server)
        }
    }

    private func tearDownWSLocked() {
        wsReady = false
        wsTask?.cancel(with: .goingAway, reason: nil)
        wsTask = nil
        wsSession?.invalidateAndCancel()
        wsSession = nil
    }

    // MARK: - 10Hz push loop

    func setPushing(_ on: Bool) {
        guard pushing != on else { return }
        pushing = on
        if on {
            queue.async { self.startPushLoopLocked() }
        } else {
            queue.async { self.stopPushLoopLocked() }
            DispatchQueue.main.async { self.framesPerSecond = 0 }
        }
    }

    private func startPushLoopLocked() {
        stopPushLoopLocked()
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now(), repeating: 0.1)
        t.setEventHandler { [weak self] in
            self?.pushTick()
        }
        t.resume()
        pushTimer = t

        let f = DispatchSource.makeTimerSource(queue: queue)
        f.schedule(deadline: .now() + 1, repeating: 1)
        f.setEventHandler { [weak self] in
            guard let self else { return }
            let n = self.framesInWindow
            self.framesInWindow = 0
            DispatchQueue.main.async { self.framesPerSecond = n }
        }
        f.resume()
        fpsTimer = f
    }

    private func stopPushLoopLocked() {
        pushTimer?.cancel()
        pushTimer = nil
        fpsTimer?.cancel()
        fpsTimer = nil
        framesInWindow = 0
    }

    private func pushTick() {
        var a: Int32 = 0
        var l: Int32 = 0
        var g: Int32 = 0
        guard let cstr = krw_engine_build_frame_json(200, &a, &l, &g) else {
            return
        }
        let json = String(cString: cstr)
        krw_engine_free(cstr)
        DispatchQueue.main.async {
            self.lastActors = Int(a)
            self.lastLoots = Int(l)
            self.inGame = g != 0
        }
        guard wsReady, let task = wsTask else { return }
        framesInWindow += 1
        task.send(.string(json)) { _ in }
    }
}
