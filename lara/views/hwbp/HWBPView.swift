//
//  HWBPView.swift
//  lara
//
//  Hardware breakpoint tab: process picker + thread list.
//  Requires DarkSword KRW (run the exploit on the main tab first).
//

import SwiftUI

struct hwbpproc: Identifiable, Hashable {
    let id = UUID()
    let pid: Int32
    let uid: Int32
    let name: String
}

struct hwbpthread: Identifiable, Hashable {
    let id = UUID()
    let kaddr: UInt64
    let ctid: UInt32
}

func hwbp_parsehex(_ s: String) -> UInt64? {
    var t = s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    if t.hasPrefix("0x") { t.removeFirst(2) }
    guard !t.isEmpty else { return nil }
    return UInt64(t, radix: 16)
}

func hwbp_hex(_ v: UInt64) -> String {
    String(format: "0x%llx", v)
}

struct HWBPView: View {
    @ObservedObject private var mgr = laramgr.shared
    @State private var query = ""
    @State private var procs: [hwbpproc] = []
    @State private var loading = false

    private var filtered: [hwbpproc] {
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
                        Text("在主页运行漏洞利用获取内核读写（KRW）后，才能设置硬件断点。")
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
                        Text("请先在主页获取 Kernelcache，偏移就绪后才能枚举线程。")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        Section {
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
                        }

                        Section {
                            if procs.isEmpty {
                                Text(loading ? "加载中…" : "未找到进程。")
                                    .foregroundColor(.secondary)
                            } else if filtered.isEmpty {
                                Text("无匹配结果。")
                                    .foregroundColor(.secondary)
                            } else {
                                ForEach(filtered) { p in
                                    NavigationLink(destination: HWBPThreadListView(proc: p)) {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(p.name)
                                                .font(.headline)
                                            Text("pid: \(p.pid)   uid: \(p.uid)")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                                .monospaced()
                                        }
                                    }
                                }
                            }
                        } header: {
                            Text("进程 (\(filtered.count))")
                        }
                    }
                }
            }
            .navigationTitle("断点")
        }
        .onAppear {
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

    private func reload() {
        guard mgr.dsready, mgr.hasOffsets, !loading else { return }
        loading = true
        DispatchQueue.global(qos: .userInitiated).async {
            var count: Int32 = 0
            let list = mv_list_processes(nil, &count)
            var items: [hwbpproc] = []
            if let list {
                items.reserveCapacity(Int(count))
                for i in 0..<Int(count) {
                    let e = list[i]
                    let name = withUnsafePointer(to: e.name) { ptr in
                        ptr.withMemoryRebound(to: CChar.self, capacity: 32) {
                            String(cString: $0)
                        }
                    }
                    items.append(hwbpproc(pid: e.pid, uid: e.uid, name: name))
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

struct HWBPThreadListView: View {
    let proc: hwbpproc

    @State private var threads: [hwbpthread] = []
    @State private var loading = false
    @State private var error: String?

    var body: some View {
        List {
            Section {
                HStack {
                    Text("pid: \(proc.pid)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .monospaced()
                    Spacer()
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
            }

            Section {
                if let error {
                    Text(error)
                        .foregroundColor(.red)
                        .font(.footnote)
                }
                if threads.isEmpty {
                    Text(loading ? "加载中…" : "未找到线程。")
                        .foregroundColor(.secondary)
                } else {
                    ForEach(threads) { t in
                        NavigationLink(destination: HWBPBreakpointView(pid: proc.pid, thread: t)) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("ctid: \(t.ctid)")
                                    .font(.headline)
                                    .monospaced()
                                Text(hwbp_hex(t.kaddr))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .monospaced()
                            }
                        }
                    }
                }
            } header: {
                Text("线程 (\(threads.count))")
            }
        }
        .navigationTitle(proc.name)
        .onAppear {
            if threads.isEmpty {
                reload()
            }
        }
    }

    private func reload() {
        guard !loading else { return }
        loading = true
        error = nil
        let pid = proc.pid
        DispatchQueue.global(qos: .userInitiated).async {
            var kaddrs = [UInt64](repeating: 0, count: 256)
            let n = mv_hwbp_list_threads(pid, &kaddrs, Int32(kaddrs.count))
            var items: [hwbpthread] = []
            var err: String?
            if n < 0 {
                err = n == -1 ? "KRW 未就绪。" : "进程/任务查找失败（进程可能已退出）。"
            } else {
                for i in 0..<Int(n) {
                    let kaddr = kaddrs[i]
                    items.append(hwbpthread(kaddr: kaddr, ctid: mv_hwbp_thread_ctid(kaddr)))
                }
                items.sort { $0.ctid < $1.ctid }
                if items.isEmpty {
                    err = "线程链表为空或无法解析。"
                }
            }
            DispatchQueue.main.async {
                threads = items
                error = err
                loading = false
            }
        }
    }
}
