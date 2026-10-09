//
//  TerminalViewRepresentable.swift
//  libghostty-spm
//
//  Created by Lakr233 on 2026/3/16.
//

import SwiftUI
#if canImport(UIKit)
    import UIKit
#elseif canImport(AppKit)
    import AppKit
#endif

@MainActor
struct TerminalViewRepresentable {
    let context: TerminalViewState
    let controller: TerminalController
    let configuration: TerminalSurfaceOptions
    /// A stored input, not read off `context` in the update pass: SwiftUI
    /// runs `updateNSView`/`updateUIView` only when the representable's own
    /// properties differ from the previous value. A flag read through the
    /// class reference is invisible to that comparison, and the update pass
    /// was skipped even for the visible surface.
    let isSurfaceVisible: Bool
    let focusBinding: TerminalFocusBinding?
    /// What `focusBinding` read when this value was built, so a change of
    /// the request alone still runs the update pass that acts on it.
    let focusRequest: Bool?
    #if canImport(UIKit)
        #if !targetEnvironment(macCatalyst)
            /// Stored, like `isSurfaceVisible`, so a change to
            /// `TerminalViewState.inputAccessoryItems` alone still runs the
            /// update pass.
            var inputAccessoryItems = TerminalInputAccessoryItem.defaultItems
        #endif
    #endif

    func configureView(_ view: TerminalView, initial: Bool) {
        // SwiftUI keeps the platform view when only the `context` argument
        // changes (a tab switch without `.id`). The new state takes the
        // delegate before the controller and configuration below can
        // rebuild, so the rebuilt surface and every callback reach it, and
        // the old state lets go of the view and its surface.
        let outgoing = (view.delegate as? TerminalViewState).flatMap {
            $0 === context ? nil : $0
        }
        if initial || outgoing != nil {
            if let outgoing {
                if outgoing.attachedView === view {
                    outgoing.attachedView = nil
                }
                if outgoing.surface === view.surface {
                    outgoing.surface = nil
                }
            }
            view.delegate = context
        }

        if context.attachedView !== view {
            context.attachedView = view
        }

        if let currentController = view.controller, currentController === controller {
            // Keep the current surface.
        } else {
            view.controller = controller
        }

        // Unconditional: the coordinator's didSet gates rebuilds on
        // isEquivalent, which ignores resizeThrottleMilliseconds on purpose.
        view.configuration = configuration

        // Same controller and an equivalent configuration: nothing rebuilt,
        // so the surface the view already shows is the new state's now.
        if outgoing != nil, let surface = view.surface, context.surface !== surface {
            context.terminalDidAttachSurface(surface)
            if let fontSize = view.core.fontSize {
                context.terminalDidChangeFontSize(fontSize.points)
            }
        }

        // Forward only changes: stamping unconditionally would revert an
        // imperative `setSurfaceVisible` call on every SwiftUI update and
        // pay a per-update C call for nothing.
        if view.core.hostDeclaredDisplayVisible != isSurfaceVisible {
            view.core.hostDeclaredDisplayVisible = isSurfaceVisible
            view.setSurfaceVisible(isSurfaceVisible)
        }

        #if canImport(UIKit)
            #if !targetEnvironment(macCatalyst)
                if view.inputAccessoryItems != inputAccessoryItems {
                    view.inputAccessoryItems = inputAccessoryItems
                }
            #endif
        #endif
    }

    /// Acquire-only, on both platforms: `FocusState` resets itself to nil
    /// whenever SwiftUI's own focus system re-evaluates (no native focusable
    /// view anchors it) and may never take the true the bridge writes, so
    /// treating false as "resign" drops focus right after a click or the
    /// keyboard right after it opens. Moving focus between surfaces doesn't
    /// need the resign either: the old first responder is retired when the
    /// next one acquires.
    static func acquireFocus(_ view: TerminalView) {
        #if canImport(UIKit)
            guard view.window != nil, !view.isFirstResponder else { return }
            view.becomeFirstResponder()
        #elseif canImport(AppKit)
            guard let window = view.window, window.firstResponder !== view else { return }
            window.makeFirstResponder(view)
        #endif
    }
}

/// Hands the terminal first responder when its focus binding turns true, and
/// when the view is made or lands in a window while it reads true, but never
/// on an update that leaves the binding as it was. A menu, a text field or
/// anything else that takes first responder keeps it however often the
/// terminal redraws.
///
/// Every acquire hops the runloop: it runs from SwiftUI's update pass, where
/// the first-responder dance must not mutate focus state.
@MainActor
final class TerminalFocusSynchronizer {
    private weak var view: TerminalView?
    private var binding: TerminalFocusBinding?
    private var lastRequest: Bool?

    func attach(to view: TerminalView, binding: TerminalFocusBinding?, request: Bool?) {
        self.view = view
        self.binding = binding
        view.focusBridge.onFocusChange = { [weak self] focused in
            self?.binding.setFocused(focused)
        }
        #if canImport(UIKit)
            view.focusBridge.onWindowAttach = { [weak self] in
                self?.acquireIfRequested()
            }
        #endif
        guard request != lastRequest else { return }
        lastRequest = request
        if request == true {
            DispatchQueue.main.async { [weak view] in
                guard let view else { return }
                TerminalViewRepresentable.acquireFocus(view)
            }
        }
    }

    /// Reads the binding after the hop rather than when the view was built:
    /// a host's `onAppear` writes the request in the same transaction that
    /// makes the view, and on UIKit that request precedes the window.
    func acquireIfRequested() {
        DispatchQueue.main.async { [weak self] in
            guard let self, let view, let binding else { return }
            lastRequest = binding.isFocused
            if binding.isFocused {
                TerminalViewRepresentable.acquireFocus(view)
            }
        }
    }

    func detach() {
        view?.focusBridge.onFocusChange = nil
        #if canImport(UIKit)
            view?.focusBridge.onWindowAttach = nil
        #endif
        binding = nil
        view = nil
    }
}

@MainActor
struct TerminalFocusBinding {
    let read: () -> Bool
    let write: (Bool) -> Void

    var isFocused: Bool {
        read()
    }

    func setFocused(_ focused: Bool) {
        write(focused)
    }

    static func bool(_ binding: FocusState<Bool>.Binding) -> TerminalFocusBinding {
        TerminalFocusBinding(
            read: { binding.wrappedValue },
            write: { binding.wrappedValue = $0 },
        )
    }

    static func optional<Value: Hashable>(
        _ binding: FocusState<Value?>.Binding,
        equals value: Value,
    ) -> TerminalFocusBinding {
        TerminalFocusBinding(
            read: { binding.wrappedValue == value },
            write: { focused in
                binding.wrappedValue = focused ? value : nil
            },
        )
    }
}

@MainActor
extension TerminalFocusBinding? {
    func setFocused(_ focused: Bool) {
        guard let binding = self, binding.isFocused != focused else {
            return
        }
        binding.setFocused(focused)
    }
}
