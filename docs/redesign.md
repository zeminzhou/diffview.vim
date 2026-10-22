# Diffview.vim first-version contract

Product contract for the native Vim9 diff browser.

The NERDTree integration updates the sidebar, dependency and navigation rules
in this original contract. See [NERDTree diff navigation](nerdtree.md) for current
requirements; the Git comparison and data-protection rules below still apply.

## Scope and existing behavior

Build a native Vim9, read-only diff browser using a file panel and two diff
windows in a dedicated tab. Reference: [diffview.nvim](https://github.com/sindrets/diffview.nvim)
for file navigation and information organization; no Lua/Neovim code is required.
Keep the existing AGPL-3.0-or-later license and zeminzhou copyright notices.

The old `ToggleDiffView()` has separate modified/staged lists but opens both
through one content path. `DiffBranch` currently lists ref-to-working-tree
changes, rather than two committed trees. Neither behavior is the new contract.
Affected surfaces: `plugin/main.vim`, `autoload/diffview/*.vim`, README, new Vim
help, and new independent fixture/tests. No other runtime dependency is added.
Git invocation uses Vim's `job_start()` with an argv List, captured output and
synchronous waiting; `+job` is therefore required, without asynchronous view
callbacks. Capture must preserve NUL bytes in path records. Disable Git's optional
index updates and `diff.autoRefreshIndex` for plugin queries; use literal pathspec handling for raw filenames
passed to pathspec-taking commands. A bare `--` does not disable Git patterns.
Manual-window cleanup may use a one-shot timer guarded by a view identity;
`+timers` is required. A pending cleanup must not affect a replacement view.

## Commands and content sources

| Command | Files and left side | Right side |
| --- | --- | --- |
| `:DiffviewOpen` | Three sections below | Three sections below |
| `:DiffviewOpen {left} {right}` | Direct comparison of the two specified Git trees; left tree | Right tree |
| `:DiffviewCommit [revision]` | Changes against first parent of the commit (default `HEAD`) | The commit |
| `:DiffviewRefresh` | Re-read the active view's repository and arguments | Preserve selected section/path when possible |
| `:DiffviewClose` | Close the active plugin view and clean up its resources | Return to the originating window when available |

`DiffviewOpen` accepts exactly zero or two arguments; other arities are errors.
No `..`/`...` range syntax or options/path filters in v1. Revisions are separate
arguments, validated and resolved before use; a revision cannot be interpreted
as a Git option or shell/Ex command. A resolved revision must be one complete
unsigned object ID; reject Git exclusion syntax such as `^branch` in either
position while accepting normal parent expressions such as `HEAD^1`.
Branch comparison is tree-to-tree, with
no implicit merge-base and no local modifications mixed in. Accept any revision
resolving to a tree in tree mode; commit mode must resolve to a commit.

For `DiffviewCommit`, use the first parent even for merge commits, not a
combined diff. Root commits compare an empty tree against the commit. Labels
identify both revision names and resolved short object IDs, or `EMPTY` for a
missing parent. Branch refs remain fixed for a displayed comparison; explicit
refresh re-resolves the original arguments. A commit view likewise refreshes
the original revision argument.

Local mode has separate entries, including two entries for the same path when
it has both staged and unstaged changes:

| Section | Left label/source | Right label/source |
| --- | --- | --- |
| Staged | `HEAD` committed blob, or `EMPTY` before first commit | `INDEX` stage-0 blob |
| Unstaged | `INDEX` stage-0 blob | `WORKTREE (disk)` bytes |
| Untracked | `EMPTY` | `WORKTREE (disk)` bytes; nonignored untracked files only |

Resolve the repository from Vim's current working directory, allowing repository
subdirectories, spaces and Unicode in the root. Do not change the user's cwd.
When refreshing a view, keep its original repository even if cwd has changed.
No automatic refresh in v1: `r` or `DiffviewRefresh` explicitly updates lists and
selected contents. Selection reads current index/disk contents; this is a
read-time snapshot, not an atomic snapshot of a concurrently changing repo.
With one global active view, Refresh/Close commands also work from another tab.
Cross-tab refresh must update actual target-window labels together with content,
including absent-side labels and transitions to/from an empty result.

All comparison buffers are plugin-owned read-only scratch buffers. The working
tree source is the on-disk file, never a preexisting Vim buffer. A visible label
explains that unsaved edits are excluded. Do not save, reload, overwrite, wipe,
or discard any user buffer, even when it has the selected path. Index and disk
must remain byte-for-byte unchanged by browsing. Do not run Git commands that
modify the index/object database/worktree to implement an empty tree.

## Layout and navigation

One active plugin view per Vim instance: one file-list window on the left and
two content windows beside it. Automatically select the first file when one
exists and initially focus the list. Local section headings are not files.
Each row shows status and path; renamed rows show old and new names. Escape
control characters in display names, but retain raw paths internally and parse
Git's NUL-delimited records without splitting on whitespace/newlines.

| Context | Key | Behavior |
| --- | --- | --- |
| File panel | `j` / `k` | Move cursor using normal Vim navigation |
| File panel | `<CR>` / `o` | Show selected file |
| Any plugin pane | `]f` / `[f` | Select and show next/previous file, wrapping |
| Any plugin pane | `<Tab>` / `<S-Tab>` | Cycle panes forward/backward |
| Any plugin pane | `r` | Refresh lists and selected contents |
| Any plugin pane | `q` | Close the plugin view |
| Diff panes | `]c` / `[c` | Standard Vim next/previous diff hunk |

Mappings are buffer-local. Labels clearly identify source, path and selected
local section; left/right direction must never depend on window creation order.
Repeated open validates the new request before replacing the old view, without
accumulating tabs/buffers/autocmds. Errors preserve the previous usable view.
Close is safe to repeat. Manual closing of a plugin pane/tab must not leave
callbacks targeting deleted windows or alter unrelated windows' diff/options.
If users put their own buffers/windows into the plugin tab, cleanup preserves
their contents and does not force-close modified buffers. A fully restored
custom layout is not required.
Before touching a tracked window's options, cleanup must verify it still shows
a plugin-owned buffer; a user buffer replacing that pane owns its window options.

## Edge behavior and errors

- Added/deleted files: missing side is an empty read-only buffer, labeled
  `EMPTY`/absent; present side shows actual content. Empty existing files are
  valid files, not read errors. Preserve missing-final-newline information
  where Vim can represent it; no writes or content conversion to disk.
- Renames: detect with Git's standard rename detection, use old path on left
  and new path on right. Rename-only and mode-only changes remain visible even
  if text content is identical. Unstaged filesystem moves may appear as a
  deletion plus an untracked addition, consistent with Git.
- Binary files: list them and show an explicit binary/content-unavailable
  message rather than fabricated text diffs. Respect Git's binary classification
  (including `.gitattributes -diff`) as well as NUL content. No external binary viewer.
- Symlinks, submodules and unmerged index entries: list with an explicit
  unsupported/conflict explanation; do not dereference links or present a
  fake two-way resolution. Three-way merge and submodule browsing are deferred.
  Validate path components below the repository root at read/selection time,
  including a parent directory replaced by a symlink after the list was built.
- No changes: retain a usable empty view with `No changes`; refresh/close work.
- Invalid revision, unsupported argument, Git failure, missing/non-Git cwd or
  bare repository: clear `[diffview]` error; no half-created layout, no false
  `No changes`, preserve prior usable view. A file disappearing during a read
  is an error, rather than silently treating it as an intended deletion.
- Synchronous Git is acceptable. No async framework, persistent cache, or
  performance options are required. Document measured large-input limitations.

## Compatibility and documentation

`g:ToggleDiffView()` (also callable as `ToggleDiffView()`) toggles local mode
through the new shared implementation; if any plugin view is open it closes it.
`:DiffBranch {branch}` and `g:DiffBranch(branch)` become wrappers for
`:DiffviewOpen {branch} HEAD`. Explicitly document this migration: old
ref-to-working-tree behavior changes to committed-tree comparison. Users use
`DiffviewOpen` for staged/unstaged local changes.

README and `doc/diffview.txt` must describe installation, Vim/Git requirements,
commands, direction and labels, keys, disk-versus-unsaved-buffer distinction,
refresh/close, old-entry migration, errors and limitations. Target Vim 9.1 with
`+vim9script`, `+diff`, `+windows`, `+job`, `+timers`; document actual verified patch/version and
any higher minimum required by used APIs. Do not claim an untested minimum
patch level. No Neovim/older Vim support. Preserve license/attribution and
identify modification date. Keep screenshots only if clearly labeled legacy.

Deferred: file history, three-way merges, Git mutations (stage/restore/checkout/
merge), tree folding, layout configuration, live editable diff panes, automatic
refresh, path filtering, async and Windows-specific support.

## Acceptance checklist

- A1: Tree comparisons verify left/right actual contents, ignore local dirt,
  include add/delete/rename/mode-only changes, and handle empty results.
- A2: Commit comparisons verify normal, root and merge/first-parent semantics;
  invalid revisions fail without corrupting the existing view.
- A3: Local fixture verifies staged-only, unstaged-only, both for one file,
  untracked and ignored files, clean and unborn repositories, and exact sources.
- A4: Special paths (space, Unicode, tab, newline, SOH, literal backslash,
  leading dash, `:(glob)**` and shell/Ex punctuation), nested cwd and repository
  paths are handled without injection or delimiter/pathspec confusion.
- A5: Binary, empty, unsupported entries and read/Git failures have honest
  output; no untracked symlink dereference.
- A6: Real commands and keys execute Vim9 paths; open/select/switch/refresh/
  close/reopen/manual close clean resources and preserve unrelated tab/splits.
- A7: Unsaved user buffers, index and disk bytes remain unchanged throughout;
  original modified state and content survive view lifecycle and errors. Include
  stale index stat metadata and dirty buffers inserted into the plugin layout;
  exercise `nohidden`/`autowriteall`. Test setup must not supply the product's
  optional-index-lock protection through inherited environment variables.
  A clean stale-stat file with unchanged content/mode must still show `No changes`;
  preserving index bytes alone is insufficient if raw Git output gains a false
  modified row. Preserve real mode-only, rename and content changes when filtering.
  This also applies to Git-forced binary files: a numstat `-/-` record alone
  does not prove that a same-mode raw `M` contains a real content change.
- A8: Reproducible temporary Git fixtures and headless Vim assertions return
  nonzero on failure; at least one real-terminal interaction/layout check or
  an explicit unverified statement. Modest large-file/list responsiveness probe.
- A9: README/help and legacy wrappers match behavior; AGPL/notices preserved.
- A10: Final frozen candidate SHA independently APPROVED by reviewer and PASS
  by tester. New code requires relevant rechecks against the new candidate.

## Reference plugin analysis (2026-10-22)

Upstream README/help review, requested by the user alongside implementation.
These are documented behaviors, not hands-on usability results. References are
experiential guidance; the Vim9 contract above remains the implementation target.

| Reference | Product role and documented behavior | Apply to this project |
| --- | --- | --- |
| [Diffview.nvim help](https://github.com/sindrets/diffview.nvim/blob/4516612fe98ff56ae0415a259ff6361a89419b0a/doc/diffview.txt) | Dedicated tab, file panel plus diff panes, unstaged/staged sections; flat/tree lists, file history and merge layouts. Index buffers can be edited and written to stage changes. | Primary layout reference: stable file panel, explicit comparison direction, next/previous file and native hunk navigation, owned view cleanup. Our buffers remain read-only. |
| [CodeDiff README](https://github.com/esmuellert/codediff.nvim/blob/09d9ebef2cc5a5c04db7a349cd6c61bdf84ecc8e/README.md) | Review workspace with left Explorer, side-by-side/inline diffs; default list view, Enter selection, initial Explorer focus, cursor movement does not automatically open files. Supports `]f`/`[f`, staged/unstaged groups, two-revision and explicit merge-base comparisons. Uses a downloaded native diff library. | Closest additional UX reference: initial panel focus, explicit Enter selection, stable focus on selection, separate file/hunk navigation. Use Vim's diff engine and textual statuses. |
| [Gitsigns README](https://github.com/lewis6991/gitsigns.nvim/blob/fd780920613e541cbdfac41bf711583ed49f9249/README.md) | Editing-oriented per-buffer signs, hunk preview/navigation, word diff, staged hunk actions and `diffthis` against index/revisions. | Preserve Vim's familiar `]c`/`[c` hunk workflow; keep it distinct from `]f`/`[f` file navigation. Inline previews, blame and sign-column integration are later opportunities. |
| [Neogit help](https://github.com/NeogitOrg/neogit/blob/832a2db084ac25c2801fd73a3fab58f3c82ed2ec/doc/neogit.txt) | Magit-style status interface, with separate untracked/unstaged/staged sections, inline hunks and Git actions. Integrates Diffview or CodeDiff for traditional comparison views. | Use section hierarchy to explain repository state before presenting a file diff. The same path in two sections represents two comparisons and must remain independently selectable. |
| [Fugitive help](https://github.com/tpope/vim-fugitive/blob/3b753cf8c6a4dcde6edee8827d464ba9b8c4a6f0/doc/fugitive.txt) | Vim/Neovim Git interface; `Gdiffsplit`, status navigation and revision/index objects such as `:path` and `rev:path`. Working-tree side is consistently right/bottom; index objects are writable. | Native Vim feasibility and source-identity reference: explicit HEAD/INDEX/disk labels, consistent left/right direction, familiar windows and mappings. |

### Design choices

1. File-first review: open in the panel, use j/k to browse rows and Enter/o to
   select, and retain panel focus on selection. Keep `]f`/`[f` for file changes,
   `]c`/`[c` for hunks, and Tab/Shift-Tab for panes as already specified.
2. Source identity is always visible: local section, path, left/right source
   and `WORKTREE (disk; unsaved edits excluded)`. Historical views show resolved
   object IDs. Labels belong outside file content, such as in statuslines, so
   source labels do not become synthetic diff lines.
3. Keep the panel useful during review: status plus escaped path, rename's old
   and new paths, visible current selection, and selection retained across
   refresh by section plus raw path. Use built-in text/highlight capabilities.
4. Document command differences from upstream. Diffview's one-revision open
   compares that revision to local changes; CodeDiff's one-revision repository
   command also compares with the working tree. This plugin deliberately uses
   `DiffviewCommit {rev}` for parent-to-commit, and `DiffviewOpen A B` for two
   trees. Familiar command names do not imply upstream argument compatibility.
5. Preserve a focused v1: the existing read-only three-scenario contract. Native
   Vim diff avoids CodeDiff's native-library installation path. Git mutations,
   live editing, watchers, inline diff engines, history, merge layouts, icons
   and plugin integration remain later work with separate acceptance criteria.

Upstream branch snapshots recorded above are source references, not versions
tested for compatibility. No external plugin code was copied. Terminal layout,
focus and navigation remain independent R02/T02 acceptance work on our candidate.
