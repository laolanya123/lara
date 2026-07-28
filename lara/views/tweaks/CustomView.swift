//
//  CustomView.swift
//  lara
//
//  Created by ruter on 29.03.26.
//

import SwiftUI
import UniformTypeIdentifiers

struct CustomView: View {
    @ObservedObject var mgr: laramgr
    @State private var target: String = "/"
    @State private var showimport = false
    @State private var srcpath: String = ""
    @State private var srcname: String = "未选择文件"
    @State private var isoverwriting = false

    var body: some View {
        List {
            Section {
                TextField("/path/to/target", text: $target)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)

                HStack {
                    Text("源文件")
                    Spacer()
                    Text(srcname)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Button("选择源文件") {
                    showimport = true
                }

                Button(isoverwriting ? "正在覆盖…" : "覆盖目标文件") {
                    guard !isoverwriting else { return }
                    overwrite()
                }
                .disabled(!canoverwrite)
            } header: {
                Text("自定义路径覆盖")
            } footer: {
                Text("将用所选源文件的内容覆盖目标文件。目标文件大小必须 ≥ 源文件大小。")
            }

            Section {
                Text(globallogger.logs.last ?? "暂无日志")
                    .font(.system(size: 13, design: .monospaced))
            }
        }
        .navigationTitle("自定义覆盖")
        .fileImporter(
            isPresented: $showimport,
            allowedContentTypes: [.item],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                importsource(url)
            }
        }
    }

    private var canoverwrite: Bool {
        mgr.vfsready && !target.isEmpty && !srcpath.isEmpty && !isoverwriting
    }

    private func importsource(_ url: URL) {
        let fm = FileManager.default
        let tmpdir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let dest = tmpdir.appendingPathComponent("customwrite-\(UUID().uuidString)")

        do {
            if fm.fileExists(atPath: dest.path) {
                try fm.removeItem(at: dest)
            }
            try fm.copyItem(at: url, to: dest)
            srcpath = dest.path
            srcname = url.lastPathComponent
            mgr.logmsg("selected source: \(srcname)")
        } catch {
            mgr.logmsg("failed to import source: \(error.localizedDescription)")
        }
    }

    private func overwrite() {
        guard canoverwrite else { return }
        isoverwriting = true
        DispatchQueue.global(qos: .userInitiated).async {
            let ok = mgr.vfsoverwritefromlocalpath(target: target, source: srcpath)
            DispatchQueue.main.async {
                isoverwriting = false
                ok ? mgr.logmsg("overwrite ok: \(target)") : mgr.logmsg("overwrite failed: \(target)")
            }
        }
    }
}
