@AGENTS.md

## Fork rules

- Commit directly to `main`; keep no feature or session branches. Bring work done in a worktree onto `main` by fast-forward or cherry-pick so history stays linear, with no merge commits. Pushing still needs the user's go-ahead.
- Keep Sparkle automatic update checks off (`SUEnableAutomaticChecks: false` in `project.yml`). `SUFeedURL` points at the upstream appcast, so an automatic update would replace this fork's build with upstream's.
