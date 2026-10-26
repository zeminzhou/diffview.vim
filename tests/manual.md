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
| Set an expression register and a search pattern before open/fold/refresh/close, inspect their raw values afterwards | `=`, search, unnamed, numbered and named register contents/types remain; inspecting `=` does not evaluate it |
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
Repeat terminal checks for each delivered candidate; earlier flat-panel
observations do not verify this UI.
The headless `large` case separately measures a 20,000-line file and 201-file
list, including open, select, refresh and close durations. It checks full content
and reports measurements; no latency target is invented. Review the measured
limits when deciding whether the first version is responsive enough.

For commit-picker acceptance, load the external core fzf plugin in this same
terminal Vim with `FZF_RUNTIME` on runtimepath and `runtime plugin/fzf.vim`.
Install its executable separately and record both PATH's version and the binary
selected by `fzf#exec()`. Leave `FZF_DEFAULT_OPTS` free of `--filter`: an automatic
filtered selection does not exercise interactive search or cancellation.
Prepare older, root and merge commits with distinct contents and searchable
author/subject metadata; preserve complete repository bytes before browsing.

| Picker step | Expected |
| --- | --- |
| Set nohidden/autowriteall, retain a dirty file buffer and an existing comparison, then DiffviewCommit | Real searchable picker opens in the preferred core layout with no extra Enter; original bytes remain unsaved |
| Type an older subject or author, then Enter; repeat using an abbreviated hash | Exactly that commit opens with correct parent/root/first-parent bodies, full object identity and source labels; tree keys remain usable |
| Refresh the selected comparison | Same immutable commit remains selected without opening another picker |
| From the dirty caller and from a comparison pane, reopen and press Esc; repeat with Ctrl-C | Picker UI disappears; caller focus, old comparison, dirty contents/modified flag, registers and ordinary tree survive |
| Search for an absent string, then cancel | No comparison replacement or empty view; subsequent selection still works |
| Repeat selection/cancellation with g:fzf_layout set to {window: 'enew'} | Respect the in-place layout without autosaving; restore hidden/autowrite/autowriteall and original dirty buffer |
| While the enew picker runs, change the caller's tab directory with tcd to another disposable repository, then resume input and select the older commit | Keep the new user path and tab-local scope=2, while selected contents/full OID remain bound to the original repository; Refresh does not reopen the picker |
| Close/reopen, use pane/tree mappings and return to the ordinary tree | No orphan terminal/window/buffer; both interfaces remain usable |

Record each actual selection and cancellation, dimensions, focus/layout and
prompt observations outside the repository. Compare every original repository
file, index, object and ref after restoring only declared fixture mutations.
Report missing terminal coverage explicitly rather than inferring it from the
filtered cases or the callback-injection fixture.

For reading/navigation acceptance, enable the user's normal syntax setting and
prepare tracked Python/C files, a cross-extension rename, a deleted historical
file, a known subtree pair and disk/loaded/unsaved contents that differ. Retain
the complete before-image and record the same frozen candidate for these steps:

| Reading step | Expected |
| --- | --- |
| Select Python/C and each side of the cross-extension rename; inspect visible tokens, then disable syntax and refresh | Native syntax follows each logical name/content while filetype remains diffview; syntax-off stays plain and snapshots remain readonly |
| Move from a known language to unknown, empty, binary or no-match content | No old language tokens or source/path labels remain on explanation/empty panes |
| From left/right panes move to a known line and press gf; from a tree leaf and an unrelated window use gf/DiffviewGotoFile | One adjacent ordinary tab opens the correct oldpath/destination with a clamped numeric hint; normal filetype behavior and native tab return work |
| Keep both caller and an already-loaded target dirty under nohidden/autowrite/autowriteall, then navigate and close Diffview | Reuse target edits without reload or saves; caller/options/registers remain and the user tab/buffer survives Close |
| Open with -- prefixes, change DiffviewFilter, clear it, filter a rename's old/new name and literal special paths | Segment-aware OR matching retains raw identities, duplicate staged/unstaged entries and the existing selected snapshot; counts/flags/header rows follow the visible projection |
| Filter to no match, clear, refresh after cwd changes and invoke native NERDTreeRender | No matching changes differs from No changes; source/syntax clear and recover correctly; the visible screen row selects the exact raw node |
| Use gf/filter/clear/return/r/q, then run the commit picker in both default popup and enew layouts | Tree and pane keys remain usable; picker search/Enter/Esc/Ctrl-C retains prefixes/full OID/root/dirty state and leaves no extra UI or Enter prompt |

Record actual syntax colors/tokens, paths, line numbers, summary/leaf counts,
focus, return/close behavior and complete fixture comparisons. Headless token
assertions and callback boundaries do not substitute for this terminal evidence.
