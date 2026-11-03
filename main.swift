import AppKit
import AVFoundation
import Vision
import ServiceManagement
import Carbon

let yawLimit = 35.0 * Double.pi / 180   // tune: head turn that counts as "away"
let framesNeeded = 3                    // at ~3 fps ≈ 1 s

let teams = NSAppleScript(source: """
tell application "Google Chrome"
  activate
  if (count of windows) = 0 then make new window
  set found to false
  repeat with w in windows
    set i to 0
    repeat with t in tabs of w
      set i to i + 1
      if URL of t contains "teams.cloud.microsoft" or URL of t contains "teams.microsoft.com" then
        set active tab index of w to i
        set index of w to 1
        set found to true
        exit repeat
      end if
    end repeat
    if found then exit repeat
  end repeat
  if not found then tell front window to make new tab with properties {URL:"https://teams.cloud.microsoft/"}
end tell
""")!

final class App: NSObject, NSApplicationDelegate, AVCaptureVideoDataOutputSampleBufferDelegate {
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    let session = AVCaptureSession()
    let handler = VNSequenceRequestHandler()
    let request = VNDetectFaceRectanglesRequest()
    let pauseItem = NSMenuItem(title: "Pause", action: #selector(toggle), keyEquivalent: "")
    let loginItem = NSMenuItem(title: "Launch at login", action: #selector(toggleLogin), keyEquivalent: "")
    var paused = false
    var fired = false
    var away = 0, front = 0   // only touched on the capture queue
    var last = 0.0

    func applicationDidFinishLaunching(_ n: Notification) {
        let menu = NSMenu()
        pauseItem.target = self; loginItem.target = self
        menu.addItem(pauseItem); menu.addItem(loginItem)
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        item.menu = menu
        if !UserDefaults.standard.bool(forKey: "init") {
            UserDefaults.standard.set(true, forKey: "init")
            try? SMAppService.mainApp.register()
        }
        refreshUI()
        setupHotkey()
        AVCaptureDevice.requestAccess(for: .video) { ok in
            DispatchQueue.main.async { ok ? self.setupCamera() : self.refreshUI() }
        }
    }

    func setupCamera() {
        guard let dev = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: dev) else { return }
        session.beginConfiguration()
        session.sessionPreset = .low
        session.addInput(input)
        let out = AVCaptureVideoDataOutput()
        out.alwaysDiscardsLateVideoFrames = true
        out.setSampleBufferDelegate(self, queue: DispatchQueue(label: "cam"))
        session.addOutput(out)
        session.commitConfiguration()
        if (try? dev.lockForConfiguration()) != nil {
            // slowest rate the format allows (3 fps may be unsupported and throws); captureOutput throttles the rest
            if let low = dev.activeFormat.videoSupportedFrameRateRanges.map({ $0.minFrameRate }).min(), low > 0 {
                let d = CMTime(value: 1000, timescale: Int32(low * 1000))
                dev.activeVideoMinFrameDuration = d
                dev.activeVideoMaxFrameDuration = d
            }
            dev.unlockForConfiguration()
        }
        if !paused { session.startRunning() }
    }

    func captureOutput(_ o: AVCaptureOutput, didOutput sb: CMSampleBuffer, from c: AVCaptureConnection) {
        let t = CMSampleBufferGetPresentationTimeStamp(sb).seconds
        if t - last < 0.3 { return }   // ~3 fps
        last = t
        guard let px = CMSampleBufferGetImageBuffer(sb) else { return }
        try? handler.perform([request], on: px)
        guard let yaw = (request.results?.first)?.yaw?.doubleValue else { return }  // no face: ignore
        if abs(yaw) > yawLimit { away += 1; front = 0 } else { front += 1; away = 0 }
        if !fired && away >= framesNeeded {
            fired = true
            DispatchQueue.main.async { teams.executeAndReturnError(nil) }
        } else if fired && front >= framesNeeded {
            fired = false   // re-arm
        }
    }

    @objc func toggle() {
        paused.toggle()
        if paused { session.stopRunning() } else { away = 0; front = 0; if !session.inputs.isEmpty { session.startRunning() } }
        refreshUI()
    }

    @objc func toggleLogin() {
        let s = SMAppService.mainApp
        if s.status == .enabled { try? s.unregister() } else { try? s.register() }
        refreshUI()
    }

    func refreshUI() {
        pauseItem.title = paused ? "Resume" : "Pause"
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
        item.button?.title = paused ? "👁‍🗨" : "👁"
    }

    func setupHotkey() {  // Ctrl+Opt+L
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            DispatchQueue.main.async { (NSApp.delegate as? App)?.toggle() }
            return noErr
        }, 1, &spec, nil, nil)
        var ref: EventHotKeyRef?
        RegisterEventHotKey(UInt32(kVK_ANSI_L), UInt32(controlKey | optionKey),
                            EventHotKeyID(signature: 0x4C4B4157, id: 1), GetApplicationEventTarget(), 0, &ref)
    }
}

let app = NSApplication.shared
let delegate = App()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
