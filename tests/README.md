# Acceptance tests

The suite retains the 21 source/safety scenarios, adds real NERDTree integration
cases, and compares all fixture bytes,
including indexes and object databases, before and after browsing.

Use an external NERDTree checkout. Dependencies are never downloaded or vendored
by the runner:

```sh
deps=$(mktemp -d)
git clone https://github.com/preservim/nerdtree.git "$deps/nerdtree"
git -C "$deps/nerdtree" checkout 690d061b591525890f1471c6675bcb5bdc8cdff9
git clone https://github.com/Xuyuanp/nerdtree-git-plugin.git "$deps/nerdtree-git-plugin"
git -C "$deps/nerdtree-git-plugin" checkout e1fe727127a813095854a5b063c15e955a77eafb
NERDTREE_RUNTIME="$deps/nerdtree" \
NERDTREE_GIT_RUNTIME="$deps/nerdtree-git-plugin" sh tests/run.sh
```

`NERDTREE_RUNTIME` is mandatory; a missing checkout returns nonzero with setup
instructions. `NERDTREE_GIT_RUNTIME` enables the separate real git-plugin
coexistence case. Without it the runner explicitly reports that case NOT RUN;
a complete NERDTree acceptance run includes both dependencies. The git-status
plugin is a compatibility test dependency, not a Diffview runtime requirement.

The runner requires Git, POSIX shell tools, and Vim 9.1 with `+vim9script`,
`+diff`, `+windows`, `+job` and `+timers`. Override `VIM` to select a Vim executable.

To test a separately checked-out revision, run:

```sh
DIFFVIEW_TEST_RUNTIME=/path/to/candidate \
NERDTREE_RUNTIME=/path/to/nerdtree \
NERDTREE_GIT_RUNTIME=/path/to/nerdtree-git-plugin sh tests/run.sh
```

The runner prints the candidate SHA and any uncommitted product files. It
creates isolated temporary Git repositories, loads the real plugin, runs public
commands and the real tree's Enter mapping, and checks actual left/right contents.
NERDTree classes, renderer and FlagSet objects are exercised; no tree stub is
used. Tree selection uses raw node identity rather than parsing escaped labels.
Failures return nonzero and retain fixtures, assertion output and Vim logs at
the printed path. Successful runs remove their temporary files. Git global and
system configuration, hooks and signing are isolated. The Vim process receives
the default optional-lock behavior, so a missing product-side no-optional-locks
guard cannot be hidden by the runner. A stale-stat fixture proves that ordinary
`git status` would rewrite its index; plugin browsing must preserve its bytes.
It must also omit stat-only false `M` rows in clean and mixed-change lists while
retaining real content changes and mode-only entries.

Core coverage:

- Staged-only, unstaged-only, both for one path, untracked and ignored files.
- Root path with spaces/Unicode; launching in a nested directory; refreshing
  after changing cwd retains the original repository.
- Read-only snapshots, real diff windows, initial panel focus, explicit refresh,
  close, repeated close, reopening through the legacy toggle.
- Real NERDTree left pane, snapshot names/filetypes, left/right order and status-line section,
  selected path and HEAD/INDEX/WORKTREE/EMPTY labels; unsaved-edits notice.
- Unsaved user buffer contents/modified state, original window, scratch-buffer
  and active-autocmd cleanup; all fixture disk/index/object bytes unchanged.
- Clean, unborn and non-Git repositories.
- Space/Unicode, leading dash, tab, newline and shell/Ex punctuation in paths;
  distinct content per filename proves the right entry was selected.
- Explicit `r` sees test-created disk edits/new paths and retains selection;
  snapshots remain fixed until refreshed, and `q` closes the view.
- SOH (0x01), literal backslash-n and tracked `:(glob)**` names are distinct
  literal paths; no inherited Git pathspec settings mask product mistakes.
- `nohidden` + `autowriteall`, two dirty file buffers, unrelated window options,
  manually closed pane, user buffer replacing a plugin pane, invalid open,
  refresh, close and reopen; no automatic saves or loss of modified state.
- Manual pane/tab closure waits up to one second for owned buffers to disappear;
  inserted dirty user panes survive. Immediate reopen drains old one-shot timers
  with a bounded wait and verifies the replacement's buffers and contents remain.
- User takeover of a plugin pane preserves its subsequently chosen diff, bind,
  fold and wrap options on close, including a dirty unnamed user buffer.
- Replacing a listed file's parent directory with an external symlink before
  selection must show an explicit error/unsupported message and never read the
  external marker. The test restores its deliberate filesystem edits and
  compares the repository and external fixture bytes afterwards.
- Forced-binary paths also exercise disappearing files and symlink ancestors;
  Binary classification cannot replace the required read/unsupported error.

Additional scenarios:

| Case | Expected acceptance |
| --- | --- |
| trees | Divergent endpoint direction, left-only deletion absent from merge-base diff, ignored local/index dirt, add/delete/rename/mode, explicit trees/subtrees, legal quote/$()/pipe refs, empty result, legacy DiffBranch and Toggle |
| commits | Normal, root, first-parent merge and default HEAD contents; source identities; forced-binary ordinary/root commits |
| historical_refresh | Fixed refs until refresh; explicit refresh re-resolves original names, preserves repository/selection and updates labels across tabs |
| errors | Invalid revisions, blob/tree type mismatch, arities/ranges/options, non-Git/bare cwd and shallow missing parent; tagged error and old usable view retained |
| exclusions | Regression: leading ^ exclusions rejected in each/both tree positions and commit mode while preserving the old view; valid merged^1/HEAD^1 remain accepted |
| edges | Empty add, deleted file, rename/mode, missing final newline, NUL binary and Git-marked binary in staged/unstaged/untracked, symlinks, gitlink and unmerged index |
| cross_tab | Regression: absent-side labels from origin tab; empty/source clearing and restored changes from a separate dirty user tab; body, source metadata and visible labels agree |
| read_failure | Disappearing text/forced-binary files and missing Git executable report errors while preserving the previous comparison |
| navigation | Actual next/previous wrapping, pane Tab/Shift-Tab cycling, directory toggling and buffer-local mappings |
| binary_clean | forced ASCII, NUL, empty, no-final-LF and normalized CRLF files with stale stat remain No changes on open/refresh |
| binary_mixed | omit unchanged forced/no-final-LF/CRLF rows; retain real forced/NUL/text changes, both mode groups, pure rename, empty add/delete, and all fixture bytes |
| large | 20,000-line content and 201 files, selection preserved on refresh; measured open/select/refresh/close timings |
| empty_start | A fresh Vim with one empty unnamed buffer and no alternate buffer directly opens/refreshes/closes the real tree; no preparatory edit may hide an upstream Creator E194 |
| tree_nodes | Actual nodes/renderer/flags, descendant indicators, expanded nested sections, collapse/reveal/refresh, raw control-character identities, and no Git calls for tree navigation |
| tree_history | Deleted/absent history, comparison-relative subtree roots, both file/directory collision directions; all entries remain selectable without disk placeholders |
| tree_isolation | Existing and mirrored user trees, custom options/maps/listeners/prototypes, cwd/registers/autocommands and dirty buffers survive open/refresh/close/manual cleanup |
| dependency | A missing real NERDTree reports installation guidance and preserves the original layout/dirty buffer |
| tree_rollback | Injected tree initialization/render failures preserve the old usable comparison and leave no partial resources |
| tree_git | Optional real nerdtree-git-plugin coexistence: local status callbacks and flags remain isolated from staged/history diff flags and user trees |

Raw-identity fixtures include newline and BEL filenames alongside their literal
`^@`/`^G` display twins. Selection must distinguish them before and after tree
operations, including NERDTree's own control-byte delimiter. Historical ghosts
and the same staged/unstaged path are explicitly selected again after refresh.

New fixture controls verify merge parent order, endpoint-versus-merge-base
distinction and Git's binary attribute before plugin execution. All fixture
repositories, objects/indexes and the external symlink target are compared after
the run. Tests restore their explicit ref/disk edits in finally blocks.

Follow the [terminal smoke checklist](manual.md) to verify interactive behavior.
Record exact product, test and dependency commits and actual results outside the
repository. These integration tests are preparation, not a product PASS receipt.
Other versions/platforms/geometries and larger workloads require their own checks.
Headless success alone does not establish interactive usability.
