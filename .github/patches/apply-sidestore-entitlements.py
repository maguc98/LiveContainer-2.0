#!/usr/bin/env python3
"""Re-apply the maintained SideStore entitlement-signing fix after upstream sync.

The upstream import workflow replaces SideStore-Upstream wholesale. This overlay
uses guarded, single-occurrence replacements so upstream changes cannot silently
discard or misapply the local signing fix.
"""

from pathlib import Path


def replace_once(path: Path, old: str, new: str, label: str) -> None:
    source = path.read_text(encoding="utf-8")
    if new in source:
        return
    count = source.count(old)
    if count != 1:
        raise SystemExit(
            f"{label}: expected exactly one upstream match in {path}, found {count}. "
            "Review the upstream changes before updating this overlay."
        )
    path.write_text(source.replace(old, new, 1), encoding="utf-8")


ROOT = Path(__file__).resolve().parents[2]
RESIGN = ROOT / "SideStore-Upstream/SideStore/Core/Operations/PipelineOperations/ResignAppOperation.swift"
SIGNER = ROOT / "SideStore-Upstream/Dependencies/SideSign/Sources/CodeSigning/CodeSignerAPI.swift"

replace_once(
    RESIGN,
    """        let resignedAppURL = try await self.resignAppBundle(at: appBundleURL, team: team, certificate: certificate, profiles: Array(profiles.values))""",
    """        let applicationEntitlementsByBundleID = try self.applicationEntitlementsByBundleID(
            sourceAppBundle: appBundle,
            preparedAppBundleURL: appBundleURL
        )
        let resignedAppURL = try await self.resignAppBundle(
            at: appBundleURL,
            team: team,
            certificate: certificate,
            profiles: Array(profiles.values),
            applicationEntitlementsByBundleID: applicationEntitlementsByBundleID
        )""",
    "ResignAppOperation signer call",
)

replace_once(
    RESIGN,
    """    private func resignAppBundle(at fileURL: URL, team: ALTTeam, certificate: ALTCertificate, profiles: [ALTProvisioningProfile]) async throws -> URL {
        let signer = ALTSigner(team: team, certificate: certificate)
        try await signer.signApp(at: fileURL, provisioningProfiles: profiles, progress: nil)
        return fileURL
    }
    """,
    """    private func resignAppBundle(
        at fileURL: URL,
        team: ALTTeam,
        certificate: ALTCertificate,
        profiles: [ALTProvisioningProfile],
        applicationEntitlementsByBundleID: [String: [String: any Sendable]]
    ) async throws -> URL {
        let signer = ALTSigner(team: team, certificate: certificate)
        try await signer.signApp(
            at: fileURL,
            provisioningProfiles: profiles,
            applicationEntitlementsByBundleID: applicationEntitlementsByBundleID,
            progress: nil
        )
        return fileURL
    }

    /// Builds an explicit entitlement map for the *prepared* bundle identifiers.
    /// This is important for unsigned IPAs: their Mach-O signature contains no
    /// original entitlements, even though SideStore's customization flow has
    /// already collected the user's requested entitlements and provisioned them.
    private func applicationEntitlementsByBundleID(
        sourceAppBundle: ALTApplication,
        preparedAppBundleURL: URL
    ) throws -> [String: [String: any Sendable]] {
        guard let preparedAppBundle = ALTApplication(fileURL: preparedAppBundleURL) else {
            throw OperationError.invalidApp(reason: "Could not inspect the prepared app bundle before signing.")
        }

        func relativeBundlePath(_ bundleURL: URL, under rootURL: URL) -> String? {
            let rootPath = rootURL.standardizedFileURL.path
            let bundlePath = bundleURL.standardizedFileURL.path
            guard bundlePath == rootPath || bundlePath.hasPrefix(rootPath + "/") else {
                return nil
            }
            return String(bundlePath.dropFirst(rootPath.count))
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        }

        let sourceBundles = sourceAppBundle.allAppBundles
        var result: [String: [String: any Sendable]] = [:]

        for preparedBundle in preparedAppBundle.allAppBundles {
            guard
                let preparedRelativePath = relativeBundlePath(preparedBundle.fileURL, under: preparedAppBundleURL),
                let sourceBundle = sourceBundles.first(where: {
                    relativeBundlePath($0.fileURL, under: sourceAppBundle.fileURL) == preparedRelativePath
                })
            else {
                throw OperationError.invalidApp(
                    reason: "Could not match prepared bundle '\\(preparedBundle.bundleIdentifier)' with its source bundle."
                )
            }

            var requestedEntitlements =
                context.customEntitlementsByBundleID[sourceBundle.bundleIdentifier]
                ?? context.customEntitlementsByBundleID[preparedBundle.bundleIdentifier]
                ?? sourceBundle.entitlements

            // These additional entitlements are also used when requesting the
            // main app's provisioning profile, so they must reach the signer.
            if !sourceBundle.isExtension {
                for (key, value) in context.additionalEntitlements {
                    requestedEntitlements[key.rawValue] = value
                }
            }

            result[preparedBundle.bundleIdentifier] = requestedEntitlements
        }

        return result
    }
    """,
    "ResignAppOperation signer helper",
)

replace_once(
    SIGNER,
    """    public func signApp(at appURL: URL, provisioningProfiles profiles: [ProvisioningProfile], progress: Progress? = nil) async throws
    {
        debugLog("[SideSign] AppBundleSigner.signApp called")""",
    """    public func signApp(at appURL: URL, provisioningProfiles profiles: [ProvisioningProfile], progress: Progress? = nil) async throws
    {
        try await signApp(
            at: appURL,
            provisioningProfiles: profiles,
            applicationEntitlementsByBundleID: [:],
            progress: progress
        )
    }

    /// Signs using the caller's declared entitlements instead of relying only on
    /// entitlements embedded in the original Mach-O signature. Every entitlement
    /// is still filtered against the matched provisioning profile below.
    public func signApp(
        at appURL: URL,
        provisioningProfiles profiles: [ProvisioningProfile],
        applicationEntitlementsByBundleID: [String: [String: any Sendable]],
        progress: Progress? = nil
    ) async throws
    {
        debugLog("[SideSign] AppBundleSigner.signApp called")""",
    "SideSign explicit entitlement API",
)

replace_once(
    SIGNER,
    """            let applicationEntitlements = app.entitlements""",
    """            let applicationEntitlements =
                applicationEntitlementsByBundleID[app.bundleIdentifier] ?? app.entitlements""",
    "SideSign entitlement lookup",
)

replace_once(
    SIGNER,
    """                if let applicationValue = applicationEntitlements[key] {
                    if key == "keychain-access-groups" {""",
    """                if let applicationValue = applicationEntitlements[key] {
                    // A disabled boolean or an empty array means the user did not
                    // request this capability. Do not re-add it just because the
                    // provisioning profile happens to contain it.
                    if let requestedValue = applicationValue as? Bool, !requestedValue {
                        filteredEntitlements.removeValue(forKey: key)
                        continue
                    }
                    if let requestedValues = applicationValue as? [String], requestedValues.isEmpty {
                        filteredEntitlements.removeValue(forKey: key)
                        continue
                    }

                    if key == "keychain-access-groups" {""",
    "SideSign empty/disabled entitlement filtering",
)

print("SideStore entitlement overlay applied.")
