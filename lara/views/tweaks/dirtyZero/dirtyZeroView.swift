//
//  dirtyZeroView.swift
//  lara
//
//  Created by lunginspector on 5/14/26.
//

import SwiftUI

struct dirtyZeroView: View {
    @EnvironmentObject private var mgr: laramgr
    @AppStorage("tweakArray") var tweakArray: [ZeroSection] = TweakArray.tweaks
    @AppStorage("enableRiskyTweaks") var enableRiskyTweaks: Bool = false
    
    var body: some View {
        NavigationStack {
            List {
                Section(header: HeaderLabel(text: "操作", icon: "wrench.and.screwdriver"), footer: Text("所有修改都在内存中完成，如果出现问题，请重启设备。由 [jailbreak.party](https://jailbreak.party) 倾情制作。这部分功能也有[独立 App](https://github.com/jailbreakdotparty/dirtyZero)！")) {
                    Button("应用所选功能", action: {
                        applyTweaks()
                    })
                    Button("注销", action: {
                        mgr.respring()
                    })
                    Toggle("启用高风险功能", isOn: $enableRiskyTweaks)
                }
                
                ListedTweaksSection
            }
            .navigationTitle("dirtyZero")
        }
    }
    
    private var ListedTweaksSection: some View {
        ForEach($tweakArray) { $section in
            if (section.name == "Risky Tweaks" && enableRiskyTweaks) || section.name != "Risky Tweaks" {
                Section(header: HeaderDropdown(text: section.name, icon: section.icon, isExpanded: $section.isExpanded, useItemCount: true, itemCount: section.tweaks.count)) {
                    if section.isExpanded {
                        ForEach($section.tweaks) { $tweak in
                            if (doubleSystemVersion() >= tweak.minSupportedVersion && doubleSystemVersion() <= tweak.maxSupportedVersion) || weonadebugbuild_pjbweouttahereexclamationmark {
                                PlainToggle(text: tweak.name, icon: tweak.icon, isOn: $tweak.isOn)
                            }
                        }
                    }
                }
            }
        }
    }
    
    func applyTweaks() {
        let tweaks = tweakArray.flatMap { $0.tweaks }.filter { $0.isOn }
        
        for tweak in tweaks {
            for path in tweak.paths {
                _ = mgr.vfszeropage(at: path, dumb: true)
            }
        }
        
        Alertinator.shared.alert(title: "已尝试应用所有功能！", body: "请注销设备以查看更改。用 DarkSword 清零文件比较玄学，可能需要多应用几次！", actionLabel: "注销", action: {
            mgr.respring()
        })
    }
}

// allows us to put arrays into AppStorage
extension Array: @retroactive RawRepresentable where Element: Codable {
    public init?(rawValue: String) {
        guard let data = rawValue.data(using: .utf8),
              let result = try? JSONDecoder().decode([Element].self, from: data)
        else {
            return nil
        }
        self = result
    }
    
    public var rawValue: String {
        guard let data = try? JSONEncoder().encode(self),
              let result = String(data: data, encoding: .utf8)
        else {
            return "[]"
        }
        return result
    }
}
