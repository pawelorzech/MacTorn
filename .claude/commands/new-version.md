---
allowed-tools: Bash(git add:*), Bash(git status:*), Bash(git commit:*), Bash(git tag:*), Bash(git push:*), Bash(gh release:*), Bash(make:*)
description: Cut a MacTorn release — bump the Xcode version, update CHANGELOG and README, tag, push and publish a GitHub release.
---

## Context

- Current git status: !`git status`
- Current git diff (staged and unstaged changes): !`git diff HEAD`
- Current branch: !`git branch --show-current`
- Recent commits: !`git log --oneline -10`

## Your task

Cut a new MacTorn release.

**This is a Swift / Xcode project. There are no Gradle files.** The version lives in
`MacTorn/MacTorn.xcodeproj/project.pbxproj`:

- `MARKETING_VERSION` — the user-facing version (e.g. `1.11.1`). Bump it.
- `CURRENT_PROJECT_VERSION` — the build number. Bump it too; it is what
  `Diagnostics` reports as `build` and what distinguishes two builds of the
  same marketing version.

Both appear in several build configurations — update every occurrence so Debug and
Release agree.

Steps:

1. Bump `MARKETING_VERSION` in `project.pbxproj` (every build configuration —
   Debug and Release must agree).
2. **MANDATORY — bump `CURRENT_PROJECT_VERSION` too, every single release, with no
   exceptions.** This is not optional and not "only if it feels like a big
   release": it is the build number `Diagnostics` reports as `build`, and it is
   the only thing that distinguishes two builds of the *same* marketing version
   in a bug report. It has been left at `1` across releases before (GitHub
   issue #57) — do not repeat that. Increment it (e.g. by 1, or to match the
   running release count) in **every** build configuration in `project.pbxproj`.
   Verify before moving on — this check must stay valid for *every* future
   release, so compare against the previous commit rather than a hardcoded
   number:

   ```sh
   # All six occurrences must agree with each other, and the value must be
   # strictly greater than the one currently on HEAD.
   new=$(grep -o 'CURRENT_PROJECT_VERSION = [0-9]*' MacTorn/MacTorn.xcodeproj/project.pbxproj | sort -u)
   old=$(git show HEAD:MacTorn/MacTorn.xcodeproj/project.pbxproj | grep -o 'CURRENT_PROJECT_VERSION = [0-9]*' | sort -u)
   echo "old: $old" ; echo "new: $new"
   test "$(printf '%s\n' "$new" | wc -l)" -eq 1 || echo "FAIL: configurations disagree"
   test "${new##* }" -gt "${old##* }" || echo "FAIL: build number did not increase"
   ```
3. Add the release section to `CHANGELOG.md`.
4. Update `README.md` if user-visible features changed.
5. Run the gates before tagging: `make test` and `make coverage-gate` must pass.
   Do **not** run `make test-ui` or launch the app without asking — XCUITest takes
   over the screen and steals focus from whatever the user is doing.
6. Commit, tag `vX.Y.Z`, push the branch and the tag.
7. Build the distributable: `make release` then `make verify-release`.
8. **Compute and publish the SHA-256 checksum of the release artefact.** MacTorn
   is not notarized or signed with a paid Developer ID (deliberate, out of
   scope — see GitHub issue #59), so a checksum is the only thing a user can
   verify a download against. Run `shasum -a 256` against the zipped/DMG
   release artefact produced by `make release` and paste the resulting hash
   into the GitHub release notes, e.g.:
   `shasum -a 256 <path-to-release-artifact>`
   Label it clearly in the release notes, e.g. `SHA-256: <hash>`.
9. Publish the GitHub release with `gh release create`, including the SHA-256
   line from step 8 in the release body.
10. **Replace the local install too.** Every published release must also replace
    the copy in `/Applications`, otherwise the user keeps running the old build.

Ask before publishing if anything in steps 1-5 did not come out clean.
