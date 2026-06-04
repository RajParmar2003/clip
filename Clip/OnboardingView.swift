import AppKit
import SwiftUI

/// First-launch welcome. Three short steps, plain language, then a live
/// direct-paste setup with the Accessibility permission explained honestly.
final class OnboardingController {
    private var window: NSWindow?

    func showIfNeeded() {
        guard !Preferences.shared.hasOnboarded else { return }
        show()
    }

    func show() {
        if window == nil {
            let w = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 520, height: 420),
                styleMask: [.titled, .closable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            w.title = "Welcome to Clip"
            w.titlebarAppearsTransparent = true
            w.isReleasedWhenClosed = false
            w.center()
            w.contentView = NSHostingView(rootView: OnboardingView { [weak self] in
                Preferences.shared.hasOnboarded = true
                self?.window?.orderOut(nil)
            })
            window = w
        }
        window?.makeKeyAndOrderFront(nil)
        if #available(macOS 14.0, *) {
            NSApp.activate()
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}

struct OnboardingView: View {
    let onFinish: () -> Void
    @State private var step = 0
    @State private var testText = ""

    private let totalSteps = 3

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 16)
            Group {
                switch step {
                case 0: stepIcon
                case 1: stepPin
                default: stepPaste
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 36)

            HStack {
                if step > 0 {
                    Button("Back") { step -= 1 }
                }
                Spacer()
                HStack(spacing: 6) {
                    ForEach(0..<totalSteps, id: \.self) { i in
                        Circle()
                            .fill(i == step ? Color.accentColor : Color.secondary.opacity(0.3))
                            .frame(width: 7, height: 7)
                    }
                }
                Spacer()
                if step < totalSteps - 1 {
                    Button("Next") { step += 1 }
                        .keyboardShortcut(.defaultAction)
                } else {
                    Button("Start Using Clip") { onFinish() }
                        .keyboardShortcut(.defaultAction)
                }
            }
            .padding(20)
        }
        .frame(width: 520, height: 420)
    }

    private var stepIcon: some View {
        VStack(spacing: 14) {
            Image(systemName: "paperclip.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(.tint)
            Text("Everything you copy, kept safe")
                .font(.title2.bold())
            Text("Clip lives in your menu bar — look for the paperclip at the top of your screen. Click it any time to see everything you've copied. Or press Command + Shift + V from anywhere.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Text("Everything stays on this Mac. Nothing is uploaded, ever.")
                .font(.callout.weight(.medium))
        }
    }

    private var stepPin: some View {
        VStack(spacing: 14) {
            Image(systemName: "pin.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(.orange)
            Text("Pin what matters")
                .font(.title2.bold())
            Text("Pinned items stay at the top forever — they survive restarts and \"Clear All\". Pin your address, a link you'll need later, anything you reuse. Hover over any item and click the pin, or press Command + P.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
    }

    private var stepPaste: some View {
        VStack(spacing: 14) {
            Image(systemName: "cursorarrow.click.2")
                .font(.system(size: 50))
                .foregroundStyle(.tint)
            Text("Click an item — it pastes itself")
                .font(.title2.bold())
            Text("For Clip to type the paste for you, macOS asks once for Accessibility permission. That's the standard way paste tools work — Clip uses it only to press Paste, nothing else.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button("Enable Direct Paste") {
                _ = Paster.accessibilityGranted(promptIfNeeded: true)
            }
            .controlSize(.large)
            TextField("Try it: copy some text, press Command + Shift + V, click the item", text: $testText)
                .textFieldStyle(.roundedBorder)
                .padding(.top, 4)
        }
    }
}
