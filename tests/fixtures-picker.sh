# Sourced by run.sh; history metadata and all mutations stay in disposable repos.
picker_history() {
    picker_repo=$1
    picker_ref=$2
    mkdir -p "$picker_repo/nested"
    printf 'PICK ROOT\n' > "$picker_repo/change.txt"
    printf 'PICK stable\n' > "$picker_repo/stable.txt"
    git -C "$picker_repo" add .
    GIT_AUTHOR_NAME='ROOT_AUTHOR_NEEDLE' GIT_AUTHOR_DATE='2020-01-02T03:04:05Z' \
        GIT_COMMITTER_DATE='2020-01-02T03:04:05Z' git -C "$picker_repo" commit -qm 'PICK_ROOT Unicode 中文'
    git -C "$picker_repo" tag pick-root
    git -C "$picker_repo" rev-parse HEAD > "$test_tmp/refs/$picker_ref-root"
    git -C "$picker_repo" switch -qc side
    printf 'PICK SIDE\n' > "$picker_repo/side.txt"
    git -C "$picker_repo" add .
    GIT_AUTHOR_DATE='2022-02-03T04:05:06Z' GIT_COMMITTER_DATE='2022-02-03T04:05:06Z' \
        git -C "$picker_repo" commit -qm 'PICK_SIDE merged reachability'
    git -C "$picker_repo" rev-parse HEAD > "$test_tmp/refs/$picker_ref-side"
    git -C "$picker_repo" switch -q main
    printf 'PICK OLDER\n' > "$picker_repo/change.txt"
    git -C "$picker_repo" add .
    printf 'PICK_OLDER 中文 TABBEFORE\tTABAFTER ctrl\001bell\007esc\033 quote '\''" ; $(touch FZF_INJECTED) |\n\nFixture body.\n' \
        > "$test_tmp/picker-message"
    GIT_AUTHOR_NAME='META_AUTHOR_NEEDLE 中文 $(touch FZF_AUTHOR_INJECTED)' \
        GIT_AUTHOR_DATE='2023-03-04T05:06:07Z' GIT_COMMITTER_DATE='2023-03-04T05:06:07Z' \
        git -C "$picker_repo" commit -qF "$test_tmp/picker-message"
    git -C "$picker_repo" rev-parse HEAD > "$test_tmp/refs/$picker_ref-older"
    printf 'PICK NORMAL\n' > "$picker_repo/change.txt"
    git -C "$picker_repo" add .
    GIT_AUTHOR_DATE='2021-05-06T07:08:09Z' GIT_COMMITTER_DATE='2021-05-06T07:08:09Z' \
        git -C "$picker_repo" commit -qm 'PICK_NORMAL ordinary commit'
    git -C "$picker_repo" rev-parse HEAD > "$test_tmp/refs/$picker_ref-normal"
    GIT_AUTHOR_DATE='2024-04-05T06:07:08Z' GIT_COMMITTER_DATE='2024-04-05T06:07:08Z' \
        git -C "$picker_repo" merge -q --no-ff side -m 'PICK_MERGE first parent'
    git -C "$picker_repo" rev-parse HEAD > "$test_tmp/refs/$picker_ref-merge"
    test "$(git -C "$picker_repo" rev-parse HEAD^1)" = "$(cat "$test_tmp/refs/$picker_ref-normal")"
    test "$(git -C "$picker_repo" rev-parse HEAD^2)" = "$(cat "$test_tmp/refs/$picker_ref-side")"
    printf 'PICK TIP\n' > "$picker_repo/change.txt"
    git -C "$picker_repo" add .
    GIT_AUTHOR_DATE='2025-05-06T07:08:09Z' GIT_COMMITTER_DATE='2025-05-06T07:08:09Z' \
        git -C "$picker_repo" commit -qm 'PICK_TIP current HEAD'
    git -C "$picker_repo" rev-parse HEAD > "$test_tmp/refs/$picker_ref-tip"
    git -C "$picker_repo" switch -qc hidden pick-root
    printf 'HIDDEN only\n' > "$picker_repo/hidden.txt"
    git -C "$picker_repo" add .
    GIT_AUTHOR_DATE='2030-06-07T08:09:10Z' GIT_COMMITTER_DATE='2030-06-07T08:09:10Z' \
        git -C "$picker_repo" commit -qm 'PICK_UNREACHABLE other branch'
    git -C "$picker_repo" rev-parse HEAD > "$test_tmp/refs/$picker_ref-hidden"
    git -C "$picker_repo" switch -q main
    test "$(git -C "$picker_repo" rev-list HEAD | wc -l)" -eq 6
    if git -C "$picker_repo" merge-base --is-ancestor hidden HEAD; then
        printf 'Invalid picker fixture: hidden branch is reachable\n' >&2
        exit 1
    fi
    printf 'INDEX picker dirt\n' > "$picker_repo/change.txt"
    git -C "$picker_repo" add change.txt
    printf 'DISK picker dirt\n' > "$picker_repo/change.txt"
    touch -t 202001010000 "$picker_repo/stable.txt"
    printf 'UNTRACKED picker\n' > "$picker_repo/untracked.txt"
}

new_repo "$test_tmp/picker repo 中文"
picker_history "$test_tmp/picker repo 中文" picker
GIT_DEFAULT_HASH=sha256 new_repo "$test_tmp/picker-sha256"
picker_history "$test_tmp/picker-sha256" picker256
test "$(wc -c < "$test_tmp/refs/picker-root")" -eq 41
test "$(wc -c < "$test_tmp/refs/picker256-root")" -eq 65
new_repo "$test_tmp/picker-elsewhere"
printf 'ELSEWHERE ROOT\n' > "$test_tmp/picker-elsewhere/change.txt"
git -C "$test_tmp/picker-elsewhere" add .
git -C "$test_tmp/picker-elsewhere" commit -qm elsewhere
for fixture in 'picker repo 中文' picker-sha256 picker-elsewhere; do
    cp -R "$test_tmp/$fixture" "$test_tmp/$fixture-before"
done
