@AGENTS.md

## Fork rules

- Commit directly to `main`; keep no feature or session branches. Bring work done in a worktree onto `main` by fast-forward or cherry-pick so history stays linear, with no merge commits. Pushing still needs the user's go-ahead.
- The fork has no auto-update: Sparkle, `UpdaterService`, the Check for Updates menu item and the Software Update settings were removed because the update feed belonged to upstream and would replace this fork's build with upstream's. Do not bring them back when syncing with upstream.
