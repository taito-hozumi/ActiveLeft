import AppKit
import Dispatch
import Foundation

final class CaffeinateController {
    private var systemProcess: Process?
    private var displayProcess: Process?

    var onStateChanged: (() -> Void)?

    var isActive: Bool {
        displayProcess?.isRunning == true
    }

    func startSystemAwake() throws {
        cleanupExitedProcess()

        guard systemProcess?.isRunning != true else {
            return
        }

        systemProcess = try startCaffeinate(arguments: ["-i", "-s", "-w", String(getpid())])
    }

    func startDisplayAwake() throws {
        try startSystemAwake()
        cleanupExitedProcess()

        guard displayProcess?.isRunning != true else {
            return
        }

        displayProcess = try startCaffeinate(arguments: ["-d", "-w", String(getpid())])
        onStateChanged?()
    }

    func stopDisplayAwake() {
        cleanupExitedProcess()

        guard let currentProcess = displayProcess else {
            onStateChanged?()
            return
        }

        stopProcess(currentProcess)

        if displayProcess === currentProcess {
            displayProcess = nil
        }

        onStateChanged?()
    }

    func stopAll() {
        cleanupExitedProcess()

        if let currentProcess = displayProcess {
            stopProcess(currentProcess)
        }

        if let currentProcess = systemProcess {
            stopProcess(currentProcess)
        }

        displayProcess = nil
        systemProcess = nil
        onStateChanged?()
    }

    private func startCaffeinate(arguments: [String]) throws -> Process {
        let nextProcess = Process()
        nextProcess.executableURL = URL(fileURLWithPath: "/usr/bin/caffeinate")
        nextProcess.arguments = arguments
        nextProcess.standardInput = FileHandle.nullDevice
        nextProcess.standardOutput = FileHandle.nullDevice
        nextProcess.standardError = FileHandle.nullDevice
        nextProcess.terminationHandler = { [weak self] finishedProcess in
            DispatchQueue.main.async {
                guard let self else { return }

                if self.displayProcess === finishedProcess {
                    self.displayProcess = nil
                    self.onStateChanged?()
                }

                if self.systemProcess === finishedProcess {
                    self.systemProcess = nil
                }
            }
        }

        try nextProcess.run()
        return nextProcess
    }

    private func stopProcess(_ currentProcess: Process) {
        if currentProcess.isRunning {
            currentProcess.terminate()

            if !waitForExit(currentProcess, timeout: 2.0) {
                kill(currentProcess.processIdentifier, SIGKILL)
                _ = waitForExit(currentProcess, timeout: 1.0)
            }
        }
    }

    private func cleanupExitedProcess() {
        if let currentProcess = systemProcess, !currentProcess.isRunning {
            systemProcess = nil
        }

        if let currentProcess = displayProcess, !currentProcess.isRunning {
            displayProcess = nil
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

        do {
            try caffeinateController.startSystemAwake()
        } catch {
            showStartError(error)
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
        caffeinateController.stopAll()
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
            caffeinateController.stopDisplayAwake()
            return
        }

        do {
            try caffeinateController.startDisplayAwake()
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
                self?.caffeinateController.stopAll()
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
        try controller.startSystemAwake()
        print("ActiveLeft self-test: started system caffeinate")
        try controller.startDisplayAwake()
        print("ActiveLeft self-test: started display caffeinate")
        sleep(3)
        controller.stopDisplayAwake()
        print("ActiveLeft self-test: stopped display caffeinate")
        sleep(2)
        controller.stopAll()
        print("ActiveLeft self-test: stopped system caffeinate")
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
