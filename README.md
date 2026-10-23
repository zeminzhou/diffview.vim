# diffview.vim

A native Vim9 Git diff browser with a NERDTree sidebar and two read-only
comparison panes. Review local changes, compare two Git trees, or inspect the
changes introduced by a commit without leaving Vim.

The sidebar shows changed files in expandable directories, with Git status
markers on files and their parents. The content panes use Vim's built-in diff
mode and identify the source on each side.

## Contents

- [Requirements](#requirements)
- [Installation](#installation)
- [Quick start](#quick-start)
- [Commands and comparisons](#commands-and-comparisons)
- [Reading the file tree](#reading-the-file-tree)
- [Keyboard shortcuts](#keyboard-shortcuts)
- [Refresh, snapshots and closing](#refresh-snapshots-and-closing)
- [Supported files and edge cases](#supported-files-and-edge-cases)
- [Migrating from the older version](#migrating-from-the-older-version)
- [Troubleshooting](#troubleshooting)
- [Development and testing](#development-and-testing)
- [Limitations](#limitations)
- [License and acknowledgements](#license-and-acknowledgements)

## Requirements

| Dependency | Requirement |
| --- | --- |
| Vim | Vim 9.1 with `+vim9script`, `+diff`, `+windows`, `+job` and `+timers` |
| Git | Available as `git` on Vim's `PATH` |
| NERDTree | [preservim/nerdtree](https://github.com/preservim/nerdtree), formerly `scrooloose/nerdtree`, installed and loaded |

Verified with Vim **9.1.1950**, Git **2.54.0**, and NERDTree revision
[`690d061`](https://github.com/preservim/nerdtree/commit/690d061b591525890f1471c6675bcb5bdc8cdff9)
on macOS arm64. An earlier minimum Vim patch level and other NERDTree revisions
have not been verified. Neovim and older Vim are unsupported.

[nerdtree-git-plugin](https://github.com/Xuyuanp/nerdtree-git-plugin) is optional.
Diffview supplies its own comparison markers and does not need that plugin to
show changes. Coexistence has been tested with its `e1fe727` revision.

## Installation

### vim-plug

Add these entries inside your existing `plug#begin()` / `plug#end()` block:

```vim
Plug 'preservim/nerdtree'
Plug 'zeminzhou/diffview.vim'
```

If NERDTree is already installed, keep one declaration. The entry above follows
`main`. If you previously pinned Diffview to a development branch, remove that
`branch` option before updating.

Save your vimrc and restart Vim, then run `:PlugInstall` (or
`:PlugUpdate diffview.vim` for an existing installation). Restart Vim after the
installation or update to load the new code. No plugin setup function or
configuration dictionary is required. Enable syntax highlighting with
`:syntax enable` if it is not already enabled in your configuration.

### Native Vim packages

For a new installation using Vim's standard package directory:

```sh
mkdir -p ~/.vim/pack/plugins/start
git clone https://github.com/preservim/nerdtree.git \
  ~/.vim/pack/plugins/start/nerdtree
git clone https://github.com/zeminzhou/diffview.vim.git \
  ~/.vim/pack/plugins/start/diffview.vim
```

Restart Vim after installation. These commands assume the destination
directories do not already exist; use your existing installation if they do.
Other plugin managers should load both plugins from their default branches. If you lazy-load plugins, make NERDTree available before a Diffview
command runs.

### Help and optional mappings

Open the reference with `:help diffview`. If your package manager has not
generated help tags, run `:helptags /path/to/diffview.vim/doc` with the actual
installation path.

Optional shortcuts for your vimrc:

```vim
nnoremap <silent> <leader>dv :DiffviewOpen<CR>
nnoremap <silent> <leader>dc :DiffviewClose<CR>
```

## Quick start

1. Start Vim inside a Git working tree, or use `:cd /path/to/repository`.
   Subdirectories of the repository work too.
2. Run `:DiffviewOpen` to review local changes.
3. In the tree, use `j` / `k` to move and Enter or `o` to select a file.
   On a directory, Enter or `o` expands or collapses it.
4. Use Tab to enter a content pane, then `]c` / `[c` to jump between diff hunks.
5. Press `r` to refresh or `q` to close the review and return to your original
   window.

Opening a comparison creates a dedicated tab with three panes: the file tree,
the left snapshot, and the right snapshot. The first changed file is selected,
and focus starts in the tree. Moving the tree cursor does not automatically
change the displayed comparison; select a file explicitly.

**Unsaved Vim edits are excluded.** Local comparisons read the index and files
on disk. Save a file yourself if you want its current buffer contents included.
Diffview does not save, reload or discard your user buffers.

## Commands and comparisons

| Command | Left → right |
| --- | --- |
| `:DiffviewOpen` | Local changes in separate Staged, Unstaged and Untracked sections |
| `:DiffviewOpen {left} {right}` | The specified left tree → right tree |
| `:DiffviewCommit [revision]` | First parent → commit; defaults to `HEAD` |
| `:DiffviewRefresh` | Re-read the original repository and comparison request |
| `:DiffviewClose` | Close the active view and clean up its resources |

### Local changes

```vim
:DiffviewOpen
```

| Section | Left source | Right source |
| --- | --- | --- |
| Staged | `HEAD`, or `EMPTY` before the first commit | `INDEX` |
| Unstaged | `INDEX` | `WORKTREE` on disk |
| Untracked | `EMPTY` | `WORKTREE` on disk |

A file with both staged and unstaged changes appears twice, once in each
section. For example, after staging a file and editing it again, its Staged
node compares the committed version with the index; its Unstaged node compares
the index with the current disk file. The two entries are independent.

Ignored untracked files are excluded. A clean working tree shows `No changes`.
Repositories without a first commit are supported: staged additions use an
empty left side.

### Two branches, tags or trees

Supply both endpoints in left-to-right order, using refs that exist in your
repository:

```vim
:DiffviewOpen main feature/login
:DiffviewOpen HEAD~1 HEAD
```

This compares the two endpoint trees directly. Working-tree edits, staged
changes and unsaved buffers do not enter this comparison. There is no implicit
merge-base calculation and no `..` / `...` range syntax.

Tree object IDs and `revision:directory` expressions are also accepted:

```vim
:DiffviewOpen main:src feature/login:src
:DiffviewOpen main:src\ dir feature/login:src\ dir
```

Escape whitespace with Vim's command-line backslash syntax. Subtree paths in
the sidebar are relative to the selected trees, so a file can be compared even
when neither historical path exists in the working directory.

`DiffviewOpen` accepts **zero or two arguments**. A single revision is not an
implicit comparison with the working tree. Each argument must resolve to one
tree; revision exclusions such as `^main` are rejected. Parent expressions such
as `HEAD^` are valid when the parent exists.

### Changes introduced by a commit

```vim
:DiffviewCommit
:DiffviewCommit HEAD~1
```

With no argument, inspect `HEAD`. With an argument, inspect that commit's
changes relative to its **first parent**. A merge commit uses its first parent;
a root commit uses `EMPTY` on the left. A missing parent object in shallow or
incomplete history produces an error rather than a false root comparison.

`DiffviewCommit` accepts zero or one argument resolving to a commit. The source
labels show the requested revisions and resolved short object IDs. Branches
and other refs remain fixed until an explicit refresh resolves them again.

## Reading the file tree

The sidebar is a separate NERDTree instance containing **changed paths and their
parent directories**. It does not list every file in the repository or add
Diffview markers to your ordinary NERDTree. Existing NERDTree windows keep their
own roots, options and mappings.

Local changes are grouped under Staged, Unstaged and Untracked; historical
comparisons use Trees or Commit. All directories start expanded. File markers
come from the same Git comparison that supplies the content panes:

| Marker | Meaning |
| --- | --- |
| `M` | Modified, including a file-mode change |
| `A` | Added |
| `D` | Deleted |
| `R` | Renamed |
| `T` | File type changed |
| `?` | Untracked |
| `U` | Unmerged index entry; conflict resolution is unsupported |

Directory markers aggregate the statuses of changed descendants. A directory
can therefore carry several markers. A rename shows the new name with its
previous path; each content pane identifies its own path. Deleted files and
historical paths remain selectable without creating placeholder files. A
file-to-directory replacement can show both the deleted file and a directory
with the same name.

Spaces, Unicode and control characters in filenames are handled as raw paths.
Control characters and literal backslashes are escaped in tree labels; selecting
a node uses its bound comparison entry rather than parsing the displayed text.

## Keyboard shortcuts

All plugin mappings are buffer-local and use Normal mode.

| Where | Key | Action |
| --- | --- | --- |
| Tree | `j` / `k` | Move the cursor without changing the displayed file |
| Tree | Enter / `o` | Select a file, or toggle a directory |
| Tree | `p` | Move to the parent node |
| Tree | `x` | Close the directory, or the selected file's parent |
| Tree | `O` | Expand directories recursively from the current node |
| Tree | `X` | Collapse descendant directories |
| Any Diffview pane | `]f` / `[f` | Select the next / previous file, wrapping at the ends |
| Any Diffview pane | Tab / Shift-Tab | Cycle through the three panes |
| Any Diffview pane | `r` | Refresh the original comparison |
| Any Diffview pane | `q` | Close Diffview |
| Content panes | `]c` / `[c` | Use Vim's native next / previous diff hunk navigation |

Selecting a file keeps focus in the tree. File navigation with `]f` / `[f`
reveals the selected node by expanding its ancestors when necessary.

NERDTree's normal file-opening, filesystem mutation, bookmark and root/cwd
changing mappings are not installed in this comparison tree. Use your ordinary
NERDTree or Vim windows for editing files.

## Refresh, snapshots and closing

- Refresh is explicit: press `r` or run `:DiffviewRefresh` after changing files,
  staging work or updating refs. There is no automatic refresh.
- Refresh uses the original repository even if Vim's current directory changes.
  It retains the selected section/path when available and the expansion state
  of surviving directories. When an empty comparison gains changes, its first
  file becomes selected.
- Local index/disk contents are read when you select a file. Historical object
  sources remain fixed until refresh. Reads are not an atomic snapshot of
  concurrent Git or filesystem changes.
- All three displayed buffers are read-only scratch buffers. Browsing does not
  stage, restore, check out or write files, the index or Git objects.
- There is one active Diffview view. A valid new open replaces it; an invalid
  request or Git/read/render failure reports a `[diffview]` error and preserves
  the previous usable comparison.
- `q` or `:DiffviewClose` cleans up plugin resources and returns to the original
  window when it still exists. Manually closing a plugin pane or tab also
  triggers cleanup. User-added windows and modified user buffers survive.

## Supported files and edge cases

| Case | Behavior |
| --- | --- |
| Added or deleted file | The absent side is empty, labeled `EMPTY` or `EMPTY (absent)` |
| Rename | Both paths remain visible; left reads the old path and right reads the new path |
| Empty file | Valid content; distinguished from a missing file |
| Mode-only change | Remains listed, even when both sides have identical text |
| Missing final newline | Preserved in the snapshot buffer's `endofline` setting |
| Binary file | An explanation replaces the text diff; Git binary markers, `-diff` attributes and NUL bytes are honored |
| Symlink or symlinked parent below the repository root | Explicitly unsupported; links are not followed |
| Submodule or unmerged index entry | An explanation is shown; no submodule browsing or conflict resolution |
| Clean or empty repository | `No changes`; the view can still be refreshed or closed |
| Invalid revision, non-Git directory or bare repository | An error is reported without leaving a partial view |
| File disappears before selection | A read error preserves the previous comparison; it is not treated as an empty file |

## Migrating from the older version

The old entry points remain available:

| Entry | Current behavior |
| --- | --- |
| `:call ToggleDiffView()` | Open local mode, or close any active Diffview view |
| `:DiffBranch main` | Compare the committed `main` tree → `HEAD` tree |
| `:call DiffBranch('main')` | The same branch → `HEAD` comparison |

`DiffBranch` previously compared a ref with the working directory. It now
compares committed trees; use `:DiffviewOpen` for local changes. The old flat
file list has been replaced by the required NERDTree sidebar.

Command syntax is not interchangeable with Diffview.nvim or CodeDiff. In this
plugin, use `DiffviewOpen A B` for two trees and `DiffviewCommit rev` for a
commit's first-parent changes. No single-revision working-tree shorthand is
provided.

## Troubleshooting

**Commands are missing, or the old interface still opens.** Update the plugin
from `main` and restart Vim. If your plugin manager is pinned to a development
branch, remove that pin before updating. `:scriptnames` shows loaded scripts, and
`:verbose command DiffviewOpen` identifies the command's source. Avoid keeping
two installed copies of Diffview on `runtimepath`.

**Diffview asks for a compatible NERDTree.** Install and load `preservim/nerdtree`
before opening Diffview. Check `:echo exists(':NERDTree')`; a loaded installation
normally returns `2`. For custom lazy loading, load the dependency first. The
adapter uses NERDTree node/UI APIs; the verified revision is linked under
[Requirements](#requirements). Nothing is downloaded automatically.

**The displayed content does not include my current edits.** Unsaved buffers
are excluded. Check the selected Staged/Unstaged section and the source labels,
save the file yourself if desired, then refresh. An unchanged file will not
appear in the changed-path tree.

**A ref changed but the comparison did not.** Run `:DiffviewRefresh`. Historical
endpoints are resolved when opening and again on refresh, not on every cursor
movement.

**Long labels or the unsaved-edits notice are clipped.** Widen the focused pane
with `:vertical resize 60` or Vim's window-resizing keys. Pane widths are fixed
initially; long paths can exceed the available terminal width.

**Opening or refreshing takes time.** Git commands run synchronously. Large
repositories, files, or slow storage can block Vim while the comparison is
prepared. Tree-only expansion and collapse do not start per-node Git jobs.

For command details, see `:help diffview`. For errors, inspect `:messages`,
`:version`, `:echo executable('git')`, and the installed dependency revision.

## Development and testing

Tests use external, pinned upstream checkouts; they do not download or vendor
dependencies. From the repository root:

```sh
deps=$(mktemp -d)
git clone https://github.com/preservim/nerdtree.git "$deps/nerdtree"
git -C "$deps/nerdtree" checkout 690d061b591525890f1471c6675bcb5bdc8cdff9
git clone https://github.com/Xuyuanp/nerdtree-git-plugin.git "$deps/nerdtree-git-plugin"
git -C "$deps/nerdtree-git-plugin" checkout e1fe727127a813095854a5b063c15e955a77eafb

# Developer smoke checks: Python 3 standard library, real Vim and Git.
NERDTREE_RUNTIME="$deps/nerdtree" python3 dev/check.py

# Full acceptance suite, including real git-plugin coexistence.
NERDTREE_RUNTIME="$deps/nerdtree" \
NERDTREE_GIT_RUNTIME="$deps/nerdtree-git-plugin" sh tests/run.sh
```

The full suite contains **28 scenarios** covering comparison sources, tree
identity/navigation, special paths, dependency and render failures, user-tree
isolation, lifecycle and binary/index regressions. It compares complete fixture
contents, including Git indexes and object databases. Omitting
`NERDTREE_GIT_RUNTIME` explicitly reports the coexistence case as `NOT RUN`;
provide both dependencies for a complete run. The runner supports `VIM` and
`DIFFVIEW_TEST_RUNTIME` overrides; see [tests/README.md](tests/README.md).

Interactive acceptance also covers real terminal keys, pane focus, hunk
navigation, dirty buffers, existing mirrored NERDTrees, register preservation,
resizing and closing. See the [terminal checklist](tests/manual.md). Headless
success alone does not establish terminal usability.

## Limitations

- Native Vim 9.1 only; Neovim, older Vim, Windows and other unverified platforms
  are outside the tested support scope.
- NERDTree integration is verified against the revision above. Other revisions
  and arbitrary third-party NERDTree extensions need their own checks.
- Git runs synchronously, and concurrent repository reads are not atomic.
- No staging, restore, checkout, editable diff buffers, file-history browser,
  automatic refresh, path filtering or three-way merge UI is provided.
- Binary, symlink, submodule and conflict entries are explained rather than
  rendered as editable or specialized comparisons.
- Narrow terminals can clip labels; native resizing is supported. Larger
  workloads and other terminal geometries have no performance guarantee.

## License and acknowledgements

[AGPL-3.0-or-later](LICENSE). Original copyright belongs to zeminzhou.

Navigation and information organization take inspiration from
[diffview.nvim](https://github.com/sindrets/diffview.nvim). The implementation
uses native Vim9, Git and [NERDTree](https://github.com/preservim/nerdtree).
[nerdtree-git-plugin](https://github.com/Xuyuanp/nerdtree-git-plugin) is a reference
for status markers. NERDTree and the optional git-status plugin remain separate
installations under their respective licenses.
