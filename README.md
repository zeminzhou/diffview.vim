# diffview.vim

A native Vim9, read-only Git diff browser. Modified 2026-10-22.

Browse local changes, two Git trees, or the changes introduced by a commit.

Requires Vim 9.1 with `+vim9script`, `+diff`, `+windows`, `+job` and `+timers`,
and Git on `PATH`. Verified on macOS with Vim **9.1.1950** and Git **2.54.0**;
an earlier minimum patch level has not been verified. Neovim and older Vim are
unsupported. Install [preservim/nerdtree](https://github.com/preservim/nerdtree)
(formerly scrooloose/nerdtree) on the runtimepath. Missing or incompatible
NERDTree reports an error before replacing a usable view; nothing is downloaded
automatically.

Install with your Vim package manager, for example vim-plug:

```vim
Plug 'preservim/nerdtree'
Plug 'zeminzhou/diffview.vim'
```

Run a command anywhere inside a non-bare Git worktree. A dedicated tab contains
a NERDTree, left snapshot and right snapshot:

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

The tree contains changed paths and their parents, grouped by the sections
above (Trees or Commit in historical mode). All directories start expanded.
Native NERDTree flags show each file's Git status and aggregate descendant
statuses on directories. Deleted/historical paths remain selectable without
creating files. Renames show the previous path beside the new name; a file and
a directory with the same name remain separate nodes. Control characters and
literal backslashes are escaped for display, with selection using raw node
identity.

Files with both staged and unstaged edits have separate nodes. Ignored files are
excluded. Status lines identify the selected section, sources and paths. All
three buffers are read-only scratch buffers. **Unsaved Vim edits are excluded**;
browsing never saves or reloads user buffers and never updates the Git index.

Use `j`/`k` in the tree and `<CR>` or `o` to select a file or toggle a directory.
`p` selects the parent, `O` expands recursively, `X` collapses descendant
directories, and `x` closes the selected directory (or a file's parent).
In any plugin pane, `]f`/`[f` select the next/previous file,
`<Tab>`/`<S-Tab>` cycle panes,
`r` refreshes and `q` closes. Diff panes retain Vim's `]c`/`[c` hunk navigation.
Mappings are buffer-local. Refresh is explicit; it retains the original
repository, selected section/path and surviving directory expansion state.
File navigation reveals collapsed ancestors. NERDTree's filesystem operations,
normal file opening, bookmarks and root/cwd-changing mappings are not installed
in this comparison tree. Ordinary NERDTree instances keep their own behavior.

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

Git queries run synchronously, so large inputs can block Vim. Other
versions/platforms and unusually large workloads remain unverified. Local
index/disk
snapshots are read at selection time, without atomic consistency against
concurrent Git/disk changes. No staging, restore, history browsing, automatic
refresh or three-way merge is provided.

See `:help diffview` (generate help tags with your package manager). Developer
smoke checks require a real external NERDTree checkout:

```sh
git clone https://github.com/preservim/nerdtree.git /tmp/nerdtree
git -C /tmp/nerdtree checkout 690d061b591525890f1471c6675bcb5bdc8cdff9
NERDTREE_RUNTIME=/tmp/nerdtree python3 dev/check.py
```

The adapter uses NERDTree's native nodes, renderer and FlagSet, with
instance-local virtual paths and row lookup. The verified upstream API is
NERDTree `690d061b591525890f1471c6675bcb5bdc8cdff9`; other revisions are not
verified. No NERDTree prototypes, options, global mappings or listeners are
changed. [nerdtree-git-plugin](https://github.com/Xuyuanp/nerdtree-git-plugin)
provides a reference for status flags and may coexist, but is not required.
Comparison flags come from Diffview's existing Git model, including history and
staged/unstaged distinctions; tree navigation starts no extra Git jobs.
Independent acceptance tests and optional git-plugin setup are under `tests/`.

AGPL-3.0-or-later; see [LICENSE](LICENSE). Original copyright belongs to
zeminzhou. Navigation and layout take inspiration from
[diffview.nvim](https://github.com/sindrets/diffview.nvim); implementation uses
Vim's own APIs and NERDTree. NERDTree and nerdtree-git-plugin remain separate
installations under their respective licenses.
