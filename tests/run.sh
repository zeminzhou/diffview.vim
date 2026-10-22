#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
runtime=${DIFFVIEW_TEST_RUNTIME:-$root}
test_tmp=$(mktemp -d "${TMPDIR:-/tmp}/diffview-tests.XXXXXX")
finish() {
    result=$?
    if [ "$result" -eq 0 ]; then
        rm -rf "$test_tmp"
    else
        printf 'FAIL: fixtures and logs retained at %s\n' "$test_tmp" >&2
    fi
}
trap finish EXIT
trap 'exit 130' INT TERM

unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY
unset GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_CONFIG_PARAMETERS GIT_CONFIG_COUNT
unset GIT_LITERAL_PATHSPECS GIT_GLOB_PATHSPECS GIT_NOGLOB_PATHSPECS GIT_ICASE_PATHSPECS
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 GIT_OPTIONAL_LOCKS=0
export GIT_ATTR_NOSYSTEM=1
export GIT_AUTHOR_NAME=Tester GIT_AUTHOR_EMAIL=tester@example.invalid
export GIT_COMMITTER_NAME=Tester GIT_COMMITTER_EMAIL=tester@example.invalid
export GIT_TERMINAL_PROMPT=0
export DIFFVIEW_TEST_TMP="$test_tmp" DIFFVIEW_TEST_RUNTIME="$runtime"

new_repo() {
    mkdir -p "$1"
    git -C "$1" init -q -b main
    git -C "$1" config core.hooksPath /dev/null
    git -C "$1" config core.autocrlf false
    git -C "$1" config core.filemode true
    git -C "$1" config core.attributesFile /dev/null
    git -C "$1" config core.excludesFile /dev/null
    git -C "$1" config commit.gpgsign false
}

repo="$test_tmp/local repo 中文"
new_repo "$repo"
mkdir -p "$repo/nested/subdir"
printf 'HEAD both\n' > "$repo/both.txt"
printf 'HEAD staged\n' > "$repo/staged.txt"
printf 'HEAD unstaged\n' > "$repo/unstaged.txt"
printf 'unchanged stale stat\n' > "$repo/same.txt"
printf 'same mode bytes\n' > "$repo/mode.txt"
printf 'ignored.txt\n' > "$repo/.gitignore"
git -C "$repo" add .
git -C "$repo" commit -qm initial
printf 'INDEX both\n' > "$repo/both.txt"
printf 'INDEX staged\n' > "$repo/staged.txt"
git -C "$repo" add both.txt staged.txt
printf 'DISK both\n' > "$repo/both.txt"
printf 'DISK unstaged\n' > "$repo/unstaged.txt"
printf 'DISK untracked\n' > "$repo/untracked 空格.txt"
printf 'DO NOT LIST\n' > "$repo/ignored.txt"
touch -t 202001010000 "$repo/same.txt"
chmod +x "$repo/mode.txt"

new_repo "$test_tmp/clean"
printf 'unchanged\n' > "$test_tmp/clean/file.txt"
git -C "$test_tmp/clean" add .
git -C "$test_tmp/clean" commit -qm initial
# Stale stat metadata with identical bytes must not refresh/write the index.
touch -t 202001010000 "$test_tmp/clean/file.txt"
cp -R "$test_tmp/clean" "$test_tmp/stat-probe"
GIT_OPTIONAL_LOCKS=1 git -C "$test_tmp/stat-probe" status --porcelain > "$test_tmp/stat-probe.status"
test ! -s "$test_tmp/stat-probe.status"
if cmp -s "$test_tmp/clean/.git/index" "$test_tmp/stat-probe/.git/index"; then
    printf 'Invalid fixture: default git status did not refresh stale index\n' >&2
    exit 1
fi
rm -rf "$test_tmp/stat-probe"

new_repo "$test_tmp/unborn"
printf 'INDEX unborn\n' > "$test_tmp/unborn/first.txt"
git -C "$test_tmp/unborn" add first.txt
printf 'DISK unborn\n' > "$test_tmp/unborn/first.txt"
printf 'DISK new\n' > "$test_tmp/unborn/new.txt"
mkdir "$test_tmp/nonrepo"

special="$test_tmp/special"
new_repo "$special"
tab_path=$(printf 'tab\tname.txt')
newline_path=$(printf 'line\nname.txt')
soh_path=$(printf 'ctrl\001name.txt')
special_files() {
    counter=0
    for path in 'space 中文.txt' '-leading.txt' 'semi;$(touch INJECTED)|quote'"'"'".txt' "$tab_path" "$newline_path" "$soh_path" 'literal\n.txt' ':(glob)**'; do
        counter=$((counter + 1))
        printf '%s special %s\n' "$1" "$counter" > "$special/$path"
    done
}
special_files HEAD
git -C "$special" add .
git -C "$special" commit -qm initial
special_files INDEX
git -C "$special" add .
special_files DISK

new_repo "$test_tmp/refresh"
printf 'HEAD refresh\n' > "$test_tmp/refresh/file.txt"
git -C "$test_tmp/refresh" add .
git -C "$test_tmp/refresh" commit -qm initial
printf 'DISK before refresh\n' > "$test_tmp/refresh/file.txt"

new_repo "$test_tmp/lifecycle"
printf 'DISK original\n' > "$test_tmp/lifecycle/original.txt"
printf 'DISK replacement\n' > "$test_tmp/lifecycle/replacement.txt"
git -C "$test_tmp/lifecycle" add .
git -C "$test_tmp/lifecycle" commit -qm initial
printf 'DISK tracked change\n' > "$test_tmp/lifecycle/change.txt"

new_repo "$test_tmp/ancestor"
mkdir "$test_tmp/ancestor/dir" "$test_tmp/outside"
printf 'HEAD inside\n' > "$test_tmp/ancestor/dir/file.txt"
printf 'HEAD forced inside\n' > "$test_tmp/ancestor/dir/forced.dat"
printf 'dir/forced.dat -diff\n' > "$test_tmp/ancestor/.gitattributes"
git -C "$test_tmp/ancestor" add .
git -C "$test_tmp/ancestor" commit -qm initial
printf 'DISK inside\n' > "$test_tmp/ancestor/dir/file.txt"
printf 'DISK forced inside\n' > "$test_tmp/ancestor/dir/forced.dat"
printf 'OUTSIDE fixture marker\n' > "$test_tmp/outside/file.txt"
printf 'OUTSIDE fixture marker\n' > "$test_tmp/outside/forced.dat"

. "$root/tests/fixtures-c02.sh"

# Compare all fixture bytes, including indexes/objects, after Vim exits.
cp -R "$test_tmp/local repo 中文" "$test_tmp/local-before"
cp -R "$test_tmp/clean" "$test_tmp/clean-before"
cp -R "$test_tmp/unborn" "$test_tmp/unborn-before"
cp -R "$special" "$test_tmp/special-before"
cp -R "$test_tmp/lifecycle" "$test_tmp/lifecycle-before"
cp -R "$test_tmp/ancestor" "$test_tmp/ancestor-before"
cp -R "$test_tmp/outside" "$test_tmp/outside-before"
cp -R "$test_tmp/refresh" "$test_tmp/refresh-expected"
# The refresh test itself makes these two explicit fixture edits.
printf 'DISK refreshed\n' > "$test_tmp/refresh-expected/file.txt"
printf 'NEW after open\n' > "$test_tmp/refresh-expected/new.txt"

printf 'Runtime: %s\nCandidate: ' "$runtime"
git -C "$runtime" rev-parse HEAD
git -C "$runtime" status --short -- plugin autoload
"${VIM:-vim}" --version | sed -n '1,4p'
git --version
printf 'Stale-stat index before: '
cksum "$test_tmp/clean/.git/index"

# Do not lend the product our fixture-construction safety settings.
unset GIT_OPTIONAL_LOCKS
suite_failed=0
for test_case in local clean unborn nonrepo special refresh lifecycle ownership ancestor \
    trees commits historical_refresh errors exclusions edges cross_tab read_failure navigation \
    binary_clean binary_mixed large; do
    export DIFFVIEW_TEST_CASE="$test_case"
    if "${VIM:-vim}" -Nu NONE -U NONE -i NONE -n -es \
        -V1"$test_tmp/$test_case.vim.log" -S "$root/tests/acceptance.vim" \
        > "$test_tmp/$test_case.stdout" 2>&1; then
        cat "$test_tmp/$test_case.result"
        if [ "$test_case" = large ]; then
            cat "$test_tmp/large.metrics.json"
        fi
    else
        cat "$test_tmp/$test_case.errors" "$test_tmp/$test_case.stdout" 2>/dev/null || true
        suite_failed=1
    fi
done

diff -r "$test_tmp/local-before" "$test_tmp/local repo 中文"
diff -r "$test_tmp/clean-before" "$test_tmp/clean"
diff -r "$test_tmp/unborn-before" "$test_tmp/unborn"
diff -r "$test_tmp/special-before" "$special"
diff -r "$test_tmp/lifecycle-before" "$test_tmp/lifecycle"
diff -r "$test_tmp/ancestor-before" "$test_tmp/ancestor"
diff -r "$test_tmp/outside-before" "$test_tmp/outside"
diff -r "$test_tmp/refresh-expected" "$test_tmp/refresh"
for fixture in 'history repo 中文' edges cross-tab read-failure bare.git shallow large binary-clean binary-mixed; do
    diff -r "$test_tmp/$fixture-before" "$test_tmp/$fixture"
done
printf 'Stale-stat index after: '
cksum "$test_tmp/clean/.git/index"
if [ "$suite_failed" -ne 0 ]; then
    exit 1
fi
printf 'PASS: fixture disk, index and object bytes unchanged\n'
