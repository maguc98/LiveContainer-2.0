import Foundation

enum MultitaskMode : Int {
    case virtualWindow = 0
    case nativeWindow = 1
}

extension Notification.Name {
    static let lcMultitaskContainerStateDidChange = Notification.Name("LCMultitaskContainerStateDidChange")
}

@objc class MultitaskManager : NSObject {
    static private var usingMultitaskContainers : [String] = []
    static private var foregroundMultitaskContainers: Set<String> = []
    static private let stateLock = NSLock()

    private class func postContainerStateDidChange() {
        NotificationCenter.default.post(name: .lcMultitaskContainerStateDidChange, object: nil)
    }
    
    @objc class func registerMultitaskContainer(container: String) {
        stateLock.lock()
        if !usingMultitaskContainers.contains(container) {
            usingMultitaskContainers.append(container)
        }
        stateLock.unlock()
        postContainerStateDidChange()
    }
    
    @objc class func unregisterMultitaskContainer(container: String) {
        stateLock.lock()
        usingMultitaskContainers.removeAll(where: { c in
            return c == container
        })
        foregroundMultitaskContainers.remove(container)
        stateLock.unlock()
        postContainerStateDidChange()
    }
    
    @objc class func isUsing(container: String) -> Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return usingMultitaskContainers.contains { c in
            return c == container
        }
    }
    
    @objc class func isMultitasking() -> Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return usingMultitaskContainers.count > 0
    }

    /// Tracks whether a container's scene is currently foregrounded.
    /// A registered container can remain alive while its window is in the background.
    @objc class func setContainerForeground(container: String, isForeground: Bool) {
        stateLock.lock()
        let didChange: Bool
        if isForeground {
            didChange = foregroundMultitaskContainers.insert(container).inserted
        } else {
            didChange = foregroundMultitaskContainers.remove(container) != nil
        }
        stateLock.unlock()

        if didChange {
            postContainerStateDidChange()
        }
    }

    @objc class func hasForegroundContainer() -> Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return !foregroundMultitaskContainers.isEmpty
    }
}
