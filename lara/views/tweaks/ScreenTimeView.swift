import SwiftUI

struct ScreenTimeView: View {
    @ObservedObject var mgr: laramgr
    @AppStorage("lara.screentime.disabled") private var screenTimeDisabled: Bool = false
    @State private var killScreenTimeAgent: Bool = true
    @State private var killUsageTrackingAgent: Bool = true
    @State private var killHomed: Bool = false
    @State private var killFamilycircled: Bool = false
    @State private var isWorking: Bool = false
    @State private var lastResult: String? = nil

    private var backupExists: Bool {
        FileManager.default.fileExists(atPath: "/var/mobile/Library/Preferences/com.apple.ScreenTimeAgent.plist.bak")
    }

    var body: some View {
        List {
            Section(header: HeaderLabel(text: "状态", icon: "hourglass")) {
                HStack {
                    Text("屏幕使用时间")
                    Spacer()
                    Text(screenTimeDisabled ? "已停用" : "已启用")
                        .foregroundColor(screenTimeDisabled ? .red : .green)
                        .monospaced()
                }
                HStack {
                    Text("偏好设置备份")
                    Spacer()
                    Text(backupExists ? "已找到" : "未找到")
                        .foregroundColor(backupExists ? .green : .secondary)
                        .monospaced()
                }
            }

            Section(
                header: HeaderLabel(text: "守护进程", icon: "gearshape.2"),
                footer: Text("选择要停用的守护进程。ScreenTimeAgent 和 UsageTrackingAgent 是完全停用屏幕使用时间所需的最小组合。")
            ) {
                Toggle("ScreenTimeAgent", isOn: $killScreenTimeAgent)
                    .disabled(isWorking || screenTimeDisabled)
                Toggle("UsageTrackingAgent", isOn: $killUsageTrackingAgent)
                    .disabled(isWorking || screenTimeDisabled)
                Toggle("Homed", isOn: $killHomed)
                    .disabled(isWorking || screenTimeDisabled)
                Toggle("Familycircled", isOn: $killFamilycircled)
                    .disabled(isWorking || screenTimeDisabled)
            }

            Section(
                header: HeaderLabel(text: "操作", icon: "wrench.and.screwdriver"),
                footer: Text("结束选中的守护进程，删除屏幕使用时间偏好设置，并在 launchd 的 disabled.plist 中将其标记为停用。更改需要重启设备后生效。")
            ) {
                Button {
                    applyDisable()
                } label: {
                    if isWorking && !screenTimeDisabled {
                        HStack {
                            Text("正在停用…")
                            Spacer()
                            ProgressView()
                        }
                    } else {
                        Text("停用屏幕使用时间")
                    }
                }
                .disabled(isWorking || screenTimeDisabled)

                Button {
                    applyEnable()
                } label: {
                    if isWorking && screenTimeDisabled {
                        HStack {
                            Text("正在启用…")
                            Spacer()
                            ProgressView()
                        }
                    } else {
                        Text("启用屏幕使用时间")
                    }
                }
                .disabled(isWorking || !screenTimeDisabled)
            }
        }
        .navigationTitle("屏幕使用时间")
        .onAppear {
            if !screenTimeDisabled {
                syncStateFromPlist()
            }
        }
        .alert("结果", isPresented: .constant(lastResult != nil)) {
            Button("好") { lastResult = nil }
        } message: {
            Text(lastResult ?? "")
        }
    }

    private func syncStateFromPlist() {
        DispatchQueue.global(qos: .userInitiated).async {
            let plistPath = "/private/var/db/com.apple.xpc.launchd/disabled.plist"
            let daemonLabels = [
                "com.apple.ScreenTimeAgent",
                "com.apple.UsageTrackingAgent",
            ]
            guard let data = NSData(contentsOfFile: plistPath) as Data?,
                  let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] else {
                return
            }
            let allDisabled = daemonLabels.allSatisfy { (plist[$0] as? Bool) == true }
            if allDisabled {
                DispatchQueue.main.async {
                    screenTimeDisabled = true
                }
            }
        }
    }

    private func applyDisable() {
        isWorking = true
        let agent = killScreenTimeAgent
        let usage = killUsageTrackingAgent
        let homed = killHomed
        let family = killFamilycircled
        DispatchQueue.global(qos: .userInitiated).async {
            let ok = screentime_disable(agent, usage, homed, family)
            DispatchQueue.main.async {
                isWorking = false
                if ok {
                    screenTimeDisabled = true
                    lastResult = "屏幕使用时间已停用。重启设备后生效。"
                } else {
                    lastResult = "操作失败。请查看日志了解详情。"
                }
            }
        }
    }

    private func applyEnable() {
        isWorking = true
        DispatchQueue.global(qos: .userInitiated).async {
            let ok = screentime_enable()
            DispatchQueue.main.async {
                isWorking = false
                if ok {
                    screenTimeDisabled = false
                    lastResult = "屏幕使用时间已启用。重启设备后生效。"
                } else {
                    lastResult = "操作失败。请查看日志了解详情。"
                }
            }
        }
    }
}
