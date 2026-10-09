//
//  TerminalViewRepresentable@UIKit.swift
//  libghostty-spm
//
//  Created by Lakr233 on 2026/3/16.
//

#if canImport(UIKit)
    import SwiftUI
    import UIKit

    extension TerminalViewRepresentable: UIViewRepresentable {
        func makeCoordinator() -> TerminalFocusSynchronizer {
            TerminalFocusSynchronizer()
        }

        func makeUIView(context viewContext: Context) -> TerminalView {
            let view = context.makePlatformView?() ?? TerminalView(frame: .zero)
            configureView(view, initial: true)
            viewContext.coordinator.attach(to: view, binding: focusBinding, request: focusRequest)
            viewContext.coordinator.acquireIfRequested()
            return view
        }

        func updateUIView(_ view: TerminalView, context viewContext: Context) {
            configureView(view, initial: false)
            viewContext.coordinator.attach(to: view, binding: focusBinding, request: focusRequest)
        }

        static func dismantleUIView(_: TerminalView, coordinator: TerminalFocusSynchronizer) {
            coordinator.detach()
        }
    }
#endif
