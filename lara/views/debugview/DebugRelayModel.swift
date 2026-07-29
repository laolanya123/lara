//
//  DebugRelayModel.swift
//  lara
//
//  Debug relay tab model: binds a target process for the KRW remote
//  debug service (krw_remote_debug, Duck::RemoteKrw) and starts/stops
//  the HTTP/JSON server the desktop iOSDuck/iOSDuckMcp clients talk to.
//

import Foundation
import Combine

final class DebugRelayModel: ObservableObject {
    @Published var attachedPid: Int32 = 0
    @Published var attachedName = ""
    @Published var attachedBase: UInt64 = 0
    @Published var running = false
    @Published var port: UInt16 = 0
    @Published var pairingCode = ""
    @Published var localAddress = ""
    @Published var clientCount: UInt32 = 0
    @Published var lastOperation = ""
    @Published var lastError: String?

    var attached: Bool { attachedPid != 0 }

    private let queue = DispatchQueue(label: "lara.debugrelay", qos: .userInitiated)
    private var statusTimer: DispatchSourceTimer?

    init() {
        refresh()
        let t = DispatchSource.makeTimerSource(queue: DispatchQueue.main)
        t.schedule(deadline: .now() + 1, repeating: 1)
        t.setEventHandler { [weak self] in
            self?.refresh()
        }
        t.resume()
        statusTimer = t
    }

    deinit {
        statusTimer?.cancel()
    }

    // MARK: - target binding (KRW)

    func attach(pid: Int32, name: String) {
        lastError = nil
        queue.async {
            let ok = DuckRemoteKrw_SetTarget(pid)
            DispatchQueue.main.async {
                if !ok {
                    self.lastError = "绑定失败：无法解析 pid \(pid) 的 vm_map（进程已退出，或 KRW 未就绪）。"
                }
                self.refresh()
            }
        }
    }

    func detach() {
        queue.async {
            DuckRemoteKrw_ClearTarget()
            DispatchQueue.main.async {
                self.refresh()
            }
        }
    }

    // MARK: - service control

    func start(port requested: UInt16) {
        lastError = nil
        queue.async {
            _ = DuckRemoteKrw_Start(requested)
            DispatchQueue.main.async {
                self.refresh()
            }
        }
    }

    func stop() {
        queue.async {
            DuckRemoteKrw_Stop()
            DispatchQueue.main.async {
                self.refresh()
            }
        }
    }

    // MARK: - status

    // Cheap getters only (atomics + cached strings); safe on the main thread.
    func refresh() {
        running = DuckRemoteKrw_IsRunning()
        port = DuckRemoteKrw_Port()
        clientCount = DuckRemoteKrw_ClientCount()
        pairingCode = String(cString: DuckRemoteKrw_PairingCode())
        localAddress = String(cString: DuckRemoteKrw_LocalAddress())
        lastOperation = String(cString: DuckRemoteKrw_LastOperation())
        let err = String(cString: DuckRemoteKrw_LastError())
        if !err.isEmpty {
            lastError = err
        }
        attachedPid = DuckRemoteKrw_TargetPid()
        attachedName = String(cString: DuckRemoteKrw_TargetName())
        attachedBase = DuckRemoteKrw_TargetBase()
    }
}
