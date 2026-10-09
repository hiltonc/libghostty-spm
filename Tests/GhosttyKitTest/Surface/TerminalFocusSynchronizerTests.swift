import AppKit
@testable import GhosttyTerminal
import Testing

/// A host's focus binding can hold true while something else has first
/// responder: a menu, a text field, a `FocusState` the bridge's false never
/// reached. The terminal redraws many times a second, and each redraw may run
/// the update pass, so an update that finds the binding as it was must not
/// take first responder back.
@Suite("TerminalFocusSynchronizer", .serialized)
struct TerminalFocusSynchronizerTests {
    @Test
    @MainActor
    func `repeated updates with an unchanged binding never take first responder`() async {
        let host = ResponderHost()
        let synchronizer = TerminalFocusSynchronizer()
        let binding = TerminalFocusBinding(read: { true }, write: { _ in })

        synchronizer.attach(to: host.terminal, binding: binding, request: true)
        await host.pump()
        #expect(host.window.firstResponder === host.terminal, "a request that turns true acquires")
        #expect(host.terminal.acquisitions == 1)

        host.window.makeFirstResponder(host.field)
        for _ in 0 ..< 50 {
            synchronizer.attach(to: host.terminal, binding: binding, request: true)
        }
        await host.pump()

        #expect(host.terminal.acquisitions == 1, "the binding never changed, so no update acted on it")
        #expect(host.window.firstResponder !== host.terminal, "the field keeps first responder")
    }

    @Test
    @MainActor
    func `a request that turns true again acquires again`() async {
        let host = ResponderHost()
        let synchronizer = TerminalFocusSynchronizer()
        let binding = TerminalFocusBinding(read: { true }, write: { _ in })

        synchronizer.attach(to: host.terminal, binding: binding, request: true)
        await host.pump()
        host.window.makeFirstResponder(host.field)
        synchronizer.attach(to: host.terminal, binding: binding, request: false)
        synchronizer.attach(to: host.terminal, binding: binding, request: true)
        await host.pump()

        #expect(host.terminal.acquisitions == 2)
        #expect(host.window.firstResponder === host.terminal)
    }

    @Test
    @MainActor
    func `the view's first window reads the binding as it is then`() async {
        let host = ResponderHost()
        let synchronizer = TerminalFocusSynchronizer()
        var requested = false
        let binding = TerminalFocusBinding(read: { requested }, write: { _ in })

        synchronizer.attach(to: host.terminal, binding: binding, request: false)
        requested = true
        synchronizer.acquireIfRequested()
        await host.pump()
        #expect(host.window.firstResponder === host.terminal, "the request written after the view was built is honoured")

        host.window.makeFirstResponder(host.field)
        synchronizer.attach(to: host.terminal, binding: binding, request: true)
        await host.pump()
        #expect(host.terminal.acquisitions == 1, "the request the window read is not acted on twice")
    }
}

@MainActor
private final class ResponderHost {
    let window = NSWindow(
        contentRect: CGRect(x: 0, y: 0, width: 320, height: 240),
        styleMask: [.titled],
        backing: .buffered,
        defer: false,
    )
    let terminal = CountingTerminalView(frame: CGRect(x: 0, y: 40, width: 320, height: 200))
    let field = NSTextField(frame: CGRect(x: 0, y: 0, width: 320, height: 30))

    init() {
        window.isReleasedWhenClosed = false
        window.contentView?.addSubview(terminal)
        window.contentView?.addSubview(field)
        window.orderFront(nil)
    }

    /// Suspends so the main queue drains the acquire's runloop hop.
    func pump() async {
        try? await Task.sleep(for: .milliseconds(100))
    }

    deinit {
        MainActor.assumeIsolated {
            window.orderOut(nil)
        }
    }
}

private final class CountingTerminalView: AppTerminalView {
    private(set) var acquisitions = 0

    override func becomeFirstResponder() -> Bool {
        acquisitions += 1
        return super.becomeFirstResponder()
    }
}
