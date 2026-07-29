//
//  MemHookView.swift
//  lara
//
//  Ballistic hook control panel for the selected process: install /
//  uninstall the DeltaForceClient ballistic inline hook via the KRW
//  cross-process write primitives, live counter polling, and debug
//  toggles publishing instant-hit / tracking to the shared struct.
//

import SwiftUI

struct MemHookView: View {
    let vmmap: UInt64

    @State private var busy = false
    @State private var probed = false
    @State private var installed = false
    @State private var hookaddr: UInt64 = 0
    @State private var caveaddr: UInt64 = 0
    @State private var sharedaddr: UInt64 = 0
    @State private var sharedwritable = false
    @State private var verified = false
    @State private var message: String?
    @State private var callcount: UInt64 = 0
    @State private var instantcount: UInt64 = 0
    @State private var trackcount: UInt64 = 0
    @State private var instantOn = false
    @State private var trackOn = false

    // fixed test rotation for the tracking debug toggle
    private let testPitch: Float = 0.0
    private let testYaw: Float = 90.0

    private let polltimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        Group {
            if vmmap == 0 {
                Text("vm_map 不可用，无法使用功能。")
                    .foregroundColor(.secondary)
            } else {
                Button {
                    install()
                } label: {
                    HStack {
                        Text(installed ? "弹道 hook 已安装" : "安装弹道 hook")
                        if busy {
                            Spacer()
                            ProgressView()
                        }
                    }
                }
                .disabled(busy || installed)

                Button("卸载弹道 hook") {
                    uninstall()
                }
                .disabled(busy || !installed)

                if let message {
                    Text(message)
                        .font(.footnote)
                        .foregroundColor(installed ? .green : .red)
                }

                if installed {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(String(format: "hook:   0x%llx", hookaddr))
                        Text(String(format: "cave:   0x%llx", caveaddr))
                        Text(String(format: "shared: 0x%llx%@", sharedaddr,
                                    sharedwritable ? "" : "（cave 内回退，计数可能崩溃）"))
                        Text("回读校验: \(verified ? "通过" : "未通过")")
                        Text(String(format: "callCount: %llu  instant: %llu  track: %llu",
                                    callcount, instantcount, trackcount))
                    }
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.secondary)

                    Toggle("瞬击", isOn: $instantOn)
                        .disabled(sharedaddr == 0)
                        .onChange(of: instantOn) { v in
                            publishInstant(v)
                        }
                    Toggle("追踪测试（固定 pitch/yaw）", isOn: $trackOn)
                        .disabled(sharedaddr == 0)
                        .onChange(of: trackOn) { v in
                            publishTracking(v)
                        }
                } else if probed && !busy && message == nil {
                    Text("未安装。安装前请确认当前进程是 DeltaForceClient（游戏本体）。")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
            }
        }
        .onAppear(perform: probe)
        .onReceive(polltimer) { _ in pollstats() }
    }

    private func statustext(_ s: Int32) -> String {
        switch s {
        case 0: return "成功"
        case 1: return "未安装"
        case -1: return "参数无效或 KRW 未就绪"
        case -2: return "读取 hook 点失败"
        case -3: return "hook 点指令校验失败（游戏版本不匹配？）"
        case -4: return "未找到 code cave"
        case -5: return "共享结构写入失败"
        case -6: return "stub 写入失败"
        case -7: return "hook 点写入失败（代码页不可写？）"
        case -8: return "回读校验失败"
        case -9: return "已安装（hook 点已是跳转指令）"
        case -10: return "hook 点已是跳转但 stub 不可读"
        default: return "未知错误 \(s)"
        }
    }

    private func apply(_ info: mv_hook_info, installed ok: Bool) {
        installed = ok
        hookaddr = info.hook_address
        caveaddr = info.cave_address
        sharedaddr = info.shared_address
        sharedwritable = info.shared_writable != 0
        verified = info.verified != 0
        callcount = info.call_count
    }

    private func probe() {
        guard vmmap != 0, !busy else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            let base = mv_find_main_macho_base(vmmap)
            var info = mv_hook_info()
            var ok = false
            if base != 0 {
                ok = mv_probe_ballistic_hook(vmmap, base, &info)
            }
            DispatchQueue.main.async {
                probed = true
                if ok {
                    apply(info, installed: true)
                    message = nil
                }
            }
        }
    }

    private func install() {
        guard vmmap != 0, !busy else { return }
        busy = true
        message = nil
        DispatchQueue.global(qos: .userInitiated).async {
            let base = mv_find_main_macho_base(vmmap)
            var info = mv_hook_info()
            var ok = false
            var msg: String
            if base == 0 {
                msg = "未找到主 Mach-O 基址（请确认选中的是游戏进程）。"
            } else {
                ok = mv_install_ballistic_hook(vmmap, base, &info)
                msg = "安装\(ok ? "成功" : "失败")：\(statustext(info.status))"
                if info.status == -3 {
                    msg += String(format: "（实际指令 0x%08x）", info.instruction_before)
                }
            }
            DispatchQueue.main.async {
                busy = false
                if base != 0 {
                    apply(info, installed: ok)
                }
                message = msg
            }
        }
    }

    private func uninstall() {
        guard vmmap != 0, hookaddr != 0, !busy else { return }
        busy = true
        DispatchQueue.global(qos: .userInitiated).async {
            let ok = mv_uninstall_ballistic_hook(vmmap, hookaddr)
            DispatchQueue.main.async {
                busy = false
                if ok {
                    installed = false
                    sharedaddr = 0
                    caveaddr = 0
                    instantOn = false
                    trackOn = false
                    message = "已卸载。"
                } else {
                    message = "卸载失败（hook 点不是跳转指令或写入失败）。"
                }
            }
        }
    }

    private func publishInstant(_ on: Bool) {
        guard sharedaddr != 0 else { return }
        let shared = sharedaddr
        DispatchQueue.global(qos: .userInitiated).async {
            let ok = mv_publish_instant(vmmap, shared, on)
            if !ok {
                DispatchQueue.main.async {
                    message = "瞬击发布失败。"
                }
            }
        }
    }

    private func publishTracking(_ on: Bool) {
        guard sharedaddr != 0 else { return }
        let shared = sharedaddr
        DispatchQueue.global(qos: .userInitiated).async {
            let ok = mv_publish_tracking(vmmap, shared, on, testPitch, testYaw)
            if !ok {
                DispatchQueue.main.async {
                    message = "追踪发布失败。"
                }
            }
        }
    }

    private func pollstats() {
        guard installed, sharedaddr != 0, !busy else { return }
        let shared = sharedaddr
        DispatchQueue.global(qos: .utility).async {
            var c: UInt64 = 0, i: UInt64 = 0, t: UInt64 = 0
            if mv_ballistic_read_stats(vmmap, shared, &c, &i, &t) {
                DispatchQueue.main.async {
                    callcount = c
                    instantcount = i
                    trackcount = t
                }
            }
        }
    }
}
