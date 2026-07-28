//
//  SettingsView.swift
//  lara
//
//  Created by ruter on 29.03.26.
//

import SwiftUI
import UIKit
import UniformTypeIdentifiers

enum method: String, CaseIterable {
    case vfs = "VFS"
    case sbx = "SBX"
    case hybrid = "Hybrid"
}

enum fmAppsDisplayMode: String, CaseIterable {
    case UUID = "UUID"
    case bundleID = "Bundle ID"
    case appName = "App Name"

    var label: String {
        switch self {
        case .UUID: return "UUID"
        case .bundleID: return "Bundle ID"
        case .appName: return "应用名称"
        }
    }
}

enum logsdisplaymode: String, CaseIterable {
    case tabs = "In Tabs"
    case toolbar = "In Toolbar"
    case content = "Directly in ContentView"

    var label: String {
        switch self {
        case .tabs: return "在标签页中"
        case .toolbar: return "在工具栏中"
        case .content: return "直接显示在主页"
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject var mgr: laramgr
    
    @AppStorage("selectedMethod") private var selectedMethod: method = .hybrid
    @AppStorage("keepAlive") private var keepAlive: Bool = false
    @AppStorage("stashKRW") private var stashKRW: Bool = false
    @AppStorage("keepSpringBoardRemoteCallAliveIOS16") private var keepSpringBoardRemoteCallAliveIOS16: Bool = false
    
    @State private var dlingkcache: Bool = false
    @State private var showkcacheimport: Bool = false
    @State private var importingkcache: Bool = false
    @State private var showkcachetips: Bool = false
    @State private var stashingKRWNow: Bool = false
    
    @AppStorage("logsdisplaymode") private var selectedlogdisplaymode: logsdisplaymode = .toolbar
    @AppStorage("loggerNoBS") private var loggerNoBS: Bool = true
    
    @AppStorage("showFMInTabs") private var showFMInTabs: Bool = true
    @AppStorage("selectedFMAppsDisplayMode") private var selectedFMAppsDisplayMode: fmAppsDisplayMode = .appName
    @AppStorage("fmRecursiveSearch") private var fmRecursiveSearch: Bool = false
    
    @AppStorage("rcDockUnlimited") private var rcDockUnlimited: Bool = false
    
    var body: some View {
        NavigationStack {
            List {
                Section(header: HeaderLabel(text: "关于", icon: "info.circle")) {
                    AppInfoCell()
                    NavigationLink("致谢", destination: CreditsView())
                }
                
                Section(header: HeaderLabel(text: "漏洞利用", icon: "ant")) {
                    Picker("", selection: $selectedMethod) {
                        ForEach(method.allCases, id: \.self) { method in
                            Text(method.rawValue).tag(method)
                        }
                    }
                    .pickerStyle(.segmented)
                    
                    NavigationLink("修改偏移", destination: OffsetManagementView())
                }
                
                // kernelcache
                Section {
                    if !mgr.hasOffsets {
                        // this does not need to be here any longer, but i'll keep it here anyways.
                        Button {
                            guard !dlingkcache else { return }
                            dlingkcache = true

                            DispatchQueue.global(qos: .userInitiated).async {
                                let fetched = fetchkcache()

                                if fetched {
                                    let dlkc = dlkcache()
                                    DispatchQueue.main.async {
                                        mgr.hasOffsets = dlkc
                                        dlingkcache = false
                                    }
                                    return
                                }

                                DispatchQueue.main.async {
                                    mgr.hasOffsets = false
                                    dlingkcache = false
                                }
                            }
                        } label: {
                            if dlingkcache {
                                HStack {
                                    Text("正在获取 Kernelcache…")
                                    Spacer()
                                    ProgressView()
                                }
                            } else {
                                Text("获取 Kernelcache")
                            }
                        }
                        .disabled(dlingkcache || !mgr.dsready)
                               
                        LabeledContent(content: {
                            Button(action: {
                                showkcachetips.toggle()
                            }) {
                                Image(systemName: "info.circle")
                            }
                        }) {
                            Button("导入 Kernelcache", action: {
                                guard !importingkcache else { return }
                                showkcacheimport = true
                            })
                            .disabled(dlingkcache || importingkcache)
                        }
                    } else {
                        Button("删除 Kernelcache", action: {
                            Alertinator.shared.alert(title: "清除 Kernelcache 数据？", body: "将删除所有 kernelcache 数据并移除已保存的偏移。之后需要重新获取数据才能使用 lara。", actionLabel: "确认", action: {
                                clearKcacheData()
                            })
                        })
                        .foregroundColor(.red)
                    }
                } header: {
                    HeaderLabel(text: "Kernelcache", icon: "cpu")
                } footer: {
                    if (!mgr.hasOffsets && (!mgr.dsready || (!mgr.vfsready && !mgr.sbxready))) {
                        Text("注意：需要先点击\"运行漏洞利用\"才能获取 kernelcache。\n\n删除并重新获取 kernelcache 可能修复一些问题。在提交 GitHub issue 或到我们的 [Discord](https://discord.gg/gw8PcRF3Jr) 服务器寻求支持之前，请先尝试此方法。")
                    } else {
                        Text("删除并重新获取 kernelcache 可能修复一些问题。在提交 GitHub issue 或到我们的 [Discord](https://discord.gg/gw8PcRF3Jr) 服务器寻求支持之前，请先尝试此方法。")
                    }
                }
                
                // tips
                if showkcachetips {
                    Section {
                        VStack(alignment: .leading, spacing: 0) {
                            Text("如何获取 kernelcache（macOS）")
                                .font(.footnote.weight(.semibold))
                                .foregroundColor(.primary)
                            
                            Text("1. 下载适用于你设备的 IPSW 工具。")
                            Link("https://github.com/blacktop/ipsw/releases",
                                 destination: URL(string: "https://github.com/blacktop/ipsw/releases")!)
                            
                            Text("2. 解压压缩包。")
                            Text("3. 打开终端。")
                            Text("4. 进入解压后的文件夹：")
                            Text("cd /path/to/ipsw_3.1.671_something_something/")
                                .font(.system(.caption2, design: .monospaced))
                                .textSelection(.enabled)
                                .foregroundColor(.primary)
                            
                            Text("5. 提取内核：")
                            Text("./ipsw extract --kernel [drag your ipsw here]")
                                .font(.system(.caption2, design: .monospaced))
                                .textSelection(.enabled)
                                .foregroundColor(.primary)
                            
                            Text("6. 得到 kernelcache 文件。")
                            Text("7. 将 kernelcache 传输到你的 iCloud 或 iPhone。")
                            Text("8. 点击上方按钮并选择 kernelcache，例如 kernelcache.release.iPhone14,3。")
                        }
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.vertical, 4)
                    }
                }
                
                Section(header: HeaderLabel(text: "应用", icon: "gearshape"), footer: Text("启用保持运行后，即使应用退到后台也会继续运行。")) {
                    Toggle("保持运行", isOn: $keepAlive)
                        .onChange(of: keepAlive) { _ in
                            if keepAlive {
                                if !kaenabled { toggleka() }
                            } else {
                                if kaenabled { toggleka() }
                            }
                        }
                    Toggle("禁用日志分隔线", isOn: $loggerNoBS)
                    Picker("日志显示方式", selection: $selectedlogdisplaymode) {
                        ForEach(logsdisplaymode.allCases, id: \.self) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }
                    .pickerStyle(.menu)
                }
                
                Section(header: HeaderLabel(text: "文件管理器", icon: "folder"), footer: Text("显示方式用于更改文件管理器中应用文件夹的显示形式。")) {
                    Picker("显示方式", selection: $selectedFMAppsDisplayMode) {
                        ForEach(fmAppsDisplayMode.allCases, id: \.self) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }
                    .pickerStyle(.menu)
                    Toggle("在文件管理器中递归搜索", isOn: $fmRecursiveSearch)
                    Toggle("在标签页中显示文件管理器", isOn: $showFMInTabs)
                }
                
                #if !DISABLE_REMOTECALL
                Section(header: HeaderLabel(text: "RemoteCall", icon: "syringe")) {
                    Toggle("暂存 KRW 原语", isOn: $stashKRW)
                        .onChange(of: stashKRW) { enabled in
                            if enabled && isIOS16() {
                                Alertinator.shared.alert(
                                    title: "iOS 16 警告",
                                    body: "在 iOS 16 上保存 KRW 目前不稳定。如果失败，请手动多试几次暂存 KRW。"
                                )
                            }
                        }
                    if isIOS16() {
                        Toggle("在后台保持 SpringBoard RemoteCall", isOn: $keepSpringBoardRemoteCallAliveIOS16)
                        Text("警告：如果 RemoteCall 处于激活状态时 Lara 退出，SpringBoard 可能会注销。")
                            .font(.footnote.weight(.semibold))
                            .foregroundColor(.red)

                        Button {
                            guard !stashingKRWNow else { return }
                            stashingKRWNow = true
                            mgr.stashKRWToLaunchd { success in
                                stashingKRWNow = false
                                if success {
                                    Alertinator.shared.alert(
                                        title: "KRW 已暂存",
                                        body: "KRW 原语已成功暂存到 launchd。"
                                    )
                                } else {
                                    let error = mgr.rcLastError ?? "请手动多试几次暂存 KRW。"
                                    Alertinator.shared.alert(
                                        title: "暂存 KRW 失败",
                                        body: error
                                    )
                                }
                            }
                        } label: {
                            if stashingKRWNow {
                                HStack {
                                    Text("正在暂存 KRW 到 launchd…")
                                    Spacer()
                                    ProgressView()
                                }
                            } else {
                                Text("立即暂存 KRW 到 launchd")
                            }
                        }
                        .disabled(!mgr.dsready || mgr.rcrunning || stashingKRWNow)
                    }
                    Toggle("允许 Dock 图标超过 10 个", isOn: $rcDockUnlimited)
                }
                #endif
            }
            .navigationTitle("设置")
            .fileImporter(isPresented: $showkcacheimport, allowedContentTypes: [.data], allowsMultipleSelection: false) { result in
                switch result {
                case .success(let urls):
                    guard let url = urls.first else { return }
                    importingkcache = true
                    DispatchQueue.global(qos: .userInitiated).async {
                        var ok = false
                        let shouldStopAccess = url.startAccessingSecurityScopedResource()
                        defer {
                            if shouldStopAccess {
                                url.stopAccessingSecurityScopedResource()
                            }
                        }
                        let fm = FileManager.default
                        if let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first {
                            let dest = docs.appendingPathComponent("kernelcache")
                            do {
                                if fm.fileExists(atPath: dest.path) {
                                    try fm.removeItem(at: dest)
                                }
                                try fm.copyItem(at: url, to: dest)
                                ok = dlkcache()
                            } catch {
                                print("failed to import kernelcache: \(error)")
                                ok = false
                            }
                        }
                        DispatchQueue.main.async {
                            mgr.hasOffsets = ok
                            importingkcache = false
                        }
                    }
                case .failure:
                    break
                }
            }
        }
    }
    
    private func clearKcacheData() {
        let fm = FileManager.default
        
        UserDefaults.standard.removeObject(forKey: "lara.kernelcache_path")
        UserDefaults.standard.removeObject(forKey: "lara.kernelcache_size")
        
        let docsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let kernelcacheDocPath = docsPath.appendingPathComponent("kernelcache")
        
        do {
            if fm.fileExists(atPath: kernelcacheDocPath.path) {
                try fm.removeItem(at: kernelcacheDocPath)
                mgr.logmsg("Deleted kernelcache from Documents")
            }
        } catch {
            mgr.logmsg("Failed to delete kernelcache: \(error.localizedDescription)")
        }
        
        let tempPath = NSTemporaryDirectory()
        let tempFiles = ["kernelcache.release.ipad", "kernelcache.release.iphone", "kernelcache.release.ipad3", "kernelcache.release.iphone14,3"]
        
        for file in tempFiles {
            let path = tempPath + file
            do {
                if fm.fileExists(atPath: path) {
                    try fm.removeItem(atPath: path)
                    mgr.logmsg("Deleted temp kernelcache: \(file)")
                }
            } catch {
                mgr.logmsg("Failed to delete \(file): \(error.localizedDescription)")
            }
        }
        
        mgr.logmsg("Kernelcache data cleared")
        mgr.hasOffsets = false
    }
}
