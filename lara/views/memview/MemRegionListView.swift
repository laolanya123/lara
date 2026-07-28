//
//  MemRegionListView.swift
//  lara
//
//  vm_map region list for a selected process, plus an address
//  jump box and a "jump to main Mach-O base" action.
//

import SwiftUI

struct memregion: Identifiable, Hashable {
    let id = UUID()
    let start: UInt64
    let end: UInt64
    var size: UInt64 { end - start }
}

struct MemRegionListView: View {
    let proc: memproc

    @State private var vmmap: UInt64 = 0
    @State private var regions: [memregion] = []
    @State private var loading = true
    @State private var busy = false
    @State private var jumptext = ""
    @State private var showhex = false
    @State private var hexaddr: UInt64 = 0
    @State private var status: String?

    var body: some View {
        List {
            Section {
                LabeledContent("PID", value: "\(proc.pid)")
                LabeledContent("UID", value: "\(proc.uid)")
                HStack {
                    Text("vm_map")
                    Spacer()
                    Text(vmmap != 0 ? String(format: "0x%llx", vmmap) : "—")
                        .foregroundColor(.secondary)
                        .monospaced()
                }
            } header: {
                Text("进程信息")
            }

            if let status {
                Section {
                    Text(status)
                        .foregroundColor(.red)
                        .font(.footnote)
                }
            }

            Section {
                HStack {
                    TextField("十六进制地址，如 0x100000000", text: $jumptext)
                        .keyboardType(.asciiCapable)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.system(.body, design: .monospaced))
                    Button("跳转") {
                        if let addr = memview_parsehex(jumptext) {
                            openhex(at: addr)
                        }
                    }
                    .disabled(vmmap == 0 || memview_parsehex(jumptext) == nil)
                }

                Button {
                    findbase()
                } label: {
                    if busy {
                        HStack {
                            Text("查找中…")
                            Spacer()
                            ProgressView()
                        }
                    } else {
                        Text("跳到主 Mach-O 基址")
                    }
                }
                .disabled(vmmap == 0 || busy)
            } header: {
                Text("读取内存")
            }

            Section {
                if loading {
                    HStack {
                        Text("加载区域中…")
                        Spacer()
                        ProgressView()
                    }
                } else if regions.isEmpty {
                    Text("没有可显示的区域。")
                        .foregroundColor(.secondary)
                } else {
                    ForEach(regions) { r in
                        Button {
                            openhex(at: r.start)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(String(format: "0x%011llx - 0x%011llx", r.start, r.end))
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundColor(.primary)
                                Text(memview_fmtbytes(r.size))
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
            } header: {
                Text("内存区域 (\(regions.count))")
            }
        }
        .navigationTitle(proc.name)
        .navigationDestination(isPresented: $showhex) {
            MemHexView(vmmap: vmmap, address: hexaddr)
        }
        .onAppear(perform: load)
    }

    private func openhex(at address: UInt64) {
        hexaddr = address
        showhex = true
    }

    private func load() {
        guard loading else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            let map = mv_vm_map_for_pid(proc.pid)
            var items: [memregion] = []
            if map != 0 {
                var count: Int32 = 0
                let list = mv_list_regions(map, &count)
                if let list {
                    items.reserveCapacity(Int(count))
                    for i in 0..<Int(count) {
                        items.append(memregion(start: list[i].start, end: list[i].end))
                    }
                    mv_free(list)
                }
            }
            DispatchQueue.main.async {
                vmmap = map
                regions = items
                loading = false
                if map == 0 {
                    status = "无法获取该进程的 vm_map。"
                }
            }
        }
    }

    private func findbase() {
        guard vmmap != 0, !busy else { return }
        busy = true
        DispatchQueue.global(qos: .userInitiated).async {
            let base = mv_find_main_macho_base(vmmap)
            DispatchQueue.main.async {
                busy = false
                if base != 0 {
                    openhex(at: base)
                } else {
                    status = "未找到主 Mach-O 基址。"
                }
            }
        }
    }
}
