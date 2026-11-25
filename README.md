# LiveContainer + SideStore — Custom Build

This repository is a source-level integration workspace for the **LiveContainer + built-in SideStore** edition.

## Upstreams

- LiveContainer application and integration host: https://github.com/LiveContainer/LiveContainer (branch: `main`)
- SideStore integration source: https://github.com/LiveContainer/SideStore (branch: `LiveContainerSupport`)

The SideStore repository's `LiveContainerSupport` branch is specifically maintained for SideStore to function when bundled with LiveContainer. Do not replace it with the standalone SideStore default branch.

## Source layout after the first sync

- `LiveContainer/` — complete LiveContainer source, including its Xcode project, SideStoreSupport integration points, extensions, and submodules.
- `SideStore-Upstream/` — complete SideStore integration branch source.
- `.github/workflows/sync-upstream.yml` — manually triggered source synchronization workflow.

This is a source import, not yet a finished IPA or a claim that the combined app builds. The next stage is to inspect the upstream Xcode targets, framework linkage, entitlements, app groups, extensions, and signing configuration, then wire the customized UI into the correct host target without removing SideStore refresh/signing behavior.

## License and security

Both upstream projects are AGPL-3.0. Keep their license and attribution notices with the imported source and publish corresponding source changes for distributed builds. A combined build handles app credentials and keychain data; only use source you trust and review changes before installing.

## Device target

Initial validation target: iPhone 12 mini (A14), iOS 27.3 beta. Compatibility and signing still need to be verified on-device.
