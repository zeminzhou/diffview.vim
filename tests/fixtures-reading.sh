# Sourced by run.sh; every path is inside its disposable fixture directory.
reading="$test_tmp/reading repo"
new_repo "$reading"
mkdir -p "$reading/nav" "$reading/src/deep" "$reading/src2" \
    "$reading/old dir" "$reading/new dir" "$reading/one part" "$reading/two part" "$reading/colon:dir"
printf 'def head():\n    return 1\n' > "$reading/code.py"
printf 'int amount = 1;\n' > "$reading/code.c"
printf '# rename comment\nint amount = 1;\ndef renamed():\n    return 1\n' > "$reading/move.py"
printf 'def navigation_rename():\n    return 17\n' > "$reading/old dir/same.py"
printf 'def historical():\n    return 1\n' > "$reading/historical.py"
printf 'def empty_later():\n    return 1\n' > "$reading/empty.py"
printf 'def not_python():\n    return 1\n' > "$reading/unknown.diffview_unknown"
printf '#!/bin/sh\nprintf HEAD\n' > "$reading/script"
printf '# vim: set tabstop=3:\ndef model():\n    return 1\n' > "$reading/model.py"
printf 'OLD\000binary\n' > "$reading/binary.py"
printf 'forced.py -diff\n' > "$reading/.gitattributes"
printf 'forced HEAD\n' > "$reading/forced.py"
printf 'mode stable\n' > "$reading/mode.txt"
printf 'keep\ndrop\nold\n' > "$reading/stats.txt"
printf 'gone one\ngone two\n' > "$reading/gone.txt"
printf 'return 0' > "$reading/noeol.py"
printf 'HEAD one\nHEAD two\nHEAD three\nHEAD four\nHEAD five\nHEAD six\n' > "$reading/nav/target.py"
printf 'HEAD nonregular\n' > "$reading/nav/nonregular.py"
printf 'HEAD nested\n' > "$reading/src/keep.py"
printf 'HEAD deep\n' > "$reading/src/deep/keep.py"
printf 'HEAD boundary\n' > "$reading/src2/out.py"
printf 'LEFT subtree\n' > "$reading/one part/common.py"
printf 'OLD other subtree\n' > "$reading/two part/common.py"
printf 'LEFT colon subtree\n' > "$reading/colon:dir/common.py"
ln -s code.py "$reading/link.py"
git -C "$reading" add .
git -C "$reading" commit -qm READING_ROOT
git -C "$reading" tag reading-left
printf 'NEXT first subtree\n' > "$reading/one part/common.py"
printf 'RIGHT subtree\n' > "$reading/two part/common.py"
printf 'RIGHT colon subtree\n' > "$reading/colon:dir/common.py"
rm "$reading/historical.py"
git -C "$reading" add -A
git -C "$reading" commit -qm READING_NEXT
git -C "$reading" tag reading-right
GIT_COMMITTER_DATE='2020-01-02T03:04:05Z' git -C "$reading" update-ref --create-reflog \
    -m root refs/heads/reading-clock "$(git -C "$reading" rev-parse reading-left)"
GIT_COMMITTER_DATE='2021-01-02T03:04:05Z' git -C "$reading" update-ref \
    -m next refs/heads/reading-clock "$(git -C "$reading" rev-parse reading-right)"
git -C "$reading" rev-parse reading-left > "$test_tmp/refs/reading-left"
git -C "$reading" rev-parse reading-right > "$test_tmp/refs/reading-right"
git -C "$reading" rev-parse reading-left^{tree} > "$test_tmp/refs/reading-left-tree"
git -C "$reading" rev-parse reading-right^{tree} > "$test_tmp/refs/reading-right-tree"
git -C "$reading" mktree < /dev/null > "$test_tmp/refs/reading-empty-tree"

printf 'def indexed():\n    return 2\n' > "$reading/code.py"
git -C "$reading" add code.py
git -C "$reading" mv move.py move.c
git -C "$reading" mv 'old dir/same.py' 'new dir/same.c'
: > "$reading/empty-added.py"
git -C "$reading" add empty-added.py
printf 'def worktree():\n    return 3\n' > "$reading/code.py"
printf 'int amount = 2;\n' > "$reading/code.c"
: > "$reading/empty.py"
printf 'def still_unknown():\n    return 2\n' > "$reading/unknown.diffview_unknown"
printf '#!/usr/bin/python3\ndef launch():\n    return 2\n' > "$reading/script"
printf '# vim: set tabstop=3:\ndef model():\n    return 2\n' > "$reading/model.py"
printf 'NEW\000binary\n' > "$reading/binary.py"
printf 'forced DISK\n' > "$reading/forced.py"
chmod +x "$reading/mode.txt"
printf 'keep\nfresh\nnew\nextra\n' > "$reading/stats.txt"
rm "$reading/gone.txt"
printf 'return 1' > "$reading/noeol.py"
printf 'CURRENT first\nCURRENT second\n' > "$reading/nav/target.py"
rm "$reading/nav/nonregular.py"
mkdir "$reading/nav/nonregular.py"
printf 'DIRECTORY child\n' > "$reading/nav/nonregular.py/child"
printf 'DISK nested\n' > "$reading/src/keep.py"
printf 'DISK deep\n' > "$reading/src/deep/keep.py"
printf 'DISK boundary\n' > "$reading/src2/out.py"
printf 'ONE current\n' > "$reading/one part/common.py"
printf 'TWO current\n' > "$reading/two part/common.py"
printf 'COLON current\n' > "$reading/colon:dir/common.py"
printf 'OLDPATH current\n' > "$reading/old dir/same.py"
printf 'untracked unknown\n' > "$reading/new.py"
rm "$reading/link.py"
ln -s code.c "$reading/link.py"

# Independent Git output is the count oracle, not hand-counted snapshot lines.
git --no-optional-locks -c diff.autoRefreshIndex=false -C "$reading" \
    diff --cached --numstat -z > "$test_tmp/reading-staged.numstat"
git --no-optional-locks -c diff.autoRefreshIndex=false -C "$reading" \
    diff --numstat -z > "$test_tmp/reading-unstaged.numstat"
git --no-optional-locks -c diff.autoRefreshIndex=false -C "$reading" \
    diff --numstat -z reading-left reading-right > "$test_tmp/reading-history.numstat"
git --no-optional-locks -c diff.autoRefreshIndex=false -C "$reading" \
    diff --numstat -z "$(cat "$test_tmp/refs/reading-empty-tree")" reading-left \
    > "$test_tmp/reading-root.numstat"
git -C "$reading" diff --cached --name-status > "$test_tmp/reading-renames.control"
test "$(git -C "$reading" show :code.py | head -n 1)" = 'def indexed():'
test "$(git -C "$reading" show reading-left:historical.py | head -n 1)" = 'def historical():'
test "$(git -C "$reading" diff --numstat -- stats.txt)" = "$(printf '3\t2\tstats.txt')"
test "$(git -C "$reading" diff --numstat -- mode.txt)" = "$(printf '0\t0\tmode.txt')"
test "$(git -C "$reading" diff --numstat -- forced.py)" = "$(printf '%s\t%s\tforced.py' - -)"
test ! -e "$reading/historical.py"
test "$(git -C "$reading" rev-parse 'reading-clock@{2020-06-01T00:00:00Z}')" = \
    "$(cat "$test_tmp/refs/reading-left")"
mkdir "$test_tmp/reading-outside"
printf 'OUTSIDE navigation marker\n' > "$test_tmp/reading-outside/target.py"
cp -R "$reading" "$test_tmp/reading-before"
cp -R "$test_tmp/reading-outside" "$test_tmp/reading-outside-before"
