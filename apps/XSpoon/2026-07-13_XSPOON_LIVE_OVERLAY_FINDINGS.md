# XSpoon Live Overlay Findings - 2026-07-13

## Objective

Show live Accessibility readings beside the mouse while Inspect is armed, without activating Hammerspoon, XSpoon, or the target application.

## Confirmed facts

- `AXUIElementCopyElementAtPosition` works. The live reader returns the hovered element role, title/value/description, frame, app, and supported actions.
- Hammerspoon 1.1.1 is running, has Accessibility permission, and the live `~/.hammerspoon/init.lua` compiles.
- Hammerspoon's existing Accessibility grant can read the element under the pointer with `hs.axuielement.systemElementAtPosition`.
- The existing `Control-Option-I`, `Control-Option-O`, `Control-Option-E`, and `Control-Option-M` bindings remain unique in Hammerspoon.
- A Hammerspoon `hs.webview` creates a native window but initially reports `isVisible = false` while Hammerspoon is running as an accessory/menu-bar-only process.
- Calling `hs.application.get("Hammerspoon"):activate(true)` makes that webview visible. It also brings Hammerspoon forward, which is unacceptable for an inspector overlay.

## Root causes

The Hammerspoon callout failed because its accessory-process window did not become visible until Hammerspoon was activated. That behavior is incompatible with a no-focus inspector.

The first XSpoon panel test had no live data because XSpoon tried to call the Accessibility API itself. Accessibility authorization is per application identity, and calling `AXIsProcessTrustedWithOptions` from the inspect path caused repeated macOS permission prompts when XSpoon was untrusted.

## Decision

Hammerspoon remains the global-hotkey, Accessibility reader, and automation owner. It must not render the live callout.

XSpoon owns the live callout with a small AppKit `NSPanel` configured as:

- Borderless and non-activating.
- Mouse-event ignoring, so it cannot intercept the inspected control.
- `popUpMenu` presentation level and full-screen auxiliary behavior.
- `orderFrontRegardless()` without `NSApp.activate`.
- One persistent SwiftUI hosting view updated only when Hammerspoon reports a changed element.

This preserves the menu-bar application model and does not require the Inspector settings window to open.

When `Control-Option-O` starts inspection, Hammerspoon polls the existing permitted AX surface every 120 ms. It atomically writes `~/.hammerspoon/live_element_latest.json` only when the payload changes, then sends XSpoon one change notification. XSpoon does not call `AXIsProcessTrusted`, `AXIsProcessTrustedWithOptions`, or `AXUIElementCopyElementAtPosition`.

The build installer now signs the finished `/Applications/XSpoon.app` with the local Apple Development identity. It also verifies the finished bundle before installation. The resource bundle was moved from the app root into `Contents/Resources`, allowing the signature to seal the complete bundle.

Verified installed designated requirement:

```text
identifier "com.singleton23.XSpoon"
anchor apple generic
Apple Development: jay23singleton@gmail.com (U7MJ89XZ2M)
```

The signed XSpoon identity remains correct for ordinary macOS application behavior, but live inspection no longer depends on XSpoon having an Accessibility grant.

## Native notifications

Native Notification Center banners are unsuitable for live hover inspection: they cannot be positioned beside the mouse and are not designed to update several times per second. They remain optional for completed capture confirmation only.

## Verification gates

1. Build and install XSpoon after the AppKit panel change.
2. Press `Control-Option-O` over Finder or System Settings.
3. Confirm the compact `XSpoon live` panel changes role/title as the pointer moves and does not activate XSpoon or Hammerspoon.
4. Press `Control-Option-E` to confirm capture still opens the shortcut setup flow.
5. Confirm `Control-Option-I` only opens/closes the menu-bar popover.

## References

- Hammerspoon `hs.webview`: https://www.hammerspoon.org/docs/hs.webview.html
- Hammerspoon `hs.axuielement`: https://www.hammerspoon.org/docs/hs.axuielement.html
- Hammerspoon distributed notifications: https://www.hammerspoon.org/docs/hs.distributednotifications.html
- Apple `NSPanel.isFloatingPanel`: https://developer.apple.com/documentation/appkit/nspanel/isfloatingpanel
- Apple `AXIsProcessTrustedWithOptions`: https://developer.apple.com/documentation/applicationservices/1459186-axisprocesstrustedwithoptions
