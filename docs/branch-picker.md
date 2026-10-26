# Branch comparison and search

## Commands and comparison

```
:DiffviewBranch main
:DiffviewBranch origin/main
:DiffviewBranch refs/remotes/origin/main
:DiffviewBranch
:DiffviewBranch main -- src tests
:DiffviewBranch -- src
```

`DiffviewBranch [branch] [-- literal-prefix...]` compares the selected target
branch on the left with the invoking checkout's committed HEAD on the right.
This is a direct comparison of two committed trees, equivalent in direction to
`DiffviewOpen target HEAD`. It does not use a merge base and does not include
staged, unstaged or unsaved editor content. Comparing the current branch with
itself produces the normal `No changes` view.

With one branch argument, open directly without requiring fzf. With no branch
argument, search locally available branch refs using the optional core
junegunn/fzf integration already used by DiffviewCommit. Enter accepts exactly
one branch. Esc, Ctrl-C and no match preserve the previous view and caller.
More than one argument before `--` is a usage error. Prefix parsing and matching
reuse the existing literal path-filter contract, including rename old/new paths,
invalid-prefix rejection, clear, statistics, syntax and gf behavior.

`DiffBranch` and `g:DiffBranch()` remain compatibility wrappers with their existing
raw-revision and refresh behavior. Open and Commit retain their existing behavior.

## Branch identity and resolution

- Enumerate local `refs/heads/` and locally stored `refs/remotes/` refs only.
  Never fetch or contact a remote. Exclude symbolic refs such as origin/HEAD;
  include ordinary local and remote-tracking refs, even when they share an OID.
- Accept an exact full ref under either namespace. For short names, prefer an
  exact local branch, then an exact remote-tracking branch. Thus `origin/main`
  prefers a local branch literally named origin/main when one exists; the full
  `refs/remotes/origin/main` spelling disambiguates it. Tags, arbitrary revision
  expressions, leading option arguments and unknown names are rejected.
- Branch names are raw identity, not shell fragments or display text. Use the
  existing argv Git runner and explicit refs; do not interpolate shell commands
  or use substring/prefix matching to identify a selected ref.
- Picker rows clearly distinguish local and remote-tracking refs, show the branch
  name and a short OID, and remain searchable by name. Escape display metadata
  using the existing display policy. Do not add network status/ahead-behind or
  per-branch history queries.
- Capture the original repository, current HEAD full commit OID and current
  branch label before launching fzf. A detached HEAD is supported and labeled
  as detached HEAD; an unborn HEAD fails clearly without replacing the old view.
- Capture each enumerated target ref's full commit OID with its source row.
  On selection, use this captured OID and the captured HEAD, even if refs, HEAD,
  checkout, cwd or cwd scope change while the picker runs. SHA-1 and SHA-256
  repositories are supported using validated complete 40/64-hex OIDs.
- Direct invocation also captures both tips for the resulting comparison. Pane
  sources identify target/current branch (or detached HEAD) and resolved object
  identity. Refresh rereads the same two captured commits in the original repo,
  retains prefixes and labels, and does not reopen fzf or follow moved refs.
  Invoke DiffviewBranch again to compare newer tips. Existing generic Open and
  explicit Commit named-revision refresh semantics remain unchanged.

## Shared picker and failure behavior

Reuse the existing core fzf dependency checks, noninteractive version check,
single-selection options and creation/cleanup protection. Extract the existing
picker lifecycle into one small shared helper if necessary; do not duplicate its
dirty-buffer, window, cwd-scope and live-terminal rollback machinery or build a
general provider framework. Keep the existing Commit callback contract intact.

The branch callback accepts an empty list as cancellation and otherwise exactly
one string equal to one captured source row. Reject non-list/non-string,
multiple, malformed, truncated, forged and non-source output before opening.
Use the associated captured tuple rather than parsing an arbitrary accepted
prefix as a ref. Preserve no-print-query/no-expect/no-multi and the existing
normal exit handling. Missing or incompatible dependencies must fail without
download/install prompts; direct branch comparison continues to work.

Candidate Git resolution, tree construction, initial content reads and rendering
must succeed before replacing the old comparison. Failures preserve the old
view, dirty caller/targets, registers and user resources. Retain the existing
creation and selected-view rollback guarantees, including initial and latest
user cd/lcd/tcd scopes, enew/default popup layouts, pre-terminal and FileType
post-live-job faults, and cleanup limited to owned UI/jobs. Do not change global
core fzf state, clear errors or add global autocmd/timer workarounds.

No Git/index/ref/worktree writes, checkout, save, restore, stage or merge are
performed. No new runtime dependency beyond the existing optional core fzf.

## Implementation scope

- Register DiffviewBranch in plugin/main.vim and route through current.vim.
- Add the minimal branch-ref and HEAD snapshot queries in git.vim, using the
  shared Git runner. Preserve existing path, object and read-only validation.
- Reuse tree comparison, projection, rendering, syntax, statistics and gf. A
  small optional source-label/snapshot field is acceptable if needed to retain
  names over Refresh; do not change generic revision semantics to achieve it.
- Update README, Vim help and the existing developer checks. Keep original
  attribution and license. Tests are maintained separately from runtime.
- Do not add merge-base syntax, branch switching/deletion/creation, remote fetch,
  commit preview, custom layouts, async loading or new completion infrastructure.

## Acceptance

1. Retain all existing 41 cases and 25 whole-fixture comparisons. New tests use
   public commands and the existing real dependency setup. Do not weaken the
   existing commit, reading, path-safety, dirty-buffer or rollback assertions.
2. Direct local/remote/full-ref comparison checks actual left/right bytes,
   names and identities; local/remote short-name collision resolves as above.
   A diverged fixture distinguishes direct tree diff from merge-base diff.
   Include same-branch empty, detached, unborn, invalid/tag/revision/option names
   and no-fzf direct operation. Keep required fixture mutations explicit and
   separately accounted for in before/after byte comparisons.
3. Real core fzf plus the actual chosen binary performs name-based selection and
   no match; records local/remote exclusion of symbolic refs, both object formats
   and prefix retention. Real filtered tests are not physical-key PTY evidence.
4. A separately labeled captured-spec boundary test keeps real core wrap/exec,
   intercepts run only, and dispatches via the actual callback contract. Move
   refs/HEAD and cwd before dispatch to verify original repo and both captured
   tips; assert immutable Refresh, labels and prefixes. Reject malformed and
   forged output and simulate read/render failures preserving the old view.
5. Reuse existing picker rollback tests where possible. Exercise branch wiring
   for both default popup and enew, dirty [nohidden, autowrite, autowriteall],
   initial/late tcd, cancellation, initialization throw and owned-live-job
   FileType fault with unrelated user jobs/resources preserved. Do not multiply
   the unchanged lifecycle matrix unnecessarily; preserve the original Commit
   coverage when sharing code.
6. On the frozen final candidate, run the candidate-owned full suite and all
   complete fixture-byte checks. Actual outer PTY covers physical branch-name
   query/Enter, Esc/Ctrl-C, local/remote, both layouts, retained prefixes/labels,
   fixed Refresh, latest cwd scope and dirty/old-view/ordinary-tree protections.
   Read final tester evidence independently before closing the release gate.
7. Review actual code/test delta and publication privacy. Keep fullscan known
   public-SHA heuristic findings distinct from new-history results. Reports,
   session identities and machine-specific evidence paths remain external to
   the public tree/history.

Branch enumeration and Git reads remain synchronous. Performance and support
claims are limited to the environments and input sizes actually exercised.
