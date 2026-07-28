//
//  DecryptView.swift
//  lara
//
//  Created by neonmodder123 on 23.05.26.
//

import SwiftUI

struct DecryptApp: Identifiable {
    let id = UUID()
    let name: String
    let bundleID: String
    let bundlePath: String
    let executable: String
    let icon: UIImage?
    var isEncrypted: DecryptStatus = .unknown
}

enum DecryptStatus {
    case encrypted, unencrypted, unknown
}

struct DecryptView: View {
    @ObservedObject private var mgr = laramgr.shared
    @State private var query = ""
    @State private var apps: [DecryptApp] = []
    @State private var decryptingbid: String? = nil
    @State private var errormsg: String? = nil
    @State private var pendingdecrypt: DecryptApp? = nil

    private let documentspath = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true).first ?? ""

    private var filteredapps: [DecryptApp] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return apps }
        let q = trimmed.lowercased()
        return apps.filter { $0.name.lowercased().contains(q) || $0.bundleID.lowercased().contains(q) }
    }

    var body: some View {
        NavigationStack {
            List {
                if !mgr.sbxready {
                    Section {
                        Text("沙盒逃逸未就绪。请先运行沙盒逃逸。")
                            .foregroundColor(.secondary)
                    } header: { Text("状态") }
                }

                HStack {
                    TextField("搜索", text: $query)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button(action: loadApps) {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(!mgr.sbxready || decryptingbid != nil)
                }

                if let error = errormsg {
                    Section {
                        PlainAlert(title: "错误", icon: "exclamationmark.triangle", text: error, color: .red)
                    }
                }

                Section {
                    if filteredapps.isEmpty {
                        Text(query.isEmpty ? "加载中…" : "无匹配结果。")
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(filteredapps) { app in
                            AppRow(app: app, isdecrypting: decryptingbid == app.bundleID) {
                                startDecrypt(app)
                            }
                        }
                    }
                } header: {
                    HeaderLabel(text: "已安装应用", icon: "app.badge")
                }
            }
            .navigationTitle("应用解密")
        }
        .onAppear {
            set_log_callback { msg in
                guard let msg = msg else { return }
                let s = String(cString: msg)
                DispatchQueue.main.async {
                    laramgr.shared.logmsg("(decrypt) \(s)")
                }
            }
            if mgr.sbxready { loadApps() }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            if let app = pendingdecrypt {
                pendingdecrypt = nil
                let pid = find_process_pid(app.executable)
                if pid > 0 {
                    doDecrypt(app, pid: pid)
                } else {
                    errormsg = "应用未在运行，请重试。"
                    decryptingbid = nil
                }
            }
        }
        .onChange(of: mgr.sbxready) { ready in
            if ready { loadApps() } else { apps.removeAll() }
        }
    }

    func loadApps() {
        guard mgr.sbxready else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            var results: [DecryptApp] = []
            let bundleFolder = "/private/var/containers/Bundle/Application"

            guard let bundles = try? FileManager.default.contentsOfDirectory(atPath: bundleFolder) else {
                DispatchQueue.main.async { apps.removeAll() }
                return
            }

            for bundle in bundles {
                let appPath = bundleFolder + "/" + bundle
                guard let contents = try? FileManager.default.contentsOfDirectory(atPath: appPath) else { continue }
                for item in contents {
                    guard item.hasSuffix(".app") else { continue }
                    let fullAppPath = appPath + "/" + item
                    let infoPath = fullAppPath + "/Info.plist"
                    guard let info = NSDictionary(contentsOfFile: infoPath) else { continue }

                    let executable = info["CFBundleExecutable"] as? String ?? ""
                    if executable.isEmpty { continue }
                    let bundleid = info["CFBundleIdentifier"] as? String ?? ""
                    let name = (info["CFBundleDisplayName"] as? String) ??
                               (info["CFBundleName"] as? String) ??
                               (item as NSString).deletingPathExtension

                    var icon: UIImage? = nil
                    if let icons = info["CFBundleIcons"] as? [String: Any],
                       let primary = icons["CFBundlePrimaryIcon"] as? [String: Any],
                       let iconfiles = primary["CFBundleIconFiles"] as? [String],
                       let iconname = iconfiles.last {
                        let iconpath = fullAppPath + "/" + iconname
                        if let img = UIImage(contentsOfFile: iconpath) { icon = img }
                        else if let img = UIImage(contentsOfFile: iconpath + "@2x.png") { icon = img }
                        else if let img = UIImage(contentsOfFile: iconpath + ".png") { icon = img }
                    }

                    let encResult = is_encrypted(fullAppPath, executable)
                    let status: DecryptStatus
                    if encResult > 0 { status = .encrypted }
                    else if encResult == 0 { status = .unencrypted }
                    else { status = .unknown }

                    results.append(DecryptApp(
                        name: name, bundleID: bundleid, bundlePath: fullAppPath,
                        executable: executable,
                        icon: icon ?? UIImage(named: "unknown"),
                        isEncrypted: status
                    ))
                    break
                }
            }

            results.sort { $0.name.lowercased() < $1.name.lowercased() }
            DispatchQueue.main.async { apps = results }
        }
    }

    func startDecrypt(_ app: DecryptApp) {
        guard decryptingbid == nil && pendingdecrypt == nil else { return }
        guard mgr.dsready else { errormsg = "Darksword 未就绪，请先运行漏洞利用。"; return }
        guard mgr.sbxready else { errormsg = "尚未逃逸沙盒。"; return }

        let appurl = URL(fileURLWithPath: app.bundlePath)
        var total: Int64 = 0
        if let enumerator = FileManager.default.enumerator(at: appurl, includingPropertiesForKeys: [.fileSizeKey]) {
            for case let furi as URL in enumerator {
                if let fs = (try? furi.resourceValues(forKeys: [.fileSizeKey]))?.fileSize {
                    total += Int64(fs)
                }
            }
        }
        if total > 200 * 1024 * 1024 {
            Alertinator.shared.alert(
                title: "大型应用",
                body: "该应用超过 200 MB，解密可能需要一段时间。",
                actionLabel: "继续",
                action: { self.runDecrypt(app) }
            )
            return
        }
        runDecrypt(app)
    }

    func runDecrypt(_ app: DecryptApp) {
        errormsg = nil
        decryptingbid = app.bundleID

        let pid = find_process_pid(app.executable)
        if pid > 0 {
            doDecrypt(app, pid: pid)
        } else {
            pendingdecrypt = app

            var bgTask: UIBackgroundTaskIdentifier = .invalid
            bgTask = UIApplication.shared.beginBackgroundTask(withName: "AutoResumeDecrypt") {
                UIApplication.shared.endBackgroundTask(bgTask)
            }

            let ret = launch_app(app.bundleID)
            guard ret == 0 else {
                UIApplication.shared.endBackgroundTask(bgTask)
                pendingdecrypt = nil
                decryptingbid = nil
                errormsg = "无法启动应用。请手动打开。"
                return
            }

            DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 2.5) {
                launch_app(Bundle.main.bundleIdentifier!)
                usleep(500000)

                if self.pendingdecrypt != nil {
                    self.pendingdecrypt = nil
                    let foundPid = find_process_pid(app.executable)
                    if foundPid > 0 {
                        DispatchQueue.main.async {
                            self.doDecrypt(app, pid: foundPid)
                        }
                    } else {
                        DispatchQueue.main.async {
                            self.decryptingbid = nil
                            self.errormsg = "启动后未找到进程。请手动操作。"
                        }
                    }
                }

                DispatchQueue.main.async {
                    UIApplication.shared.endBackgroundTask(bgTask)
                }
            }
        }
    }

    func doDecrypt(_ app: DecryptApp, pid: pid_t) {
        let appName = (app.bundlePath as NSString).lastPathComponent
        let ipaName = app.name
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "\t", with: "")
            .appending(".ipa")
        let workDir = documentspath + "/Decrypted/.tmp_" + app.bundleID
        let destAppPath = workDir + "/" + appName
        let payloadDir = workDir + "/Payload"
        let payloadAppPath = payloadDir + "/" + appName
        let ipaPath = documentspath + "/Decrypted/" + ipaName

        laramgr.shared.logmsg("(decrypt) decrypting \(app.bundleID)...")

        DispatchQueue.global(qos: .userInitiated).async {
            let fm = FileManager.default

            try? fm.removeItem(atPath: workDir)
            try? fm.createDirectory(atPath: payloadDir, withIntermediateDirectories: true)

            guard let enumerator = fm.enumerator(atPath: app.bundlePath) else {
                DispatchQueue.main.async {
                    decryptingbid = nil
                    errormsg = "无法枚举应用包以复制"
                    laramgr.shared.logmsg("(decrypt) cannot enumerate \(app.bundlePath)")
                }
                return
            }

            for case let subpath as String in enumerator {
                let src = (app.bundlePath as NSString).appendingPathComponent(subpath)
                let dst = (destAppPath as NSString).appendingPathComponent(subpath)
                var isDir: ObjCBool = false
                guard fm.fileExists(atPath: src, isDirectory: &isDir) else { continue }
                if isDir.boolValue {
                    try? fm.createDirectory(atPath: dst, withIntermediateDirectories: true)
                } else {
                    try? fm.copyItem(atPath: src, toPath: dst)
                }
            }

            let mainBinary = destAppPath + "/" + app.executable
            let mainRet = decrypt_binary_pid((app.bundlePath + "/" + app.executable), pid, mainBinary)
            guard mainRet == 0 else {
                DispatchQueue.main.async {
                    decryptingbid = nil
                    errormsg = "主二进制解密失败"
                    laramgr.shared.logmsg("(decrypt) main binary decrypt failed")
                }
                return
            }

            let srcFrameworks = app.bundlePath + "/Frameworks"
            var srcFwSt = stat()
            if stat(srcFrameworks, &srcFwSt) == 0 {
                let frameworksPath = destAppPath + "/Frameworks"
                let frameworks = (try? fm.contentsOfDirectory(atPath: frameworksPath)) ?? []
                for fw in frameworks where fw.hasSuffix(".framework") {
                    let fwName = (fw as NSString).deletingPathExtension
                    let fwBinary = frameworksPath + "/" + fw + "/" + fwName
                    if !fm.fileExists(atPath: fwBinary) { continue }
                    if is_encrypted_path(fwBinary) > 0 {
                        let fwRet = decrypt_binary_pid(fwBinary, pid, fwBinary)
                        if fwRet != 0 {
                            laramgr.shared.logmsg("(decrypt) framework \(fwName) decrypt failed")
                        }
                    }
                }
            }

            do {
                try fm.moveItem(atPath: destAppPath, toPath: payloadAppPath)
            } catch {
                DispatchQueue.main.async {
                    decryptingbid = nil
                    errormsg = "移动应用包失败：\(error.localizedDescription)"
                    laramgr.shared.logmsg("(decrypt) move failed: \(error.localizedDescription)")
                }
                return
            }

            do {
                try createZipArchive(
                    fromDirectory: URL(fileURLWithPath: workDir, isDirectory: true),
                    to: URL(fileURLWithPath: ipaPath)
                )
            } catch {
                DispatchQueue.main.async {
                    decryptingbid = nil
                    errormsg = "创建 IPA 失败：\(error.localizedDescription)"
                    laramgr.shared.logmsg("(decrypt) zip failed: \(error.localizedDescription)")
                }
                return
            }

            try? fm.removeItem(atPath: workDir)

            DispatchQueue.main.async {
                decryptingbid = nil
                laramgr.shared.logmsg("(decrypt) ipa saved to \(ipaPath)")
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    presentShareSheet(with: URL(fileURLWithPath: ipaPath))
                }
            }
        }
    }
}

struct AppRow: View {
    let app: DecryptApp
    let isdecrypting: Bool
    let ondecrypt: () -> Void

    var body: some View {
        HStack {
            if let icon = app.icon {
                Image(uiImage: icon)
                    .resizable().frame(width: 40, height: 40)
                    .clipShape(RoundedRectangle(cornerRadius: 9))
            } else {
                Image("unknown")
                    .resizable().frame(width: 40, height: 40)
                    .clipShape(RoundedRectangle(cornerRadius: 9))
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(app.name).font(.headline)
                Text(app.bundleID).font(.caption).foregroundColor(.gray)
                HStack(spacing: 4) {
                    switch app.isEncrypted {
                    case .encrypted:
                        Text("已加密").font(.caption2).foregroundStyle(.orange)
                    case .unencrypted:
                        Text("未加密").font(.caption2).foregroundStyle(.green)
                    case .unknown:
                        Text("不符合条件").font(.caption2).foregroundStyle(.gray)
                    }
                }
            }

            Spacer()

            switch app.isEncrypted {
            case .encrypted:
                Button(action: ondecrypt) {
                    if isdecrypting { ProgressView() }
                    else { Text("解密") }
                }
                .disabled(isdecrypting)
            case .unknown:
                Button(action: ondecrypt) {
                    if isdecrypting { ProgressView() }
                    else { Text("解密") }
                }
                .disabled(true)
            case .unencrypted:
                Image(systemName: "checkmark.circle").foregroundColor(.green)
            }
        }
        .opacity(isdecrypting ? 0.6 : 1.0)
    }
}

