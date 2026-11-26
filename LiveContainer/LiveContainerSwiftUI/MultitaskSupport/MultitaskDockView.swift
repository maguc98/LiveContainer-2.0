//
//  MultitaskDockView.swift
//  LiveContainer
//
//  Created by boa-z on 2025/6/28.
//

import Foundation
import SwiftUI
import UIKit
import Combine

// MARK: - App Info Provider
class AppInfoProvider {
    
    static let shared = AppInfoProvider()
    
    private var infoCacheByUUID = [String: LCAppInfo]()
    private var infoCacheByName = [String: LCAppInfo]()
    private let cacheQueue = DispatchQueue(label: "com.livecontainer.appinfoprovider.cachequeue", attributes: .concurrent)
    
    private init() {}
    
    public func findAppInfo(appName: String, dataUUID: String) -> LCAppInfo? {
        if let appInfo = findAppInfoFromSharedModel(appName: appName, dataUUID: dataUUID) {
            return appInfo
        }
        if let appInfo = findAppInfo(byUUID: dataUUID) {
            return appInfo
        }
        return findAppInfo(byName: appName)
    }
    
    public func findAppInfo(byUUID dataUUID: String) -> LCAppInfo? {
        if let cachedInfo = cacheQueue.sync(execute: { infoCacheByUUID[dataUUID] }) {
            return cachedInfo
        }
        
        guard let appGroupPath = LCSharedUtils.appGroupPath()?.path else { return nil }
        
        let searchPaths = [
            "\(appGroupPath)/LiveContainer/Data/Application/\(dataUUID)/LCAppInfo.plist",
            "\(appGroupPath)/Containers/\(dataUUID)/LCAppInfo.plist",
            "\(FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?.path ?? "")/Data/Application/\(dataUUID)/LCAppInfo.plist"
        ]
        
        for path in searchPaths {
            if FileManager.default.fileExists(atPath: path),
               let appInfoDict = NSDictionary(contentsOfFile: path),
               let bundlePath = appInfoDict["bundlePath"] as? String,
               let appInfo = LCAppInfo(bundlePath: bundlePath) {
                
                cacheQueue.async(flags: .barrier) { self.infoCacheByUUID[dataUUID] = appInfo }
                return appInfo
            }
        }
        return nil
    }

    public func findAppInfo(byName appName: String) -> LCAppInfo? {
        if let cachedInfo = cacheQueue.sync(execute: { infoCacheByName[appName] }) {
            return cachedInfo
        }

        var searchPaths: [String] = []
        if let appGroupPath = LCSharedUtils.appGroupPath()?.path {
            searchPaths.append("\(appGroupPath)/LiveContainer/Applications")
        }
        if let docPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?.path {
            searchPaths.append("\(docPath)/Applications")
        }

        for appsPath in searchPaths {
            guard let appDirs = try? FileManager.default.contentsOfDirectory(atPath: appsPath) else { continue }
            
            for appDir in appDirs where appDir.hasSuffix(".app") {
                if let appInfo = LCAppInfo(bundlePath: "\(appsPath)/\(appDir)"), appInfo.displayName() == appName {
                    cacheQueue.async(flags: .barrier) { self.infoCacheByName[appName] = appInfo }
                    return appInfo
                }
            }
        }
        return nil
    }

    private func findAppInfoFromSharedModel(appName: String, dataUUID: String) -> LCAppInfo? {
        let allApps = DataManager.shared.model.apps + DataManager.shared.model.hiddenApps
        
        for appModel in allApps {
            if appModel.appInfo.containers.contains(where: { $0.folderName == dataUUID }) {
                return appModel.appInfo
            }
        }
        
        for appModel in allApps {
            if appModel.appInfo.displayName() == appName {
                return appModel.appInfo
            }
        }
        return nil
    }
    
    public func clearCache() {
        cacheQueue.async(flags: .barrier) {
            self.infoCacheByUUID.removeAll()
            self.infoCacheByName.removeAll()
        }
    }
}

// MARK: - App Model for Dock
@objc class DockAppModel: NSObject, ObservableObject, Identifiable {
    let id = UUID()
    @objc let appName: String
    @objc let appUUID: String
    let appInfo: LCAppInfo?
    let view: UIView?
    
    @objc init(appName: String, appUUID: String, appInfo: LCAppInfo? = nil, view: UIView?) {
        self.appName = appName
        self.appUUID = appUUID
        self.appInfo = appInfo
        self.view = view
        super.init()
    }
}

// MARK: - MultitaskDockView Manager
@available(iOS 16.0, *)
@objc public class MultitaskDockManager: NSObject, ObservableObject {
    @objc public static let shared = MultitaskDockManager()
    
    @Published var apps: [DockAppModel] = []
    @Published var isVisible: Bool = false
    @Published @objc var isCollapsed: Bool = false
    @Published var isDockHidden: Bool = false
    @Published var settingsChanged: Bool = false

    @objc public var windowHostingView = VirtualWindowsHostView()
    internal var hostingController: UIHostingController<AnyView>?
    private var switcherWindow: UIWindow?
    private weak var originalKeyWindow: UIWindow?
    // Preserve the user's chosen vertical position when the rail is refreshed or rotated.
    private var requestedDockCenterY: CGFloat?

    public struct Constants {
        // MARK: - Layout & Sizing
        static let defaultDockWidth: CGFloat = 90.0
        static let minAdaptiveDockWidth: CGFloat = 50.0
        static let minAdaptiveIconSize: CGFloat = 10.0
        static let maxIconSize: CGFloat = 100.0
        static let minCollapsedHeight: CGFloat = 60.0
        static let minCollapsedButtonSize: CGFloat = 44.0
        static let maxCollapsedButtonSize: CGFloat = 80.0
        static let initialDockShowHeight: CGFloat = 120.0

        // MARK: - Margins & Padding
        static let adaptiveWidthVerticalMargin: CGFloat = 20.0
        static let dockVerticalMargin: CGFloat = 30.0
        static let dockContentSpacing: CGFloat = 8.0
        static let dockVerticalPadding: CGFloat = 30.0
        // Extra padding is derived from dockVerticalPadding to match the SwiftUI layout exactly
        
        // MARK: - Ratios & Factors
        static let iconToWidthRatio: CGFloat = 0.75
        static let collapsedButtonToWidthRatio: CGFloat = 0.7
        static let maxHeightRatioOfAvailableArea: CGFloat = 0.85
        
        // MARK: - Animation & Interaction
        static var dockHiddenOffset: CGFloat {
            get {
                let ans = LCUtils.appGroupUserDefault.double(forKey: "LCDockWidth")
                if ans != 0 {
                    return ans * 2 / 3
                } else {
                    return 50
                }
            }
        }
        static var hideGestureThreshold: CGFloat {
            get {
                let ans = LCUtils.appGroupUserDefault.double(forKey: "LCDockWidth")
                if ans != 0 {
                    return ans / 5
                } else {
                    return 16
                }
            }
        }
        static let edgeSwipeThreshold: CGFloat = 30.0
        
        static let standardAnimationDuration: TimeInterval = 0.3
        static let longAnimationDuration: TimeInterval = 0.4
        static let shortAnimationDuration1: TimeInterval = 0.15
        static let shortAnimationDuration2: TimeInterval = 0.1
        
        static let standardSpringDamping: CGFloat = 0.8
        static let showHideSpringDamping: CGFloat = 0.7
        static let standardSpringVelocity: CGFloat = 0.3
        static let showHideSpringVelocity: CGFloat = 0.5
        
        static let initialScale: CGFloat = 0.8
        static let bringToFrontScale: CGFloat = 1.02
    }
    
    // The new navigation handle is a narrow rail fixed to the right edge.
    public var dockWidth: CGFloat { 34.0 }

    // Calculate icon size based on dock width
    private func calculateIconSize(for width: CGFloat) -> CGFloat {
        let iconSize = width * Constants.iconToWidthRatio
        return max(Constants.minAdaptiveIconSize, min(Constants.maxIconSize, iconSize))
    }

    private func calculateButtonSize(for width: CGFloat) -> CGFloat {
        let targetSize = width * Constants.collapsedButtonToWidthRatio
        return max(Constants.minCollapsedButtonSize, min(Constants.maxCollapsedButtonSize, targetSize))
    }

    private func expandedDockBaseHeight(for width: CGFloat, buttonSize: CGFloat) -> CGFloat {
        let spacingCount = max(self.apps.count + 1, 0)
        let totalSpacingHeight = CGFloat(spacingCount) * Constants.dockContentSpacing
        return Constants.dockVerticalPadding + buttonSize * 2 + totalSpacingHeight
    }

    private func expandedDockHeight(for width: CGFloat, iconSize: CGFloat) -> CGFloat {
        let buttonSize = calculateButtonSize(for: width)
        let baseHeight = expandedDockBaseHeight(for: width, buttonSize: buttonSize)
        let iconHeight = CGFloat(self.apps.count) * iconSize
        return baseHeight + iconHeight
    }

    private func collapsedDockHeight(for width: CGFloat) -> CGFloat {
        let buttonSize = calculateButtonSize(for: width)
        return Constants.dockVerticalPadding + buttonSize
    }
    

    // Calculate adaptive icon size
    public var adaptiveIconSize: CGFloat {
        return calculateIconSize(for: dockWidth)
    }

    public var keyWindow: UIWindow? {
        if let originalKeyWindow { return originalKeyWindow }

        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        if let activeWindow = scenes
            .first(where: { $0.activationState == .foregroundActive })?
            .windows.first(where: { $0.isKeyWindow }) {
            return activeWindow
        }
        if let foregroundWindow = scenes
            .filter({ $0.activationState == .foregroundActive || $0.activationState == .foregroundInactive })
            .flatMap({ $0.windows })
            .first(where: { $0.isKeyWindow }) {
            return foregroundWindow
        }
        return scenes.flatMap({ $0.windows }).first(where: { $0.isKeyWindow })
    }

    public var safeAreaInsets: UIEdgeInsets {
        if #available(iOS 11.0, *) {
            return keyWindow?.safeAreaInsets ?? .zero
        }
        return .zero
    }

    private var safeAreaHeight: CGFloat {
        (keyWindow?.bounds.height ?? UIScreen.main.bounds.height) - safeAreaInsets.top - safeAreaInsets.bottom
    }
    
    override init() {
        super.init()
        // The home summary reads this singleton before SwiftUI has necessarily attached
        // its UIWindowScene. Defer host-view attachment until a key window exists.
        setupDockView()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(userDefaultsDidChange),
            name: UserDefaults.didChangeNotification,
            object: LCUtils.appGroupUserDefault
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(deviceOrientationDidChange),
            name: UIDevice.orientationDidChangeNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(sceneWindowDidBecomeAvailable(_:)),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(sceneWindowDidBecomeAvailable(_:)),
            name: UIWindow.didBecomeKeyNotification,
            object: nil
        )
        DispatchQueue.main.async {
            self.attachWindowHostingViewIfNeeded()
        }
    }

    @objc private func sceneWindowDidBecomeAvailable(_ notification: Notification) {
        DispatchQueue.main.async {
            self.attachWindowHostingViewIfNeeded()
            if !self.apps.isEmpty && !self.isVisible {
                self.showDock()
            }
        }
    }

    private func attachWindowHostingViewIfNeeded() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { self.attachWindowHostingViewIfNeeded() }
            return
        }
        guard let window = self.keyWindow,
              let rootViewController = window.rootViewController else { return }

        guard let rootView = rootViewController.view else { return }
        let attachmentView = rootView.subviews.first ?? rootView
        if self.windowHostingView.superview !== attachmentView {
            self.windowHostingView.removeFromSuperview()
            self.windowHostingView.frame = attachmentView.bounds
            self.windowHostingView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            attachmentView.addSubview(self.windowHostingView)
        }
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
        NotificationCenter.default.removeObserver(self, name: UIDevice.orientationDidChangeNotification, object: nil)
    }

    @objc private func deviceOrientationDidChange() {
        DispatchQueue.main.async {
            if self.isVisible {
                self.updateDockFrame()
            }
        }
    }
    
    @objc private func userDefaultsDidChange() {
        DispatchQueue.main.async {
            self.settingsChanged.toggle()
            if self.isVisible {
                self.updateDockFrame()
            }
        }
    }
    
    private func setupDockView() {
        DispatchQueue.main.async {
            let dockView = AnyView(MultitaskDockSwiftView()
                .environmentObject(self))
            
            self.hostingController = UIHostingController(rootView: dockView)
            self.hostingController?.view.autoresizingMask = [.flexibleTopMargin, .flexibleLeftMargin, .flexibleRightMargin, .flexibleBottomMargin]
            self.hostingController?.view.backgroundColor = .clear
        }
    }

    private func updateDockFrame(animated: Bool = true) {
        guard let hostingController = hostingController,
              let keyWindow = keyWindow else { return }
        let bounds = keyWindow.bounds
        let width = dockWidth
        let height: CGFloat = 148
        let centerY = requestedDockCenterY ?? bounds.midY
        let minY = safeAreaInsets.top + Constants.dockVerticalMargin
        let maxY = max(minY, bounds.height - safeAreaInsets.bottom - height - Constants.dockVerticalMargin)
        let originY = max(minY, min(maxY, centerY - height / 2))
        let frame = CGRect(x: bounds.width - width - 2,
                           y: originY,
                           width: width,
                           height: height)
        applyNewFrame(frame, for: hostingController, animated: animated)
    }

    /// Moves the side rail while keeping its entire body inside the usable safe area.
    func moveDockVertically(toCenterY centerY: CGFloat) {
        guard let hostingController, let keyWindow else { return }
        let bounds = keyWindow.bounds
        let height = hostingController.view.bounds.height > 0 ? hostingController.view.bounds.height : 148
        let minY = safeAreaInsets.top + Constants.dockVerticalMargin
        let maxY = max(minY, bounds.height - safeAreaInsets.bottom - height - Constants.dockVerticalMargin)
        let originY = max(minY, min(maxY, centerY - height / 2))
        requestedDockCenterY = originY + height / 2

        var frame = hostingController.view.frame
        frame.origin.y = originY
        hostingController.view.frame = frame
    }

    func finishDockVerticalDrag() {
        let feedback = UIImpactFeedbackGenerator(style: .soft)
        feedback.impactOccurred()
    }

    // MARK: - Frame Calculation Helpers

    private func calculateTargetDockHeight(forWidth width: CGFloat) -> CGFloat { 148 }

    func calculateTargetX(isDockHidden: Bool, isOnRightSide: Bool, dockWidth: CGFloat, screenWidth: CGFloat) -> CGFloat {

        let safeInsets = self.safeAreaInsets
        var ans : CGFloat
        if isOnRightSide {
            ans = screenWidth - dockWidth
            if self.hostingController?.view.window?.windowScene?.interfaceOrientation == UIInterfaceOrientation.landscapeLeft {
                ans -= safeInsets.right
            }
            
            if isDockHidden {
                ans += Constants.dockHiddenOffset
            }
        } else {
            ans = 0
            if self.hostingController?.view.window?.windowScene?.interfaceOrientation == UIInterfaceOrientation.landscapeRight {
                ans += safeInsets.left
            }
            if isDockHidden {
                ans -= Constants.dockHiddenOffset
            }
        }
        
        return ans;

    }

    private func calculateTargetY(for currentFrame: CGRect, dockHeight: CGFloat, screenHeight: CGFloat) -> CGFloat {
        let safeAreaMinY = self.safeAreaInsets.top + Constants.dockVerticalMargin
        let safeAreaMaxY = screenHeight - self.safeAreaInsets.bottom - dockHeight - Constants.dockVerticalMargin
        
        if currentFrame.height > 0 {
            let desiredY = currentFrame.midY - dockHeight / 2
            return max(safeAreaMinY, min(safeAreaMaxY, desiredY))
        } else {
            let safeAreaCenterY = safeAreaMinY + (safeAreaMaxY - safeAreaMinY) / 2
            return max(safeAreaMinY, min(safeAreaMaxY, safeAreaCenterY - dockHeight / 2))
        }
    }

    private func applyNewFrame(_ newFrame: CGRect, for hostingController: UIHostingController<AnyView>, animated: Bool) {
        if animated {
            UIView.animate(
                withDuration: Constants.standardAnimationDuration,
                delay: 0,
                usingSpringWithDamping: Constants.standardSpringDamping,
                initialSpringVelocity: Constants.standardSpringVelocity,
                options: .curveEaseOut
            ) {
                hostingController.view.frame = newFrame
            }
        } else {
            hostingController.view.frame = newFrame
        }
    }
    
    @objc public func addRunningApp(_ appName: String, appUUID: String, view: UIView?) {
        let appInfo = AppInfoProvider.shared.findAppInfo(appName: appName, dataUUID: appUUID)
        addRunningAppWithInfo(appInfo, appUUID: appUUID, view: view)
    }
    
    @objc public func removeRunningApp(_ appUUID: String) {
        guard isDockEnabled() else { return }
        
        DispatchQueue.main.async {
            self.apps.removeAll { $0.appUUID == appUUID }
            
            if self.apps.isEmpty {
                self.hideDock()
            } else if self.isVisible {
                self.updateDockFrame()
            }
        }
    }
    
    @objc public func showDock() {
        guard isDockEnabled() else { return }
        guard !isVisible, let hostingController = hostingController else { return }
        
        guard let keyWindow = self.keyWindow else { return }
        attachWindowHostingViewIfNeeded()
        
        DispatchQueue.main.async {
            self.isVisible = true
            
            let screenBounds = keyWindow.bounds
            let currentDockWidth = self.dockWidth
            let initialHeight = Constants.initialDockShowHeight
            
            // If not already in view hierarchy, add it
            if hostingController.view.superview == nil {
                keyWindow.addSubview(hostingController.view)
                hostingController.view.frame = CGRect(
                    x: screenBounds.width - currentDockWidth,
                    y: (screenBounds.height - initialHeight) / 2,
                    width: currentDockWidth,
                    height: initialHeight
                )
            }
            
            self.updateDockFrame(animated: false) 
            
            // The rail has its own local gesture recognizer; don't replace host-window gestures.
            hostingController.view.alpha = 0
            let initialScale = Constants.initialScale
            hostingController.view.transform = CGAffineTransform(scaleX: initialScale, y: initialScale)
            
            UIView.animate(
                withDuration: Constants.standardAnimationDuration,
                delay: 0,
                usingSpringWithDamping: Constants.showHideSpringDamping,
                initialSpringVelocity: Constants.showHideSpringVelocity,
                options: .curveEaseOut
            ) {
                hostingController.view.alpha = 1
                hostingController.view.transform = .identity
            }
        }
    }
    
    @objc public func hideDock() {
        guard isVisible, let hostingController = hostingController else { return }

        DispatchQueue.main.async {
            guard let keyWindow = self.keyWindow else {
                hostingController.view.isHidden = true
                self.isVisible = false
                return
            }
            UIView.animate(
                withDuration: Constants.standardAnimationDuration,
                delay: 0,
                usingSpringWithDamping: Constants.showHideSpringDamping,
                initialSpringVelocity: Constants.showHideSpringVelocity,
                options: .curveEaseOut
            ) {
                hostingController.view.alpha = 0
                let finalScale = Constants.initialScale
                hostingController.view.transform = CGAffineTransform(scaleX: finalScale, y: finalScale)
                let screenBounds = keyWindow.bounds
                let currentDockWidth = self.dockWidth
                let targetX = self.calculateTargetX(isDockHidden: true, isOnRightSide: hostingController.view.frame.midX > screenBounds.width / 2, dockWidth: currentDockWidth, screenWidth: screenBounds.width)
                let targetY = hostingController.view.frame.origin.y
                hostingController.view.frame.origin = CGPoint(x: targetX, y: targetY)
            } completion: { _ in
                self.isVisible = false
                hostingController.view.transform = .identity
            }
        }
    }

    @objc public func animateFrame(to finalFrame: CGRect) {
        guard let hostingController = self.hostingController else { return }
        
        UIView.animate(
            withDuration: Constants.standardAnimationDuration,
            delay: 0,
            usingSpringWithDamping: Constants.standardSpringDamping,
            initialSpringVelocity: Constants.standardSpringVelocity,
            options: .curveEaseOut
        ) {
            hostingController.view.frame = finalFrame
        }
    }

    @objc public func updateFrameAfterAnimation(finalOffset: CGSize) {
        guard let hostingController = self.hostingController else { return }
        
        let newFrame = hostingController.view.frame.offsetBy(dx: finalOffset.width, dy: finalOffset.height)
        
        hostingController.view.frame = newFrame
    }

    func handleSwipeToHideOrShowGesture(for originalFrame: CGRect, translation: CGSize) -> Bool {
        guard let screenWidth = keyWindow?.bounds.width else { return false }
        let isOnRightSide = originalFrame.origin.x > screenWidth / 2
        let isSwipingAway = (isOnRightSide && translation.width > 0) || (!isOnRightSide && translation.width < 0)
        
        if isSwipingAway {
            guard !self.isDockHidden else { return false }
            self.hideDockToSide()
            let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
            impactFeedback.impactOccurred()
            return true
        } else {
            guard self.isDockHidden else { return false }
            self.showDockFromHidden()
            let impactFeedback = UIImpactFeedbackGenerator(style: .light)
            impactFeedback.impactOccurred()
            return true
        }
    }
    
    // Check if gesture is for cross-screen movement (left to right or vice versa)
    func isPositionChangeGesture(for originalFrame: CGRect, translation: CGSize) -> Bool {
        let horizontalDistance = abs(translation.width)
        let verticalDistance = abs(translation.height)
        
        guard !self.isDockHidden, horizontalDistance > verticalDistance else {
            return false
        }
        
        guard let screenWidth = keyWindow?.bounds.width else { return false }
        let isOnRightSide = originalFrame.origin.x > screenWidth / 2
        
        guard !self.isDockHidden else { return false }
        
        let isMovingToOtherSide = (isOnRightSide && translation.width < 0) || (!isOnRightSide && translation.width > 0)
        guard isMovingToOtherSide else { return false }
        
        let draggedX = originalFrame.origin.x + translation.width
        let screenCenter = screenWidth / 2
        
        if isOnRightSide {
            return draggedX < screenCenter
        } else {
            return (draggedX + originalFrame.width) > screenCenter
        }
    }
    
    // Find and bring corresponding multitask view to front
    func bringMultitaskViewToFront(uuid: String, from center: CGPoint? = nil) -> Bool {
        attachWindowHostingViewIfNeeded()
        windowHostingView.isHidden = false
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene else {
            return false
        }

        for window in windowScene.windows {
            if let targetView = findMultitaskView(in: window, withUUID: uuid) {
                passURLSchemeToView(targetView)
                animateViewAppearance(targetView, from: center, in: window)
                return true
            }
        }
        
        return false
    }

    private func passURLSchemeToView(_ view: UIView) {
        if let launchUrl = UserDefaults.standard.string(forKey: "launchAppUrlScheme") {
            UserDefaults.standard.removeObject(forKey: "launchAppUrlScheme")
            if let decoratedVC = view._viewDelegate() as? DecoratedAppSceneViewController {
                decoratedVC.appSceneVC.openURLScheme(launchUrl)
            }
        }
    }

    private func animateViewAppearance(_ view: UIView, from center: CGPoint?, in window: UIWindow) {
        let isHidden = view.isHidden || view.alpha < 0.1
        let decoratedVC = view._viewDelegate() as? DecoratedAppSceneViewController
        let isMaximized = decoratedVC?.isMaximized ?? false

        if UserDefaults.lcShared().bool(forKey: "LCMaxOneAppOnStage") && isMaximized {
            MultitaskDockManager.shared.minimizeAllWindows(except: decoratedVC)
        }

        let targetFrame = view.frame
        let perspective = CATransform3DIdentity
        if isHidden {
            view.layer.removeAllAnimations()
            view.isHidden = false
            view.alpha = 1
            view.frame = targetFrame
            view.layer.transform = CATransform3DIdentity

            let origin = center ?? CGPoint(x: targetFrame.midX, y: targetFrame.midY)
            let startScale: CGFloat = 0.18
            view.frame.size = CGSize(width: max(1, targetFrame.width * startScale), height: max(1, targetFrame.height * startScale))
            view.center = origin
            var startTransform = CATransform3DIdentity
            startTransform.m34 = -1.0 / 900.0
            startTransform = CATransform3DRotate(startTransform, -0.12, 1, 0, 0)
            startTransform = CATransform3DScale(startTransform, startScale, startScale, 1)
            view.layer.transform = startTransform
            view.layer.shadowOpacity = 0
            view.layer.shadowRadius = 0

            if let decoratedVC = view._viewDelegate(), PiPManager.shared?.isPiP(withDecoratedVC: decoratedVC) == true {
                PiPManager.shared?.stopPiP()
                view.frame = targetFrame
                view.layer.transform = CATransform3DIdentity
            }

            bringViewToFront(view, in: window)
            UIView.animate(
                withDuration: 0.62,
                delay: 0,
                usingSpringWithDamping: 0.78,
                initialSpringVelocity: 0.55,
                options: [.curveEaseOut, .allowUserInteraction],
                animations: {
                    view.frame = targetFrame
                    var endTransform = CATransform3DIdentity
                    endTransform.m34 = -1.0 / 1200.0
                    endTransform = CATransform3DRotate(endTransform, 0.025, 1, 0, 0)
                    view.layer.transform = endTransform
                    view.layer.shadowColor = UIColor.black.cgColor
                    view.layer.shadowOpacity = 0.16
                    view.layer.shadowRadius = 22
                    view.layer.shadowOffset = CGSize(width: 0, height: 12)
                },
                completion: { _ in
                    UIView.animate(withDuration: 0.18, delay: 0, options: [.curveEaseOut, .allowUserInteraction]) {
                        view.layer.transform = CATransform3DIdentity
                        view.layer.shadowOpacity = 0
                        view.layer.shadowRadius = 0
                        view.layer.shadowOffset = .zero
                    }
                }
            )
        } else {
            bringViewToFront(view, in: window)
            UIView.animate(
                withDuration: 0.22,
                delay: 0,
                options: [.curveEaseIn, .allowUserInteraction],
                animations: {
                    var transform = CATransform3DIdentity
                    transform.m34 = -1.0 / 1000.0
                    transform = CATransform3DRotate(transform, 0.035, 1, 0, 0)
                    transform = CATransform3DScale(transform, 0.975, 0.975, 1)
                    view.layer.transform = transform
                    view.layer.shadowOpacity = 0.12
                    view.layer.shadowRadius = 16
                },
                completion: { _ in
                    UIView.animate(
                        withDuration: 0.42,
                        delay: 0,
                        usingSpringWithDamping: 0.72,
                        initialSpringVelocity: 0.48,
                        options: [.curveEaseOut, .allowUserInteraction],
                        animations: {
                            view.layer.transform = CATransform3DIdentity
                            view.layer.shadowOpacity = 0
                            view.layer.shadowRadius = 0
                            view.layer.shadowOffset = .zero
                        }
                    )
                }
            )
        }
    }

    private func bringViewToFront(_ view: UIView, in window: UIWindow) {
        if let superview = view.superview {
            superview.bringSubviewToFront(view)
        }
        if let windowSuperview = window.superview {
            windowSuperview.bringSubviewToFront(window)
        }
    }
    
    // Recursively find multitask view
    private func findMultitaskView(in view: UIView, withUUID uuid: String) -> UIView? {
        apps.first { $0.appUUID == uuid }?.view
    }
    
    // Get view's dataUUID property through reflection
    private func getDataUUID(from view: UIView) -> String? {
        let mirror = Mirror(reflecting: view)
        
        if let child = (mirror.children.first { $0.label == "dataUUID" })?.value as? String {
            return child
        }
        
        if view.responds(to: NSSelectorFromString("dataUUID")) {
            return view.value(forKey: "dataUUID") as? String
        }
        
        return nil
    }
    
    @objc public func addRunningAppWithInfo(_ appInfo: LCAppInfo?, appUUID: String, view: UIView?) {
        guard isDockEnabled() else { return }
        
        if apps.contains(where: { $0.appUUID == appUUID }) {
            return
        }
        
        let appName = appInfo?.displayName() ?? "Unknown App"
        let appModel = DockAppModel(appName: appName, appUUID: appUUID, appInfo: appInfo, view: view)
        
        DispatchQueue.main.async {
            self.attachWindowHostingViewIfNeeded()
            self.windowHostingView.isHidden = false
            self.apps.append(appModel)
            
            if self.apps.count == 1 {
                self.showDock()
            } else if self.isVisible {
                self.updateDockFrame()
            }
        }
    }
    
    // Return to the container with a visible transition. Capture the active app view,
    // animate it toward the rail, and only hide the virtual-window layer after the animation.
    @objc public func returnToMainApp() {
        DispatchQueue.main.async {
            guard !self.windowHostingView.isHidden else { return }
            let active = self.frontmostRunningApp()?.view
            let host = self.windowHostingView
            guard let active, let snapshot = active.snapshotView(afterScreenUpdates: false) else {
                UIView.animate(withDuration: 0.30, delay: 0, options: [.curveEaseInOut, .beginFromCurrentState]) {
                    host.transform = CGAffineTransform(scaleX: 0.92, y: 0.92)
                } completion: { _ in
                    host.isHidden = true
                    host.transform = .identity
                }
                return
            }
            let railFrame = self.hostingController?.view.convert(self.hostingController?.view.bounds ?? .zero, to: host) ?? CGRect(x: host.bounds.maxX - 34, y: host.bounds.midY - 74, width: 34, height: 148)
            let snapshotFrame = active.convert(active.bounds, to: host)
            snapshot.frame = snapshotFrame
            snapshot.layer.cornerRadius = 12
            snapshot.clipsToBounds = true
            host.addSubview(snapshot)
            active.isHidden = true
            UIView.animate(withDuration: 0.46, delay: 0, usingSpringWithDamping: 0.84, initialSpringVelocity: 0.28, options: [.curveEaseInOut, .beginFromCurrentState]) {
                // Spatial transition only: no opacity changes. The snapshot travels
                // to the rail and visibly scales down into its landing point.
                snapshot.frame = CGRect(x: railFrame.midX - 12, y: railFrame.midY - 12, width: 24, height: 24)
                snapshot.transform = CGAffineTransform(scaleX: 0.22, y: 0.22)
                snapshot.layer.cornerRadius = 12
                host.transform = CGAffineTransform(scaleX: 0.985, y: 0.985)
            } completion: { _ in
                snapshot.removeFromSuperview()
                active.isHidden = false
                host.isHidden = true
                host.transform = .identity
            }
        }
    }

    // The side-rail dot toggles the current container's floating title/control bar.
    @objc public func toggleForegroundToolbar() {
        DispatchQueue.main.async {
            guard let app = self.frontmostRunningApp(),
                  let view = app.view,
                  let decoratedVC = view._viewDelegate() as? DecoratedAppSceneViewController else { return }
            decoratedVC.toggleFloatingToolbarVisibility()
        }
    }

    // Up/down swipes move directly between running container windows.
    @objc public func cycleForegroundApp(_ direction: Int) {
        DispatchQueue.main.async {
            let orderedApps = self.windowHostingView.subviews.reversed().compactMap { subview in
                self.apps.first(where: { $0.view === subview })
            }
            guard !orderedApps.isEmpty else { return }
            let current = self.frontmostRunningApp()
            let currentIndex = current.flatMap { active in
                orderedApps.firstIndex(where: { $0.appUUID == active.appUUID })
            } ?? 0
            let step = direction >= 0 ? 1 : -1
            let nextIndex = (currentIndex + step + orderedApps.count) % orderedApps.count
            _ = self.bringMultitaskViewToFront(uuid: orderedApps[nextIndex].appUUID)
        }
    }

    private func frontmostRunningApp() -> DockAppModel? {
        for subview in windowHostingView.subviews.reversed() {
            guard let app = apps.first(where: { $0.view === subview }),
                  let view = app.view,
                  !view.isHidden,
                  view.alpha > 0.1 else { continue }
            return app
        }
        for subview in windowHostingView.subviews.reversed() {
            if let app = apps.first(where: { $0.view === subview }) { return app }
        }
        return apps.last
    }

    // The app cards live on a separate full-screen window; the side rail stays icon-free.
    @objc public func presentSwitcher() {
        DispatchQueue.main.async {
            guard self.switcherWindow == nil,
                  let hostWindow = self.keyWindow,
                  let scene = hostWindow.windowScene else { return }
            self.originalKeyWindow = hostWindow
            let overlay = UIWindow(windowScene: scene)
            overlay.frame = hostWindow.bounds
            overlay.windowLevel = UIWindow.Level(rawValue: UIWindow.Level.normal.rawValue + 1)
            overlay.backgroundColor = .clear
            overlay.rootViewController = UIHostingController(rootView: MultitaskSwitcherView(dockManager: self))
            self.switcherWindow = overlay
            overlay.makeKeyAndVisible()
        }
    }

    @objc public func dismissSwitcher() {
        DispatchQueue.main.async {
            let overlay = self.switcherWindow
            self.switcherWindow = nil
            overlay?.isHidden = true
            overlay?.rootViewController = nil
            self.originalKeyWindow?.makeKeyAndVisible()
            self.originalKeyWindow = nil
        }
    }

    @objc public func minimizeAllWindows(except: DecoratedAppSceneViewController? = nil) {
        DispatchQueue.main.async {
            self.apps.forEach { app in
                if let vc = app.view?._viewDelegate() as? DecoratedAppSceneViewController,
                   vc != except {
                    app.view?.layer.removeAllAnimations()
                    vc.minimizeWindow()
                }
            }
        }
    }
    
    @objc public func toggleDockCollapse() {
        DispatchQueue.main.async {
            self.isCollapsed.toggle()
            self.updateDockFrame()
            self.notifyDockCollapseChanged()
        }
    }
    
    @objc public func notifyDockCollapseChanged() {
        self.updateDockFrame()
        // find fullscreen apps and hide its UINavigationBar
        self.apps.forEach { app in
            if let vc = app.view?._viewDelegate() as? DecoratedAppSceneViewController, vc.isMaximized {
                vc.updateVerticalConstraints()
            }
        }
    }
    
    // Toggle dock hide/show state
    @objc public func toggleDockVisibility() {
        DispatchQueue.main.async {
            self.isDockHidden.toggle()
            self.updateDockFrame()
        }
    }
    
    @objc public func showDockFromHidden() {
        DispatchQueue.main.async {
            self.isDockHidden = false
            self.updateDockFrame()
            self.setupEdgeGestureRecognizers()
        }
    }
    
    @objc public func hideDockToSide() {
        DispatchQueue.main.async {
            self.isDockHidden = true
            self.updateDockFrame()
            self.setupEdgeGestureRecognizers()
        }
    }
    
    // Add edge gesture recognition areas when dock is hidden
    private func setupEdgeGestureRecognizers() {
        // Navigation is handled by the visible side rail itself.
    }

    @objc private func handleEdgeSwipe(_ gesture: UIScreenEdgePanGestureRecognizer) {
        guard isDockHidden, gesture.state == .began || gesture.state == .changed else {
            return
        }
        
        let translation = gesture.translation(in: gesture.view)
        let swipeDistance = abs(translation.x)
        
        if swipeDistance > Constants.edgeSwipeThreshold {
            showDockFromHidden()
        }
    }
    
    // MARK: - Multitask Mode Check
    private func isDockEnabled() -> Bool {
        let multitaskMode = MultitaskMode(rawValue: LCUtils.appGroupUserDefault.integer(forKey: "LCMultitaskMode")) ?? .virtualWindow
        return multitaskMode == .virtualWindow
    }
}

// MARK: - System-style Side Navigation Rail
@available(iOS 16.0, *)
public struct MultitaskDockSwiftView: View {
    @EnvironmentObject var dockManager: MultitaskDockManager
    @State private var gestureStartedAt: Date?
    @State private var latestTranslation: CGSize = .zero
    @State private var switcherWorkItem: DispatchWorkItem?
    @State private var switcherWasPresented = false
    @State private var isRepositioningRail = false
    @State private var didRepositionRail = false

    // A deliberate long press turns the rail into a vertical grab handle.
    private var repositionGesture: some Gesture {
        LongPressGesture(minimumDuration: 0.34, maximumDistance: 12)
            .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .global))
            .onChanged { value in
                guard case .second(true, let drag?) = value else { return }
                isRepositioningRail = true
                didRepositionRail = true
                dockManager.moveDockVertically(toCenterY: drag.location.y)
            }
            .onEnded { value in
                if case .second(true, let drag?) = value {
                    dockManager.moveDockVertically(toCenterY: drag.location.y)
                    dockManager.finishDockVerticalDrag()
                }
                isRepositioningRail = false
            }
    }

    private var railGesture: some Gesture {
        DragGesture(minimumDistance: 8, coordinateSpace: .global)
            .onChanged { value in
                if gestureStartedAt == nil {
                    gestureStartedAt = Date()
                    switcherWasPresented = false
                }
                latestTranslation = value.translation

                // Drag inward and hold: reveal the full-screen background app cards.
                guard value.translation.width < -62,
                      abs(value.translation.width) > abs(value.translation.height) * 1.15,
                      switcherWorkItem == nil,
                      !switcherWasPresented else { return }

                let work = DispatchWorkItem {
                    guard gestureStartedAt != nil,
                          latestTranslation.width < -62,
                          abs(latestTranslation.width) > abs(latestTranslation.height) * 1.15 else { return }
                    switcherWasPresented = true
                    dockManager.presentSwitcher()
                }
                switcherWorkItem = work
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.48, execute: work)
            }
            .onEnded { value in
                let elapsed = Date().timeIntervalSince(gestureStartedAt ?? Date())
                switcherWorkItem?.cancel()
                switcherWorkItem = nil

                // A completed long-press drag repositions the rail; it is not an app-switch gesture.
                if didRepositionRail {
                    didRepositionRail = false
                    gestureStartedAt = nil
                    latestTranslation = .zero
                    switcherWasPresented = false
                    return
                }

                if switcherWasPresented {
                    // Keep the task-switcher open; the user can now tap a card.
                } else if abs(value.translation.height) > 42,
                          abs(value.translation.height) > abs(value.translation.width) * 1.25 {
                    dockManager.cycleForegroundApp(value.translation.height < 0 ? 1 : -1)
                } else if value.translation.width > 72 {
                    // Swipe outward/right to tuck the rail, leaving a small visible tab.
                    dockManager.hideDockToSide()
                } else if value.translation.width < -72 {
                    // Swipe inward/left to reveal the rail. The larger hit area makes
                    // the gesture usable even when only the edge tab is visible.
                    dockManager.showDockFromHidden()
                }

                gestureStartedAt = nil
                latestTranslation = .zero
                switcherWasPresented = false
            }
    }

    public var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "chevron.up")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.primary.opacity(0.48))
            Button {
                dockManager.toggleForegroundToolbar()
            } label: {
                ZStack {
                    Circle().fill(Color.accentColor.opacity(0.20)).frame(width: 34, height: 34)
                    Circle().fill(Color.accentColor).frame(width: 13, height: 13)
                    Circle().stroke(Color.primary.opacity(0.30), lineWidth: 1.1).frame(width: 20, height: 20)
                }
                .frame(width: 42, height: 42)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("显示或隐藏顶部应用控制栏")
            Capsule().fill(Color.primary.opacity(0.22)).frame(width: 2, height: 48)
            Image(systemName: "chevron.down")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.primary.opacity(0.48))
        }
        .padding(.vertical, 10)
        .frame(width: 46, height: 160)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.primary.opacity(isRepositioningRail ? 0.24 : 0.12), lineWidth: isRepositioningRail ? 1.35 : 0.8))
        .shadow(color: Color.black.opacity(isRepositioningRail ? 0.17 : 0.10), radius: isRepositioningRail ? 15 : 10, x: 0, y: 4)
        .scaleEffect(isRepositioningRail ? 1.06 : 1)
        .animation(.spring(response: 0.24, dampingFraction: 0.72), value: isRepositioningRail)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .simultaneousGesture(railGesture)
        .simultaneousGesture(repositionGesture)
        .accessibilityHint("长按后上下拖动可调整侧边栏位置")
        .background(Color.clear)
    }
}

// MARK: - Full-screen Container App Switcher
@available(iOS 16.0, *)
private struct MultitaskSwitcherView: View {
    @ObservedObject var dockManager: MultitaskDockManager
    @State private var appeared = false
    @State private var previewImages: [String: UIImage] = [:]
    @State private var pressedUUID: String?
    @State private var selectedUUID: String?
    @Namespace private var cardTransition
    private let columns = [GridItem(.flexible(), spacing: 13), GridItem(.flexible(), spacing: 13)]

    private var activeCount: Int {
        dockManager.apps.filter { !($0.view?.isHidden ?? true) }.count
    }

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.black.opacity(0.24))
                .ignoresSafeArea()
                .overlay(.ultraThinMaterial.opacity(0.48))
                .onTapGesture { close() }

            VStack(spacing: 0) {
                header
                    .padding(.bottom, 20)

                ScrollView(showsIndicators: false) {
                    LazyVGrid(columns: columns, spacing: 14) {
                        ForEach(Array(dockManager.apps.enumerated()), id: \.element.id) { index, app in
                            appCard(app, index: index)
                        }
                    }
                    .padding(.bottom, 8)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 28)
            .padding(.bottom, 20)
            .background {
                RoundedRectangle(cornerRadius: 32, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: 32, style: .continuous)
                            .strokeBorder(.white.opacity(0.66), lineWidth: 1)
                    }
                    .shadow(color: .black.opacity(0.12), radius: 34, y: 16)
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 38)
            .scaleEffect(appeared ? 1 : 0.88, anchor: .bottom)
            .rotation3DEffect(.degrees(appeared ? 0 : -7), axis: (x: 1, y: 0, z: 0), perspective: 0.7)
            .offset(y: appeared ? 0 : 70)
        }
        .ignoresSafeArea()
        .onAppear {
            withAnimation(.spring(response: 0.68, dampingFraction: 0.72, blendDuration: 0.2)) { appeared = true }
            capturePreviews()
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 8) {
                    Text("后台应用")
                        .font(.system(size: 27, weight: .bold, design: .rounded))
                    Capsule().fill(Color.green)
                        .frame(width: 7, height: 7)
                        .shadow(color: .green.opacity(0.4), radius: 5)
                }
                Text("正在运行 \(dockManager.apps.count) 个容器 · \(activeCount) 个前台")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(action: close) {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.primary.opacity(0.65))
                    .frame(width: 42, height: 42)
                    .background(.white.opacity(0.45), in: Circle())
                    .overlay(Circle().stroke(.white.opacity(0.6), lineWidth: 0.8))
            }
            .buttonStyle(.plain)
            .scaleEffect(appeared ? 1 : 0.72)
            .rotationEffect(.degrees(appeared ? 0 : 35))
            .offset(x: appeared ? 0 : 22, y: appeared ? 0 : -10)
            .accessibilityLabel("关闭后台应用")
        }
    }

    private func appCard(_ app: DockAppModel, index: Int) -> some View {
        let isActive = !(app.view?.isHidden ?? true)
        return Button {
            let feedback = UIImpactFeedbackGenerator(style: .medium)
            feedback.impactOccurred()
            withAnimation(.spring(response: 0.58, dampingFraction: 0.68, blendDuration: 0.16)) {
                pressedUUID = app.appUUID
                selectedUUID = app.appUUID
            }
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                ZStack(alignment: .bottomLeading) {
                    previewContent(for: app)
                        .matchedGeometryEffect(id: app.appUUID, in: cardTransition)
                        .frame(height: 174)
                        .clipped()

                    LinearGradient(colors: [.clear, .black.opacity(0.34)], startPoint: .center, endPoint: .bottom)
                    HStack(spacing: 6) {
                        Circle().fill(isActive ? Color.green : Color.white.opacity(0.6)).frame(width: 7, height: 7)
                        Text(isActive ? "正在运行" : "后台")
                            .font(.system(size: 10, weight: .bold))
                            .tracking(0.3)
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(.black.opacity(0.24), in: Capsule())
                    .padding(11)

                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 27, height: 27)
                        .background(.white.opacity(0.22), in: Circle())
                        .overlay(Circle().stroke(.white.opacity(0.36), lineWidth: 0.7))
                        .padding(11)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                }
                .clipShape(RoundedRectangle(cornerRadius: 21, style: .continuous))

                HStack(spacing: 9) {
                    appIcon(app)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(app.appName)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        Text(isActive ? "点击切换到此应用" : "轻点继续使用")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 11)
                .padding(.vertical, 12)
            }
            .background(.white.opacity(0.38), in: RoundedRectangle(cornerRadius: 25, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 25, style: .continuous).stroke(.white.opacity(0.72), lineWidth: 0.9))
            .shadow(color: .black.opacity(0.06), radius: 12, y: 5)
            .scaleEffect(pressedUUID == app.appUUID ? 0.96 : 1)
        }
        .buttonStyle(.plain)
        .offset(y: appeared ? 0 : 90)
        .scaleEffect(appeared ? 1 : 0.82)
        .rotation3DEffect(.degrees(appeared ? 0 : (index.isMultiple(of: 2) ? 9 : -9)), axis: (x: 0.7, y: 1, z: 0), perspective: 0.65)
        .animation(.spring(response: 0.62, dampingFraction: 0.72, blendDuration: 0.18).delay(Double(index) * 0.075), value: appeared)
    }

    @ViewBuilder private func previewContent(for app: DockAppModel) -> some View {
        if let image = previewImages[app.appUUID] {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .overlay(.black.opacity(0.02))
        } else {
            ZStack {
                LinearGradient(colors: [
                    Color(red: 0.80, green: 0.88, blue: 1.0),
                    Color(red: 0.88, green: 0.83, blue: 0.98)
                ], startPoint: .topLeading, endPoint: .bottomTrailing)
                appIcon(app)
                    .scaleEffect(2.0)
                    .blur(radius: 18)
                    .opacity(0.18)
                appIcon(app)
                    .scaleEffect(1.45)
            }
        }
    }

    @ViewBuilder private func appIcon(_ app: DockAppModel) -> some View {
        if app.appName.localizedCaseInsensitiveContains("customchat") {
            Image(systemName: "bubble.left.and.bubble.right.fill")
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(Color(red: 0.38, green: 0.48, blue: 0.78))
                .frame(width: 34, height: 34)
                .background(.white.opacity(0.65), in: RoundedRectangle(cornerRadius: 11))
        } else if let icon = app.appInfo?.iconIsDarkIcon(false) {
            Image(uiImage: icon)
                .resizable()
                .scaledToFit()
                .frame(width: 34, height: 34)
                .clipShape(RoundedRectangle(cornerRadius: 10))
        } else {
            Image(systemName: "app.fill")
                .font(.system(size: 17))
                .foregroundStyle(.blue)
                .frame(width: 34, height: 34)
                .background(.white.opacity(0.65), in: RoundedRectangle(cornerRadius: 10))
        }
    }

    private func capturePreviews() {
        DispatchQueue.main.async {
            for app in dockManager.apps {
                guard let view = app.view, view.bounds.width > 0, view.bounds.height > 0 else { continue }
                let renderer = UIGraphicsImageRenderer(size: view.bounds.size)
                let image = renderer.image { context in
                    view.drawHierarchy(in: view.bounds, afterScreenUpdates: false)
                }
                previewImages[app.appUUID] = image
            }
        }
    }

    private func close() {
        withAnimation(.spring(response: 0.52, dampingFraction: 0.74, blendDuration: 0.18)) { appeared = false }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.42) {
            dockManager.dismissSwitcher()
        }
    }
}
// MARK: - Collapsed Dock View
@available(iOS 16.0, *)
struct CollapsedDockView: View {
    let isHidden: Bool
    @EnvironmentObject var dockManager: MultitaskDockManager

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .fill(Color(red: 0.88, green: 0.93, blue: 0.99).opacity(isHidden ? 0.48 : 0.82))
                .frame(width: dockManager.adaptiveIconSize, height: dockManager.adaptiveIconSize)

            // High-contrast, easy-to-find dot replaces the old collapse arrow.
            Circle()
                .fill(Color(red: 0.34, green: 0.48, blue: 0.68))
                .frame(width: dockManager.adaptiveIconSize * 0.22,
                       height: dockManager.adaptiveIconSize * 0.22)
                .overlay(Circle().stroke(Color.white.opacity(0.9), lineWidth: 1.2))
                .shadow(color: Color.black.opacity(0.12), radius: 2, x: 0, y: 1)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .stroke(Color.white.opacity(0.84), lineWidth: 1)
        )
        .shadow(color: Color(red: 0.34, green: 0.43, blue: 0.57).opacity(0.10), radius: 7, x: 0, y: 3)
        .scaleEffect(isHidden ? 0.94 : 1.0)
        .animation(.easeInOut(duration: 0.2), value: isHidden)
        .animation(.spring(response: MultitaskDockManager.Constants.longAnimationDuration, dampingFraction: MultitaskDockManager.Constants.standardSpringDamping), value: dockManager.adaptiveIconSize)
    }
}

// MARK: - Collapse Button View
@available(iOS 16.0, *)
struct CollapseButtonView: View {
    @EnvironmentObject var dockManager: MultitaskDockManager

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .fill(Color(red: 0.88, green: 0.93, blue: 0.99).opacity(0.78))
                .frame(width: dockManager.adaptiveIconSize, height: dockManager.adaptiveIconSize)

            Image(systemName: "chevron.down")
                .foregroundStyle(Color(red: 0.36, green: 0.47, blue: 0.61))
                .font(.system(size: dockManager.adaptiveIconSize * 0.37, weight: .semibold))
        }
        .overlay(
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .stroke(Color.white.opacity(0.84), lineWidth: 1)
        )
        .shadow(color: Color(red: 0.34, green: 0.43, blue: 0.57).opacity(0.08), radius: 6, x: 0, y: 3)
        .animation(.spring(response: MultitaskDockManager.Constants.longAnimationDuration, dampingFraction: MultitaskDockManager.Constants.standardSpringDamping), value: dockManager.adaptiveIconSize)
    }
}

// MARK: - Minimize All Button View
@available(iOS 16.0, *)
struct MinimizeAllButtonView: View {
    @EnvironmentObject var dockManager: MultitaskDockManager

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .fill(Color(red: 0.88, green: 0.93, blue: 0.99).opacity(0.78))
                .frame(width: dockManager.adaptiveIconSize, height: dockManager.adaptiveIconSize)

            Image(systemName: "rectangle.stack.badge.minus")
                .foregroundStyle(Color(red: 0.36, green: 0.47, blue: 0.61))
                .font(.system(size: dockManager.adaptiveIconSize * 0.36, weight: .semibold))
        }
        .overlay(
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .stroke(Color.white.opacity(0.84), lineWidth: 1)
        )
        .shadow(color: Color(red: 0.34, green: 0.43, blue: 0.57).opacity(0.08), radius: 6, x: 0, y: 3)
    }
}

// MARK: - Icon Cache Manager
class IconCacheManager {
    static let shared = IconCacheManager()
    private var cache: [String: UIImage] = [:]
    private let cacheQueue = DispatchQueue(label: "icon.cache.queue", attributes: .concurrent)
    
    private init() {}
    
    func getIcon(for key: String) -> UIImage? {
        return cacheQueue.sync {
            return cache[key]
        }
    }
    
    func setIcon(_ icon: UIImage, for key: String) {
        cacheQueue.async(flags: .barrier) {
            self.cache[key] = icon
        }
    }
    
    func clearCache() {
        cacheQueue.async(flags: .barrier) {
            self.cache.removeAll()
        }
    }
}
// MARK: - App Icon View
@available(iOS 16.0, *)
struct AppIconView: View {
    let app: DockAppModel
    @State private var isPressed = false
    @State private var appIcon: UIImage?
    @State private var isLoading = true
    @EnvironmentObject var dockManager: MultitaskDockManager
    @AppStorage("darkModeIcon", store: LCUtils.appGroupUserDefault) var darkModeIcon = false
    
    private var iconSize: CGFloat {
        return dockManager.adaptiveIconSize
    }

    private var isCustomChat: Bool {
        app.appName.localizedCaseInsensitiveContains("customchat")
    }

    private var customChatPlanetIcon: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.80, green: 0.89, blue: 1.00),
                            Color(red: 0.88, green: 0.83, blue: 0.98)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            Circle()
                .stroke(Color.white.opacity(0.76), lineWidth: 1)
                .frame(width: iconSize * 0.72, height: iconSize * 0.72)
                .rotation3DEffect(.degrees(58), axis: (x: 1, y: 0, z: 0.2))
            Image(systemName: "bubble.left.and.bubble.right.fill")
                .font(.system(size: iconSize * 0.39, weight: .medium))
                .foregroundStyle(
                    LinearGradient(
                        colors: [
                            Color(red: 0.30, green: 0.55, blue: 0.83),
                            Color(red: 0.56, green: 0.43, blue: 0.78)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            Image(systemName: "sparkles")
                .font(.system(size: iconSize * 0.20, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.96))
                .offset(x: iconSize * 0.22, y: -iconSize * 0.22)
        }
        .frame(width: iconSize, height: iconSize)
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.88), lineWidth: 1)
        )
    }

    var body: some View {
        Group {
            if isCustomChat {
                customChatPlanetIcon
            } else if isLoading && appIcon == nil {
                LoadingIconView()
            } else if let icon = appIcon {
                IconImageView(icon: icon)
            } else {
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.gray.opacity(0.16))
            }
        }
        .frame(width: iconSize, height: iconSize)
        .shadow(color: Color(red: 0.34, green: 0.43, blue: 0.57).opacity(0.13), radius: 8, x: 0, y: 4)
        .scaleEffect(isPressed ? 1.08 : 1.0)
        .animation(.easeInOut(duration: 0.1), value: isPressed)
        .animation(.easeInOut(duration: MultitaskDockManager.Constants.standardAnimationDuration), value: dockManager.settingsChanged)
        .onAppear {
            if !isCustomChat {
                loadAppIcon()
            }
        }
        .onPressGesture(
            onPress: { 
                isPressed = true
            },
            onRelease: { location in 
                isPressed = false
                let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
                impactFeedback.impactOccurred()
                let _ = dockManager.bringMultitaskViewToFront(uuid: app.appUUID, from: location)
            }
        )
        .contentShape(Rectangle())
    }
    
    private func loadAppIcon() {
        let cacheKey = "\(app.appName)_\(app.appUUID)"
        
        if let cachedIcon = IconCacheManager.shared.getIcon(for: cacheKey) {
            self.appIcon = cachedIcon
            self.isLoading = false
            return
        }
        
        DispatchQueue.global(qos: .userInitiated).async {
            var finalIcon: UIImage?
            
            if let appInfo = self.app.appInfo {
                finalIcon = appInfo.iconIsDarkIcon(darkModeIcon)
            } else {
                if let foundAppInfo = AppInfoProvider.shared.findAppInfo(appName: self.app.appName, dataUUID: self.app.appUUID) {
                    finalIcon = foundAppInfo.iconIsDarkIcon(darkModeIcon)
                }
            }
            
            DispatchQueue.main.async {
                self.isLoading = false
                if let icon = finalIcon {
                    self.appIcon = icon
                    IconCacheManager.shared.setIcon(icon, for: cacheKey)
                }
            }
        }
    }
}

// MARK: - Press Gesture Helper
extension View {
    func onPressGesture(onPress: @escaping () -> Void, onRelease: @escaping (_ location: CGPoint) -> Void) -> some View {
        self.simultaneousGesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .global)
                .onChanged { value in
                    if value.translation == CGSize.zero {
                        onPress()
                    }
                }
                .onEnded { value in
                    onRelease(value.startLocation)
                }
        )
    }
}

// MARK: - Loading Icon View
struct LoadingIconView: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.gray.opacity(0.3))
            
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                .scaleEffect(1.2)
        }
    }
}
