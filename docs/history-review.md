# File and line history, merge-base review and commit previews

This extends the delivered read-only comparison, branch and commit pickers.
Existing default Open, Branch and Commit behavior remains unchanged. DiffBranch
stays removed. No checkout, fetch, stage, restore, save or history rewrite occurs.

## Public entry points

| Entry | Meaning |
| --- | --- |
| `DiffviewFileHistory` | History of the contextual file at the contextual committed start point |
| `DiffviewFileHistory [revision] -- path` | History of exactly one root-relative literal path at revision, default HEAD |
| `DiffviewFileHistory revision` | Contextual file at the explicit committed revision |
| `:[range]DiffviewLineHistory [revision]` | Trace the current line or explicit inclusive line range in the contextual file |
| `DiffviewOpen --merge-base A B [-- paths...]` | Captured unique merge-base(A,B) on the left, captured B on the right |
| `DiffviewBranch --merge-base [branch] [-- paths...]` | Captured unique merge-base(target,HEAD) on the left, captured HEAD on the right; omitted branch uses the existing branch picker |

Examples:

```vim
:DiffviewFileHistory
:DiffviewFileHistory HEAD~3 -- src/parser.py
:DiffviewFileHistory -- path\ with\ spaces.py
:DiffviewLineHistory
:10,24DiffviewLineHistory
:'<,'>DiffviewLineHistory
:DiffviewOpen --merge-base main feature -- src tests
:DiffviewBranch --merge-base main
:DiffviewBranch --merge-base -- src
```

File and line history use the existing optional core fzf installation and binary.
Direct merge-base comparisons do not require fzf. No separate fzf.vim, Python,
Node, pager or external diff dependency is introduced.

## Context, path identity and starting objects

Resolve context once, before history queries or picker creation. Capture the
original repository root, complete start commit OID, raw root-relative path and,
for line history, the validated numeric range. Never derive identity from a
display string, branch label or scratch-buffer URI.

For an ordinary file buffer, derive the repository from that file's directory,
even when Vim cwd points elsewhere. Default start is captured HEAD. A named
revision overrides that start and must resolve to exactly one commit. An unnamed
or unrelated scratch buffer needs FileHistory's explicit `-- path` form; that
form uses the invoking cwd repository. Reject multiple paths, empty/dot/directory
paths, absolute paths, traversal, leading option revisions and ambiguous arity.
The explicit path denotes a Git path, so a deleted worktree file is allowed.

In an owned Diffview pane, use that pane's selected entry and captured endpoint:
left uses oldpath, right uses destination path. On the panel, require an actual
file node and use its destination/right context; folders, headers and no-match
rows are errors. Add only minimal endpoint provenance to the existing model if
needed; never re-resolve a displayed mutable ref to infer an endpoint later.
For proven commit:subdirectory trees, prepend the captured side prefix and use
the proven owning commit. Unknown raw tree provenance is not a history start;
fail clearly rather than guess a commit from the tree or parse a colon label.

Commit comparisons use the actual parent/selected commit; root's EMPTY side has
no history start. Merge-base and Branch use their captured commit endpoints.
Local comparisons use captured HEAD as the history start: index, disk and unsaved
buffers are not commits. A path newly added or renamed only in uncommitted state
and absent from that HEAD is rejected, with no invented historical mapping.

Paths are exact literal Git names, not existing prefix filters or glob/pathspecs.
Preserve raw POSIX backslash/colon, spaces, tabs, newline, Unicode and shell-like
punctuation. Use the protected argv Git runner and deliberate NUL framing.
History requires a regular tracked text/file entry at its starting commit;
FileHistory can also start at a deleted path when Git history finds a prior
entry, while line tracing requires an existing regular text blob at start.
Reject directories, symlink and submodule entries for line tracing; do not read
worktree symlink targets or execute content/editor hooks to inspect history.

## File history semantics

FileHistory follows the selected file backwards through the first-parent
history of the captured start, using Git's native rename following. State
`first-parent, follows renames` in the picker header and documentation. This is
a mainline review trail; it does not enumerate a separate side-branch graph.
Copy following, arbitrary DAG expansion and simultaneous multi-file history
are outside this change. Native rename detection is heuristic; do not claim
perfect identity across rewrites, copies or delete/recreate cycles.

Each source member captures its full 40/64-hex commit OID and the historical
raw path at that commit, with rename old/new information sufficient to show
the relevant first-parent change. Retain escaped short ID/date/author/subject
rows, and show escaped historical path when it changes. Follow real Git output
framing; metadata/control characters must never become extra picker records.
Do not run a separate diff/log process for every source commit during launch.

Enter opens the existing first-parent-to-selected-commit comparison with a
projection for that historical file/rename, selects the matching entry and
shows the complete file snapshots. It does not open the file's latest spelling
at an old commit, or an unfiltered unrelated commit by accident. Root commits
retain EMPTY-left behavior. A rename's actual old/new names and source IDs
must remain correct. Missing shallow parents fail and retain the old view.

Search, Esc/Ctrl-C and no-match use the existing picker protections. An empty
history leaves the old comparison and caller intact with a clear message.
Selected commit/path/repository remain fixed through Refresh; history is not
reloaded or picker reopened. Run FileHistory again to obtain a newer trail.

## Line history semantics

Register a range-aware command. With no explicit Ex range, use the current
cursor line. A supplied range, including Visual `'<,'>`, is an inclusive pair
of positive line numbers; do not accept a free-form Git -L expression or regex.
Only the contextual ordinary file or owned content pane is accepted, not a
panel row, directory, arbitrary scratch or explicit unrelated `-- path` form.

The displayed source must exactly match the chosen committed blob, including
line count and final EOL. Compare captured lines/EOL with the Git blob, without
writing or reloading the caller. If unsaved, index/disk or mismatched explicit
revision content would make the range refer to different lines, reject with a
clear committed-content requirement. FileHistory remains available on dirty
files. This release does not remap edited worktree lines to historical lines.
Binary, nonregular, absent/EMPTY source, invalid/out-of-bounds/reversed range
and unavailable commit reject before replacing a view or starting a picker.

Trace that numeric range backwards with native Git -L from one captured start,
using first-parent semantics. Let Git track changes/renames as supported by
the recorded native behavior; do not substitute blame-last-touch results for
line history. Coder/reviewer/tester must independently control actual -L path
grammar and merge/rename behavior before relying on it. If a legal raw filename
cannot be expressed by native -L, fail explicitly, preserve all state and record
that specific supported-input boundary; do not silently escape into a different
file or fake a successful empty history.

Rows capture full commit OID plus its actual historical path/range association.
Reuse the NUL-delimited first-parent file-history metadata to associate traced
commit IDs with historical raw paths if native -L output lacks raw path records.
Do not recover identity by guessing from human patch headers, quoted display
names or a latest-path fallback. Missing associations fail clearly.
Enter shows that commit's normal first-parent whole-file comparison, projected
to the affected historical file. The preview may show the traced range and
the relevant patch; the accepted view is not a synthetic range-only blob.
Headers distinguish `line history` and the captured start/path/range from a
general commit picker. Root/merge/shallow and immutable Refresh rules are the
same as FileHistory. No new hunk-editing, blame gutter or line-mapping engine.

## Explicit merge-base review

Recognize one leading `--merge-base` option before revision/branch arguments;
the existing first standalone `--` remains the literal-prefix separator.
Reject duplicate/unknown options and invalid arity. Do not add `A...B` parsing
or change existing direct comparison defaults. Branch namespace resolution,
local/remote collisions and symbolic-ref exclusion remain exactly as delivered.

Resolve A/B or target/HEAD to full commit OIDs first, in the original root.
Use `git merge-base --all` on these captured IDs. Exactly one valid complete
commit result is required. No base (including unrelated/shallow history) or
multiple bases (criss-cross ancestry) is a clear error preserving the old view;
do not arbitrarily choose one or construct a virtual merge. Never fetch.

Render the captured base-to-right-tip direct tree comparison. Labels explicitly
identify `merge-base(A, B)` plus its object identity on the left, and B/current
branch plus its captured identity on the right. Do not label the left as A's tip.
Both resulting IDs/root/labels/prefixes are immutable over Refresh; no re-running
merge-base, ref lookup or picker. Invoke again to review newer tips. This fixed
mode is intentionally different from ordinary named-revision Open Refresh.
For Branch picker, capture target tuples/HEAD before UI as today and compute the
base only for the accepted tuple using those original IDs. All ordinary side
path provenance, syntax/statistics, no-match/filter/clear and gf remain valid.

## Commit previews in fzf

Enable a read-only preview for no-argument DiffviewCommit and both new history
pickers. Existing Branch picker remains a branch selector without a new preview
requirement. Explicit Commit still opens directly without fzf or an extra pane.
Default preview uses fzf's right half with wrapping; Ctrl-/ toggles it. Respect
the core's outer layout preference. Use built-in fzf preview scrolling rather
than add another Vim layout/configuration system.

Preview follows the focused source member before Enter. Show full commit ID,
author/date, commit message, changed-file summary and textual patch, subject to
the clearly marked output limits below.
Use the same first-parent/root semantics as the comparison opened by Enter,
including merge commits; do not accidentally show Git's combined/default merge
diff instead. Commit prefixes restrict patch/file summary but not the commit
message; historical pickers use their captured historical path. State that line
history acceptance opens a full-file comparison even if the preview emphasizes
the traced lines. Binary/symlink/submodule changes get textual metadata, never
external diff, textconv, pager, hooks or editor content execution.

Output is plain escaped text: strip/render control bytes safely, no raw terminal
escape/OSC sequences from messages or paths. Keep a fixed output ceiling of
2000 lines and 4096 displayed bytes per line, with explicit truncation markers
and intact character boundaries for giant single-line metadata. These are UI output limits, not an assertion of
bounded Git runtime/disk work. Do not precompute every commit's patch at launch.
Only the focused commit is loaded; a preview failure displays a local tagged
error while the picker/old comparison remain usable. It must not silently open
a comparison, accept another row or turn into successful blank output.

Use one small, isolated preview worker with the existing Vim executable/Git
capabilities. Prefer reusing the protected argv Git code in a native Vim worker;
the fzf shell boundary may contain only properly quoted fixed executable/helper
and context paths plus a restricted numeric token or complete validated OID.
Never interpolate raw root/file/branch/author/subject/message into executable
shell text, `eval`, an Ex expression or an unquoted fzf placeholder. Capture the
original root, eligible source tuples and filters in a private per-picker 0700
directory, using JSON/binary-safe data for paths; worker must validate the token
against that immutable source context. No network/default external command.

The worker runs without user init/plugins/packpath/modelines, uses only the
captured data and protected Git runner, and prints preview text to stdout.
Prove actual core placeholder framing and worker dispatch with native controls
before choosing the final small helper protocol. If the proposed worker cannot
meet job ownership/cancellation guarantees, report concrete evidence to PM;
do not grow a daemon/provider framework or add an interpreter dependency.

Core fzf preview work runs outside the main editor interaction. Fast focus
changes, toggle, cancel, accept, dependency/launch/post-live-job faults and Vim
exit must terminate owned workers/Git jobs and remove only owned temp context.
Do not remove context before the native exit/sink/preview processes stop reading
it. Keep source data alive for delayed callback validation. Unrelated user jobs,
terminals, popups and files remain intact. No persistent preview cache, global
autocmd/option/error masking or generic process supervisor.

## Integration and failure contracts

Reuse one picker creation/selection/exit/rollback path, minimally extended for
commit, branch, file history and line history request data. Preserve whole-row
source membership, list/type/single-row validation, no-print-query/no-expect/
no-multi and default-output isolation. A preview token is not acceptance output.
Rows sharing an OID with different historical paths remain distinct if needed.
Do not expose new test-only product APIs or repurpose Branch JSON rows as commit
prefixes. Capture at launch, validate before UI mutation, read/render candidates
before replacing the old view. Projection and Refresh must retain context.

All existing dirty-buffer, [nohidden/autowrite/autowriteall], bufhidden=wipe,
15 raw register, focus/window option, ordinary-tree and initial/latest cd/lcd/tcd
scope guarantees apply to the new paths. Retain the early-cancel/invalid-output
scope fix and post-open global cwd repair. Preserve owned-live-terminal stop,
default popup/enew failure rollback and foreign job isolation. History read,
missing source/parent, worker/preview, malformed callback and renderer errors
retain usable old views/user data, tagged causes and complete repo bytes.

No source-content saves or force-wipes of real user buffers. Existing normal
real-file gf hook policy and syntax isolation/fallback are unchanged. Preserve
AGPL and original attribution. Old designs' deferred-feature statements are
superseded by this contract only for these three requested areas.

## Ownership and staged delivery

Coder owns plugin/main.vim, autoload/diffview/current.vim, git.vim, tree.vim only
if a header needs it, at most one small preview worker module/helper under
autoload/diffview/, README.md, doc/diffview.txt and dev/check.py. A small history
module is allowed if it removes unrelated query logic from current.vim; avoid
new reusable framework layers. Tester alone owns tests/**. PM owns this contract
and coordination; reviewer reads independently with external evidence.

Use three source milestones on one retained new branch: (1) merge-base and
endpoint provenance, (2) file/line history on the shared picker, (3) focused
preview and owned lifecycle, plus README/help/dev. Milestones are reviewable
commits, not independently approved release pins. Tester can prepare fixtures
and reviewer can verify design/native Git/core mechanisms from the design base;
functional acceptance waits for a complete PM-pinned product+tests commit.

## Acceptance and publication gates

Retain all delivered 45 cases and 27 complete fixture comparisons. Add grouped
file-history, line-history, merge-base and preview cases, with minimal purposeful
fixtures. Keep all old function assertions unless a new approved contract
requires an explicit migration; no generic state-field or autocmd removal.

1. Independent native Git oracles establish regular/root/rename/delete/recreate/
   first-parent merge histories, numeric -L insertion/deletion/movement and
   special path grammar, shallow boundaries and complete 40/64 IDs. Test ordinary
   buffers/cwd mismatch, both snapshot sides/panel, subtree provenance, raw tree
   refusal and dirty line mismatch without saving/reloading. Accepted rows must
   show exact historical file bytes/renames and fixed Refresh after ref/cwd moves.
2. Merge-base fixtures distinguish base-to-B from A-tip-to-B; include unique
   ancestor/same-commit, unrelated, missing/shallow and two-base criss-cross DAG.
   Test Open and direct/real-fzf Branch mode, labels/projection/gf and fixed IDs
   through acceptance/Refresh, while direct defaults retain delivered semantics.
3. Real core+actual binary filtered searches execute history source selection;
   separately labeled captured-run boundaries retain real wrap/exec and exercise
   original root/start/path/range, mutable refs/cwd, malformed/non-source output,
   missing objects and read/render rollback. Never call private functions to
   bypass the actual callback contract or label a shim as real UI.
4. Worker native controls and exact product preview tests prove ordinary/root/
   merge first-parent patch, prefix/historical path, safe hostile metadata/paths,
   bounded visible output/error, no external diff/textconv/pager execution,
   no writes and no interpreter/install dependency. Observe real worker start
   and quiet cleanup after rapid focus/cancel/accept and both-layout live faults;
   keep unrelated user jobs and all owned temp context boundaries strict.
5. Full candidate-owned headless suite and every complete fixture-byte compare
   run on the final exact PM pin. Actual outer PTY must physically query/scroll/
   preview/toggle/Enter/Esc/Ctrl-C in both layouts, navigate file/selected line
   history, verify preview vs opened patch, exercise merge-base Branch and
   ordinary Commit/Branch regression, dirty/cwd/register/tree preservation and
   final owned buffer/job/context cleanup. Separate metadata controls, filtered
   transport, callback shims, injected/native prompts and physical UI evidence.
6. Reviewer independently audits actual code/test delta/connected ownership and
   publication privacy, then actually reads the final tester report/receipts/
   drivers/actions/screens/manifests before release gate closure. Preserve known
   public-dependency-SHA fullscan raw1 versus new-history results accurately;
   no custom suppression or public private report/session/evidence paths.

Git history enumeration remains synchronous; a preview worker does not make all
queries asynchronous. Record actual dependency binaries, performance and limits;
do not invent support for other platforms, giant histories or responsive resize.
Blame gutters, copy-aware/DAG history UI, three-way conflicts, virtual merge bases,
Git mutations, automatic refresh, persistent caches and new layouts are deferred.
