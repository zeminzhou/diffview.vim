# Sourced after existing fixtures; new_repo still supplies config/hook isolation.
branch_punctuation='feature/$(touch${IFS}BRANCH_INJECTED)|quote'
printf '%s\n' "$branch_punctuation" > "$test_tmp/refs/branch-punctuation"
branch_graph() {
    branch_fixture="$1"
    branch_ref_prefix="$2"
    mkdir -p "$branch_fixture/src"
    printf 'BASE shared\n' > "$branch_fixture/shared.txt"
    printf 'BASE src\n' > "$branch_fixture/src/choice.txt"
    git -C "$branch_fixture" add .
    git -C "$branch_fixture" commit -qm BR_ROOT
    git -C "$branch_fixture" rev-parse HEAD > "$test_tmp/refs/$branch_ref_prefix-root"
    git -C "$branch_fixture" checkout -qb BR_LOCAL_PICK
    printf 'TARGET shared\n' > "$branch_fixture/shared.txt"
    printf 'TARGET src\n' > "$branch_fixture/src/choice.txt"
    printf 'TARGET only\n' > "$branch_fixture/target-only.txt"
    git -C "$branch_fixture" add .
    git -C "$branch_fixture" commit -qm BR_TARGET
    git -C "$branch_fixture" rev-parse HEAD > "$test_tmp/refs/$branch_ref_prefix-target"
    git -C "$branch_fixture" branch alias-target
    git -C "$branch_fixture" branch origin/collision
    git -C "$branch_fixture" check-ref-format --branch "$branch_punctuation" > /dev/null
    git -C "$branch_fixture" branch "$branch_punctuation"
    git -C "$branch_fixture" tag BR_TAG_NOT_BRANCH
    git -C "$branch_fixture" checkout -q main
    printf 'MAIN shared\n' > "$branch_fixture/shared.txt"
    printf 'MAIN src\n' > "$branch_fixture/src/choice.txt"
    printf 'MAIN only\n' > "$branch_fixture/current-only.txt"
    git -C "$branch_fixture" add .
    git -C "$branch_fixture" commit -qm BR_CURRENT
    git -C "$branch_fixture" rev-parse HEAD > "$test_tmp/refs/$branch_ref_prefix-head"
    git -C "$branch_fixture" update-ref refs/remotes/origin/BR_REMOTE_PICK \
        "$(cat "$test_tmp/refs/$branch_ref_prefix-target")"
    git -C "$branch_fixture" update-ref refs/remotes/origin/collision \
        "$(cat "$test_tmp/refs/$branch_ref_prefix-root")"
    git -C "$branch_fixture" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/collision
    git -C "$branch_fixture" symbolic-ref refs/heads/BR_LOCAL_ALIAS refs/heads/BR_LOCAL_PICK
    git -C "$branch_fixture" for-each-ref --format='%(refname)%09%(objectname)%09%(symref)' \
        refs/heads/ refs/remotes/ > "$test_tmp/$branch_ref_prefix-refs.oracle"
    test "$(wc -l < "$test_tmp/$branch_ref_prefix-refs.oracle")" -eq 9
    test "$(git -C "$branch_fixture" merge-base BR_LOCAL_PICK main)" = \
        "$(cat "$test_tmp/refs/$branch_ref_prefix-root")"
    git -C "$branch_fixture" diff --name-only BR_LOCAL_PICK main > "$test_tmp/$branch_ref_prefix-direct.oracle"
    git -C "$branch_fixture" diff --name-only BR_LOCAL_PICK...main > "$test_tmp/$branch_ref_prefix-mergebase.oracle"
    test "$(wc -l < "$test_tmp/$branch_ref_prefix-direct.oracle")" -eq 4
    test "$(wc -l < "$test_tmp/$branch_ref_prefix-mergebase.oracle")" -eq 3
    printf 'INDEX branch dirt\n' > "$branch_fixture/shared.txt"
    git -C "$branch_fixture" add shared.txt
    printf 'DISK branch dirt\n' > "$branch_fixture/shared.txt"
    printf 'DISK src dirt\n' > "$branch_fixture/src/choice.txt"
    printf 'LOCAL untracked\n' > "$branch_fixture/local-only.txt"
    cp -R "$branch_fixture" "$branch_fixture-before"
}

GIT_DEFAULT_HASH=sha1 new_repo "$test_tmp/branch repo"
branch_graph "$test_tmp/branch repo" branch
test "$(git -C "$test_tmp/branch repo" rev-parse --show-object-format)" = sha1
GIT_DEFAULT_HASH=sha256 new_repo "$test_tmp/branch-sha256"
branch_graph "$test_tmp/branch-sha256" branch256
test "$(git -C "$test_tmp/branch-sha256" rev-parse --show-object-format)" = sha256
