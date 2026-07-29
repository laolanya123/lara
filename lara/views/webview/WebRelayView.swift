//
//  WebRelayView.swift
//  lara
//
//  Web relay tab: bind the Delta Force process (KRW), create a relay
//  session and push radar frames to the web viewer.
//  Requires DarkSword KRW (run the exploit on the main tab first).
//

import SwiftUI
import UIKit

struct WebRelayView: View {
    @ObservedObject private var mgr = laramgr.shared
    @StateObject private var model = WebRelayModel()
    @AppStorage("webRelayServer") private var server = "114.66.17.29:8080"
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
                        Text("在主页运行漏洞利用获取内核读写（KRW）后，才能读取游戏数据并推送到网页雷达。")
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
                        Text("请先在主页获取 Kernelcache，偏移就绪后才能读取游戏进程。")
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
            .navigationTitle("网页")
        }
        .onAppear {
            model.refreshAttachState()
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
            serverSection
            if !model.sessionCode.isEmpty {
                sessionSection
            }
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
                Text("选择 DeltaForceClient 绑定 KRW 读取。")
            }
        }
    }

    // MARK: - 中继服务器

    private var serverSection: some View {
        Section {
            TextField("服务器地址（如 114.66.17.29:8080）", text: $server)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .disabled(model.connState != .disconnected)

            switch model.connState {
            case .disconnected:
                Button("连接服务器") {
                    hideKeyboard()
                    model.connect(server: server)
                }
                .disabled(!model.attached)
            case .connecting:
                HStack {
                    ProgressView()
                    Text("连接中…")
                        .foregroundColor(.secondary)
                }
            case .connected, .reconnecting:
                Button("断开连接", role: .destructive) {
                    model.disconnect()
                }
            }
        } header: {
            Text("中继服务器")
        } footer: {
            if !model.attached {
                Text("请先绑定游戏进程。")
            }
        }
    }

    // MARK: - 会话

    private var sessionSection: some View {
        Section {
            HStack {
                Text("会话码")
                Spacer()
                Text(model.sessionCode)
                    .font(.headline)
                    .monospaced()
            }
            HStack {
                Text(model.sessionURL)
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Button {
                    UIPasteboard.general.string = model.sessionURL
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        copied = false
                    }
                } label: {
                    Label(copied ? "已复制" : "一键复制",
                          systemImage: copied ? "checkmark" : "doc.on.doc")
                        .font(.subheadline)
                }
            }
        } header: {
            Text("网页雷达")
        } footer: {
            Text("把网址发给电脑浏览器打开，即可实时查看雷达。")
        }
    }

    // MARK: - 状态

    private var statusSection: some View {
        Section {
            HStack {
                Text("连接状态")
                Spacer()
                Text(model.connState.rawValue)
                    .foregroundColor(model.connState == .connected ? .green : .secondary)
            }
            HStack {
                Text("对局状态")
                Spacer()
                Text(model.inGame ? "对局中" : "未在对局")
                    .foregroundColor(model.inGame ? .green : .secondary)
            }
            HStack {
                Text("发送帧率")
                Spacer()
                Text("\(model.framesPerSecond) 帧/秒")
                    .monospaced()
            }
            HStack {
                Text("目标数量")
                Spacer()
                Text("人物 \(model.lastActors) · 物资 \(model.lastLoots)")
                    .monospaced()
            }
            Toggle("推送数据", isOn: Binding(
                get: { model.pushing },
                set: { model.setPushing($0) }
            ))
            .disabled(model.connState != .connected || !model.attached)

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
