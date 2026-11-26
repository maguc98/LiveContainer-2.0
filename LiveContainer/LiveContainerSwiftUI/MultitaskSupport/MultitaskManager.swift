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
}
