import AppKit
@testable import GhosttyTerminal
import SwiftUI
import Testing

/// `TerminalSurfaceView` observes its whole state, so a program that retitles
/// its window or scrolls re-runs the body many times a second. The platform
/// view's update pass runs only for a change it reads.
@Suite("TerminalSurfaceUpdateGating", .serialized)
struct TerminalSurfaceUpdateGatingTests {
    @Test
    @MainActor
    func `a publish the platform view does not read skips its update pass`() async {
        let harness = await GhosttySurfaceHarness.make()
        defer { harness.tearDown() }
        let host = UpdateHost()
        await host.settle()
        let updatesBefore = host.view.updates

        for index in 0 ..< 5 {
            host.state.terminalDidChangeTitle("title \(index)")
            await host.pump()
        }

        #expect(host.state.title == "title 4", "the titles were published")
        #expect(host.view.updates == updatesBefore, "no title reached the update pass")
    }

    @Test
    @MainActor
    func `a change the platform view reads runs its update pass`() async {
        let harness = await GhosttySurfaceHarness.make()
        defer { harness.tearDown() }
        let host = UpdateHost()
        await host.settle()
        let updatesBefore = host.view.updates

        host.state.configuration.resizeThrottleMilliseconds = 10
        await host.pump()

        #expect(host.view.updates > updatesBefore)
    }
}

private struct FocusedSurface: View {
    let state: TerminalViewState
    @FocusState private var focused: Bool

    var body: some View {
        TerminalSurfaceView(context: state)
            .terminalFocusOnAppear($focused)
            .frame(width: 320, height: 240)
    }
}

@MainActor
private final class UpdateHost {
    let state = TerminalViewState()
    let window: NSWindow

    init() {
        state.configuration.backend = .inMemory(
            InMemoryTerminalSession(write: { _ in }, resize: { _ in }),
        )
        state.makePlatformView = { UpdateCountingTerminalView(frame: .zero) }
        window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 320, height: 240),
            styleMask: [.titled],
            backing: .buffered,
            defer: false,
        )
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: FocusedSurface(state: state))
        window.orderFront(nil)
    }

    var view: UpdateCountingTerminalView {
        state.attachedView as! UpdateCountingTerminalView
    }

    func pump() async {
        try? await Task.sleep(for: .milliseconds(250))
    }

    /// Waits out the update passes a new window runs on its own: its first
    /// layouts, the publishes they provoke, and the window becoming key.
    func settle() async {
        var quietPumps = 0
        var updates = view.updates
        while quietPumps < 3 {
            await pump()
            quietPumps = updates == view.updates ? quietPumps + 1 : 0
            updates = view.updates
        }
    }

    deinit {
        MainActor.assumeIsolated {
            window.contentView = nil
            window.orderOut(nil)
        }
    }
}

/// `configureView` assigns `configuration` on every update pass.
private final class UpdateCountingTerminalView: AppTerminalView {
    private(set) var updates = 0

    override var configuration: TerminalSurfaceOptions {
        get { super.configuration }
        set {
            updates += 1
            super.configuration = newValue
        }
    }
}
