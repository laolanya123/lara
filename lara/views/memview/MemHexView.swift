//
//  MemHexView.swift
//  lara
//
//  Hex + ASCII dump of remote process memory, 16 bytes per row,
//  one display page (0x400 bytes) at a time. Reads happen on a
//  background thread via mv_read_remote(); long-pressing a byte
//  opens an editor that writes back via mv_write_remote().
//

import SwiftUI

struct MemHexView: View {
    let vmmap: UInt64

    @State private var address: UInt64
    @State private var addrtext: String
    @State private var bytes: [UInt8] = []
    @State private var bytecount = 0
    @State private var loading = false
    @State private var status: String?

    @State private var editTarget: EditTarget?
    @State private var edittext = ""
    @State private var editerror: String?
    @State private var writing = false

    private let pagesize: UInt64 = 0x400

    private struct EditTarget: Identifiable {
        let id = UUID()
        let addr: UInt64
        let current: UInt8
    }

    init(vmmap: UInt64, address: UInt64) {
        self.vmmap = vmmap
        _address = State(initialValue: address)
        _addrtext = State(initialValue: String(format: "0x%llx", address))
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                TextField("地址", text: $addrtext)
                    .keyboardType(.asciiCapable)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.system(.body, design: .monospaced))
                    .padding(8)
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(8)
                Button("跳转") {
                    if let addr = memview_parsehex(addrtext) {
                        address = addr
                        read()
                    }
                }
                .disabled(loading || memview_parsehex(addrtext) == nil)
            }
            .padding()

            if let status {
                Text(status)
                    .font(.footnote)
                    .foregroundColor(.red)
                    .padding(.horizontal)
                    .padding(.bottom, 4)
            }

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    ForEach(0..<rowcount, id: \.self) { row in
                        hexrow(row)
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 4)
            }

            Text("长按字节可编辑写入")
                .font(.caption2)
                .foregroundColor(.secondary)
                .padding(.bottom, 2)

            HStack {
                Button {
                    address = address >= pagesize ? address - pagesize : 0
                    addrtext = String(format: "0x%llx", address)
                    read()
                } label: {
                    Label("上一页", systemImage: "chevron.left")
                }
                .disabled(loading || address == 0)

                Spacer()

                if loading {
                    ProgressView()
                } else {
                    Text(String(format: "0x%llx", address))
                        .font(.system(.footnote, design: .monospaced))
                        .foregroundColor(.secondary)
                }

                Spacer()

                Button {
                    address += pagesize
                    addrtext = String(format: "0x%llx", address)
                    read()
                } label: {
                    Label("下一页", systemImage: "chevron.right")
                }
                .disabled(loading)
            }
            .padding()
        }
        .navigationTitle("内存读取")
        .onAppear {
            read()
        }
        .sheet(item: $editTarget, onDismiss: { editerror = nil }) { target in
            editsheet(target)
        }
    }

    private var rowcount: Int { (bytecount + 15) / 16 }

    @ViewBuilder
    private func hexrow(_ row: Int) -> some View {
        HStack(spacing: 0) {
            Text(String(format: "0x%010llx  ", address + UInt64(row * 16)))
                .foregroundColor(.secondary)
            ForEach(0..<16, id: \.self) { i in
                let idx = row * 16 + i
                if idx < bytecount {
                    Text(String(format: "%02x ", bytes[idx]))
                        .foregroundColor(.primary)
                        .onLongPressGesture {
                            edittext = String(format: "%02x", bytes[idx])
                            editerror = nil
                            editTarget = EditTarget(addr: address + UInt64(idx), current: bytes[idx])
                        }
                } else {
                    Text("   ")
                }
                if i == 7 { Text(" ") }
            }
            Text(" " + ascii(row))
                .foregroundColor(.secondary)
        }
        .font(.system(size: 12, design: .monospaced))
    }

    private func ascii(_ row: Int) -> String {
        var out = ""
        for i in 0..<16 {
            let idx = row * 16 + i
            if idx >= bytecount { break }
            let b = bytes[idx]
            out += (b >= 0x20 && b < 0x7f) ? String(UnicodeScalar(b)) : "."
        }
        return out
    }

    @ViewBuilder
    private func editsheet(_ target: EditTarget) -> some View {
        VStack(spacing: 16) {
            Text("写入内存")
                .font(.headline)
            Text(String(format: "地址 0x%llx（当前 %02x）", target.addr, target.current))
                .font(.system(.footnote, design: .monospaced))
                .foregroundColor(.secondary)
            TextField("十六进制字节，如 90 或 1f 20 03 d5", text: $edittext)
                .keyboardType(.asciiCapable)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.system(.body, design: .monospaced))
                .textFieldStyle(.roundedBorder)
            if let editerror {
                Text(editerror)
                    .font(.footnote)
                    .foregroundColor(.red)
            }
            HStack {
                Button("取消") {
                    editTarget = nil
                }
                .disabled(writing)
                Spacer()
                if writing { ProgressView() }
                Button("写入") {
                    commit(target)
                }
                .disabled(writing || parsehexbytes(edittext) == nil)
            }
        }
        .padding()
        .presentationDetents([.height(240)])
    }

    private func parsehexbytes(_ s: String) -> [UInt8]? {
        var t = s.lowercased().replacingOccurrences(of: "0x", with: "")
        t = t.filter { !$0.isWhitespace && $0 != "," }
        guard !t.isEmpty, t.count % 2 == 0, t.count <= 128 else { return nil }
        var out: [UInt8] = []
        var i = t.startIndex
        while i < t.endIndex {
            let j = t.index(i, offsetBy: 2)
            guard let b = UInt8(t[i..<j], radix: 16) else { return nil }
            out.append(b)
            i = j
        }
        return out
    }

    private func commit(_ target: EditTarget) {
        guard let data = parsehexbytes(edittext) else { return }
        writing = true
        editerror = nil
        DispatchQueue.global(qos: .userInitiated).async {
            let n = data.withUnsafeBufferPointer { ptr -> Int in
                guard let base = ptr.baseAddress else { return 0 }
                return mv_write_remote(vmmap, target.addr, base, data.count)
            }
            DispatchQueue.main.async {
                writing = false
                if n == data.count {
                    editTarget = nil
                    read()
                } else {
                    editerror = "写入失败（\(n)/\(data.count) 字节）：页面不可写或映射失败。"
                }
            }
        }
    }

    private func read() {
        guard !loading else { return }
        loading = true
        status = nil
        let addr = address
        let size = Int(pagesize)
        DispatchQueue.global(qos: .userInitiated).async {
            var buf = [UInt8](repeating: 0, count: size)
            let n = buf.withUnsafeMutableBufferPointer { ptr -> Int in
                guard let base = ptr.baseAddress else { return 0 }
                return mv_read_remote(vmmap, addr, base, size)
            }
            DispatchQueue.main.async {
                bytes = buf
                bytecount = n
                loading = false
                if n == 0 {
                    status = "读取失败（KRW 未就绪或参数无效）。"
                }
            }
        }
    }
}
