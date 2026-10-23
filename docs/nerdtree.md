# NERDTree diff navigation

Diffview uses a dedicated, read-only NERDTree as its left pane and keeps the two
existing snapshot panes. This replaces the flat file panel in all comparison
modes. Install `preservim/nerdtree` (formerly `scrooloose/nerdtree`) alongside
Diffview. A missing dependency produces a clear install error before changing a
usable view. There is no second sidebar implementation or automatic download.

## Tree and selection

The tree contains changed paths and their parent directories, not the complete
working directory. Local roots are Staged, Unstaged and Untracked; history uses
Trees or Commit. Each section has an expandable directory hierarchy. File nodes
show Git status flags; parent directories indicate descendant changes. Empty
comparisons say No changes. Repository/mode/source direction and the disk-only
unsaved-buffer notice remain visible. All sections start expanded; selecting the
first entry gives the same content and focus as before.

A path in both Staged and Unstaged has two independently selectable nodes in its
respective sections. Deleted files and historical paths absent on disk remain
nodes; rename nodes identify old and new paths. Tree-ID and subtree comparisons
use comparison-relative paths and never infer worktree contents. File/directory
replacement at the same pathname must keep every diff entry reachable.

Use real NERDTree node classes, renderer and flag sets on a separate tree
instance. Build its nodes from the existing comparison model, with no filesystem
mirror or placeholder files. Leaf nodes carry their comparison entry as
`node.diffview_entry` (including section, raw path, oldpath and status); directory
nodes have no entry. The instance UI locates visible nodes through
`ui.getLineNum(node)` and `NERDTreeFileNode.GetSelected()` returns that exact node.
Keep raw paths and entry identities separately from escaped display text. Selection never reparses labels, prefixes or status flags.
This covers spaces, Unicode, tabs, newlines, control bytes and literal escape
sequences already supported by Diffview.

## Interaction and isolation

- j/k move in the tree; Enter/o toggle a directory or select a file. Selection
  retains tree focus. Provide NERDTree-style parent/recursive expansion/collapse
  navigation where compatible with a read-only comparison tree.
- ]f/[f visit every comparison entry, open its ancestors and reveal its node.
  Tab/Shift-Tab, r, q and native diff hunk keys keep their existing meanings.
- Refresh retains selected section/raw path when present, directory expansion
  state for surviving nodes and the original Git request. Re-rendering or
  toggling directories does not run Git per node.
- This is a read-only comparison tree. Do not bind NERDTree filesystem mutation,
  normal file-opening, bookmark-writing or root/cwd-changing actions. Native
  NERDTree outside this dedicated view retains its own mappings and behavior.
- Do not change global NERDTree prototypes, options, listeners or key mappings.
  Existing tab/window/mirrored NERDTrees, original buffers/window options, cwd,
  registers and user autocommands are preserved. Only owned resources close.
- Keep current transactional open/refresh error behavior, ownership checks,
  timer cleanup and cross-tab source labels. Missing/read/Git/renderer failures
  retain a usable prior comparison and do not leave partial resources.

No extra status subprocesses or nerdtree-git-plugin dependency are needed:
flags come from the same already validated Git comparison model. The existing
index/object/disk nonmutation, binary classification, safe-read, revision and
unsaved-buffer contracts apply unchanged. The adapter may use instance-local
NERDTree method overrides to support virtual paths and byte-safe row selection;
keep these isolated and document the upstream API/version actually verified.

## Verification

Run the existing source/content/lifecycle/security cases with real NERDTree on
the runtimepath; update presentation assertions rather than weaken content or
byte-preservation checks. Add focused checks for actual NERDTree objects and
rendering, flags and descendant indicators, nested folding/reveal, staged and
unstaged duplicates, deletion/history/subtree nodes, refresh expansion state,
file/directory replacement and exact special-path selection. Check missing
NERDTree, a pre-existing independent NERDTree and the git-status plugin together,
nondefault NERDTree options, original maps/global prototypes, manual closures,
reopen, no stale callbacks and rollback on failure. Use real terminal interaction
for expansion/selection/layout/closing and check for unwanted hit-enter prompts.

Development/test dependency: provide the external checkout with
`NERDTREE_RUNTIME=/path/to/nerdtree`; do not vendor or fetch it during tests.
Document a pinned checkout command for reproducibility and fail helpfully when
it is absent. Real NERDTree is required for integration tests; a stub is not
acceptance evidence.

## Upstream reference

Reviewed NERDTree `690d061b591525890f1471c6675bcb5bdc8cdff9` and
nerdtree-git-plugin `e1fe727127a813095854a5b063c15e955a77eafb`.
NERDTree provides per-instance node/UI objects and scoped FlagSet markers;
nerdtree-git-plugin demonstrates status markers via path listeners. Its local
filesystem status cache does not represent Diffview's staged/history endpoints,
so use Diffview's existing model rather than its Git status engine. Dependencies
remain separate installations; preserve their licenses and the existing AGPL
notices. This document describes the intended integration; implementation and
verified coverage are recorded in the user documentation and tests.
