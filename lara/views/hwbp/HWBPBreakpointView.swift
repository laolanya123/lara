//
//  HWBPBreakpointView.swift
//  lara
//
//  Per-thread hardware breakpoint management (stage A: arm/clear via
//  KRW on the thread's saved debug state) and hit handling (stage B:
//  pc polling, register dump/edit, stack preview).
//

import SwiftUI

struct hwbpentry: Identifiable, Hashable {
    let id = UUID()
    var slot: Int
    var addr: UInt64
    var enabled: Bool = true
    var hit: Bool = false
    var lastPc: UInt64 = 0
}

struct HWBPBreakpointView: View {
    let pid: Int32
    let thread: hwbpthread

    @State private var addrText = ""
    @State private var slot = 0
    @State private var entries: [hwbpentry] = []
    @State private var status: String?
    @State private var polling = false

    private let pollTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        List {
            Section {
                TextField("断点地址（十六进制）", text: $addrText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.asciiCapable)
                    .font(.system(.body, design: .monospaced))
                Picker("槽位", selection: $slot) {
                    ForEach(0..<6, id: \.self) { Text("DBGBVR\($0)").tag($0) }
                }
                HStack {
                    Button("设置") { arm() }
                        .disabled(hwbp_parsehex(addrText) == nil)
                    Spacer()
                    Button("清除该槽") { clearSlot(slot) }
                        .foregroundColor(.red)
                }
                if let status {
                    Text(status)
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
            } header: {
                Text("设置断点")
            } footer: {
                Text("断点写入线程 pcb 的调试寄存器，在该线程下次被调度时生效。命中后若无异常接收者，目标进程可能收到 SIGTRAP 而崩溃。")
            }

            Section {
                if entries.isEmpty {
                    Text("尚未设置断点。")
                        .foregroundColor(.secondary)
                } else {
                    ForEach(entries) { e in
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text(hwbp_hex(e.addr))
                                    .font(.system(.body, design: .monospaced))
                                Text("槽 \(e.slot)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Spacer()
                                if e.hit {
                                    Text("已命中")
                                        .font(.caption)
                                        .foregroundColor(.green)
                                } else if e.enabled {
                                    Text("等待命中")
                                        .font(.caption)
                                        .foregroundColor(.orange)
                                } else {
                                    Text("已禁用")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            Text("pc: \(e.lastPc != 0 ? hwbp_hex(e.lastPc) : "-")")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .monospaced()
                            HStack {
                                if e.hit {
                                    NavigationLink("查看寄存器") {
                                        HWBPRegsView(pid: pid, thread: thread, breakAddr: e.addr)
                                    }
                                }
                                Spacer()
                                Button(e.enabled ? "禁用" : "启用") { toggle(e) }
                                Button("清除") { clearEntry(e) }
                                    .foregroundColor(.red)
                            }
                            .buttonStyle(.borderless)
                            .font(.footnote)
                        }
                    }
                }
            } header: {
                Text("断点列表（1s 轮询）")
            }
        }
        .navigationTitle("ctid \(thread.ctid)")
        .onReceive(pollTimer) { _ in pollOnce() }
    }

    private func setStatus(_ rc: Int32, addr: UInt64) {
        switch rc {
        case 0:
            status = "已写入 pcb: \(hwbp_hex(addr))（槽 \(slot)）"
        case -1:
            status = "槽位 \(slot) 已被其他地址占用，请先清除。"
        default:
            status = "machine context 定位失败（rc=\(rc)），详见日志。"
        }
    }

    private func arm() {
        guard let addr = hwbp_parsehex(addrText) else { return }
        let kaddr = thread.kaddr
        let s = Int32(slot)
        DispatchQueue.global(qos: .userInitiated).async {
            let rc = mv_hwbp_set(kaddr, s, addr, 1)
            DispatchQueue.main.async {
                setStatus(rc, addr: addr)
                if rc == 0 {
                    if let idx = entries.firstIndex(where: { $0.slot == slot }) {
                        entries[idx].addr = addr
                        entries[idx].enabled = true
                        entries[idx].hit = false
                    } else {
                        entries.append(hwbpentry(slot: slot, addr: addr))
                    }
                }
            }
        }
    }

    private func toggle(_ e: hwbpentry) {
        let kaddr = thread.kaddr
        let enable = !e.enabled
        DispatchQueue.global(qos: .userInitiated).async {
            let rc = mv_hwbp_set(kaddr, Int32(e.slot), e.addr, enable ? 1 : 0)
            DispatchQueue.main.async {
                if rc == 0, let idx = entries.firstIndex(where: { $0.id == e.id }) {
                    entries[idx].enabled = enable
                    if enable { entries[idx].hit = false }
                } else if rc != 0 {
                    status = "操作失败（rc=\(rc)），详见日志。"
                }
            }
        }
    }

    private func clearSlot(_ s: Int) {
        if let e = entries.first(where: { $0.slot == s }) {
            clearEntry(e)
        } else {
            let kaddr = thread.kaddr
            DispatchQueue.global(qos: .userInitiated).async {
                mv_hwbp_clear(kaddr, Int32(s))
            }
            status = "已清除槽 \(s)。"
        }
    }

    private func clearEntry(_ e: hwbpentry) {
        let kaddr = thread.kaddr
        DispatchQueue.global(qos: .userInitiated).async {
            mv_hwbp_clear(kaddr, Int32(e.slot))
        }
        entries.removeAll { $0.id == e.id }
    }

    private func pollOnce() {
        guard !polling else { return }
        let targets = entries.filter { $0.enabled && !$0.hit }
        guard !targets.isEmpty else { return }
        polling = true
        let kaddr = thread.kaddr
        DispatchQueue.global(qos: .userInitiated).async {
            var results: [(UUID, Bool, UInt64)] = []
            for e in targets {
                var pc: UInt64 = 0
                let hit = mv_hwbp_poll_hit(kaddr, e.addr, &pc)
                results.append((e.id, hit != 0, pc))
            }
            DispatchQueue.main.async {
                for r in results {
                    if let idx = entries.firstIndex(where: { $0.id == r.0 }) {
                        entries[idx].lastPc = r.2
                        if r.1 { entries[idx].hit = true }
                    }
                }
                polling = false
            }
        }
    }
}

struct HWBPRegsView: View {
    let pid: Int32
    let thread: hwbpthread
    let breakAddr: UInt64

    static let regNames: [String] = (0...28).map { "x\($0)" } + ["fp", "lr", "sp", "pc", "cpsr"]

    @State private var originals = [UInt64](repeating: 0, count: 34)
    @State private var fields = [String](repeating: "", count: 34)
    @State private var stackBase: UInt64 = 0
    @State private var stackBytes: [UInt8] = []
    @State private var message: String?
    @State private var loaded = false

    var body: some View {
        List {
            Section {
                Text("命中地址: \(hwbp_hex(breakAddr))")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .monospaced()
                HStack {
                    Button("重新读取") { reload() }
                    Spacer()
                    Button("写回修改") { writeBack() }
                        .disabled(!dirty)
                }
                if let message {
                    Text(message)
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
            }

            Section("寄存器") {
                if !loaded {
                    Text("读取中…")
                        .foregroundColor(.secondary)
                } else {
                    ForEach(0..<34, id: \.self) { i in
                        HStack {
                            Text(Self.regNames[i])
                                .frame(width: 44, alignment: .leading)
                                .foregroundColor(.secondary)
                            TextField("hex", text: $fields[i])
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .keyboardType(.asciiCapable)
                                .font(.system(.footnote, design: .monospaced))
                        }
                    }
                }
            }

            Section("栈（sp 起 0x80 字节）") {
                if stackBytes.isEmpty {
                    Text("无法读取栈内存。")
                        .foregroundColor(.secondary)
                } else {
                    ForEach(0..<(stackBytes.count / 8), id: \.self) { row in
                        let base = stackBase + UInt64(row * 8)
                        let bytes = stackBytes[(row * 8)..<(row * 8 + 8)]
                        Text("\(String(format: "0x%llx", base))  \(bytes.map { String(format: "%02x", $0) }.joined(separator: " "))")
                            .font(.system(size: 11, design: .monospaced))
                    }
                }
            }
        }
        .navigationTitle("命中现场")
        .onAppear {
            if !loaded {
                reload()
            }
        }
    }

    private var dirty: Bool {
        for i in 0..<34 {
            if let v = hwbp_parsehex(fields[i]), v != originals[i] {
                return true
            }
        }
        return false
    }

    private func reload() {
        message = nil
        let kaddr = thread.kaddr
        let pid = self.pid
        DispatchQueue.global(qos: .userInitiated).async {
            var regs = [UInt64](repeating: 0, count: 34)
            let rc = mv_hwbp_read_state(kaddr, &regs)
            var stack = [UInt8]()
            var stackBase: UInt64 = 0
            var msg: String?
            if rc == 0 {
                let sp = regs[31]
                let vmmap = mv_vm_map_for_pid(pid)
                if vmmap != 0 && sp != 0 {
                    stackBase = sp & ~UInt64(0xF)
                    var buf = [UInt8](repeating: 0, count: 0x80)
                    let n = mv_read_remote(vmmap, stackBase, &buf, buf.count)
                    if n == buf.count {
                        stack = buf
                    }
                }
                if stack.isEmpty {
                    msg = "寄存器已读取；栈内存读取失败。"
                }
            } else {
                msg = "寄存器读取失败（rc=\(rc)），machine context 可能失效。"
            }
            DispatchQueue.main.async {
                if rc == 0 {
                    originals = regs
                    fields = regs.map { String(format: "%llx", $0) }
                    stackBytes = stack
                    self.stackBase = stackBase
                    loaded = true
                }
                message = msg
            }
        }
    }

    private func writeBack() {
        let kaddr = thread.kaddr
        var writes: [(Int32, UInt64)] = []
        for i in 0..<34 {
            if let v = hwbp_parsehex(fields[i]), v != originals[i] {
                writes.append((Int32(i), v))
            }
        }
        guard !writes.isEmpty else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            var failed = 0
            for w in writes {
                if mv_hwbp_write_reg(kaddr, w.0, w.1) != 0 {
                    failed += 1
                }
            }
            DispatchQueue.main.async {
                message = failed == 0 ? "已写回 \(writes.count) 个寄存器。" : "\(failed)/\(writes.count) 个寄存器写回失败。"
                reload()
            }
        }
    }
}
