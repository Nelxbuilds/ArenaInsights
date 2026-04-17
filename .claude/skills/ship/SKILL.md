---
name: ship
description: >
  Ship a new version: bump version, commit, tag, and push to trigger a CurseForge release.
  Supports semver with pre-release labels.
  Use when the user says "ship", "ship it", "ship beta", "ship patch", "/ship minor", "/ship 0.2.0", "release", "tag a release", etc.
user_invocable: true
args: "[patch|minor|major|beta|<explicit-version>]"
---

# NelxRated Ship Skill

You help the user bump the addon version, create a git tag, and push. You MUST ask for confirmation before every destructive or shared-state action.

## Step 1: Parse Arguments

The user provides one of:
- `patch` / `minor` / `major` — auto-calculate the next version
- `beta` — create or increment a beta pre-release
- An explicit version like `0.2.0` or `1.0.0-beta`
- No argument — ask which bump type they want

## Step 2: Read Current Version and Existing Tags

Read `NelxRated.toc` and extract the `## Version:` field. This is the current version.

Parse it as semver: `MAJOR.MINOR.PATCH[-PRERELEASE]`

**Read existing git tags** by running:
```bash
git tag --list 'v*' --sort=-version:refname
```

Use these tags to:
- Detect if the calculated new version tag already exists (abort with a warning if so)
- For `beta` bumps: show the user which beta tags already exist for the relevant base version (e.g. if bumping `0.2.0-beta`, list any existing `v0.2.0-beta*` tags)

Examples of how bumps work (TOC version is always stable, beta is derived from tags):

| TOC Version | Existing beta tags              | `patch` | `minor` | `major` | `beta`          |
|-------------|---------------------------------|---------|---------|---------|-----------------|
| `0.1.0`     | (none)                          | `0.1.1` | `0.2.0` | `1.0.0` | `0.1.0-beta`    |
| `0.1.0`     | `v0.1.0-beta`                   | `0.1.1` | `0.2.0` | `1.0.0` | `0.1.0-beta-1`  |
| `0.1.0`     | `v0.1.0-beta`, `v0.1.0-beta-1` | `0.1.1` | `0.2.0` | `1.0.0` | `0.1.0-beta-2`  |
| `1.2.3`     | (none)                          | `1.2.4` | `1.3.0` | `2.0.0` | `1.2.3-beta`    |

### Beta bump rules

Beta versions are derived from **existing git tags**, not the TOC version. The TOC always holds the stable base version.

Given the TOC version `X.Y.Z`, look at existing tags matching `vX.Y.Z-beta*`:
- If no `vX.Y.Z-beta*` tags exist: new version is `X.Y.Z-beta`
- If `vX.Y.Z-beta` exists but no numbered betas: new version is `X.Y.Z-beta-1`
- If `vX.Y.Z-beta-N` is the highest numbered beta: new version is `X.Y.Z-beta-(N+1)`

The beta suffix always uses hyphens: `-beta`, `-beta-1`, `-beta-2`, etc.

### Stable bump rules

- `patch`: If current has a pre-release suffix, strip it (promotes to stable). Otherwise increment PATCH.
- `minor`: Always increment MINOR, reset PATCH to 0, strip pre-release.
- `major`: Always increment MAJOR, reset MINOR and PATCH to 0, strip pre-release.

If the user provides an explicit version, use it as-is (validate it looks like semver).

### Beta releases are tag-only

Beta bumps are lightweight — they **only create a tag and push it**. No file changes, no commit, no release-prep. Skip Steps 4, 5, 6, and 7 entirely. Go directly from Step 3 (confirm) to Step 8 (tag) then Step 9 (push).

## Step 3: Confirm the Version

For **stable** bumps (patch/minor/major), show:
```
Current version: <current>
New version:     <new>
Tag:             v<new>
Existing tags:   <list of relevant existing tags, or "none">
```

For **beta** bumps (tag-only, no file changes), show:
```
New tag:         v<new>
Existing tags:   <list of relevant existing beta tags, or "none">
```

If the target tag already exists, warn the user and ask how to proceed (pick a different version or abort).

Ask: **"Proceed?"**

Do NOT continue until the user confirms.

## Step 4: Run Release Prep

Tell the user you're running the release-prep agent as a pre-flight check. Spawn the `release-prep` agent.

If release-prep reports blockers (linter errors, unchecked epic criteria, etc.), show the report to the user and ask if they want to continue anyway or abort.

## Step 4.5: Sync README

Run `/update-readme` to ensure README.md reflects the current feature set before the release commit. This happens automatically — no user prompt needed. If the skill makes changes, those changes will be included in the Step 7 commit alongside the TOC and CHANGELOG.

## Step 5: Update the TOC

Edit `NelxRated.toc` to set the new version:
```
## Version: <new-version>
```

## Step 6: Update CHANGELOG.md

If `CHANGELOG.md` exists, check if there's already a section for the new version. If not, add a new section at the top (after the `# Changelog` heading) with today's date:

```markdown
## [<new-version>] -- <YYYY-MM-DD>

### Changed
- Version bump from <old-version>
```

Tell the user they should flesh out the changelog entry before pushing, and ask if they want to edit it now or continue.

## Step 7: Commit

Stage only the changed files (`NelxRated.toc`, `CHANGELOG.md`, and any files release-prep created/modified).

Ask: **"Ready to commit these changes?"**

Create a commit with message:
```
release: v<new-version>
```

## Step 8: Tag

Ask: **"Create tag v<new-version>?"**

Create an annotated tag:
```bash
git tag -a v<new-version> -m "Release v<new-version>"
```

## Step 9: Push

Ask: **"Push commit and tag to origin?"**

If confirmed:
```bash
git push origin main --follow-tags
```

## Step 10: Summary

Print a short summary:
```
Done! Released v<new-version>
- TOC updated
- Commit: <short-hash>
- Tag: v<new-version>
- Pushed to origin/main
```

## Important Rules

- **Always ask before acting** on commits, tags, and pushes. Never auto-proceed.
- **Never force-push**. If the push fails, tell the user and let them decide.
- **Never amend commits**. Always create new ones.
- The commit message must end with the co-author line:
  `Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>`
