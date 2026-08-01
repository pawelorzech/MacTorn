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

1. Bump `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in `project.pbxproj`.
2. Add the release section to `CHANGELOG.md`.
3. Update `README.md` if user-visible features changed.
4. Run the gates before tagging: `make test` and `make coverage-gate` must pass.
   Do **not** run `make test-ui` or launch the app without asking — XCUITest takes
   over the screen and steals focus from whatever the user is doing.
5. Commit, tag `vX.Y.Z`, push the branch and the tag.
6. Publish the GitHub release with `gh release create`.
7. Build the distributable: `make release` then `make verify-release`.
8. **Replace the local install too.** Every published release must also replace the
   copy in `/Applications`, otherwise the user keeps running the old build.

Ask before publishing if anything in steps 1-4 did not come out clean.
