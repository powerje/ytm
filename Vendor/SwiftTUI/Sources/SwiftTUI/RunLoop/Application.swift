import Foundation
#if os(macOS)
import AppKit
#endif

public class Application {
    private let node: Node
    private let window: Window
    private let control: Control
    private let renderer: Renderer

    private let runLoopType: RunLoopType

    private var arrowKeyParser = ArrowKeyParser()
    private let keyEventParser = KeyEventParser()

    /// When set, every decoded key press is offered to this handler first.
    /// Return `true` to consume the event; `false` falls through to the
    /// default focus-based handling.
    public var keyHandler: ((KeyEvent) -> Bool)?

    /// Called once, before the terminal is restored and the process exits.
    public var willStop: (() -> Void)?

    /// Terminal attributes captured before entering raw mode, restored on
    /// any exit path (including crashes) through `atexit`.
    private static var originalTermios: termios?
    private static var exitHandlerInstalled = false

    private var invalidatedNodes: [Node] = []
    private var updateScheduled = false

    public init<I: View>(rootView: I, runLoopType: RunLoopType = .dispatch) {
        self.runLoopType = runLoopType

        node = Node(view: VStack(content: rootView).view)
        node.build()

        control = node.control!

        window = Window()
        window.addControl(control)

        window.firstResponder = control.firstSelectableElement
        window.firstResponder?.becomeFirstResponder()

        renderer = Renderer(layer: window.layer)
        window.layer.renderer = renderer

        node.application = self
        renderer.application = self
    }

    var stdInSource: DispatchSourceRead?
    private var sigIntSource: DispatchSourceSignal?
    private var sigTermSource: DispatchSourceSignal?
    private var sigHupSource: DispatchSourceSignal?

    public enum RunLoopType {
        /// The default option, using Dispatch for the main run loop.
        case dispatch

        /// Runs the main thread's `RunLoop`. Unlike `dispatch`, work on the
        /// main queue is executed on the main thread itself, which Swift
        /// concurrency's `MainActor` requires.
        case runLoop

        #if os(macOS)
        /// This creates and runs an NSApplication with an associated run loop. This allows you
        /// e.g. to open NSWindows running simultaneously to the terminal app. This requires macOS
        /// and AppKit.
        case cocoa
        #endif
    }

    public func start() {
        setInputMode()
        updateWindowSize()
        control.layout(size: window.layer.frame.size)
        renderer.draw()

        let stdInSource = DispatchSource.makeReadSource(fileDescriptor: STDIN_FILENO, queue: .main)
        stdInSource.setEventHandler(qos: .default, flags: [], handler: self.handleInput)
        stdInSource.resume()
        self.stdInSource = stdInSource

        let sigWinChSource = DispatchSource.makeSignalSource(signal: SIGWINCH, queue: .main)
        sigWinChSource.setEventHandler(qos: .default, flags: [], handler: self.handleWindowSizeChange)
        sigWinChSource.resume()

        signal(SIGINT, SIG_IGN)
        let sigIntSource = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
        sigIntSource.setEventHandler(qos: .default, flags: [], handler: self.stop)
        sigIntSource.resume()
        self.sigIntSource = sigIntSource

        signal(SIGTERM, SIG_IGN)
        let sigTermSource = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        sigTermSource.setEventHandler(qos: .default, flags: [], handler: self.stop)
        sigTermSource.resume()
        self.sigTermSource = sigTermSource

        signal(SIGHUP, SIG_IGN)
        let sigHupSource = DispatchSource.makeSignalSource(signal: SIGHUP, queue: .main)
        sigHupSource.setEventHandler(qos: .default, flags: [], handler: self.stop)
        sigHupSource.resume()
        self.sigHupSource = sigHupSource

        switch runLoopType {
        case .dispatch:
            dispatchMain()
        case .runLoop:
            while true {
                RunLoop.main.run(mode: .default, before: .distantFuture)
            }
        #if os(macOS)
        case .cocoa:
            NSApplication.shared.setActivationPolicy(.accessory)
            NSApplication.shared.run()
        #endif
        }
    }

    private func setInputMode() {
        var tattr = termios()
        tcgetattr(STDIN_FILENO, &tattr)
        if Application.originalTermios == nil {
            Application.originalTermios = tattr
        }
        tattr.c_lflag &= ~tcflag_t(ECHO | ICANON)
        tcsetattr(STDIN_FILENO, TCSAFLUSH, &tattr);
        if !Application.exitHandlerInstalled {
            Application.exitHandlerInstalled = true
            atexit { Application.restoreTerminal() }
        }
    }

    /// Restores the terminal to the state it had before `start()`. Safe to
    /// call more than once.
    public static func restoreTerminal() {
        guard var tattr = originalTermios else { return }
        tcsetattr(STDIN_FILENO, TCSAFLUSH, &tattr)
        let reset = EscapeSequence.disableAlternateBuffer + EscapeSequence.showCursor
        reset.withCString { _ = write(STDOUT_FILENO, $0, strlen($0)) }
    }

    private func handleInput() {
        let data = FileHandle.standardInput.availableData

        guard let string = String(data: data, encoding: .utf8) else {
            return
        }

        if let keyHandler {
            var unhandled = ""
            for event in keyEventParser.parse(string) {
                if keyHandler(event) { continue }
                switch event {
                case .character(let c): unhandled.append(c)
                case .enter: unhandled.append("\n")
                case .backspace: unhandled.append(ASCII.DEL)
                case .tab: unhandled.append("\t")
                case .up: unhandled.append("\u{1b}[A")
                case .down: unhandled.append("\u{1b}[B")
                case .right: unhandled.append("\u{1b}[C")
                case .left: unhandled.append("\u{1b}[D")
                case .escape, .pageUp, .pageDown, .home, .end: break
                }
            }
            handleCharacters(unhandled)
            return
        }
        handleCharacters(string)
    }

    private func handleCharacters(_ string: String) {
        for char in string {
            if arrowKeyParser.parse(character: char) {
                guard let key = arrowKeyParser.arrowKey else { continue }
                arrowKeyParser.arrowKey = nil
                if key == .down {
                    if let next = window.firstResponder?.selectableElement(below: 0) {
                        window.firstResponder?.resignFirstResponder()
                        window.firstResponder = next
                        window.firstResponder?.becomeFirstResponder()
                    }
                } else if key == .up {
                    if let next = window.firstResponder?.selectableElement(above: 0) {
                        window.firstResponder?.resignFirstResponder()
                        window.firstResponder = next
                        window.firstResponder?.becomeFirstResponder()
                    }
                } else if key == .right {
                    if let next = window.firstResponder?.selectableElement(rightOf: 0) {
                        window.firstResponder?.resignFirstResponder()
                        window.firstResponder = next
                        window.firstResponder?.becomeFirstResponder()
                    }
                } else if key == .left {
                    if let next = window.firstResponder?.selectableElement(leftOf: 0) {
                        window.firstResponder?.resignFirstResponder()
                        window.firstResponder = next
                        window.firstResponder?.becomeFirstResponder()
                    }
                }
            } else if char == ASCII.EOT {
                stop()
            } else {
                window.firstResponder?.handleEvent(char)
            }
        }
    }

    func invalidateNode(_ node: Node) {
        invalidatedNodes.append(node)
        scheduleUpdate()
    }

    func scheduleUpdate() {
        if !updateScheduled {
            DispatchQueue.main.async { self.update() }
            updateScheduled = true
        }
    }

    private func update() {
        updateScheduled = false

        for node in invalidatedNodes {
            node.update(using: node.view)
        }
        invalidatedNodes = []

        control.layout(size: window.layer.frame.size)
        renderer.update()
    }

    private func handleWindowSizeChange() {
        updateWindowSize()
        control.layer.invalidate()
        update()
    }

    private func updateWindowSize() {
        var size = winsize()
        guard ioctl(STDOUT_FILENO, UInt(TIOCGWINSZ), &size) == 0,
              size.ws_col > 0, size.ws_row > 0 else {
            assertionFailure("Could not get window size")
            return
        }
        window.layer.frame.size = Size(width: Extended(Int(size.ws_col)), height: Extended(Int(size.ws_row)))
        renderer.setCache()
    }

    /// Stops the application: restores the terminal and exits the process.
    public func quit() {
        stop()
    }

    private func stop() {
        willStop?()
        willStop = nil
        renderer.stop()
        resetInputMode() // Fix for: https://github.com/rensbreur/SwiftTUI/issues/25
        exit(0)
    }

    /// Fix for: https://github.com/rensbreur/SwiftTUI/issues/25
    private func resetInputMode() {
        // Reset ECHO and ICANON values:
        var tattr = termios()
        tcgetattr(STDIN_FILENO, &tattr)
        tattr.c_lflag |= tcflag_t(ECHO | ICANON)
        tcsetattr(STDIN_FILENO, TCSAFLUSH, &tattr);
    }

}
