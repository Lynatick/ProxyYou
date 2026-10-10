import Cocoa
import FlutterMacOS
import UserNotifications

@main
class AppDelegate: FlutterAppDelegate {
  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    // https://github.com/leanflutter/window_manager/issues/214
    return false
  }

  override func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply
  {
    do {
      try MacSystemProxy.shared.restore()
      return .terminateNow
    } catch {
      let alert = NSAlert()
      alert.messageText = "Не удалось восстановить системный прокси"
      alert.informativeText = error.localizedDescription
      alert.runModal()
      return .terminateCancel
    }
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
  override func applicationWillTerminate(_ notification: Notification) {
    MacSystemProxy.shared.finishSession()
    super.applicationWillTerminate(notification)
  }
  override func applicationDidFinishLaunching(_ aNotification: Notification) {
    // Request notification authorization
    UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge]) {
      granted, error in
      if let error = error {
        print("Error requesting notification authorization: \(error)")
      }
    }
  }

  // // window manager restore from dock: https://leanflutter.dev/blog/click-dock-icon-to-restore-after-closing-the-window
  // override func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
  //     if !flag {
  //         for window in NSApp.windows {
  //             if !window.isVisible {
  //                 window.setIsVisible(true)
  //             }
  //             window.makeKeyAndOrderFront(self)
  //             NSApp.activate(ignoringOtherApps: true)
  //         }
  //     }
  //     return true
  // }
}
