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
| fzf (optional) | Core `junegunn/fzf` integration and PATH binary, for commit/branch search |

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
| `:DiffviewCommit` | Search HEAD history with fzf, then first parent → selected commit |
| `:DiffviewCommit {revision}` | First parent → specified commit; no fzf required |
| `:DiffviewBranch [branch]` | Target branch → captured committed HEAD; search local/remote refs with fzf when omitted |
| `:DiffviewRefresh` | Re-read the original repository and comparison request |
| `:DiffviewFilter [paths...]` | Project changed entries onto literal path prefixes; no arguments clears |
| `:DiffviewGotoFile` / `gf` | Open the current side's real worktree file in a new ordinary tab |
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

Before an optional `--` path separator, `DiffviewOpen` accepts **zero or two revisions**. A single revision is not an
implicit comparison with the working tree. Each argument must resolve to one
tree; revision exclusions such as `^main` are rejected. Parent expressions such
as `HEAD^` are valid when the parent exists.

### Changes introduced by a commit

```vim
:DiffviewCommit
:DiffviewCommit HEAD
:DiffviewCommit HEAD~1
```

With no argument, search all commits reachable from the current repository's
`HEAD`, including merged history. Rows show a short commit ID, date, author and
subject. Type to search, press Enter to select one commit, or Esc / Ctrl-C to
cancel. Selecting opens the usual **first parent → commit** comparison; a merge
commit uses its first parent and a root commit uses `EMPTY` on the left. A
missing parent in shallow or incomplete history produces an error.

Commit search optionally requires the core
[junegunn/fzf](https://github.com/junegunn/fzf) Vim integration and an `fzf` binary
on `PATH`; the separate `fzf.vim` plugin is not required. For vim-plug, add
`Plug 'junegunn/fzf'` alongside the existing plugins and install the binary with
your package manager. For native packages, install the core checkout under your
Vim package directory and install the binary separately. Diffview never downloads
dependencies. Search is verified with core fzf `b412a45` and binary **0.67.0**;
other versions remain unverified. The picker uses core fzf's normal layout
preferences.

An explicit revision bypasses fzf. Use `:DiffviewCommit HEAD` for the former
no-argument behavior, or `:DiffviewCommit HEAD~1` to inspect an older commit
directly. Exactly zero or one revision is accepted before an optional `--`.

A picked commit stays bound to its original repository and full object ID.
Refresh reuses that immutable ID and does not reopen the picker, even if cwd or
refs change. Explicit named revisions retain their existing behavior: refresh
resolves the original name again. Source labels show the requested revision or
picked object ID and resolved short IDs. Cancellation, no match and errors retain
the old usable comparison and unsaved buffers. Controls in metadata are escaped
for display and never used as commands.

History loading runs synchronously before fzf appears, so large histories can
pause Vim. Unique commits on other branches, reflogs and file-specific history
are outside this search.

### Compare or search branches

```vim
:DiffviewBranch main
:DiffviewBranch origin/main -- src tests
:DiffviewBranch refs/remotes/origin/main
:DiffviewBranch
:DiffviewBranch -- src
```

An explicit branch opens directly without fzf. With no branch argument, search
locally available local and remote-tracking refs using the same optional core
fzf integration. Rows distinguish LOCAL and REMOTE and show a short object ID.
Type a branch name, Enter to select, or Esc / Ctrl-C to cancel. Symbolic aliases
such as `origin/HEAD` are excluded. No remote is fetched or contacted.

The left side is the target branch and the right side the invoking checkout's
committed HEAD. Both tips and their names are captured when invoked, so Refresh
keeps that exact comparison even if refs, checkout or cwd change. Invoke
`DiffviewBranch` again to compare newer tips. Detached HEAD is supported;
unborn HEAD reports an error. This is a direct tree comparison, with no merge
base, staged changes, disk edits or unsaved buffer content.

An exact local short name wins over a remote-tracking name. For example, a
local branch literally named `origin/main` wins that spelling; use
`refs/remotes/origin/main` to disambiguate. Full refs under `refs/heads/` and
`refs/remotes/` are accepted. Tags and revision expressions are rejected; use
`DiffviewOpen target HEAD` for general named revisions and dynamic Refresh.
The optional `--` prefixes, syntax, statistics, gf and failure/data protections
are shared with the other comparison commands.

### Syntax, filtering and worktree navigation

When Vim syntax is enabled, each content pane uses its logical filename and
snapshot content for native language detection, including historical names and
different extensions on each side of a rename. Its filetype stays `diffview`.
Detection runs in an isolated Vim with only built-in runtime resources; it does
not open a similarly named disk file or run your language FileType, modeline or
indent hooks. The existing `FileType diffview` creation event is retained.
Unknown, empty and nontext sides are plain. Syntax errors report a notice and
fall back to plain text without losing the comparison. `:syntax off` is respected.

Restrict any comparison with literal prefixes, or change the current projection:

```vim
:DiffviewOpen -- src tests
:DiffviewOpen main feature/login -- src
:DiffviewCommit -- src
:DiffviewCommit HEAD~1 -- path\ with\ spaces
:DiffviewFilter ./src/core tests
:DiffviewFilter
```

Prefixes are relative to the compared trees, match exact paths or slash-delimited
descendants and are ORed. Renames match either old or new path. `.` means all;
absolute paths and `..` components are rejected. Wildcards and Git pathspec
punctuation are literal. Changing the filter keeps the full comparison and any
still-selected snapshots, without recomputing Git diff/history or resolving refs.
Refresh remembers the filter. A new open resets it. `No matching changes` means
the full comparison has changes outside the filter; `No changes` means it is clean.
Commit search still searches all HEAD-reachable commits; its prefixes filter the
selected commit, and stay bound to the original repository and full selected ID.

Press `gf` on a file node or content pane, or run `:DiffviewGotoFile`. The panel
uses the destination path and line 1; the left pane uses the old path and the
right pane the new path, with a clamped numeric line hint. This opens the existing
current worktree file, reusing an already loaded dirty buffer without saving or
reloading it. The new ordinary tab stays available after closing Diffview.
Normal real-file editor hooks apply. Commit roots and proven `rev:directory`
prefixes can map to worktree paths; arbitrary tree-only expressions cannot.
Missing files, symlinks and nonregular targets report an error and create nothing.
This is numeric positioning, not semantic historical line mapping.

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

File leaves show `+N -M` from the same Git numstat query, or `+? -?` for unknown
counts (including untracked/nontext entries). Zero/zero mode changes and pure
renames stay visible. The summary counts visible/full comparison entries and
sums known visible line changes; duplicate staged/unstaged entries count twice.
An active filter is escaped in a separate header. The first two source/notice
headers and the raw identity behind each rendered node remain unchanged.

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
| Any Diffview pane | `gf` | Open the real worktree file in a new normal tab |
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

`:call ToggleDiffView()` still opens local mode or closes an active view.
The old `:DiffBranch` command and `g:DiffBranch()` function have been removed;
migrate to `:DiffviewBranch`. Use `:DiffviewOpen target HEAD` when named refs
should be resolved again on Refresh. The old flat file list has been replaced
by the required NERDTree sidebar.

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

**A ref changed but the comparison did not.** Run `:DiffviewRefresh`. Explicitly
named historical endpoints are resolved when opening and again on refresh,
not on every cursor movement. A commit picked with fzf keeps its full object ID;
run `DiffviewCommit` again to choose another commit.

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
git clone https://github.com/junegunn/fzf.git "$deps/fzf"
git -C "$deps/fzf" checkout b412a450538e5f4a1d7057732e75d945dafa18a6
# Install the fzf binary separately with your package manager (verified: 0.67.0).

# Developer smoke checks: Python 3 standard library, real Vim and Git.
NERDTREE_RUNTIME="$deps/nerdtree" python3 dev/check.py

# Add real fzf smoke and a separate injected-callback boundary probe.
NERDTREE_RUNTIME="$deps/nerdtree" FZF_RUNTIME="$deps/fzf" python3 dev/check.py

# Full acceptance suite, including real git-plugin coexistence.
NERDTREE_RUNTIME="$deps/nerdtree" \
NERDTREE_GIT_RUNTIME="$deps/nerdtree-git-plugin" \
FZF_RUNTIME="$deps/fzf" sh tests/run.sh
```

The suite retains the original 28 comparison/tree/safety scenarios. Picker
coverage checks commit sources, original-repository binding, cancellation and
malformed output separately from real terminal interaction. It compares complete
fixture contents, including Git indexes and object databases. Omitting
`NERDTREE_GIT_RUNTIME` explicitly reports the coexistence case as `NOT RUN`;
provide all three dependencies for a complete run. The runner supports `VIM` and
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
