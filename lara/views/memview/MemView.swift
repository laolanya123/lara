//
//  MemView.swift
//  lara
//
//  Memory viewer tab: process list + search.
//  Requires DarkSword KRW (run the exploit on the main tab first).
//

import SwiftUI

struct memproc: Identifiable, Hashable {
    let id = UUID()
    let pid: Int32
    let uid: Int32
    let name: String
}

func memview_parsehex(_ s: String) -> UInt64? {
    var t = s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    if t.hasPrefix("0x") { t.removeFirst(2) }
    guard !t.isEmpty else { return nil }
    return UInt64(t, radix: 16)
}

func memview_fmtbytes(_ size: UInt64) -> String {
    if size >= 1024 * 1024 {
        return String(format: "%.1f MB", Double(size) / 1048576.0)
    }
    if size >= 1024 {
        return String(format: "%.1f KB", Double(size) / 1024.0)
    }
    return "\(size) B"
}

struct MemView: View {
    @ObservedObject private var mgr = laramgr.shared
    @State private var query = ""
    @State private var procs: [memproc] = []
    @State private var loading = false

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
                        Text("在主页运行漏洞利用获取内核读写（KRW）后，才能枚举进程并查看内存。")
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
                        Text("请先在主页获取 Kernelcache，偏移就绪后才能查看进程内存。")
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
                                    NavigationLink(destination: MemRegionListView(proc: p)) {
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
            .navigationTitle("内存")
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
