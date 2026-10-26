# Acceptance tests

The complete suite has 50 grouped scenarios and 31 whole-fixture comparisons,
including the delivered 45 scenarios and 27 fixtures. It compares repository
indexes, objects, refs and worktree bytes before and after browsing.

Use external NERDTree and core fzf checkouts. Dependencies are never downloaded or vendored
by the runner:

```sh
deps=$(mktemp -d)
git clone https://github.com/preservim/nerdtree.git "$deps/nerdtree"
git -C "$deps/nerdtree" checkout 690d061b591525890f1471c6675bcb5bdc8cdff9
git clone https://github.com/Xuyuanp/nerdtree-git-plugin.git "$deps/nerdtree-git-plugin"
git -C "$deps/nerdtree-git-plugin" checkout e1fe727127a813095854a5b063c15e955a77eafb
git clone https://github.com/junegunn/fzf.git "$deps/fzf"
git -C "$deps/fzf" checkout 26ff936df038b6a62ec42cf18db27b2ea2bb8ec3
NERDTREE_RUNTIME="$deps/nerdtree" \
NERDTREE_GIT_RUNTIME="$deps/nerdtree-git-plugin" \
FZF_RUNTIME="$deps/fzf" sh tests/run.sh
```

`NERDTREE_RUNTIME` is mandatory; a missing checkout returns nonzero with setup
instructions. `NERDTREE_GIT_RUNTIME` enables the separate real git-plugin
coexistence case. Without it the runner explicitly reports that case NOT RUN;
a complete NERDTree acceptance run includes both dependencies. The git-status
plugin is a compatibility test dependency, not a Diffview runtime requirement.
`FZF_RUNTIME` and an already installed `fzf` executable on PATH are required for
the picker integration cases. The separate fzf.vim plugin is not used. Core fzf
may choose a newer bundled binary instead of PATH's binary; record both versions
and the actual `fzf#exec()` result printed in the picker facts. The core plugin
at this ref is byte-identical to the earlier b412a450 control pin; record the
actual checkout rather than rewriting the dependency to match older evidence.

The runner requires Git, POSIX shell tools (including xargs, ps and mkfifo for
preview transport/ownership controls), and Vim 9.1 with `+vim9script`,
`+diff`, `+windows`, `+job`, `+timers` and `+terminal`. Override `VIM` to select a Vim executable.

To test a separately checked-out revision, run:

```sh
DIFFVIEW_TEST_RUNTIME=/path/to/candidate \
NERDTREE_RUNTIME=/path/to/nerdtree \
NERDTREE_GIT_RUNTIME=/path/to/nerdtree-git-plugin \
FZF_RUNTIME=/path/to/fzf sh tests/run.sh
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
| trees | Divergent endpoint direction, left-only deletion absent from merge-base diff, ignored local/index dirt, add/delete/rename/mode, explicit trees/subtrees, legal quote/$()/pipe refs, empty result, supported target-to-HEAD commands and Toggle |
| commits | Normal, root, first-parent merge and explicit HEAD contents; source identities; forced-binary ordinary/root commits |
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
| tree_nodes | Actual nodes/renderer/flags, descendant indicators, expanded nested sections, collapse/reveal/refresh, raw control-character identities, no Git calls for tree navigation, and expression/search/anonymous/numeric/named register preservation |
| tree_history | Deleted/absent history, comparison-relative subtree roots, both file/directory collision directions; all entries remain selectable without disk placeholders |
| tree_isolation | Existing and mirrored user trees, custom options/maps/listeners/prototypes, cwd/registers/autocommands and dirty buffers survive open/refresh/close/manual cleanup |
| dependency | A missing real NERDTree reports installation guidance and preserves the original layout/dirty buffer |
| tree_rollback | FileType failure plus native mid-render throws during new Open and changed-model Refresh preserve tree/node/row identities, bodies/sources, readonly/options, focus, registers, buffers/windows/timers/autocommands and the original dirty buffer |
| tree_git | Optional real nerdtree-git-plugin coexistence: local status callbacks and flags remain isolated from staged/history diff flags and user trees |
| picker_real | Real core/binary filtered selection by subject, author and short hash; reachable side history, root/merge semantics, metadata punctuation, fixed full-OID refresh and dirty-buffer protection |
| picker_no_match | Real core/binary no match preserves caller focus, old comparison, registers, dirty buffer and an ordinary NERDTree |
| picker_enew | Real core with nohidden/autowrite/autowriteall: enew selection/no-match/abort, layout throw and enew/default-popup post-job FileType throw preserve dirty bytes, caller options and old view/resources; pre-existing tcd survives no-match/fault and default-popup selection including deferred WinEnter; only owned picker jobs/popups are cleaned and a pre-existing user job keeps running |
| picker_async | Real core terminal job: change caller tcd while the enew picker runs, wait for the typed query and unique match before Enter; preserve the latest path AND tab-local scope, original repo/full OID, fixed refresh and dirty bytes |
| picker_sha256 | Real core/binary selection and refresh retain the full 64-character commit identity and actual bodies |
| picker_missing | Missing core plugin/binary give errors and preserve the comparison; explicit HEAD works with neither dependency |
| picker_old_binary | Unmodified real core with an incompatible version-reporting binary fixture rejects without consuming input or running an installer/picker; explicit HEAD remains usable |
| picker_errors | Unborn, non-Git, bare and injected Git history failure report errors without replacing the old view |
| picker_api | Public fzf callback boundary only: original repository/full OID after cwd/ref changes; malformed, duplicate and forged rows, launch/read/render errors and immutable refresh |
| reading_syntax | Actual built-in Python/C/shebang tokens, per-side rename and deleted names, syntax-off/unknown/empty/nontext clearing, raw EOL, modeline/FileType isolation and partial syntax error fallback |
| reading_goto | Public gf/command opens adjacent normal tabs, clamps line hints, reuses dirty targets without saving, preserves caller/options/registers, maps rename/subtree sides, rejects unknown tree/missing/nonregular/symlink targets; real FileType and loaded-target BufEnter failures restore focus/resources while retaining user hook edits |
| reading_filter | Initial Open/Commit/fzf prefixes, local duplicate groups, rename old/new identity, segment/OR/normalization, literal control/display twins, retained selected snapshots, no diff/ref/history reload, no-match/clear/Refresh and read/native-render failure rollback |
| reading_stats | Independent Git numstat oracle for local/tree/ordinary/root commit metadata; known zeros versus unsupported/binary/untracked unknowns, leaf/header totals and dynamic native rows; malformed-count boundary rejection |
| branch_direct | Direct local/remote/full-ref tips, short-name collision, diverged endpoints, same-branch empty, detached/invalid/unborn and no-fzf behavior; retired command/function absent |
| branch_real | Actual core/binary name-filtered local/remote selection and no match in explicit SHA-1/SHA-256 fixtures; symbolic aliases excluded, prefixes/labels/root and both captured tips remain fixed after refs/HEAD/cwd move |
| branch_api | Captured-run boundary with real core wrap/exec: namespace/source membership, both-OID/original-root/prefix binding, malformed output, launch/read/render rollback and immutable Refresh |
| branch_lifecycle | Minimal default-popup/enew Branch wiring for dirty initial/late tcd, real binary abort, initialization throw, post-live-job failure and unrelated user job preservation |
| history_file | Real core/binary first-parent rename/root/delete/recreate selections in both object formats, dirty contextual file despite unrelated cwd, invalid input/no-match and shallow-parent rollback |
| history_line | Whole-file acceptance of native numeric line traces across inserted/moved ranges, committed-content requirement, subtree provenance, EMPTY/raw-tree/panel refusal and unsaved data preservation |
| history_mergebase | Unique/ancestor/same base versus direct defaults, immutable Open/direct or real-picker Branch labels/prefixes/root, unrelated/shallow/two-base rejection |
| history_api | Actual core wrap/exec with only run captured: native CID/path/range oracles, both pane sides/panel/subtree contexts, literal raw names, moved HEAD/cwd, strict callback/read/render rollback; actual preview-command output/status/limits/error boundary |
| history_preview | Real core terminal previews and focused whole IDs, rapid changes/toggle/cancel/accept, both layouts and provably live Git-at-FileType faults; owned context/process-group cleanup with a foreign user job still running |

Picker fixtures include six HEAD-reachable commits, a merged side branch and an
excluded branch, Unicode/control/shell punctuation metadata, SHA-1/SHA-256 and
staged/disk/unsaved differences. The runner clears inherited fzf defaults before
setting intentional per-case defaults. Actual filtered core/binary execution
is separate from the callback fixture under `picker-api/`, which retains real
core wrap/exec and only intercepts run to capture the public spec and dispatch its
sink/exit callbacks, including invalid types and exit codes. Neither is terminal UI evidence:
search/Enter, Esc and Ctrl-C must also be exercised in a real terminal.
The asynchronous actor case uses `term_sendkeys` with an observed query and
settled result count before Enter. It is real core/binary execution in headless
Vim, separate from both callback injection and the outer terminal checklist.
The incompatible-binary case copies the real core file into a private temporary
runtime without its bundled executable. Its version-only binary and installer
sentinel exercise dependency rejection, not successful execution of an old fzf.

The coexistence case drains jobs and channel-close callbacks after native tree
creation, mirroring and buffer entry before recording its baseline. It then
declares a temporary disk change and explicitly triggers the ordinary tree's
status update. That external actor may update its own markers and `=` register;
comparison markers/content and the ordinary tree's structure must stay intact.
After restoring the disk edit and settling callbacks, subsequent Diffview
operations must preserve the new ordinary-tree baseline and a reseeded safe
expression. The plain isolation case retains strict unchanged-register/flag
checks throughout, without an external actor.

Raw-identity fixtures include newline and BEL filenames alongside their literal
`^@`/`^G` display twins. Selection must distinguish them before and after tree
operations, including NERDTree's own control-byte delimiter. Historical ghosts
and the same staged/unstaged path are explicitly selected again after refresh.
The public `NERDTreeRender()` entry must retain the comparison headers and raw
registers. A unique leaf's reported row must contain its actual display string;
Enter at that row must still show the exact expected comparison. Matching two
internal lookup methods alone cannot establish that screen rows are correct.
Register snapshots read the raw `=` expression without evaluating it and include
the complete `getreginfo()` for the unnamed, numbered, named, small-delete and
search registers, including unnamed-register identity. Open, Toggle in both
directions, Refresh, Close and render failures must preserve these snapshots. Render
faults are injected into `root.renderToString`, after native UI.render has begun
clearing/unlocking its buffer. The refresh test declares and restores its temporary
content/addition edits; whole-fixture comparisons still require original bytes.

New fixture controls verify merge parent order, endpoint-versus-merge-base
distinction and Git's binary attribute before plugin execution. All fixture
repositories, objects/indexes and the external symlink target are compared after
the run. Tests restore their explicit ref/disk edits in finally blocks.

Follow the [terminal smoke checklist](manual.md) to verify interactive behavior.
Record exact product, test and dependency commits and actual results outside the
repository. Compilation and fixture controls alone do not establish product PASS;
run the complete suite and terminal checklist against the exact candidate.
Other versions/platforms/geometries and larger workloads require their own checks.
Headless success alone does not establish interactive usability.

The reading fixture adds two whole-directory comparisons (repository and the
disposable outside-symlink target) to the original 23. Its numstat oracle is
captured directly from Git before product execution. A narrow existing Git
wrapper boundary supplies malformed numeric output only for the rejection
checks; it does not replace the real count, syntax, tree or fzf integrations.
The four reading groups are prepared tests, not evidence of product PASS until
the complete candidate-owned runner and same-candidate terminal checks execute.
The POSIX reading fixture also tracks a filename C:\literal.txt; Open,
projection and actual gf must keep its colon and single backslash intact.
Absolute/traversal filters and use-time symlink checks remain rejection cases.

The two branch fixtures add two complete repository comparisons to the existing
25. Independent Git controls distinguish direct endpoint changes from merge-base
changes and confirm both object formats and the local/remote/symbolic-ref set.
The former DiffBranch command and global function must be absent. Their old
direction/dirty/invalid-input assertions now use supported Open commands;
the new immutable Branch behavior is checked in its own groups.
Toggle coverage remains. Use Open target HEAD when named refs must re-resolve on
Refresh, or Branch when both captured tips must remain fixed.

Branch API injection intercepts only run, sharing the existing captured-spec
fixture with Commit; real wrap/exec and the original Commit lifecycle assertions
remain intact. Filtered core selection and generated abort/term_sendkeys actors
are headless dependency evidence, not physical-key terminal acceptance.

History adds four complete repository comparisons: SHA-1 and SHA-256 review
trails, a shallow clone and a criss-cross/unrelated-base graph. Native first-parent
follow/raw and numeric -L oracles are captured before running the product; raw
paths are not recovered from human patch headers. The planned full suite is
50 groups and 31 whole-fixture comparisons, including all former 45/27.
Rename and delete commits also create a child under the former file spelling,
then delete that child later. Exact historical-file source/view/preview checks
must omit that unrelated child while preserving the real rename or D entry.
The existing shallow clone also checks that a correct CID/status cannot disguise
a missing first parent as a successful root-addition preview.

The preview group uses a private temp root to observe owned source contexts.
The existing real-Git wrapper can log PID/PGID and, only in the declared live
fault check, insert an external FIFO output route before execing actual Git.
That slow actor proves Git is live before cancellation, rather than mistaking an
already-finished query for cleanup. A separate output-boundary check supplies
a nonzero Git result with a forged earlier status-zero line; it must remain a
local error. Normal selection/source tests continue to use actual Git output.
No interpreter or alternate worker is installed in the product.

Commit previews share the physical terminal row with the query at narrow
geometries. The old async query check samples terminal cells in the left half,
requiring the complete prompt/query and two settled unique-result observations;
it does not disable preview or relax any post-selection identity/state checks.
Worker-output commands and captured-run callbacks remain separate scopes from
real headless fzf preview execution and the final physical-key terminal gate.
Git argv logging uses one atomically published NUL record per invocation and a
short append-only manifest. This preserves literal LF/empty/Unicode arguments
and concurrent preview calls without treating a filename fragment as a query.
Malformed or incomplete records fail the test instead of being skipped.
The `history_preview` case runs inside a native Vim terminal at 240x60 so the
unchanged default popup and right-half preview can display a complete commit ID.
It still checks actual right-side cells for two settled observations; this
headless terminal geometry check does not replace the physical-key PTY gate.
