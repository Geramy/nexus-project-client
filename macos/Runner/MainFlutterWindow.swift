import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    self.contentViewController = flutterViewController

    // Launch at 65% of the screen's visible area, centered. Falls back to the
    // nib's frame if no screen is reported.
    if let visible = (self.screen ?? NSScreen.main)?.visibleFrame {
      let width = visible.width * 0.65
      let height = visible.height * 0.65
      let x = visible.origin.x + (visible.width - width) / 2
      let y = visible.origin.y + (visible.height - height) / 2
      self.setFrame(NSRect(x: x, y: y, width: width, height: height), display: true)
    } else {
      self.setFrame(self.frame, display: true)
    }

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}
