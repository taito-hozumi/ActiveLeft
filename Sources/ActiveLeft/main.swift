import AppKit
import Dispatch
import Foundation

final class CaffeinateController {
    private var process: Process?

    var onStateChanged: (() -> Void)?

    var isActive: Bool {
        process?.isRunning == true
    }

    func start() throws {
        cleanupExitedProcess()

        guard !isActive else {
            return
        }

        let nextProcess = Process()
        nextProcess.executableURL = URL(fileURLWithPath: "/usr/bin/caffeinate")
        nextProcess.arguments = ["-d", "-w", String(getpid())]
        nextProcess.standardInput = FileHandle.nullDevice
        nextProcess.standardOutput = FileHandle.nullDevice
        nextProcess.standardError = FileHandle.nullDevice
        nextProcess.terminationHandler = { [weak self] finishedProcess in
            DispatchQueue.main.async {
                guard let self, self.process === finishedProcess else {
                    return
                }

                self.process = nil
                self.onStateChanged?()
            }
        }

        try nextProcess.run()
        process = nextProcess
        onStateChanged?()
    }

    func stop() {
        cleanupExitedProcess()

        guard let currentProcess = process else {
            onStateChanged?()
            return
        }

        if currentProcess.isRunning {
            currentProcess.terminate()

            if !waitForExit(currentProcess, timeout: 2.0) {
                kill(currentProcess.processIdentifier, SIGKILL)
                _ = waitForExit(currentProcess, timeout: 1.0)
            }
        }

        if process === currentProcess {
            process = nil
        }

        onStateChanged?()
    }

    private func cleanupExitedProcess() {
        if let currentProcess = process, !currentProcess.isRunning {
            process = nil
        }
    }

    private func waitForExit(_ process: Process, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)

        while process.isRunning && Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
        }

        return !process.isRunning
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let caffeinateController = CaffeinateController()
    private var signalSources: [DispatchSourceSignal] = []
    private var statusItem: NSStatusItem?

    private lazy var statusMenu: NSMenu = {
        let menu = NSMenu()
        menu.autoenablesItems = false

        let toggleItem = NSMenuItem(
            title: "Switch to Active",
            action: #selector(toggleFromMenu),
            keyEquivalent: ""
        )
        toggleItem.target = self
        menu.addItem(toggleItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: "Quit ActiveLeft",
            action: #selector(quit),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)

        return menu
    }()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        installSignalHandlers()

        caffeinateController.onStateChanged = { [weak self] in
            self?.renderStatus()
        }

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem = item

        if let button = item.button {
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.toolTip = "ActiveLeft"
        }

        renderStatus()
    }

    func applicationWillTerminate(_ notification: Notification) {
        caffeinateController.stop()
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        let isContextClick = event?.type == .rightMouseUp
            || event?.modifierFlags.contains(.control) == true

        if isContextClick {
            showMenu(from: sender)
        } else {
            toggleState()
        }
    }

    @objc private func toggleFromMenu() {
        toggleState()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func toggleState() {
        if caffeinateController.isActive {
            caffeinateController.stop()
            return
        }

        do {
            try caffeinateController.start()
        } catch {
            renderStatus()
            showStartError(error)
        }
    }

    private func renderStatus() {
        let state = caffeinateController.isActive ? "Active" : "Left"
        statusItem?.button?.title = "ActiveLeft: \(state)"
        statusItem?.button?.toolTip = "ActiveLeft is \(state)"

        if let toggleItem = statusMenu.items.first {
            toggleItem.title = caffeinateController.isActive
                ? "Switch to Left"
                : "Switch to Active"
        }
    }

    private func showMenu(from button: NSStatusBarButton) {
        renderStatus()

        statusItem?.menu = statusMenu
        button.performClick(nil)
        statusItem?.menu = nil
    }

    private func showStartError(_ error: Error) {
        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "ActiveLeft could not start"
        alert.informativeText = "Failed to run /usr/bin/caffeinate: \(error.localizedDescription)"
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func installSignalHandlers() {
        [SIGINT, SIGTERM, SIGHUP].forEach { signalNumber in
            signal(signalNumber, SIG_IGN)

            let source = DispatchSource.makeSignalSource(signal: signalNumber, queue: .main)
            source.setEventHandler { [weak self] in
                self?.caffeinateController.stop()
                exit(128 + signalNumber)
            }
            source.resume()
            signalSources.append(source)
        }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()

if CommandLine.arguments.contains("--self-test") {
    let controller = CaffeinateController()

    do {
        try controller.start()
        print("ActiveLeft self-test: started caffeinate")
        sleep(3)
        controller.stop()
        print("ActiveLeft self-test: stopped caffeinate")
        exit(0)
    } catch {
        fputs("ActiveLeft self-test failed: \(error.localizedDescription)\n", stderr)
        exit(1)
    }
}

if let bundleIdentifier = Bundle.main.bundleIdentifier {
    let existingInstance = NSRunningApplication
        .runningApplications(withBundleIdentifier: bundleIdentifier)
        .first { application in
            application.processIdentifier != getpid() && !application.isTerminated
        }

    if let existingInstance {
        existingInstance.activate()
        exit(0)
    }
}

app.delegate = delegate
app.run()
