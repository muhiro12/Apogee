# Dependency maintenance

Repository maintainers own dependency alerts, update pull requests, and their
verification. Review new security alerts promptly, resolve applicable alerts
before the next package release, and record a reason when dismissing an alert.
Do not publish credentials or real account payloads in an issue or advisory.

Enable Dependabot alerts for the repository's committed `Package.resolved` and
keep secret scanning and push protection enabled. GitHub's
[Swift dependency support](https://docs.github.com/en/code-security/reference/supply-chain-security/supported-ecosystems-and-repositories#swift)
does not establish that an advisory database covers every dependency risk.
Adopters must also review their own resolved dependency graph: the package's
lockfile does not pin the versions selected by a consuming package.

The [Dependabot configuration](../.github/dependabot.yml) proposes monthly
Swift-package and GitHub Actions updates, with at most two open version-update
pull requests per ecosystem. Maintainers review the changes and supported
toolchains before merging. Updates are not automatically merged, and security
alerts should not wait for the monthly version-update schedule.

Swift dependency major upgrades require an intentional compatibility decision
and are excluded from routine version-update proposals. This does not replace
security alert triage. Dependabot branches run verification through their pull
request event only, avoiding a duplicate push workflow for the same update.

The generator version is an explicit pin in the maintainer command, outside
Dependabot's manifest discovery. Review its upstream release notes and
advisories when running the OpenAPI updater. The maintainer package has no
external dependencies of its own; its temporary generator package is a local
build artifact. Reconcile third-party license notices when dependencies change.

CI runs package tests, generator-tool tests, and the Release build with Swift
warnings treated as errors on both supported Xcode versions. GitHub Actions
are pinned to reviewed commit hashes; Dependabot can propose pin updates.
Release publication remains gated on the same verification workflow.

Dependency review and code scanning are not separate required workflows at
present. Add one when a concrete check provides actionable findings and a
maintainer owns its triage. A passing build, an empty alert list, or the absence
of a scanner is not a security audit. Do not leave failing security checks or
update pull requests unattended; fix, dismiss with evidence, or track a bounded
follow-up before release.
