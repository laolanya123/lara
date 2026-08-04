//
//  ContentView.swift
//  lara
//
//  Created by ruter on 23.03.26.
//

import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject private var mgr: laramgr
    @ObservedObject private var logger = globallogger
    @AppStorage("selectedMethod") private var selectedmethod: method = .hybrid
    @AppStorage("logsdisplaymode") private var selectedlogsdisplaymode: logsdisplaymode = .toolbar
    @AppStorage("loggerNoBS") private var loggernobs: Bool = true
    
    @State private var showSettings: Bool = false
    @State private var dlingkcache: Bool = false
    
    init() {
        globallogger.capture()
    }
    
    var body: some View {
        NavigationStack {
            List {
                AlertsSection
                KRWSection
                RCSection
                ActionsSection
                DebugSection
                InlineLogsSection
            }
            .navigationTitle("lara")
            .toolbar {
                if selectedlogsdisplaymode == .toolbar {
                    Button(action: {
                        mgr.showLogs.toggle()
                    }) {
                        Image(systemName: "terminal")
                    }
                }
                Button(action: {
                    showSettings.toggle()
                }) {
                    Image(systemName: "gear")
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
        }
    }
    
    private var AlertsSection: some View {
        Section {
            if !mgr.hasOffsets {
                PlainAlert(title: "未找到偏移！", icon: "exclamationmark.triangle.fill", text: "缺少 Kernelcache 偏移。请点击\"运行漏洞利用\"，然后获取偏移。")
            }
        }
    }
    
    private var KRWSection: some View {
        Section {
            LabeledContent(content: {
                if mgr.dsready {
                    Image(systemName: "checkmark.circle")
                } else if mgr.dsrunning {
                    HStack {
                        Text("\(Int(mgr.dsprogress * 100))%")
                        ProgressView()
                    }
                } else if mgr.dsattempted && mgr.dsfailed {
                    Image(systemName: "xmark.circle")
                }
            }) {
                Button("运行漏洞利用 (\(laramgr.exploitName))", action: {
                    offsets_init()
                    mgr.run()
                })
                .disabled(mgr.dsready || mgr.dsrunning || isdebugged())
            }
            
            if !mgr.hasOffsets {
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
            } else {
                if selectedmethod == .hybrid {
                    LabeledContent(content: {
                        if mgr.vfsready && mgr.sbxready {
                            Image(systemName: "checkmark.circle")
                        } else if mgr.vfsrunning || mgr.sbxrunning {
                            HStack {
                                Text("运行中…")
                                ProgressView()
                            }
                        } else if (mgr.vfsattempted && mgr.vfsfailed) || (mgr.sbxattempted && mgr.sbxfailed) {
                            Image(systemName: "xmark.circle")
                        }
                    }) {
                        Button("初始化系统", action: {
                            mgr.vfsinit()
                            mgr.sbxescape()
                        })
                        .disabled(!mgr.hasOffsets || !mgr.dsready || mgr.vfsrunning || mgr.sbxrunning || (mgr.vfsready && mgr.sbxready))
                    }
                }
                
                // initalize vfs
                if selectedmethod == .vfs {
                    LabeledContent(content: {
                        if mgr.vfsready {
                            Image(systemName: "checkmark.circle")
                        } else if mgr.vfsrunning {
                            HStack {
                                Text("\(Int(mgr.dsprogress * 100))%")
                                ProgressView()
                            }
                        } else if mgr.vfsattempted && mgr.vfsfailed {
                            Image(systemName: "xmark.circle")
                        }
                    }) {
                        Button("初始化 VFS", action: {
                            mgr.vfsinit()
                        })
                        .disabled(!mgr.dsready || mgr.vfsready || mgr.vfsrunning || isdebugged())
                    }
                }
                
                // escape sandbox
                if selectedmethod == .sbx {
                    LabeledContent(content: {
                        if mgr.sbxready {
                            Image(systemName: "checkmark.circle")
                        } else if mgr.sbxrunning {
                            HStack {
                                Text("运行中…")
                                ProgressView()
                            }
                        } else if mgr.sbxattempted && mgr.sbxfailed {
                            Image(systemName: "xmark.circle")
                        }
                    }) {
                        Button("逃逸沙盒", action: {
                            mgr.sbxescape()
                        })
                        .disabled(!mgr.dsready || mgr.sbxready || mgr.sbxrunning || isdebugged())
                    }
                }
            }
        } header: {
            HeaderLabel(text: "内核读写", icon: "externaldrive")
        } footer: {
            if isdebugged() {
                Text("调试器附加时不可用。")
            }
        }
    }
    
    private var RCSection: some View {
        Group {
            #if !DISABLE_REMOTECALL
            Section {
                // init remotecall
                LabeledContent(content: {
                    if mgr.rcready {
                        Image(systemName: "checkmark.circle")
                    } else if mgr.rcrunning {
                        HStack {
                            Text("运行中…")
                            ProgressView()
                        }
                    } else if mgr.rcfailed {
                        Image(systemName: "xmark.circle")
                    }
                }) {
                    Button("初始化 RemoteCall", action: {
                        mgr.rcinit(process: "SpringBoard", migbypass: false) { success in
                            if success {
                                mgr.logmsg("rc init succeeded!")
                                let pid = mgr.rccall(name: "getpid")
                                mgr.logmsg("remote getpid() returned: \(pid)")
                            } else {
                                mgr.logmsg("rc init failed")
                                mgr.rcfailed = true
                            }
                        }
                    })
                    .disabled(!mgr.dsready || isdebugged() || mgr.rcrunning || mgr.rcready)
                }
                
                // destroy remotecall
                if mgr.rcready {
                    Button("销毁 RemoteCall", action: {
                        mgr.rcdestroy()
                    })
                }
            } header: {
                HeaderLabel(text: "RemoteCall", icon: "syringe")
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    if let error = mgr.rcLastError ?? mgr.sbProc?.lastError {
                        Text("错误：\(error)")
                            .foregroundColor(.red)
                    }
                    if RemoteCall.isLiveContainerRuntime() && !RemoteCall.isLiveProcessRuntime() {
                        Text("RemoteCall 需要启用 PAC 的 LiveContainer 启动上下文。RemoteCall 不可用时，主漏洞利用仍可能正常工作。")
                    }
                    if isdebugged() {
                        Text("调试器附加时不可用。")
                    }
                    Text("RemoteCall 相对不稳定，可能无法正常工作。")
                    if isIOS16() {
                        Text("iOS 16 提示：点击\"初始化 RemoteCall\"后打开控制中心，可显著提高成功率和速度。")
                            .fontWeight(.semibold)
                            .foregroundColor(.orange)
                        Text("如果约 2 分钟后初始化仍然失败，请注销、重新打开 Lara 再试。")
                            .fontWeight(.semibold)
                            .foregroundColor(.red)
                    }
                }
                .font(.footnote)
            }
            #endif
        }
    }
    
    private var ActionsSection: some View {
        Section(header: HeaderLabel(text: "操作", icon: "wrench.and.screwdriver")) {
            Button("注销", action: {
                mgr.respring()
            })
            
            Button("触发 Panic!", action: {
                mgr.panic()
            })
            
            if isdebugged() {
                Button("断开调试器", action: {
                    exit(0)
                })
            }
        }
    }
    
    private var DebugSection: some View {
        Group {
            if weonadebugbuild_pjbweouttahereexclamationmark {
                if mgr.dsready {
                    Section(header: HeaderLabel(text: "调试专用", icon: "ant")) {
                        LabeledContent("kernel_base") {
                            Text(String(format: "0x%llx", mgr.kernbase))
                                .font(.system(.body, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                        LabeledContent("kernel_slide") {
                            Text(String(format: "0x%llx", mgr.kernslide))
                                .font(.system(.body, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var InlineLogsSection: some View {
        if selectedlogsdisplaymode == .content {
            Section {
                ScrollView {
                    if loggernobs {
                        let combined = logger.logs.joined(separator: "\n")
                        Text(combined)
                            .font(.system(size: 13, design: .monospaced))
                            .lineSpacing(1)
                            .textSelection(.enabled)
                            .onTapGesture {
                                UIPasteboard.general.string = combined
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            }
                    } else {
                        ForEach(Array(logger.logs.enumerated()), id: \.offset) { _, log in
                            Text(log)
                                .font(.system(size: 13, design: .monospaced))
                                .lineSpacing(1)
                                .textSelection(.enabled)
                                .onTapGesture {
                                    UIPasteboard.general.string = log
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                }
                        }
                    }
                }
                .frame(height: 250)
                
                Button("全部复制") {
                    UIPasteboard.general.string = logger.logs.joined(separator: "\n\n")
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                }
                
                Button("清空") {
                    logger.clear()
                }
                .foregroundColor(.red)
            } header: {
                HeaderLabel(text: "日志", icon: "terminal")
            }
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(laramgr())
}
