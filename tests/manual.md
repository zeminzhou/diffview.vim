# Terminal smoke checklist

Use a real terminal against the checkout being tested. Record the commit,
Vim/Git versions, terminal dimensions and observed results when running it.

Prepare a disposable repository and external evidence directory in a shell:

```sh
manual_repo=$(mktemp -d /tmp/diffview-manual.XXXXXX)
manual_evidence=$(mktemp -d /tmp/diffview-manual-evidence.XXXXXX)
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
unset GIT_OPTIONAL_LOCKS
git -C "$manual_repo" init -q -b main
git -C "$manual_repo" config user.name Tester
git -C "$manual_repo" config user.email tester@example.invalid
git -C "$manual_repo" config core.hooksPath /dev/null
git -C "$manual_repo" config commit.gpgsign false
awk 'BEGIN { for (i = 1; i <= 30; i++) print "HEAD line " i }' > "$manual_repo/file.txt"
git -C "$manual_repo" add .
git -C "$manual_repo" commit -qm root
awk 'NR == 3 { print "INDEX three"; next } NR == 25 { print "INDEX twenty-five"; next } { print }' \
  "$manual_repo/file.txt" > "$manual_evidence/staged.txt"
cp "$manual_evidence/staged.txt" "$manual_repo/file.txt"
git -C "$manual_repo" add file.txt
awk 'NR == 15 { print "DISK fifteen"; next } { print }' \
  "$manual_repo/file.txt" > "$manual_evidence/disk.txt"
cp "$manual_evidence/disk.txt" "$manual_repo/file.txt"
printf 'untracked text\n' > "$manual_repo/new.txt"
cp "$manual_repo/.git/index" "$manual_evidence/index"
```

Point `DIFFVIEW_TEST_RUNTIME` at the checkout being tested,
verify its SHA, then start a real terminal Vim from the disposable repository:

```sh
export DIFFVIEW_TEST_RUNTIME
export NERDTREE_RUNTIME
git -C "$DIFFVIEW_TEST_RUNTIME" rev-parse HEAD
git -C "$NERDTREE_RUNTIME" rev-parse HEAD
cd "$manual_repo"
vim -Nu NONE -U NONE -i NONE -n \
  --cmd 'execute "set runtimepath^=" . fnameescape($NERDTREE_RUNTIME)' \
  --cmd 'execute "set runtimepath^=" . fnameescape($DIFFVIEW_TEST_RUNTIME)' \
  -c 'runtime plugin/NERD_tree.vim' \
  -c 'runtime plugin/main.vim'
```

| Step | Expected |
| --- | --- |
| In a fresh Vim with an empty unnamed buffer and no alternate file, run DiffviewOpen directly | The real tree opens without E194, preparatory edits or an extra Enter prompt |
| Edit file.txt, append an unsaved line, create a split, then DiffviewOpen | One dedicated three-pane tab; real NERDTree focused without extra Enter; readable section/source/path labels and unsaved exclusion notice; original tab/split retained |
| j/k over sections/directories/files, Enter and o | Directories toggle; files retain tree focus; staged HEAD→INDEX differs from unstaged INDEX→disk; unsaved text absent; node flags and descendant indicators are visible |
| Collapse a directory, then ]f/[f; Tab/Shift-Tab | Next/previous reveal nodes by expanding ancestors; wrapping and pane focus work; left/right direction stays correct |
| Expand one directory and collapse another, then r | Selection and surviving expansion state remain; flags and selected content update together |
| In staged diff panes use ]c/[c | Native hunk navigation moves between line 3 and line 25 changes |
| r, q, reopen, then manually close a content pane/tab | Refresh/close usable; no orphan scratch panes; origin and unsaved contents survive |
| DiffviewOpen HEAD HEAD, then DiffviewCommit HEAD | Empty comparison stays usable; root commit uses EMPTY on left, HEAD/object identity on right |
| Compare trees containing deleted paths and a file↔directory replacement | Missing historical paths and every collision entry remain selectable, subtree names are comparison-relative, no disk placeholders appear |
| Keep an ordinary tree open and mirrored in another tab, then open/refresh/close Diffview | Original tree root, expansion, cursor, maps, flags and options remain; ordinary NERDTree actions still work afterwards |
| Repeat with nerdtree-git-plugin and nondefault NERDTree display settings | Local status callbacks cannot replace comparison flags or redirect selection; no extra panes or writes |
| Return to original buffer, inspect modified state; quit without saving | Original unsaved content remains modified; browsing has not saved it |

After Vim exits, compare the evidence bytes:

```sh
cmp "$manual_evidence/index" "$manual_repo/.git/index"
cmp "$manual_evidence/disk.txt" "$manual_repo/file.txt"
```

Record actual outcomes and evidence paths outside the repository, including
product/test/dependency SHAs and whether the git-status coexistence case ran.
NERDTree terminal results await a frozen implementation; earlier flat-panel
observations do not verify this UI.
The headless `large` case separately measures a 20,000-line file and 201-file
list, including open, select, refresh and close durations. It checks full content
and reports measurements; no latency target is invented. Review the measured
limits when deciding whether the first version is responsive enough.
