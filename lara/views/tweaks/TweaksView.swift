//
//  TweaksView.swift
//  lara
//
//  Created by lunginspector on 5/3/26.
//

import SwiftUI

struct TweaksView: View {
    @AppStorage("logsdisplaymode") private var selectedlogsdisplaymode: logsdisplaymode = .toolbar
    @ObservedObject var mgr: laramgr
    
    var body: some View {
        NavigationStack {
            List {
                Section(header: HeaderLabel(text: "SpringBoard", icon: "house")) {
                    NavigationLink("RemoteCall 定制", destination: RemoteView(mgr: mgr))
                        .disabled(!mgr.rcready)
                    NavigationLink("Liquid Glass", destination: LiquidGlassView())
                        .disabled(!mgr.vfsready)
                    NavigationLink("SpringBoard 定制", destination: SpringBoardView(mgr: mgr))
                        .disabled(!mgr.vfsready)
                }
                
                Section(header: HeaderLabel(text: "锁屏", icon: "lock")) {
                    NavigationLink("密码主题", destination: PasscodeView(mgr: mgr))
                        .disabled(!mgr.sbxready)
                }
                
                Section(header: HeaderLabel(text: "应用", icon: "app")) {
                    NavigationLink("卡片覆盖", destination: CardView())
                        .disabled(!mgr.vfsready)
                    NavigationLink("应用解密", destination: DecryptView())
                        .disabled(!mgr.sbxready)
                    NavigationLink("3 应用限制绕过", destination: AppsView())
                        .disabled(!mgr.sbxready)
                    NavigationLink("黑名单解除", destination: WhitelistView())
                        .disabled(!mgr.sbxready)
                    NavigationLink("JIT 启用", destination: JitView())
                        .disabled(!mgr.sbxready)
                }
                
                Section(header: HeaderLabel(text: "用户界面", icon: "eye")) {
                    NavigationLink("dirtyZero", destination: dirtyZeroView())
                        .disabled(!mgr.vfsready)
                    NavigationLink("显示隐藏图标", destination: ShowHiddenIconsView(mgr: mgr))
                        .disabled(!mgr.sbxready && !mgr.vfsready)
                    NavigationLink("MobileGestalt", destination: GestaltView(mgr: mgr))
                        .disabled(!mgr.sbxready)
                    NavigationLink("字体覆盖", destination: FontPicker(mgr: mgr))
                        .disabled(!mgr.vfsready)
                    NavigationLink("系统颜色补丁", destination: SystemColor(mgr: mgr))
                        .disabled(!mgr.sbxready || !mgr.vfsready)
                }
                
                Section(header: HeaderLabel(text: "系统", icon: "gear")) {
                    NavigationLink("VarClean", destination: VarCleanView())
                        .disabled(!mgr.sbxready)
                    NavigationLink("自定义覆盖", destination: CustomView(mgr: mgr))
                        .disabled(!mgr.vfsready)
                    NavigationLink("OTA 更新", destination: OTAView(mgr: mgr))
                    NavigationLink("屏幕使用时间", destination: ScreenTimeView(mgr: mgr))
                }
                
                Section(header: HeaderLabel(text: "已损坏", icon: "exclamationmark.triangle.fill")) {
                    NavigationLink("DarkBoard", destination: DarkBoardView())
                        .disabled(true)
                }
                
                NavigationLink("额外工具", destination: ToolsView())
            }
            .disabled(!mgr.dsready)
            .navigationTitle("功能")
            .toolbar {
                if selectedlogsdisplaymode == .toolbar {
                    Button(action: {
                        mgr.showLogs.toggle()
                    }) {
                        Image(systemName: "terminal")
                    }
                }
            }
        }
    }
}
