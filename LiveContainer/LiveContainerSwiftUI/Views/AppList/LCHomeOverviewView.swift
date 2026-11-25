import SwiftUI

/// A lightweight overview for the app library. All install and launch actions are
/// forwarded to the existing LCAppListView handlers so the original workflows remain intact.
struct LCHomeOverviewView: View {
    let appCount: Int
    let hiddenCount: Int
    let sideStoreAvailable: Bool
    let canInstall: Bool
    let onInstallIPA: () -> Void
    let onInstallURL: () -> Void
    let onOpenSideStore: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    private let blue = Color(red: 0.31, green: 0.48, blue: 0.86)
    private let lavender = Color(red: 0.57, green: 0.48, blue: 0.82)
    private let mint = Color(red: 0.30, green: 0.62, blue: 0.52)

    var body: some View {
        VStack(alignment: .leading, spacing: 17) {
            HStack(spacing: 8) {
                Image(systemName: "square.stack.3d.up.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(blue)
                    .frame(width: 29, height: 29)
                    .background(blue.opacity(0.13), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                Text("应用管理中心")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .tracking(1.5)
                    .foregroundColor(.secondary)

                Spacer(minLength: 8)

                HStack(spacing: 5) {
                    Circle()
                        .fill(sideStoreAvailable ? mint : Color.secondary.opacity(0.55))
                        .frame(width: 6, height: 6)
                    Text(sideStoreAvailable ? "应用商店已就绪" : "未检测到应用商店")
                        .font(.system(size: 8, weight: .bold, design: .rounded))
                        .tracking(0.55)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
                .foregroundColor(sideStoreAvailable ? mint : .secondary)
                .padding(.horizontal, 9)
                .padding(.vertical, 7)
                .background((sideStoreAvailable ? mint : Color.secondary).opacity(0.10), in: Capsule())
            }

            HStack(alignment: .bottom, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("lc.appList.myApps".loc)
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)

                    Text("管理、安装与启动应用")
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                        .tracking(1.1)
                        .foregroundColor(.secondary)
                }

                Spacer(minLength: 0)

                if canInstall {
                    Menu {
                        Button("lc.appList.installFromIpa".loc, systemImage: "doc.badge.plus", action: onInstallIPA)
                        Button("lc.appList.installFromUrl".loc, systemImage: "link.badge.plus", action: onInstallURL)
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(width: 43, height: 43)
                            .background(LinearGradient(colors: [blue, lavender], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                            .shadow(color: blue.opacity(0.24), radius: 9, x: 0, y: 5)
                    }
                    .accessibilityLabel("添加应用")
                }
            }

            HStack(spacing: 9) {
                metricTile(title: "应用", value: "\(appCount)", symbol: "square.grid.2x2.fill", tint: blue)

                metricTile(title: "隐藏", value: "\(hiddenCount)", symbol: "eye.slash.fill", tint: lavender)

                Button(action: onOpenSideStore) {
                    metricTile(title: "应用商店", value: sideStoreAvailable ? "已就绪" : "—", symbol: "arrow.down.app.fill", tint: mint)
                }
                .buttonStyle(.plain)
                .disabled(!sideStoreAvailable)
            }
        }
        .padding(17)
        .background {
            RoundedRectangle(cornerRadius: 25, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.91, green: 0.95, blue: 1.0).opacity(colorScheme == .dark ? 0.12 : 0.95),
                            Color(red: 0.96, green: 0.93, blue: 1.0).opacity(colorScheme == .dark ? 0.10 : 0.88),
                            Color(.secondarySystemBackground).opacity(colorScheme == .dark ? 0.72 : 0.40)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        }
        .overlay {
            RoundedRectangle(cornerRadius: 25, style: .continuous)
                .stroke(Color.primary.opacity(colorScheme == .dark ? 0.10 : 0.055), lineWidth: 1)
        }
        .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.14 : 0.045), radius: 17, x: 0, y: 8)
        .padding(.horizontal, 15)
        .padding(.top, 12)
        .padding(.bottom, 5)
    }

    private func metricTile(title: String, value: String, symbol: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(tint)

            Text(value)
                .font(.system(size: 19, weight: .bold, design: .rounded))
                .foregroundColor(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.68)

            Text(title)
                .font(.system(size: 8, weight: .bold, design: .rounded))
                .tracking(0.65)
                .foregroundColor(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, minHeight: 76, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(Color.primary.opacity(colorScheme == .dark ? 0.08 : 0.035), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .stroke(Color.primary.opacity(0.045), lineWidth: 1)
        }
        .contentShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
    }
}
