//
//  TerminalViewRepresentable@AppKit.swift
//  libghostty-spm
//
//  Created by Lakr233 on 2026/3/16.
//

#if !canImport(UIKit) && canImport(AppKit)
    import AppKit
    import SwiftUI

    extension TerminalViewRepresentable: NSViewRepresentable {
        func makeCoordinator() -> TerminalFocusSynchronizer {
            TerminalFocusSynchronizer()
        }

        func makeNSView(context viewContext: Context) -> TerminalView {
            let view = context.makePlatformView?() ?? TerminalView(frame: .zero)
            configureView(view, initial: true)
            viewContext.coordinator.attach(to: view, binding: focusBinding, request: focusRequest)
            viewContext.coordinator.acquireIfRequested()
            return view
        }

        func updateNSView(_ view: TerminalView, context viewContext: Context) {
            configureView(view, initial: false)
            viewContext.coordinator.attach(to: view, binding: focusBinding, request: focusRequest)
        }

        static func dismantleNSView(_: TerminalView, coordinator: TerminalFocusSynchronizer) {
            coordinator.detach()
        }
    }
#endif
