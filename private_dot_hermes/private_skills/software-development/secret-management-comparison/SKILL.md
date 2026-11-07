---
name: secret-management-comparison
description: "Use when comparing secrets tooling. Trace plaintext paths."
version: 1.0.0
author: Hermes Agent
license: MIT
metadata:
  hermes:
    tags: [security, secrets, research, nixos, supply-chain]
    category: software-development
---

# Secret-management comparison

## When to Use

Use when comparing encrypted configuration, local secret managers, or runtime secret delivery. Separate repository protection from endpoint protection.

## Procedure

1. **Pin the exact implementation and version.** Read the user's lockfile/package resolution when available. For source-level tools, inspect the exact release's dependency manifest as well as the CLI release version; wrappers can embed an older library than the installed CLI.
2. **Trace bytes end to end.** Record separately: repository representation, Nix/evaluation/build-store inputs, decrypting process, runtime filesystem/path, file owner/mode, service/user access, and reboot/rotation behavior. State whether plaintext is persistent, memory-backed, in swap, or only transiently rendered.
3. **Distinguish mechanisms.** Separate native encryption formats from external CLI backends, Git clean/smudge filters, password-manager template functions, and generic command hooks. A generic command can compose tools but does not create a native integration or change the destination's plaintext lifetime.
4. **Check target-path ownership.** Assign exactly one writer to each file path. If one manager supplies another's path, use a distinct runtime secret path and a managed symlink/pointer rather than two tools writing the same file.
5. **Check key custody and bootstrap.** Identify where private identities live, how a new host is enrolled, whether a machine SSH key can be used, and what breaks if the key is lost or rotated. Avoid putting private keys or plaintext secret values in the Nix store.
6. **Verify security records from primary databases.** Query each project's GitHub Security Advisories API and OSV using canonical Go module, PyPI, or ecosystem identifiers. Deduplicate GHSA/OSV/CVE aliases; preserve dates, affected/fixed ranges, severity, triggering conditions, and whether the default deployment reaches the vulnerable code path. Treat an empty database query as scoped evidence, not proof of no vulnerability.
7. **Audit dependencies of wrappers.** Read source manifests and implementation calls to determine whether a wrapper embeds the vulnerable library or invokes the affected CLI subcommand. Do not transfer every CLI advisory to an integration that never calls that command.
8. **Assess project assurance carefully.** Compare release dates/cadence and release authors; distinguish contributor counts from authorized maintainer counts. Separate checksum signatures, transparency proofs, SLSA provenance, and reproducible-build evidence—they are different properties. Treat Scorecard as a hygiene signal, not a crypto verdict.
9. **Make a threat-model recommendation.** State when ciphertext in public Git is adequate, where plaintext persists after apply, what can read it, and when runtime delivery is required. Recommend one owner per secret destination and call out rotation that requires activation/apply versus a runtime manager/agent.
10. **Declare coverage gaps.** If the exact lockfile, maintainer roster, compromise history, ecosystem query, or reproducible-build status cannot be verified, say so instead of treating silence as a clean bill of health.

## Output checklist

- Explain plaintext path and permissions before discussing marketing claims.
- Distinguish repository-at-rest protection from endpoint/runtime protection.
- List each advisory with its own ID/date/severity/range/fix/trigger and default-path applicability.
- Call out wrapper dependency lag and advisories not yet indexed by OSV.
- Keep citations adjacent to claims; for JSON-only contracts, place numbered citations in string fields and provide a URL map in an allowed source field.
- End with a concrete split between user-level dotfiles, system/boot secrets, and any shared credential.