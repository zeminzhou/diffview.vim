# Sourced by run.sh; all paths belong to disposable test repositories.
tree_repo="$test_tmp/tree repo"
new_repo "$tree_repo"
mkdir -p "$tree_repo/src/deep" "$tree_repo/other" "$tree_repo/gone" \
    "$tree_repo/old dir" "$tree_repo/weird" "$tree_repo/.hidden"
printf 'HEAD nested\n' > "$tree_repo/src/deep/both.txt"
printf 'HEAD change\n' > "$tree_repo/src/deep/change.txt"
printf 'HEAD sibling\n' > "$tree_repo/src/sibling.txt"
printf 'HEAD src same\n' > "$tree_repo/src/same.txt"
printf 'HEAD other same\n' > "$tree_repo/other/same.txt"
printf 'HEAD deleted\n' > "$tree_repo/gone/leaf.txt"
printf 'stable tree rename\n' > "$tree_repo/old dir/old.txt"
printf 'HEAD hidden\n' > "$tree_repo/.hidden/change.txt"
tree_tab=$(printf 'tab\tname.txt')
tree_newline=$(printf 'line\nname.txt')
tree_soh=$(printf 'ctrl\001name.txt')
tree_bel=$(printf 'bell\007name.txt')
tree_paths() {
    counter=0
    for path in "$tree_tab" "$tree_newline" "$tree_soh" 'line^@name.txt' 'literal\n.txt' ':(glob)**' \
        "$tree_bel" 'bell^Gname.txt'; do
        counter=$((counter + 1))
        printf '%s identity %s\n' "$1" "$counter" > "$tree_repo/weird/$path"
    done
}
tree_paths HEAD
git -C "$tree_repo" add .
git -C "$tree_repo" commit -qm initial
printf 'INDEX nested\n' > "$tree_repo/src/deep/both.txt"
printf 'INDEX sibling\n' > "$tree_repo/src/sibling.txt"
tree_paths INDEX
git -C "$tree_repo" add .
git -C "$tree_repo" mv 'old dir/old.txt' 'new name.txt'
printf 'DISK nested\n' > "$tree_repo/src/deep/both.txt"
printf 'DISK change\n' > "$tree_repo/src/deep/change.txt"
printf 'DISK src same\n' > "$tree_repo/src/same.txt"
printf 'DISK other same\n' > "$tree_repo/other/same.txt"
printf 'DISK hidden\n' > "$tree_repo/.hidden/change.txt"
tree_paths DISK
rm "$tree_repo/gone/leaf.txt"
mkdir -p "$tree_repo/new deep"
printf 'DISK nested untracked\n' > "$tree_repo/new deep/leaf.txt"
# These independent controls verify the fixture before the adapter sees it.
test "$(git -C "$tree_repo" show :src/deep/both.txt)" = 'INDEX nested'
test "$(git -C "$tree_repo" show HEAD:src/deep/both.txt)" = 'HEAD nested'
test ! -e "$tree_repo/gone/leaf.txt"

tree_history="$test_tmp/tree-history"
new_repo "$tree_history"
mkdir -p "$tree_history/flip" "$tree_history/deleted/deep" "$tree_history/sub tree"
printf 'LEFT file to directory\n' > "$tree_history/swap"
printf 'LEFT directory child\n' > "$tree_history/flip/old.txt"
printf 'LEFT historical only\n' > "$tree_history/deleted/deep/only.txt"
printf 'LEFT subtree\n' > "$tree_history/sub tree/child.txt"
git -C "$tree_history" add .
git -C "$tree_history" commit -qm left
git -C "$tree_history" tag nt-left
rm "$tree_history/swap" "$tree_history/flip/old.txt" "$tree_history/deleted/deep/only.txt"
rmdir "$tree_history/flip" "$tree_history/deleted/deep" "$tree_history/deleted"
mkdir "$tree_history/swap"
printf 'RIGHT directory child\n' > "$tree_history/swap/child.txt"
printf 'RIGHT directory to file\n' > "$tree_history/flip"
printf 'RIGHT subtree\n' > "$tree_history/sub tree/child.txt"
git -C "$tree_history" add -A
git -C "$tree_history" commit -qm right
git -C "$tree_history" tag nt-right
test "$(git -C "$tree_history" diff --name-only nt-left nt-right | wc -l)" -eq 6
test ! -e "$tree_history/deleted"
printf 'LOCAL dirt excluded from history\n' > "$tree_history/swap/child.txt"
printf 'LOCAL only\n' > "$tree_history/local-only.txt"

new_repo "$test_tmp/user-tree"
mkdir -p "$test_tmp/user-tree/open/closed"
printf 'USER tree file\n' > "$test_tmp/user-tree/open/file.txt"
printf 'USER deep file\n' > "$test_tmp/user-tree/open/closed/deep.txt"
git -C "$test_tmp/user-tree" add .
git -C "$test_tmp/user-tree" commit -qm initial
printf 'USER tree disk change\n' > "$test_tmp/user-tree/open/file.txt"

for fixture in 'tree repo' tree-history user-tree; do
    cp -R "$test_tmp/$fixture" "$test_tmp/$fixture-before"
done
