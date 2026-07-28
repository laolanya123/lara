//
//  WhitelistView.swift
//  lara
//
//  Created by ruter on 29.03.26.
//

import SwiftUI
import Darwin

struct WhitelistView: View {
    @ObservedObject private var mgr = laramgr.shared

    private struct wlfile: Identifiable {
        let id = UUID()
        let name: String
        let path: String
    }

    private let files: [wlfile] = [
        .init(name: "Rejections.plist", path: "/private/var/db/MobileIdentityData/Rejections.plist"),
        .init(name: "AuthListBannedUpps.plist", path: "/private/var/db/MobileIdentityData/AuthListBannedUpps.plist"),
        .init(name: "AuthListBannedCdHashes.plist", path: "/private/var/db/MobileIdentityData/AuthListBannedCdHashes.plist"),
    ]

    @State private var contents: [String: String] = [:]
    @State private var status: String?
    @State private var patching = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        loadall()
                    } label: {
                        if patching {
                            HStack {
                                ProgressView()
                                Text("处理中…")
                            }
                        } else {
                            Text("刷新")
                        }
                    }
                    .disabled(!mgr.sbxready || patching)

                    Button("修补（写入空 Plist）") {
                        patchall()
                    }
                    .disabled(!mgr.sbxready || patching)
                } header: {
                    Text("操作")
                } footer: {
                    Text("用空 plist 覆盖 MobileIdentityData 黑名单文件。")
                }

                ForEach(files) { f in
                    Section {
                        ScrollView {
                            Text(contents[f.path] ?? "（未加载）")
                                .font(.system(size: 13, design: .monospaced))
                                .textSelection(.enabled)
                        }
                        .frame(minHeight: 120)
                    } header: {
                        Text(f.name)
                    } footer: {
                        Text(f.path)
                    }
                }
            }
            .navigationTitle("黑名单解除")
            .alert("状态", isPresented: .constant(status != nil)) {
                Button("好") { status = nil }
            } message: {
                Text(status ?? "")
            }
            .onAppear {
                if mgr.sbxready {
                    loadall()
                }
            }
        }
    }

    private func loadall() {
        guard mgr.sbxready else {
            status = "沙盒逃逸未就绪"
            return
        }
        patching = true
        defer { patching = false }
        var next: [String: String] = [:]
        for f in files {
            guard let data = sbxread(path: f.path, maxSize: 2 * 1024 * 1024) else {
                next[f.path] = "（读取失败）"
                continue
            }
            next[f.path] = render(data: data)
        }
        contents = next
    }

    private func patchall() {
        guard mgr.sbxready else {
            status = "沙盒逃逸未就绪"
            return
        }
        patching = true
        defer { patching = false }

        guard let data = try? PropertyListSerialization.data(
            fromPropertyList: [:],
            format: .xml,
            options: 0
        ) else {
            status = "构建空 plist 失败"
            return
        }

        var failures: [String] = []

        for f in files {
            let result = sbxwrite(path: f.path, data: data)
            if !result.hasPrefix("ok") {
                failures.append("\(f.name): \(result)")
            }
        }

        if failures.isEmpty {
            status = "已修补全部文件！"
        } else {
            status = "修补失败：\(failures.joined(separator: ", "))"
        }

        loadall()
    }

    private func sbxread(path: String, maxSize: Int) -> Data? {
        do {
            let url = URL(fileURLWithPath: path)
            let data = try Data(contentsOf: url, options: .mappedIfSafe)
            if data.count > maxSize {
                return data.prefix(maxSize)
            }
            return data
        } catch {
            return nil
        }
    }

    private func sbxwrite(path: String, data: Data) -> String {
        let fd = open(path, O_WRONLY | O_CREAT | O_TRUNC, 0o644)
        if fd == -1 {
            return vfsfallback(path: path, data: data, reason: "open failed: errno=\(errno) \(String(cString: strerror(errno)))")
        }
        defer { close(fd) }

        let result = data.withUnsafeBytes { ptr in
            write(fd, ptr.baseAddress, ptr.count)
        }

        if result == -1 {
            return vfsfallback(path: path, data: data, reason: "write failed: errno=\(errno) \(String(cString: strerror(errno)))")
        }

        return "ok (\(result) bytes)"
    }

    private func vfsfallback(path: String, data: Data, reason: String) -> String {
        guard mgr.vfsready else {
            return reason + " | vfs not ready"
        }
        let ok = mgr.vfsoverwritewithdata(target: path, data: data)
        return ok ? "ok (vfs overwrite)" : reason + " | vfs overwrite failed"
    }

    private func render(data: Data) -> String {
        if let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
           let xmlData = try? PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0),
           let xml = String(data: xmlData, encoding: .utf8) {
            return xml
        }

        if let s = String(data: data, encoding: .utf8) {
            return s
        }

        let maxBytes = min(data.count, 4096)
        let hex = data.prefix(maxBytes).map { String(format: "%02x", $0) }.joined(separator: " ")
        if data.count > maxBytes {
            return hex + "\n... (\(data.count) bytes total)"
        }
        return hex
    }
}
