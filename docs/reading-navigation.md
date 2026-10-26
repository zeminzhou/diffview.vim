# Reading and navigation

This contract extends the existing read-only comparison browser with language
syntax, worktree navigation, literal path filtering and line statistics. Existing
local/tree/commit source semantics and the core fzf lifecycle remain in force.

## Scope and commands

| Entry | Behavior |
| --- | --- |
| `DiffviewOpen [left right] [-- paths...]` | Existing comparison, restricted to the supplied literal path prefixes |
| `DiffviewCommit [revision] [-- paths...]` | Existing explicit commit or fzf selection, restricted to those prefixes |
| `DiffviewFilter [paths...]` | Change the active comparison's path projection; no arguments clears it |
| `DiffviewGotoFile` / buffer-local `gf` | Open the selected path's current worktree file in a new ordinary tab |

Examples:

```vim
DiffviewOpen -- src tests
DiffviewOpen main feature -- src
DiffviewCommit HEAD~1 -- src
DiffviewCommit -- src
DiffviewFilter src/core path\ with\ spaces
DiffviewFilter
```

The first standalone `--` separates revisions from paths. Before it, Open still
accepts zero or two revisions and Commit zero or one. Empty paths after `--`
mean all paths. Without a separator, previous argument validation is unchanged.
`DiffviewFilter` treats all its arguments as paths, not options or revisions.
The legacy Toggle/DiffBranch wrappers keep their current behavior.

`DiffviewCommit -- src` still searches the full HEAD-reachable commit list and
filters the chosen commit's changed paths. This is not file-history search.
The selected full OID, original repository and filter survive Refresh; it does
not relaunch fzf. Explicit named revisions retain re-resolution on Refresh.

## Language syntax in snapshots

- Keep `filetype=diffview`, existing buffer names/roles and readonly/nofile state.
  Set buffer-local syntax from the logical source filename and snapshot content.
  The left side uses oldpath and the right side path, including cross-extension
  renames. Historical/deleted names do not need to exist on disk.
- Reuse Vim's built-in detection and syntax resources. Respect the user's global
  syntax setting; do not run `syntax on` or enable global filetype plugins.
  With syntax disabled, keep the comparison plain. Unknown language is plain.
- Detection must not execute modelines or additional user BufRead/FileType/indent
  hooks on the snapshot, and must not read a similarly named worktree file.
  A private owned detection context may be used; it must be cleaned up without
  leaving buffers/windows, changing cwd/registers/options or replacing user data.
  Do not build an extensible language-provider framework or a new dependency.
- Source FileType remains diffview, so real-file LSP/format/indent hooks are not
  attached to snapshots. The real file opened by gf uses normal Vim filetypes.
  Preserve the existing FileType diffview creation event and its error rollback;
  language detection/application must not add language-specific FileType events.
- Clear stale syntax for EMPTY, No changes, No matching changes and unsupported
  explanation buffers. Switching from Python to an unknown extension must not
  retain Python syntax. Buffer text/source/EOL remain exact.
- A syntax resource error is a nonfatal display failure: retain correct content
  and sources, clear partial syntax in the owned buffer, leave it readonly, and
  report a tagged notice. Do not turn successful Git content into an invalid or
  half-updated comparison. Existing Git/read/tree failures still keep old views.

## Opening the real worktree file

The action explicitly opens the current worktree file, not a historical checkout
and not an editable snapshot. It does not change the existing comparison.

| Invocation context | Raw path and line hint |
| --- | --- |
| Tree file node | Entry destination path, line 1 |
| Tree directory/header/empty result | Tagged error; no navigation or resource change |
| Left content pane | Entry oldpath, current snapshot line |
| Right content pane | Entry destination path, current snapshot line |
| Command from another window/tab | Selected entry destination path, line 1 |

Line hints are numeric and clamped to the target buffer's valid range. They are
not a claim of exact historical-to-current line mapping; a dirty/reorganized
current file may differ. No diff alignment, blame or content-search engine is
introduced in this iteration.

Use raw entry identity and captured comparison metadata, never NERDTree's opaque
physical path or a rendered label. Full-root commit refs/commit IDs have a known
worktree prefix. For `rev:directory`, use that side's validated repository-relative
directory prefix when the rev part resolves to a commit root. Preserve distinct
left/right prefixes when the compared subtrees differ. Capture this mapping as
part of comparison preparation; gf must not re-resolve moving refs or switch the
comparison. Arbitrary tree IDs/tree-only expressions with no provable worktree
root mapping must report unsupported rather than guess a matching disk file.
They remain valid read-only comparisons. A missing historical path also errors;
never create a placeholder, checkout a blob, or silently select another path.

Before opening, validate the mapped repository-relative path and every component
below the original repository root. Reject traversal, symlink ancestors/leaf and
nonregular or missing targets, reusing the safe worktree-path checks. Do not
follow an outside symlink. This check happens on use, not only when listing.

Open in a new ordinary user tab adjacent to the comparison, focused on the file.
If that absolute path already has a loaded buffer, reuse that buffer and its
unsaved contents without reload. Otherwise perform a normal file open. Never
install Diffview role variables, readonly flags or q/r/gf mappings on the user
buffer. The comparison remains available; native tab navigation returns to it.
Closing Diffview must not wipe this user tab/buffer.

Do not force-save or discard either the caller or target, including with
nohidden/autowrite/autowriteall. Keep original window contents/options/layout,
registers and directory scopes intact; do not explicitly chdir to open the file.
The user file receives normal editor filetype behavior. User-defined editing
autocommands/autochdir policy are normal real-file behavior, not snapshot hooks;
the plugin must not globally disable or rewrite that policy. An ordinary open
failure cleans only this action's new resources and returns to the invoking
window with the old comparison intact. Use escaped absolute filenames/buffer
numbers, never interpolate raw paths as Ex commands.

The preservation guarantee covers pre-existing caller/target data and forbids
plugin-driven force-save, reload or force-wipe of real user targets. It does not
reconstruct temporary hook text or modified flags that Vim itself discards or
resets while unwinding a failed first file load. Attribute that boundary using
the same native open primitive, without suppressing normal real-file hooks.
Retain strict new-file FileType failure rollback and also verify a BufEnter
failure while reusing an already-loaded dirty target.

## Literal path projection

Paths are relative to the comparison root, independent of later cwd changes. For
tree/subtree comparison they are relative to the compared trees, not filesystem
existence. Match an exact path or its slash-delimited descendants. Multiple
prefixes are ORed; case is significant. Normalize redundant `./`, internal `.`
and trailing/repeated slash separators. `.` or an empty filter list means all.
Reject absolute paths and any `..` component. Do not resolve filters on disk.

This iteration uses literal prefixes: `*.py`, `:(glob)**`, backslashes, dollar
signs and other punctuation have no glob/pathspec/regex/shell meaning. Existing
literal Git-read protection remains. Spaces and control-character identities
follow the existing raw argument/entry rules, with safe escaping only for UI.
No exclude patterns, status filters or new file-picker dependency are included.

A rename/copy matches either oldpath or path; retain the original single entry,
status and both identities. File/directory collisions and staged/unstaged entries
with the same path remain distinct. Directory status flags are aggregated from
visible entries only. Keep full unfiltered comparison data alongside its visible
projection so clearing a filter restores entries without running a new diff.

Changing a filter does not re-resolve refs, load commit history or recompute Git
diff metadata. Retain the selected section/rawpath if visible, along with its
existing snapshots; otherwise choose the first visible entry and read it through
the normal safe selection path. That selection may run normal blob/index reads.
Preserve expansion of surviving directories. Invalid filters or read/render
failure retain the prior filter, tree, snapshots, labels, focus and user state.

If the full comparison is empty, continue showing `No changes`. If changes exist
but no entry matches, show `No matching changes`, clear old source/path/syntax,
and disable diff. Clearing the filter recovers the full view. New Open/Commit
without paths resets to all; Refresh remembers the current prefixes.

## Line statistics and display

Preserve counts from the SAME raw/numstat query already used for tracked local,
tree and commit comparisons. Do not run per-file diff commands or manually count
worktree lines. Keep has-key filtering so valid zero/zero mode-only and pure
rename records survive; the existing text/binary stat-only exclusions remain.

Entry metadata gains `added` and `deleted`: nonnegative integer counts, or -1
for unknown/nontext values. Binary -/- and unsupported conflict/link/gitlink
records are unknown; untracked entries remain unknown in this iteration rather
than scanning every untracked file. Zero is a known count, never an unknown.
Validate numstat fields instead of silently parsing malformed output as zero.

Show a short `+N -M` suffix on file leaves; unknown is `+? -?`. Raw metadata,
entry identity, status flags and path labels stay separate from that suffix.
Directories keep existing native status aggregation; no new per-directory stat
or per-node Git job is required.

Preserve the existing first two header lines (mode and sources/unsaved notice).
Add a summary line such as `3/8 entries | +12 -4 | 1 unknown`, counting visible
entries against the full comparison and summing only known visible counts.
Show unknown count only when nonzero. A staged and unstaged path counts as two
comparison entries, not two unique files. Append an escaped `Filter: ...` line
only while restricted. File bodies remain pure snapshots, without stat headers.

Header length must drive visible row lookup. Native `NERDTreeRender`, folding,
refresh and selection must keep headers/stats/filter text and exact screen-row
to-node identity, including display-colliding control-character paths.

## Implementation boundaries

- plugin/main.vim: shared revision/filter argument parsing entry points, new
  Filter/GotoFile commands; no changed old arity without `--`.
- autoload/diffview/git.vim: retain numstat counts and safe worktree mapping/path
  support; preserve current argv runner, exclusion guard and all read protections.
- autoload/diffview/current.vim: full/visible model, filter transaction, syntax
  application and ordinary-file navigation. Reuse existing view ownership/error
  handling; keep fzf original-root/full-OID/cancel/default/enew behavior.
- autoload/diffview/tree.vim: leaf counts and dynamic summary/filter headers only;
  retain real native nodes/rendering, raw identity and instance-only adaptations.
- README/help/dev and independently owned tests cover the final behavior.
  A small focused helper file is acceptable if it isolates native detection;
  no generic command/picker/provider architecture is requested.

## Acceptance gates

1. Retain the existing 37 scenarios and all 23 whole-fixture comparisons, real
   pinned NERDTree/core fzf/git-plugin and original B01-B07/FB02-FB06 safeguards.
2. Syntax: real Vim syntax tokens for Python/C or Go, cross-language rename sides,
   historical/deleted filename and shebang where native detection supports it;
   unknown/empty/binary clearing, syntax-off respected, partial Syntax error
   fallback, exact body/EOL/readonly and no user FileType/modeline execution.
3. gf: actual public key/command, correct side/path and clamped line; new normal
   tab, reused dirty target, dirty origin/nohidden/auto-write protection, literal
   special paths, preserved comparison and user tab survival on Close. Cover
   distinct subtree prefixes and unknown-tree mapping rejection; missing target,
   replaced symlink parent, nonregular target and open/FileType errors rollback.
4. Filtering: local/tree/commit/fzf callbacks, repeated clear/Refresh across cwd
   and ref changes, nested literal prefixes/OR, old/new rename, duplicate groups,
   file-dir collisions, special raw paths and invalid traversal/arity; no-match
   versus clean result, unchanged selected snapshots and no diff/log/ref reload
   on projection. Inject read/native mid-render failure and retain prior state.
5. Stats: added/deleted/modified/empty/no-EOL/rename/mode-only, binary/forcedbinary,
   unsupported and untracked unknown, filtered/full entry counts and known sums;
   compare actual Git numstat plus real rendered labels. Re-run stale-stat
   text/binary/CRLF byte protections; never update index to fix false rows.
6. Real native render/fold/public rerender and cross-tab Refresh must preserve
   header/row/node/source identity, registers, user trees and resource cleanup.
7. Same frozen candidate gets independent full headless and actual terminal
   acceptance: syntax visible, filter/clear/gf/focus/return/refresh/close, dirty
   buffers and default/enew commit picker still usable, no extra Enter prompt.
   Evidence stays outside public source; public docs contain reproducible steps.

File history, merge-base mode, stage/restore/merge UI, async/automatic refresh,
multi-view/layout configuration, fuzzy file picking and commit preview are later
scope. Historical-to-current semantic line mapping and glob/pathspec filters
are not implied by the new numeric line hint/literal-prefix filter.
