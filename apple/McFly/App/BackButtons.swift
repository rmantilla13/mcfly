#if os(iOS)
import UIKit

/// Back buttons only go back. Held down, iOS's back button opens a menu of
/// every screen behind it; McFly's stacks are a screen or two deep, so the
/// menu is only in the way. Each screen a navigation controller covers gets a
/// back item that turns that menu down, and the button keeps its look, its
/// tap and the swipe back. Installed once, at launch (McFlyApp).
enum BackButtons {
    static func install() { _ = installed }

    private static let installed: Void = {
        swap(#selector(UINavigationController.pushViewController(_:animated:)),
             #selector(UINavigationController.mcfly_pushViewController(_:animated:)))
        swap(#selector(UINavigationController.setViewControllers(_:animated:)),
             #selector(UINavigationController.mcfly_setViewControllers(_:animated:)))
    }()

    private static func swap(_ original: Selector, _ replacement: Selector) {
        guard let a = class_getInstanceMethod(UINavigationController.self, original),
              let b = class_getInstanceMethod(UINavigationController.self, replacement) else { return }
        method_exchangeImplementations(a, b)
    }

    /// The back item `controller` lends the screen pushed over it, unless it has one of its own.
    fileprivate static func plain(_ controller: UIViewController) {
        let item = controller.navigationItem
        guard item.backBarButtonItem == nil else { return }
        item.backBarButtonItem = BackItem(title: item.backButtonTitle, style: .plain, target: nil, action: nil)
    }
}

/// A back item that takes no menu: UIKit hands it one of the screens behind, and it lets it drop.
private final class BackItem: UIBarButtonItem {
    override var menu: UIMenu? {
        get { nil }
        set {}
    }
}

private extension UINavigationController {
    // Swapped with UIKit's own, so each calls the other: these names run UIKit's.
    @objc func mcfly_pushViewController(_ controller: UIViewController, animated: Bool) {
        if let top = topViewController { BackButtons.plain(top) }
        mcfly_pushViewController(controller, animated: animated)
    }

    @objc func mcfly_setViewControllers(_ controllers: [UIViewController], animated: Bool) {
        controllers.dropLast().forEach(BackButtons.plain)
        mcfly_setViewControllers(controllers, animated: animated)
    }
}
#endif
