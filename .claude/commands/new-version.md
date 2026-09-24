---
allowed-tools: Bash(git add:*), Bash(git status:*), Bash(git commit:*), Bash(git tag:*), Bash(git push:*), Bash(git show:*), Bash(git diff:*), Bash(git branch:*), Bash(git log:*), Bash(grep:*), Bash(gh release:*), Bash(make:*), Bash(hdiutil create:*), Bash(shasum:*), Bash(ditto:*)
description: Cut a MacTorn release — bump the Xcode version, update CHANGELOG and README, tag, push and publish a GitHub release.
---

## Context

- Current git status: !`git status`
- Current git diff (staged and unstaged changes): !`git diff HEAD`
- Current branch: !`git branch --show-current`
- Recent commits: !`git log --oneline -10`

## Your task

Cut a new MacTorn release.

The version lives in `MacTorn/MacTorn.xcodeproj/project.pbxproj`:

- `MARKETING_VERSION` — the user-facing version (e.g. `1.11.1`). Bump it.
- `CURRENT_PROJECT_VERSION` — the build number. Bump it too; it is what
  `Diagnostics` reports as `build` and what distinguishes two builds of the
  same marketing version.

Both appear in several build configurations — update every occurrence so Debug and
Release agree.

Steps:

1. Bump `MARKETING_VERSION` in `project.pbxproj` (every build configuration —
   Debug and Release must agree).
2. Bump `CURRENT_PROJECT_VERSION` on every release, in every build configuration
   (usually +1). It's the `build` that `Diagnostics` reports — the only way to
   tell two builds of the same marketing version apart in a bug report. Verify
   against HEAD before moving on:

   ```sh
   # All occurrences must agree, and the value must exceed the one on HEAD.
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
7. Build and verify: `make release` then `make verify-release`. This produces
   `DerivedData/Release/Build/Products/Release/MacTorn.app` — not a DMG.
8. Package and checksum. MacTorn is not notarized or Developer-ID signed
   (deliberate — issue #59), so the checksum is the only thing a user can verify
   a download against:

   ```sh
   hdiutil create -volname MacTorn -srcfolder DerivedData/Release/Build/Products/Release/MacTorn.app -ov -format UDZO MacTorn-vX.Y.Z.dmg
   shasum -a 256 MacTorn-vX.Y.Z.dmg | tee MacTorn-vX.Y.Z.dmg.sha256
   ```
9. `gh release create vX.Y.Z MacTorn-vX.Y.Z.dmg MacTorn-vX.Y.Z.dmg.sha256` with
   `SHA-256: <hash>` in the release body.
10. Replace the local install, otherwise the user keeps running the old build.
    Quit the running app first, then:
    `ditto DerivedData/Release/Build/Products/Release/MacTorn.app /Applications/MacTorn.app`

Ask before publishing if anything in steps 1-5 did not come out clean.
