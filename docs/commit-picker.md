# Commit search with fzf

## User flow

- `:DiffviewCommit` opens an fzf picker for commits reachable from the current
  repository's `HEAD`, including merged history. Resolve the repository from
  Vim's current working directory, including nested directories.
- Each row shows an abbreviated commit ID, date, author and subject. Typing
  searches these fields. Enter selects one commit; Esc or Ctrl-C cancels.
- Selection opens the existing first-parent-to-commit comparison. Root commits
  retain the empty left side and merge commits retain first-parent semantics.
  NERDTree, source labels and pane keys behave as they do for explicit revisions.
- `:DiffviewCommit {revision}` continues to open that revision directly, without
  fzf. Use `:DiffviewCommit HEAD` for the former no-argument behavior. Existing
  arity/type/revision validation remains in force.

## Dependencies and implementation boundary

The picker requires the core `junegunn/fzf` Vim integration to be loaded and an
`fzf` executable on PATH. It does not require the separate `fzf.vim` plugin.
Missing dependencies report installation guidance and the explicit-HEAD
alternative. Do not download dependencies automatically. Other Diffview commands
and explicit commit revisions do not require fzf.

Use the core `fzf#run`/`fzf#wrap` API and respect its normal layout preferences.
Supply a list generated through the existing direct-argv Git runner, retaining
its read-only/index protections. Avoid shell pipelines containing repository
metadata. No preview command, picker abstraction, new settings or initial-query
argument is needed.

Bind each row to one full SHA-1 or SHA-256 object ID. Escape control characters
in displayed metadata; never interpret a subject/author as shell code, Ex code,
options or a revision. Accept exactly one selected item from the supplied list.
Picker output such as a printed query or an expected key must not become a
commit request, even with user fzf defaults enabled.

Capture the repository before launching fzf. A delayed callback must open the
selected full ID in that same repository, regardless of cwd/ref changes while
the picker runs. Refresh reuses the selected immutable ID and never reopens the
picker; explicit named revisions retain their existing refresh behavior.

## State and error contract

Cancel/no match leaves an existing comparison, caller focus and dirty buffers
intact. Dependency, Git/history, invalid-selection and selected-commit read or
render errors preserve the old usable comparison. Report errors with the normal
`[diffview]` prefix. An unborn/non-Git/bare repository must fail clearly rather
than opening an empty picker. Do not save/discard user buffers, mutate an
ordinary NERDTree, change cwd permanently, or write index/objects/refs/worktree.
The picker's own temporary UI must be cleaned up on selection and cancellation.

## Acceptance

1. Real core fzf and its binary select an older commit by searchable metadata;
   assert actual left/right contents, selected OID/source labels, NERDTree and
   readonly/diff state. Include Unicode and shell/control punctuation metadata.
2. Exercise root and first-parent merge selections and refresh without another
   picker. Selecting by short hash must work; SHA-256 IDs remain accepted.
3. Real selection and Esc/Ctrl-C cancellation in a terminal: search, Enter,
   focus/cleanup, dirty-buffer protection and an existing view remain usable.
   Headless filtered fzf checks do not replace this interactive evidence.
4. Missing plugin/binary, no match, unborn/non-Git/bare repo and failed selected
   comparison preserve the old view. Explicit `HEAD` works without fzf.
5. Verify original-repository/full-ID binding across an asynchronous cwd/ref
   change, and reject malformed or unexpected picker output. A focused API-boundary
   probe may cover callback injection separately from real fzf execution.
6. Retain the existing 28 scenarios and complete fixture byte comparisons with
   real NERDTree and real nerdtree-git-plugin. Backend default-HEAD tests should
   now call `DiffviewCommit HEAD`; picker tests exercise the public no-arg command.
7. README/help explain optional installation, search/selection/cancel,
   explicit-HEAD migration, history scope and refresh semantics. Public files and
   new commit metadata contain no private evidence paths or coordination data.

Git history loading is synchronous and includes all commits reachable from HEAD;
large histories can pause Vim before the picker appears. Other branches' unique
commits, reflogs, history rewriting and file-specific history are outside scope.
