#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
runtime=${DIFFVIEW_TEST_RUNTIME:-$root}
if [ -z "${NERDTREE_RUNTIME:-}" ] || [ ! -f "$NERDTREE_RUNTIME/plugin/NERD_tree.vim" ]; then
    printf 'NERDTree is required: set NERDTREE_RUNTIME to its external checkout (see tests/README.md).\n' >&2
    exit 1
fi
if [ -n "${NERDTREE_GIT_RUNTIME:-}" ] && [ ! -f "$NERDTREE_GIT_RUNTIME/nerdtree_plugin/git_status.vim" ]; then
    printf 'Invalid NERDTREE_GIT_RUNTIME: expected an external nerdtree-git-plugin checkout.\n' >&2
    exit 1
fi
if [ -z "${FZF_RUNTIME:-}" ] || [ ! -f "$FZF_RUNTIME/plugin/fzf.vim" ]; then
    printf 'Real core fzf is required for picker tests: set FZF_RUNTIME to its external checkout.\n' >&2
    exit 1
fi
if ! command -v fzf > /dev/null 2>&1; then
    printf 'Picker integration tests require the real fzf executable on PATH.\n' >&2
    exit 1
fi
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
unset FZF_DEFAULT_OPTS FZF_DEFAULT_OPTS_FILE FZF_DEFAULT_COMMAND
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 GIT_OPTIONAL_LOCKS=0
export GIT_ATTR_NOSYSTEM=1
export GIT_AUTHOR_NAME=Tester GIT_AUTHOR_EMAIL=tester@example.invalid
export GIT_COMMITTER_NAME=Tester GIT_COMMITTER_EMAIL=tester@example.invalid
export GIT_TERMINAL_PROMPT=0
export DIFFVIEW_TEST_TMP="$test_tmp" DIFFVIEW_TEST_RUNTIME="$runtime" NERDTREE_RUNTIME FZF_RUNTIME

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
. "$root/tests/fixtures-nerdtree.sh"
. "$root/tests/fixtures-picker.sh"

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
printf 'Core fzf: '
git -C "$FZF_RUNTIME" rev-parse HEAD
git -C "$FZF_RUNTIME" status --short -- plugin
printf 'PATH fzf: '
fzf --version
printf 'NERDTree: '
git -C "$NERDTREE_RUNTIME" rev-parse HEAD
git -C "$NERDTREE_RUNTIME" status --short -- plugin autoload lib nerdtree_plugin syntax
if [ -n "${NERDTREE_GIT_RUNTIME:-}" ]; then
    export NERDTREE_GIT_RUNTIME
    printf 'nerdtree-git-plugin: '
    git -C "$NERDTREE_GIT_RUNTIME" rev-parse HEAD
fi
printf 'Stale-stat index before: '
cksum "$test_tmp/clean/.git/index"

# Do not lend the product our fixture-construction safety settings.
unset GIT_OPTIONAL_LOCKS
export DIFFVIEW_TEST_REAL_GIT="$(command -v git)"
export DIFFVIEW_TEST_GIT_LOG="$test_tmp/product-git.argv"
: > "$DIFFVIEW_TEST_GIT_LOG"
mkdir "$test_tmp/git-bin"
mkdir "$test_tmp/no-fzf-bin"
ln -s "$DIFFVIEW_TEST_REAL_GIT" "$test_tmp/no-fzf-bin/git"
ln -s /bin/sh "$test_tmp/no-fzf-bin/sh"
mkdir -p "$test_tmp/old-fzf-core/plugin" "$test_tmp/old-fzf-bin"
# Unmodified real core without a bundled binary; never touch the user's checkout.
cp "$FZF_RUNTIME/plugin/fzf.vim" "$test_tmp/old-fzf-core/plugin/fzf.vim"
cat > "$test_tmp/old-fzf-bin/fzf" <<'EOF'
#!/bin/sh
if [ "${1:-}" = --version ]; then
    printf 'version\n' >> "$DIFFVIEW_TEST_TMP/picker-old-version.calls"
    printf '0.1.0 fixture\n'
    exit 0
fi
printf 'unexpected picker execution\n' > "$DIFFVIEW_TEST_TMP/picker-old-executed"
exit 86
EOF
cat > "$test_tmp/old-fzf-core/install" <<'EOF'
#!/bin/sh
printf 'unexpected installer execution\n' > "$DIFFVIEW_TEST_TMP/picker-old-install"
exit 86
EOF
chmod +x "$test_tmp/old-fzf-bin/fzf" "$test_tmp/old-fzf-core/install"
cat > "$test_tmp/git-bin/git" <<'EOF'
#!/bin/sh
printf '%s\000' "$@" >> "$DIFFVIEW_TEST_GIT_LOG"
printf '\n' >> "$DIFFVIEW_TEST_GIT_LOG"
if [ "${DIFFVIEW_TEST_FAIL_LOG:-0}" = 1 ]; then
    for argument do
        if [ "$argument" = log ]; then
            printf 'fixture history read failure\n' >&2
            exit 1
        fi
    done
fi
exec "$DIFFVIEW_TEST_REAL_GIT" "$@"
EOF
chmod +x "$test_tmp/git-bin/git"
export PATH="$test_tmp/git-bin:$PATH"
suite_failed=0
test_cases='local clean unborn nonrepo special refresh lifecycle ownership ancestor
    trees commits historical_refresh errors exclusions edges cross_tab read_failure navigation
    binary_clean binary_mixed large empty_start tree_nodes tree_history tree_isolation dependency tree_rollback
    picker_real picker_no_match picker_enew picker_async picker_sha256 picker_missing picker_old_binary picker_errors picker_api'
if [ -n "${NERDTREE_GIT_RUNTIME:-}" ]; then
    test_cases="$test_cases tree_git"
else
    printf 'NOT RUN: tree_git (set NERDTREE_GIT_RUNTIME for the full coexistence check)\n'
fi
for test_case in $test_cases; do
    export DIFFVIEW_TEST_CASE="$test_case"
    if "${VIM:-vim}" -Nu NONE -U NONE -i NONE -n -es \
        -V1"$test_tmp/$test_case.vim.log" -S "$root/tests/acceptance.vim" \
        > "$test_tmp/$test_case.stdout" 2>&1 && [ -f "$test_tmp/$test_case.result" ]; then
        cat "$test_tmp/$test_case.result"
        if [ "$test_case" = large ]; then
            cat "$test_tmp/large.metrics.json"
        fi
        if [ "$test_case" = picker_real ]; then
            cat "$test_tmp/picker-real.facts.json"
        fi
        if [ "$test_case" = picker_enew ]; then
            cat "$test_tmp/picker-enew.facts.json"
        fi
        if [ "$test_case" = picker_async ]; then
            cat "$test_tmp/picker-async.facts.json"
        fi
    else
        if [ ! -f "$test_tmp/$test_case.result" ]; then
            printf 'FAIL: %s (no completion receipt from Vim)\n' "$test_case" >&2
        fi
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
for fixture in 'history repo 中文' edges cross-tab read-failure bare.git shallow large binary-clean binary-mixed \
    'tree repo' tree-history user-tree 'picker repo 中文' picker-sha256 picker-elsewhere; do
    diff -r "$test_tmp/$fixture-before" "$test_tmp/$fixture"
done
printf 'Stale-stat index after: '
cksum "$test_tmp/clean/.git/index"
if [ "$suite_failed" -ne 0 ]; then
    exit 1
fi
printf 'PASS: fixture disk, index and object bytes unchanged\n'
