//
//  TabView.swift
//  LiveContainerSwiftUI
//
//  Created by s s on 2024/8/21.
//

import Foundation
import SwiftUI
import UIKit


private struct LCHideNativeTabBar: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 16.0, *) {
            content
                .toolbar(.hidden, for: .tabBar)
                .onAppear {
                    // Also hide UIKit's native tab bar so only the custom glass bar remains.
                    UITabBar.appearance().isHidden = true
                }
        } else {
            content.onAppear {
                UITabBar.appearance().isHidden = true
            }
        }
    }
}

struct LCTabView: View {
    @State var errorShow = false
    @State var crashReportShow = false
    @State private var showHiddenSources = false
    @State private var hasForegroundContainerApp = MultitaskManager.hasForegroundContainer()
    @State var errorInfo = ""
    
    @EnvironmentObject var sharedModel : SharedModel
    @EnvironmentObject var sceneDelegate: SceneDelegate
    @State var shouldToggleMainWindowOpen = false
    @Environment(\.scenePhase) var scenePhase
    @StateObject var downloadHelper = DownloadHelper()

    let pub = NotificationCenter.default.publisher(for: UIScene.didDisconnectNotification)
    
    var body: some View {
        TabView(selection: $sharedModel.selectedTab) {
            LCHomeView()
                .tabItem { Label("首页", systemImage: "house.fill") }
                .tag(LCTabIdentifier.home)

            LCAppListView()
                .tabItem { Label("lc.tabView.apps".loc, systemImage: "square.stack.3d.up.fill") }
                .tag(LCTabIdentifier.apps)

            if DataManager.shared.model.multiLCStatus != 2 {
                LCTweaksView()
                    .tabItem { Label("lc.tabView.tweaks".loc, systemImage: "wrench.and.screwdriver") }
                    .tag(LCTabIdentifier.tweaks)
            }

            LCSettingsView()
                .tabItem { Label("lc.tabView.settings".loc, systemImage: "gearshape.fill") }
                .tag(LCTabIdentifier.settings)
        }
        .modifier(LCHideNativeTabBar())
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !hasForegroundContainerApp {
                customBottomBar
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.84), value: hasForegroundContainerApp)
        .onAppear {
            hasForegroundContainerApp = MultitaskManager.hasForegroundContainer()
        }
        .onReceive(
            NotificationCenter.default.publisher(for: .lcMultitaskContainerStateDidChange)
                .receive(on: DispatchQueue.main)
        ) { _ in
            withAnimation(.spring(response: 0.32, dampingFraction: 0.84)) {
                hasForegroundContainerApp = MultitaskManager.hasForegroundContainer()
            }
        }
        .tint(Color(red: 0.29, green: 0.43, blue: 0.94))
        .background(Color(uiColor: .systemGroupedBackground))
        .sheet(isPresented: $showHiddenSources) {
            NavigationView {
                LCSourcesView()
                    .navigationTitle("lc.tabView.sources".loc)
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("lc.common.done".loc) { showHiddenSources = false }
                        }
                    }
            }
        }
        .downloadAlert(helper: downloadHelper)
        .environmentObject(downloadHelper)
        .alert("lc.common.error".loc, isPresented: $errorShow){
            Button("lc.common.ok".loc, action: {
            })
            Button("lc.common.copy".loc, action: {
                copyError()
            })
        } message: {
            Text(errorInfo)
        }
        .sheet(isPresented: $crashReportShow) {
            NavigationView {
                ScrollView {
                    Text(errorInfo)
                        .font(.system(size: 12).monospaced())
                        .fixedSize(horizontal: false, vertical: false)
                        .textSelection(.enabled)
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        if #available(iOS 16.0, *) {
                            if let log = UserDefaults.lcShared().url(forKey: "LC32BitTranslationLayerLogFile") {
                                ShareLink(item: log)
                            } else {
                                ShareLink(item: errorInfo)
                            }
                        } else {
                            Button("lc.common.copy".loc) {
                                copyError()
                            }
                        }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("lc.common.ok".loc, action: {
                            crashReportShow = false
                        })
                    }
                }
                .navigationTitle("lc.common.error".loc)
                .navigationBarTitleDisplayMode(.inline)
            }
        }
        .task {
            closeDuplicatedWindow()
            checkLastLaunchError()
            checkTeamId()
            checkAndSaveBundleId()
            checkGetTaskAllow()
            checkPrivateContainerBookmark()
        }
        .onReceive(pub) { out in
            if let scene1 = sceneDelegate.window?.windowScene, let scene2 = out.object as? UIWindowScene, scene1 == scene2 {
                if shouldToggleMainWindowOpen {
                    DataManager.shared.model.mainWindowOpened = false
                }
            }
        }
        .onOpenURL { url in
            dispatchURL(url: url)
        }
    }
    
    
    private var customBottomBar: some View {
        HStack(alignment: .center, spacing: 12) {
            HStack(spacing: 2) {
                bottomBarButton(title: "首页", symbol: "house.fill", tab: .home)
                bottomBarButton(title: "lc.tabView.apps".loc, symbol: "square.stack.3d.up.fill", tab: .apps)
                if DataManager.shared.model.multiLCStatus != 2 {
                    bottomBarButton(title: "lc.tabView.tweaks".loc, symbol: "wrench.and.screwdriver", tab: .tweaks)
                }
            }
            .padding(.horizontal, 5)
            .padding(.vertical, 5)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().stroke(Color.white.opacity(0.5), lineWidth: 0.75))
            .shadow(color: Color.black.opacity(0.04), radius: 8, x: 0, y: 3)

            Spacer(minLength: 0)

            bottomBarButton(title: "lc.tabView.settings".loc, symbol: "gearshape.fill", tab: .settings)
                .frame(width: 54, height: 54)
                .background(.ultraThinMaterial, in: Circle())
                .overlay(Circle().stroke(Color.white.opacity(0.5), lineWidth: 0.75))
                .shadow(color: Color.black.opacity(0.04), radius: 8, x: 0, y: 3)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 6)
    }

    private func bottomBarButton(title: String, symbol: String, tab: LCTabIdentifier) -> some View {
        let isSelected = sharedModel.selectedTab == tab
        return Button {
            withAnimation(.spring(response: 0.30, dampingFraction: 0.80)) {
                sharedModel.selectedTab = tab
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(size: 17, weight: .semibold))
                    .frame(width: 22, height: 22)
                if isSelected {
                    Text(title)
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                        .transition(.opacity.combined(with: .scale(scale: 0.92)))
                }
            }
            .foregroundStyle(isSelected ? Color(red: 0.29, green: 0.43, blue: 0.94) : Color.secondary)
            .frame(width: isSelected ? nil : 44, height: 44)
            .padding(.horizontal, isSelected ? 10 : 0)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }

    func dispatchURL(url: URL) {
        repeat {
            if url.isFileURL {
                sharedModel.selectedTab = .apps
                break
            }
            if url.scheme?.lowercased() == "sidestore" {
                sharedModel.selectedTab = .apps
                break
            }
            
            guard let host = url.host?.lowercased() else {
                return
            }
            
            switch host {
            case "livecontainer-launch", "install", "open-web-page", "open-url":
                sharedModel.selectedTab = .apps
            case "certificate":
                sharedModel.selectedTab = .settings
            case "source":
                // Keep Sources functional but hidden from the bottom tab bar.
                showHiddenSources = true
            default:
                return
            }
            
        } while(false)

        sharedModel.deepLink = url
    }
    
    func closeDuplicatedWindow() {
        if let session = sceneDelegate.window?.windowScene?.session, DataManager.shared.model.mainWindowOpened {
            UIApplication.shared.requestSceneSessionDestruction(session, options: nil) { e in
                print(e)
            }
        } else {
            shouldToggleMainWindowOpen = true
        }
        DataManager.shared.model.mainWindowOpened = true
    }
    
    func checkLastLaunchError() {
        var errorStr = UserDefaults.standard.string(forKey: "error")
        
        if errorStr == nil && UserDefaults.standard.bool(forKey: "SigningInProgress") {
            errorStr = "lc.signer.crashDuringSignErr".loc
            UserDefaults.standard.removeObject(forKey: "SigningInProgress")
        }
        
        guard let errorStr else {
            return
        }
        UserDefaults.standard.removeObject(forKey: "error")
        errorInfo = errorStr
        crashReportShow = true
    }
    
    func copyError() {
        UIPasteboard.general.string = errorInfo
    }
    
    func checkTeamId() {
        if let certificateTeamId = UserDefaults.standard.string(forKey: "LCCertificateTeamId") {
            if DataManager.shared.model.multiLCStatus != 2 {
                return
            }
            
            guard let primaryLCTeamId = Bundle.main.infoDictionary?["PrimaryLiveContainerTeamId"] as? String else {
                print("Unable to find PrimaryLiveContainerTeamId")
                return
            }
            if certificateTeamId != primaryLCTeamId {
                errorInfo = "lc.settings.multiLC.teamIdMismatch".loc
                errorShow = true
                return
            }
            return
        }
        
        guard let currentTeamId = LCSharedUtils.teamIdentifier() else {
            print("Failed to determine team id.")
            return
        }
        
        if DataManager.shared.model.multiLCStatus == 2 {
            guard let primaryLCTeamId = Bundle.main.infoDictionary?["PrimaryLiveContainerTeamId"] as? String else {
                print("Unable to find PrimaryLiveContainerTeamId")
                return
            }
            if currentTeamId != primaryLCTeamId {
                errorInfo = "lc.settings.multiLC.teamIdMismatch".loc
                errorShow = true
                return
            }
        }
        UserDefaults.standard.set(currentTeamId, forKey: "LCCertificateTeamId")
    }
    
    func checkAndSaveBundleId() {
        if DataManager.shared.model.multiLCStatus == 2 {
            let scheme = UserDefaults.lcAppUrlScheme() ?? ""
            LCUtils.appGroupUserDefault.set(Bundle.main.bundleIdentifier, forKey: "LCBundleID.\(scheme)")
        }
        
        if UserDefaults.standard.bool(forKey: "LCBundleIdChecked") {
            return
        }
        
        let task = SecTaskCreateFromSelf(nil)
        guard let value = SecTaskCopyValueForEntitlement(task, "application-identifier" as CFString, nil), let appIdentifier = value.takeRetainedValue() as? String else {
            errorInfo = "Unable to determine application-identifier"
            errorShow = true
            return
        }
        
        guard let bundleId = Bundle.main.bundleIdentifier else {
            return
        }
        
        var correctBundleId = ""
        if appIdentifier.count > 11 {
            let startIndex = appIdentifier.index(appIdentifier.startIndex, offsetBy: 11)
            correctBundleId = String(appIdentifier[startIndex...])
        }
        
        if(bundleId != correctBundleId) {
            errorInfo = "lc.settings.bundleIdMismatch %@ %@".localizeWithFormat(bundleId, correctBundleId)
            errorShow = true
        }
        UserDefaults.standard.set(true, forKey: "LCBundleIdChecked")
    }
    
    func checkGetTaskAllow() {
        let task = SecTaskCreateFromSelf(nil)
        guard let value = SecTaskCopyValueForEntitlement(task, "get-task-allow" as CFString, nil), (value.takeRetainedValue() as? NSNumber)?.boolValue ?? false else {
            errorInfo = "lc.settings.notDevCert".loc
            errorShow = true
            return
        }
    }
    
    func checkPrivateContainerBookmark() {
        if sharedModel.multiLCStatus == 2 {
            return
        }
        if LCUtils.appGroupUserDefault.object(forKey: "LCLaunchExtensionPrivateDocBookmark") != nil {
            return
        }
        
        guard let bookmark = LCUtils.bookmark(for: LCPath.docPath) else {
            errorInfo = "Failed to create bookmark for Documents folder?"
            errorShow = true
            return
        }
        LCUtils.appGroupUserDefault.set(bookmark, forKey: "LCLaunchExtensionPrivateDocBookmark")
    }
}


// MARK: - LiveContainer Home

private enum LCHomePalette {
    static let blue = Color(red: 0.28, green: 0.48, blue: 0.96)
    static let purple = Color(red: 0.58, green: 0.43, blue: 0.91)
    static let muted = Color.secondary
}

private struct LCHomeSurface: ViewModifier {
    var radius: CGFloat = 22

    func body(content: Content) -> some View {
        content
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(Color.white.opacity(0.72), lineWidth: 0.8)
            }
            .shadow(color: Color.black.opacity(0.045), radius: 14, x: 0, y: 6)
    }
}

private struct LCHomeQuickActionTile: View {
    let title: String
    let subtitle: String
    let symbol: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                Image(systemName: symbol)
                    .font(.system(size: 21, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 42, height: 42)
                    .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                    Text(subtitle)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 108, alignment: .leading)
            .padding(12)
            .modifier(LCHomeSurface(radius: 20))
            .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

struct LCHomeView: View {
    @EnvironmentObject private var sharedModel: SharedModel
    @AppStorage("darkModeIcon", store: LCUtils.appGroupUserDefault) private var darkModeIcon = false

    private let quickLaunchColumns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 4)
    private let actionColumns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 3)

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header
                    quickActions
                    quickLaunch
                    if #available(iOS 16.0, *) {
                        LCHomeMultitaskSummary()
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 14)
                .padding(.bottom, 28)
            }
            .background {
                ZStack(alignment: .top) {
                    Color(uiColor: .systemGroupedBackground)
                    LinearGradient(
                        colors: [
                            Color(red: 0.78, green: 0.84, blue: 1.0).opacity(0.42),
                            Color(red: 0.88, green: 0.80, blue: 0.98).opacity(0.30),
                            Color.clear
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .frame(height: 420)
                }
                .ignoresSafeArea()
            }
            .navigationBarHidden(true)
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }

    private var header: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(LinearGradient(colors: [LCHomePalette.blue, LCHomePalette.purple], startPoint: .topLeading, endPoint: .bottomTrailing))
                Image(systemName: "square.stack.3d.up.fill")
                    .font(.system(size: 27, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 66, height: 66)
            .shadow(color: LCHomePalette.blue.opacity(0.22), radius: 12, x: 0, y: 6)

            VStack(alignment: .leading, spacing: 4) {
                Text("LiveContainer 2.0")
                    .font(.system(size: 23, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                Text("在 iOS 上运行与管理应用")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 4)

            Button {
                sharedModel.selectedTab = .settings
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 42, height: 42)
                    .background(.regularMaterial, in: Circle())
                    .overlay(Circle().stroke(Color.white.opacity(0.7), lineWidth: 0.8))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("设置")
        }
        .padding(.top, 8)
    }

    private var quickActions: some View {
        LazyVGrid(columns: actionColumns, spacing: 10) {
            LCHomeQuickActionTile(
                title: "导入 IPA",
                subtitle: "从文件选择",
                symbol: "square.and.arrow.down",
                tint: LCHomePalette.blue
            ) {
                openAppList(action: .chooseIPA)
            }

            LCHomeQuickActionTile(
                title: "在线安装",
                subtitle: "输入安装链接",
                symbol: "link",
                tint: Color(red: 0.27, green: 0.68, blue: 0.52)
            ) {
                openAppList(action: .installFromURL)
            }

            LCHomeQuickActionTile(
                title: "内置浏览器",
                subtitle: "网页与协议跳转",
                symbol: "safari",
                tint: LCHomePalette.purple
            ) {
                openAppList(action: .openBrowser)
            }
        }
    }

    private var quickLaunch: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("快速启动")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.primary)
                    Text("\(sharedModel.apps.count) 个可用应用")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("全部应用") {
                    sharedModel.selectedTab = .apps
                }
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(LCHomePalette.blue)
                .buttonStyle(.plain)
            }

            if sharedModel.apps.isEmpty {
                Button {
                    openAppList(action: .chooseIPA)
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "plus.app")
                            .font(.system(size: 24))
                            .foregroundStyle(LCHomePalette.blue)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("还没有应用")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.primary)
                            Text("导入 IPA 后，应用会显示在这里")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(16)
                    .modifier(LCHomeSurface())
                }
                .buttonStyle(.plain)
            } else {
                LazyVGrid(columns: quickLaunchColumns, spacing: 12) {
                    ForEach(Array(sharedModel.apps.prefix(4)), id: \.self) { app in
                        Button {
                            sharedModel.requestedQuickLaunchApp = app
                            sharedModel.selectedTab = .apps
                        } label: {
                            VStack(spacing: 7) {
                                Image(uiImage: app.appInfo.iconIsDarkIcon(darkModeIcon) ?? UIImage())
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 54, height: 54)
                                    .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
                                    .shadow(color: Color.black.opacity(0.10), radius: 5, x: 0, y: 3)
                                Text(app.displayName)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                    .frame(maxWidth: .infinity)
                            }
                            .padding(.vertical, 8)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("启动 \(app.displayName)")
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .modifier(LCHomeSurface())
            }
        }
    }

    private func openAppList(action: LCHomeAction) {
        sharedModel.requestedHomeAction = action
        sharedModel.selectedTab = .apps
    }
}

@available(iOS 16.0, *)
private struct LCHomeMultitaskSummary: View {
    @ObservedObject private var dockManager = MultitaskDockManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("多任务")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(.primary)
                    Text(dockManager.apps.isEmpty ? "窗口运行状态" : "\(dockManager.apps.count) 个窗口正在运行")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "rectangle.on.rectangle")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(LCHomePalette.blue)
                    .frame(width: 40, height: 40)
                    .background(LCHomePalette.blue.opacity(0.10), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            }

            if dockManager.apps.isEmpty {
                Text("暂无运行中的多任务窗口")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 5)
            } else {
                HStack(spacing: 10) {
                    ForEach(Array(dockManager.apps.prefix(3)), id: \.id) { app in
                        HStack(spacing: 7) {
                            Image(systemName: "app.fill")
                                .font(.system(size: 13))
                                .foregroundStyle(LCHomePalette.blue)
                            Text(app.appName)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 9)
                        .background(Color.primary.opacity(0.045), in: Capsule())
                    }
                }
            }
        }
        .padding(16)
        .modifier(LCHomeSurface())
    }
}
