# Sourced by run.sh after the shared fixture helpers are defined.
history="$test_tmp/history repo 中文"
new_repo "$history"
mkdir -p "$test_tmp/refs" "$history/nested" "$history/tree dir"
printf 'BASE subtree\n' > "$history/tree dir/nested.txt"
printf 'BASE shared\n' > "$history/shared.txt"
printf 'ROOT deleted\n' > "$history/deleted.txt"
printf 'stable rename content\n' > "$history/old name.txt"
printf 'stable mode content\n' > "$history/mode.txt"
printf 'BASE no final newline' > "$history/noeol.txt"
printf 'BASE\000binary\n' > "$history/binary.bin"
printf 'BASE marked text\n' > "$history/marked.dat"
printf 'marked.dat -diff\n' > "$history/.gitattributes"
git -C "$history" add .
git -C "$history" commit -qm root
git -C "$history" tag root
git -C "$history" rev-parse HEAD > "$test_tmp/refs/root"
git -C "$history" rev-parse 'HEAD^{tree}' > "$test_tmp/refs/root-tree"
git -C "$history" rev-parse HEAD:shared.txt > "$test_tmp/refs/blob"
git -C "$history" switch -qc left
printf 'LEFT shared\n' > "$history/shared.txt"
printf 'LEFT only\n' > "$history/left-only.txt"
git -C "$history" add .
git -C "$history" commit -qm left
git -C "$history" rev-parse HEAD > "$test_tmp/refs/left"
git -C "$history" rev-parse 'HEAD^{tree}' > "$test_tmp/refs/left-tree"
git -C "$history" switch -qc right root
printf 'RIGHT shared\n' > "$history/shared.txt"
printf 'RIGHT subtree\n' > "$history/tree dir/nested.txt"
printf 'RIGHT added\n' > "$history/added.txt"
: > "$history/empty-added.txt"
rm "$history/deleted.txt"
git -C "$history" mv 'old name.txt' 'new 名称.txt'
chmod +x "$history/mode.txt"
printf 'RIGHT no final newline' > "$history/noeol.txt"
printf 'RIGHT\000binary\n' > "$history/binary.bin"
printf 'RIGHT marked text\n' > "$history/marked.dat"
git -C "$history" add -A
git -C "$history" commit -qm right
git -C "$history" rev-parse HEAD > "$test_tmp/refs/right"
git -C "$history" rev-parse 'HEAD^{tree}' > "$test_tmp/refs/right-tree"
git -C "$history" branch "quote'branch"
git -C "$history" branch 'dollar$(touch${IFS}INJECTED_REF)'
git -C "$history" branch 'pipe|branch'
git -C "$history" rev-parse 'left:tree dir' > "$test_tmp/refs/left-subtree"
git -C "$history" rev-parse 'right:tree dir' > "$test_tmp/refs/right-subtree"
git -C "$history" branch moving
git -C "$history" switch -qc merged
if git -C "$history" merge --no-commit --no-ff left > "$test_tmp/merge.log" 2>&1; then
    printf 'Invalid fixture: expected shared.txt merge conflict\n' >&2
    exit 1
fi
git -C "$history" rev-parse --verify MERGE_HEAD > /dev/null
printf 'MERGED shared\n' > "$history/shared.txt"
git -C "$history" add shared.txt
git -C "$history" commit -qm merge
git -C "$history" rev-parse HEAD > "$test_tmp/refs/merge"
git -C "$history" rev-parse 'HEAD^{tree}' > "$test_tmp/refs/merge-tree"
test "$(git -C "$history" rev-parse HEAD^1)" = "$(cat "$test_tmp/refs/right")"
test "$(git -C "$history" rev-parse HEAD^2)" = "$(cat "$test_tmp/refs/left")"
# Endpoint comparison contains a deletion that merge-base comparison omits.
if git -C "$history" diff --quiet left right -- left-only.txt; then
    printf 'Invalid fixture: endpoint comparison lost left-only deletion\n' >&2
    exit 1
fi
git -C "$history" diff --quiet left...right -- left-only.txt
printf 'INDEX dirt, not historical\n' > "$history/shared.txt"
git -C "$history" add shared.txt
printf 'DISK dirt, not historical\n' > "$history/shared.txt"
printf 'LOCAL only\n' > "$history/local-only.txt"
git clone -q --no-local --depth=1 "$history" "$test_tmp/shallow"
git -C "$test_tmp/shallow" config core.attributesFile /dev/null
if git -C "$test_tmp/shallow" cat-file -e "$(cat "$test_tmp/refs/right")" 2>/dev/null; then
    printf 'Invalid fixture: shallow clone contains the first-parent commit\n' >&2
    exit 1
fi

edges="$test_tmp/edges"
new_repo "$edges"
printf 'HEAD deleted\n' > "$edges/deleted.txt"
printf 'unchanged rename\n' > "$edges/old.txt"
printf 'unchanged mode\n' > "$edges/mode.txt"
printf 'HEAD no final newline' > "$edges/noeol.txt"
printf 'HEAD\000binary\n' > "$edges/binary.bin"
printf 'HEAD marked text\n' > "$edges/marked.dat"
printf 'HEAD staged marked text\n' > "$edges/marked-staged.dat"
printf 'marked*.dat -diff\n' > "$edges/.gitattributes"
printf 'conflict base\n' > "$edges/conflict.txt"
printf 'target text\n' > "$edges/target.txt"
ln -s target.txt "$edges/leaf-link"
git -C "$edges" add .
git -C "$edges" commit -qm initial
edge_head=$(git -C "$edges" rev-parse HEAD)
conflict_base=$(git -C "$edges" rev-parse HEAD:conflict.txt)
conflict_ours=$(printf 'conflict ours\n' | git -C "$edges" hash-object -w --stdin)
conflict_theirs=$(printf 'conflict theirs\n' | git -C "$edges" hash-object -w --stdin)
rm "$edges/deleted.txt" "$edges/leaf-link"
git -C "$edges" mv old.txt new.txt
chmod +x "$edges/mode.txt"
printf 'DISK no final newline' > "$edges/noeol.txt"
printf 'DISK\000binary\n' > "$edges/binary.bin"
printf 'DISK marked text\n' > "$edges/marked.dat"
printf 'INDEX staged marked text\n' > "$edges/marked-staged.dat"
git -C "$edges" add marked-staged.dat
printf 'DISK untracked marked text\n' > "$edges/marked-untracked.dat"
ln -s ../outside/file.txt "$edges/leaf-link"
ln -s ../outside/file.txt "$edges/untracked-link"
: > "$edges/empty-added.txt"
git -C "$edges" add empty-added.txt
mkdir "$edges/submodule"
git -C "$edges" update-index --add --cacheinfo "160000,$edge_head,submodule"
printf '0 0000000000000000000000000000000000000000\tconflict.txt\n100644 %s 1\tconflict.txt\n100644 %s 2\tconflict.txt\n100644 %s 3\tconflict.txt\n' \
    "$conflict_base" "$conflict_ours" "$conflict_theirs" | git -C "$edges" update-index --index-info
git -C "$edges" diff --numstat -- marked.dat > "$test_tmp/marked.numstat"
test "$(cut -f1 "$test_tmp/marked.numstat")" = '-'
test "$(cut -f2 "$test_tmp/marked.numstat")" = '-'
git -C "$edges" diff --cached --numstat -- marked-staged.dat > "$test_tmp/marked-staged.numstat"
test "$(cut -f1 "$test_tmp/marked-staged.numstat")" = '-'
test "$(cut -f2 "$test_tmp/marked-staged.numstat")" = '-'
for marked_path in marked.dat marked-staged.dat marked-untracked.dat; do
    test "$(git -C "$edges" check-attr diff -- "$marked_path")" = "$marked_path: diff: unset"
done

new_repo "$test_tmp/cross-tab"
printf 'HEAD cross\n' > "$test_tmp/cross-tab/file.txt"
git -C "$test_tmp/cross-tab" add .
git -C "$test_tmp/cross-tab" commit -qm initial
printf 'DISK cross\n' > "$test_tmp/cross-tab/file.txt"
new_repo "$test_tmp/read-failure"
printf 'HEAD readable\n' > "$test_tmp/read-failure/file.txt"
printf 'HEAD forced readable\n' > "$test_tmp/read-failure/forced.dat"
printf 'forced.dat -diff\n' > "$test_tmp/read-failure/.gitattributes"
git -C "$test_tmp/read-failure" add .
git -C "$test_tmp/read-failure" commit -qm initial
printf 'DISK readable\n' > "$test_tmp/read-failure/file.txt"
printf 'DISK forced readable\n' > "$test_tmp/read-failure/forced.dat"
test "$(git -C "$test_tmp/ancestor" check-attr diff -- dir/forced.dat)" = 'dir/forced.dat: diff: unset'
test "$(git -C "$test_tmp/read-failure" check-attr diff -- forced.dat)" = 'forced.dat: diff: unset'
mkdir "$test_tmp/no-tools"
git init --bare -q "$test_tmp/bare.git"

binary_clean="$test_tmp/binary-clean"
new_repo "$binary_clean"
printf '*.dat -diff\ncrlf.txt text eol=crlf -diff\n' > "$binary_clean/.gitattributes"
printf 'UNCHANGED forced ASCII\n' > "$binary_clean/forced.dat"
printf 'UNCHANGED\000nul\n' > "$binary_clean/nul.bin"
: > "$binary_clean/empty.dat"
printf 'UNCHANGED no final LF' > "$binary_clean/noeol.dat"
printf 'ONE\r\nTWO\r\n' > "$binary_clean/crlf.txt"
printf 'HEAD real binary\n' > "$binary_clean/real.dat"
printf 'HEAD ordinary text\n' > "$binary_clean/text.txt"
printf 'unchanged mode\n' > "$binary_clean/mode.dat"
printf 'unchanged rename\n' > "$binary_clean/rename-old.dat"
git -C "$binary_clean" add .
git -C "$binary_clean" commit -qm initial
for stale_path in forced.dat nul.bin empty.dat noeol.dat crlf.txt; do
    touch -t 202001010000 "$binary_clean/$stale_path"
done
# Binary -/- records can survive even when Git status is honestly clean.
cp "$binary_clean/.git/index" "$test_tmp/binary-clean.index"
git --no-optional-locks -C "$binary_clean" status --porcelain > "$test_tmp/binary-clean.status"
test ! -s "$test_tmp/binary-clean.status"
git --no-optional-locks -c diff.autoRefreshIndex=false -C "$binary_clean" \
    diff --raw --numstat -z -- forced.dat > "$test_tmp/binary-clean.raw-numstat"
test -s "$test_tmp/binary-clean.raw-numstat"
git --no-optional-locks -c diff.autoRefreshIndex=false -C "$binary_clean" \
    diff --name-only -- forced.dat > "$test_tmp/binary-clean.false-row"
test "$(cat "$test_tmp/binary-clean.false-row")" = forced.dat
cmp "$test_tmp/binary-clean.index" "$binary_clean/.git/index"

binary_mixed="$test_tmp/binary-mixed"
cp -R "$binary_clean" "$binary_mixed"
printf 'INDEX real binary\n' > "$binary_mixed/real.dat"
chmod +x "$binary_mixed/mode.dat"
git -C "$binary_mixed" add real.dat mode.dat
printf 'DISK real binary\n' > "$binary_mixed/real.dat"
printf 'DISK ordinary text\n' > "$binary_mixed/text.txt"
chmod -x "$binary_mixed/mode.dat"
printf 'CHANGED\000nul\n' > "$binary_mixed/nul.bin"
git -C "$binary_mixed" mv rename-old.dat rename-new.dat
rm "$binary_mixed/empty.dat"
: > "$binary_mixed/added.dat"
git -C "$binary_mixed" add added.dat
for stale_path in forced.dat noeol.dat crlf.txt; do
    touch -t 202001010000 "$binary_mixed/$stale_path"
done
cp "$binary_mixed/.git/index" "$test_tmp/binary-mixed.index"
git --no-optional-locks -C "$binary_mixed" status --porcelain > "$test_tmp/binary-mixed.status"
test "$(wc -l < "$test_tmp/binary-mixed.status")" -eq 7
cmp "$test_tmp/binary-mixed.index" "$binary_mixed/.git/index"

new_repo "$test_tmp/large"
awk 'BEGIN { for (i = 1; i <= 20000; i++) printf "line %05d: a moderately large native Vim diff snapshot for acceptance\n", i }' \
    > "$test_tmp/large/000-large.txt"
item=1
while [ "$item" -le 200 ]; do
    printf 'item %s\n' "$item" > "$test_tmp/large/item-$item.txt"
    item=$((item + 1))
done

for fixture in 'history repo 中文' edges cross-tab read-failure bare.git shallow large binary-clean binary-mixed; do
    cp -R "$test_tmp/$fixture" "$test_tmp/$fixture-before"
done
