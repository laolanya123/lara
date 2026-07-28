//
//  MemHexView.swift
//  lara
//
//  Hex + ASCII dump of remote process memory, 16 bytes per row,
//  one display page (0x400 bytes) at a time. Reads happen on a
//  background thread via mv_read_remote().
//

import SwiftUI

struct MemHexView: View {
    let vmmap: UInt64

    @State private var address: UInt64
    @State private var addrtext: String
    @State private var lines: [String] = []
    @State private var loading = false
    @State private var status: String?

    private let pagesize: UInt64 = 0x400

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
                Text(lines.joined(separator: "\n"))
                    .font(.system(size: 12, design: .monospaced))
                    .lineSpacing(1)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
                    .padding(.bottom, 8)
            }

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
            let newlines = hexlines(data: buf, base: addr, count: n)
            DispatchQueue.main.async {
                lines = newlines
                loading = false
                if n == 0 {
                    status = "读取失败（KRW 未就绪或参数无效）。"
                }
            }
        }
    }

    private func hexlines(data: [UInt8], base: UInt64, count: Int) -> [String] {
        var out: [String] = []
        out.reserveCapacity(count / 16 + 1)
        var off = 0
        while off < count {
            let rowcount = min(16, count - off)
            var hexpart = ""
            var asciipart = ""
            for i in 0..<16 {
                if i < rowcount {
                    let b = data[off + i]
                    hexpart += String(format: "%02x ", b)
                    asciipart += (b >= 0x20 && b < 0x7f) ? String(UnicodeScalar(b)) : "."
                } else {
                    hexpart += "   "
                }
                if i == 7 { hexpart += " " }
            }
            out.append(String(format: "0x%010llx  ", base + UInt64(off)) + hexpart + " " + asciipart)
            off += rowcount
        }
        return out
    }
}
