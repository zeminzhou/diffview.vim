# diffview.vim

A native Vim9, read-only Git diff browser. Modified 2026-10-22.

Browse local changes, two Git trees, or the changes introduced by a commit.

Requires Vim 9.1 with `+vim9script`, `+diff`, `+windows`, `+job` and `+timers`,
and Git on `PATH`. Verified on macOS with Vim **9.1.1950** and Git **2.54.0**;
an earlier minimum patch level has not been verified. Neovim and older Vim are
unsupported. No additional runtime dependencies are needed.

Install with your Vim package manager, for example vim-plug:

```vim
Plug 'zeminzhou/diffview.vim'
```

Run a command anywhere inside a non-bare Git worktree. A dedicated tab contains
the file panel, left snapshot and right snapshot:

| Command | Comparison |
| --- | --- |
| `:DiffviewOpen` | Local sections below |
| `:DiffviewOpen main topic` | Direct main tree → topic tree |
| `:DiffviewCommit [revision]` | First parent → commit, default HEAD |
| `:DiffviewRefresh` | Refresh the original request and repository |
| `:DiffviewClose` | Close the view and clean up plugin resources |

`DiffviewOpen` accepts zero or two arguments; `DiffviewCommit` accepts zero or
one. Tree mode accepts revisions resolving to trees, including tree object IDs
and `rev:directory` expressions. Escape argument whitespace as in other Vim
commands, for example `:DiffviewOpen main:src\ dir topic:src\ dir`. There is no
implicit merge-base, revision exclusions (`^rev`), or `..`/`...` range syntax.
Commit mode uses the first parent of merge commits; a root commit compares
EMPTY → commit. Missing parent objects
in shallow/incomplete history cause a Git error rather than a false root view.
Local modifications are excluded from tree/commit comparisons. Source labels
show the revision and resolved short tree/commit object IDs. Refs remain fixed
until explicit refresh, which resolves the original arguments again.

| Section | Left | Right |
| --- | --- | --- |
| Staged | HEAD (or EMPTY before the first commit) | Index |
| Unstaged | Index | Working tree on disk |
| Untracked | EMPTY | Working tree on disk |

Files with both staged and unstaged edits have separate rows. Ignored files are
excluded. Status lines identify the selected section, sources and paths. All
three buffers are read-only scratch buffers. **Unsaved Vim edits are excluded**;
browsing never saves or reloads user buffers and never updates the Git index.

Use `j`/`k` in the file panel and `<CR>` or `o` to show a file. In any plugin
pane, `]f`/`[f` select the next/previous file, `<Tab>`/`<S-Tab>` cycle panes,
`r` refreshes and `q` closes. Diff panes retain Vim's `]c`/`[c` hunk navigation.
Mappings are buffer-local. Refresh is explicit; it retains the original
repository and the selected section/path when available.

Selecting a file keeps focus in the panel. Close returns to the originating
window when it still exists. Manually closing a plugin pane or tab cleans up the
remaining plugin resources; user-added windows and modified user buffers survive.
Narrow panes can clip notices and long source/path labels; use Vim's window
resizing commands to widen the focused pane.

Added/deleted files have an empty absent side. Renames show both names;
mode-only changes remain listed. Binary files, symlinks, submodules and index
conflicts show an explanation instead of a text comparison. Git binary markers
and `-diff` attributes are honored, including for files without NUL bytes.
Git/read failures show `[diffview]` errors and retain the previous usable
comparison. Empty
repositories and clean worktrees show `No changes`. Paths through symlinked
directories are unsupported, and are checked again at selection time.

Compatibility: `:call ToggleDiffView()` opens local mode or closes any active
view. `:DiffBranch branch` and `:call DiffBranch('branch')` now compare
**branch → HEAD committed trees**; the old ref-to-working-tree behavior has
changed. Use `:DiffviewOpen` for local changes. These commands intentionally
differ from Diffview.nvim/CodeDiff: their single-revision commands commonly
compare with the working tree; here parent-to-commit uses `DiffviewCommit rev`
and two-tree comparisons use `DiffviewOpen A B`.

Git queries run synchronously, so large inputs can block Vim. One headless probe
on the verified environment, with 1,001 modified files and a selected 1,000,008
byte file, took about 0.21 s to open and 0.19 s to refresh. This is a single local
measurement, not a bound on other repositories or file sizes. Real-terminal
layout/focus validation and Windows support are not claimed. Local index/disk
snapshots are read at selection time, without atomic consistency against
concurrent Git/disk changes. No staging, restore, history browsing, automatic
refresh or three-way merge is provided.

See `:help diffview` (generate help tags with your package manager). Developer
smoke checks: `python3 dev/check.py`; independent acceptance tests are maintained
separately under `tests/`.

AGPL-3.0-or-later; see [LICENSE](LICENSE). Original copyright belongs to
zeminzhou. Navigation and layout take inspiration from
[diffview.nvim](https://github.com/sindrets/diffview.nvim); implementation uses
Vim's own APIs.
