import AppKit
import SwiftUI

struct SystemBackdrop: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        Self.makeBackdrop()
    }

    static func makeBackdrop() -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.blendingMode = .behindWindow
        view.state = .active
        view.appearance = NSAppearance(named: .darkAqua)
        view.material = .hudWindow

        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}
