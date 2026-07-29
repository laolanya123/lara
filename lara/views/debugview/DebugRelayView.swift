//
//  DebugRelayView.swift
//  lara
//
//  Debug relay tab: pick the game process (KRW target) and run the
//  iOS Duck HTTP/JSON debug service (port 9595) so the desktop
//  iOSDuck / iOSDuckMcp clients can attach to it.
//  Requires DarkSword KRW (run the exploit on the main tab first).
//

import SwiftUI
import UIKit

struct DebugRelayView: View {
    @ObservedObject private var mgr = laramgr.shared
    @StateObject private var model = DebugRelayModel()
    @AppStorage("debugRelayPort") private var port = 9595
    @State private var query = "DeltaForce"
    @State private var procs: [memproc] = []
    @State private var loading = false
    @State private var copied = false

    private var filtered: [memproc] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return procs }
        let q = trimmed.lowercased()
        return procs.filter {
            $0.name.lowercased().contains(q) || String($0.pid).contains(q)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if !mgr.dsready {
                    VStack(spacing: 12) {
                        Image(systemName: "lock.shield")
                            .font(.system(size: 40))
                            .foregroundColor(.secondary)
                        Text("请先运行漏洞")
                            .font(.headline)
                        Text("在主页运行漏洞利用获取内核读写（KRW）后，才能绑定游戏进程并启动远程调试服务。")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if !mgr.hasOffsets {
                    VStack(spacing: 12) {
                        Image(systemName: "cpu")
                            .font(.system(size: 40))
                            .foregroundColor(.secondary)
                        Text("缺少 Kernelcache 偏移")
                            .font(.headline)
                        Text("请先在主页获取 Kernelcache，偏移就绪后才能绑定游戏进程。")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    content
                }
            }
            .navigationTitle("调试")
        }
        .onAppear {
            model.refresh()
            if mgr.dsready && mgr.hasOffsets && procs.isEmpty {
                reload()
            }
        }
        .onChange(of: mgr.dsready) { ready in
            if ready {
                reload()
            } else {
                procs = []
            }
        }
        .onChange(of: mgr.hasOffsets) { hasoffs in
            if hasoffs && mgr.dsready && procs.isEmpty {
                reload()
            }
        }
    }

    private var content: some View {
        List {
            gameSection
            serviceSection
            statusSection
        }
    }

    // MARK: - 游戏进程

    private var gameSection: some View {
        Section {
            if model.attached {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(model.attachedName)
                            .font(.headline)
                        Text("pid: \(model.attachedPid)   基址: 0x\(String(model.attachedBase, radix: 16))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .monospaced()
                    }
                    Spacer()
                    Button("重新选择") {
                        model.detach()
                    }
                    .font(.subheadline)
                }
            } else {
                HStack {
                    TextField("搜索进程（名称或 PID）", text: $query)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button {
                        reload()
                    } label: {
                        if loading {
                            ProgressView()
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                    .disabled(loading)
                }

                if procs.isEmpty {
                    Text(loading ? "加载中…" : "未找到进程。")
                        .foregroundColor(.secondary)
                } else if filtered.isEmpty {
                    Text("无匹配结果（游戏未启动？先启动三角洲行动再刷新）。")
                        .foregroundColor(.secondary)
                } else {
                    ForEach(filtered) { p in
                        Button {
                            model.attach(pid: p.pid, name: p.name)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(p.name)
                                    .font(.headline)
                                    .foregroundColor(.primary)
                                Text("pid: \(p.pid)   uid: \(p.uid)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .monospaced()
                            }
                        }
                    }
                }
            }
        } header: {
            Text("游戏进程")
        } footer: {
            if !model.attached {
                Text("选择 DeltaForceClient 作为 KRW 调试目标。")
            }
        }
    }

    // MARK: - 调试服务

    private var serviceSection: some View {
        Section {
            HStack {
                Text("端口")
                Spacer()
                TextField("9595", value: $port, format: .number)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .monospaced()
                    .disabled(model.running)
            }

            if model.running {
                Button("停止服务", role: .destructive) {
                    hideKeyboard()
                    model.stop()
                }
            } else {
                Button("启动服务") {
                    hideKeyboard()
                    let bounded = min(max(port, 1024), 65535)
                    model.start(port: UInt16(bounded))
                }
                .disabled(!model.attached)
            }

            if model.running {
                HStack {
                    Text("地址")
                    Spacer()
                    Text("\(model.localAddress):\(model.port)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .monospaced()
                }
                HStack {
                    Text("配对码")
                    Spacer()
                    Text(model.pairingCode)
                        .font(.headline)
                        .monospaced()
                    Button {
                        UIPasteboard.general.string = model.pairingCode
                        copied = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            copied = false
                        }
                    } label: {
                        Label(copied ? "已复制" : "复制",
                              systemImage: copied ? "checkmark" : "doc.on.doc")
                            .font(.subheadline)
                    }
                }
                HStack {
                    Text("客户端数")
                    Spacer()
                    Text("\(model.clientCount)")
                        .monospaced()
                }
            }
        } header: {
            Text("调试服务")
        } footer: {
            if !model.attached {
                Text("请先绑定游戏进程。")
            } else if model.running {
                Text("电脑端 iOSDuck 填写上方地址、端口与配对码即可连接；USB 可用 iproxy \(model.port) \(model.port) 转发。")
            }
        }
    }

    // MARK: - 状态

    private var statusSection: some View {
        Section {
            HStack {
                Text("运行状态")
                Spacer()
                Text(model.running ? "运行中" : "已停止")
                    .foregroundColor(model.running ? .green : .secondary)
            }
            HStack {
                Text("调试目标")
                Spacer()
                Text(model.attached ? model.attachedName : "未绑定")
                    .foregroundColor(model.attached ? .green : .secondary)
            }
            if !model.lastOperation.isEmpty {
                HStack {
                    Text("最近操作")
                    Spacer()
                    Text(model.lastOperation)
                        .font(.footnote)
                        .foregroundColor(.secondary)
                        .monospaced()
                }
            }
            if let err = model.lastError {
                Text(err)
                    .foregroundColor(.red)
                    .font(.footnote)
            }
        } header: {
            Text("状态")
        }
    }

    // MARK: - helpers

    private func hideKeyboard() {
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil, from: nil, for: nil)
    }

    private func reload() {
        guard mgr.dsready, mgr.hasOffsets, !loading else { return }
        loading = true
        DispatchQueue.global(qos: .userInitiated).async {
            var count: Int32 = 0
            let list = mv_list_processes(nil, &count)
            var items: [memproc] = []
            if let list {
                items.reserveCapacity(Int(count))
                for i in 0..<Int(count) {
                    let e = list[i]
                    let name = withUnsafePointer(to: e.name) { ptr in
                        ptr.withMemoryRebound(to: CChar.self, capacity: 32) {
                            String(cString: $0)
                        }
                    }
                    items.append(memproc(pid: e.pid, uid: e.uid, name: name))
                }
                mv_free(list)
            }
            items.sort { $0.name.lowercased() < $1.name.lowercased() }
            DispatchQueue.main.async {
                procs = items
                loading = false
            }
        }
    }
}
