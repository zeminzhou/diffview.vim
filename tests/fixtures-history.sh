# Native Git oracles are captured before product execution, never derived from UI labels.
cat > "$test_tmp/history-forbidden-command" <<'EOF'
#!/bin/sh
printf 'unexpected external preview command\n' >> "$DIFFVIEW_TEST_TMP/history-command-executed"
exit 91
EOF
chmod +x "$test_tmp/history-forbidden-command"
history_graph() {
    history_fixture="$1"
    history_prefix="$2"
    mkdir -p "$history_fixture/src"
    printf 'alpha\nkeep\nold\nomega\n' > "$history_fixture/src/old.py"
    printf 'root untouched\n' > "$history_fixture/other.txt"
    printf '*.txt diff=hostile\n' > "$history_fixture/.gitattributes"
    printf 'old binary\000data\n' > "$history_fixture/binary.bin"
    ln -s src/old.py "$history_fixture/link"
    history_newline=$(printf 'line\nname.txt')
    history_tab=$(printf 'tab\tname.txt')
    history_counter=0
    for history_path in 'space 中文.txt' 'colon:name.txt' 'C:\literal.txt' ':leading.txt' '-leading.txt' \
        "$history_newline" "$history_tab" 'literal\n.txt' ':(glob)**' 'semi;$(touch HISTORY_INJECTED)|quote'; do
        history_counter=$((history_counter + 1))
        printf 'ROOT raw %s\n' "$history_counter" > "$history_fixture/$history_path"
    done
    git -C "$history_fixture" add .
    git -C "$history_fixture" commit -qm HIST_ROOT
    git -C "$history_fixture" rev-parse HEAD > "$test_tmp/refs/$history_prefix-root"
    printf 'alpha\nkeep\nedited\nomega\n' > "$history_fixture/src/old.py"
    git -C "$history_fixture" add .
    git -C "$history_fixture" commit -qm HIST_EDIT
    git -C "$history_fixture" rev-parse HEAD > "$test_tmp/refs/$history_prefix-edit"
    git -C "$history_fixture" mv src/old.py 'src/new name.py'
    mkdir "$history_fixture/src/old.py"
    printf 'UNRELATED HISTORY CHILD\n' > "$history_fixture/src/old.py/child.txt"
    git -C "$history_fixture" add .
    git -C "$history_fixture" commit -qm HIST_RENAME
    git -C "$history_fixture" rev-parse HEAD > "$test_tmp/refs/$history_prefix-rename"
    git -C "$history_fixture" branch side
    printf 'inserted\nalpha\nkeep\nedited\nomega\n' > "$history_fixture/src/new name.py"
    git -C "$history_fixture" add .
    git -C "$history_fixture" commit -qm HIST_INSERT
    git -C "$history_fixture" rev-parse HEAD > "$test_tmp/refs/$history_prefix-insert"
    printf 'inserted\nedited\nalpha\nkeep\nomega\n' > "$history_fixture/src/new name.py"
    git -C "$history_fixture" add .
    git -C "$history_fixture" commit -qm HIST_MOVE
    git -C "$history_fixture" rev-parse HEAD > "$test_tmp/refs/$history_prefix-move"
    git -C "$history_fixture" checkout -q side
    printf 'side branch only\n' > "$history_fixture/side.txt"
    git -C "$history_fixture" add .
    git -C "$history_fixture" commit -qm HIST_SIDE
    git -C "$history_fixture" rev-parse HEAD > "$test_tmp/refs/$history_prefix-side"
    git -C "$history_fixture" checkout -q main
    git -C "$history_fixture" merge -q --no-ff side -m HIST_MERGE
    git -C "$history_fixture" rev-parse HEAD > "$test_tmp/refs/$history_prefix-merge"
    git -C "$history_fixture" branch review-merge
    cp "$history_fixture/src/new name.py" "$test_tmp/$history_prefix-merge.body"
    rm "$history_fixture/src/new name.py"
    mkdir "$history_fixture/src/new name.py"
    printf 'UNRELATED DELETE CHILD\n' > "$history_fixture/src/new name.py/child.txt"
    git -C "$history_fixture" add -A
    git -C "$history_fixture" commit -qm HIST_DELETE
    git -C "$history_fixture" rev-parse HEAD > "$test_tmp/refs/$history_prefix-delete"
    rm "$history_fixture/src/new name.py/child.txt"
    rmdir "$history_fixture/src/new name.py"
    git -C "$history_fixture" add -A
    git -C "$history_fixture" commit -qm HIST_CHILD_DELETE
    git -C "$history_fixture" rev-parse HEAD > "$test_tmp/refs/$history_prefix-child-delete"
    printf 'recreated unrelated\n' > "$history_fixture/src/new name.py"
    git -C "$history_fixture" add .
    git -C "$history_fixture" commit -qm HIST_RECREATE
    git -C "$history_fixture" rev-parse HEAD > "$test_tmp/refs/$history_prefix-recreate"
    history_counter=0
    for history_path in 'space 中文.txt' 'colon:name.txt' 'C:\literal.txt' ':leading.txt' '-leading.txt' \
        "$history_newline" "$history_tab" 'literal\n.txt' ':(glob)**' 'semi;$(touch HISTORY_INJECTED)|quote'; do
        history_counter=$((history_counter + 1))
        printf 'EDIT raw %s\n' "$history_counter" > "$history_fixture/$history_path"
    done
    git -C "$history_fixture" add .
    git -C "$history_fixture" commit -qm HIST_RAW_PATHS
    git -C "$history_fixture" rev-parse HEAD > "$test_tmp/refs/$history_prefix-raw"
    # Patch and single-line limits use real Git content/metadata, not a fake worker.
    awk 'BEGIN { for (i=1;i<=2400;i++) print "preview old " i }' > "$history_fixture/large.txt"
    git -C "$history_fixture" add .
    git -C "$history_fixture" commit -qm HIST_LARGE_BASE
    git -C "$history_fixture" rev-parse HEAD > "$test_tmp/refs/$history_prefix-large-base"
    awk 'BEGIN { for (i=1;i<=2400;i++) print "preview new " i }' > "$history_fixture/large.txt"
    # Keep hostile long metadata and control bytes in a disposable commit-message file.
    {
        printf 'HIST_LIMIT '
        awk 'BEGIN { for(i=1;i<=2200;i++) printf "中文"; printf "\n\n" }'
        printf 'OSC\033]52;HISTORY_INJECTED\007 $(touch PREVIEW_INJECTED) | quote\n'
        printf 'DIFFVIEW_PREVIEW_STATUS:0\n'
    } > "$test_tmp/$history_prefix-large.message"
    git -C "$history_fixture" add .
    git -C "$history_fixture" commit -qF "$test_tmp/$history_prefix-large.message"
    git -C "$history_fixture" rev-parse HEAD > "$test_tmp/refs/$history_prefix-limit"
    # A diverged target enables direct vs merge-base Open/Branch checks in the same repo.
    git -C "$history_fixture" checkout -qb merge-target "$(cat "$test_tmp/refs/$history_prefix-root")"
    printf 'TARGET oldpath\n' > "$history_fixture/src/old.py"
    git -C "$history_fixture" add .
    git -C "$history_fixture" commit -qm HIST_TARGET
    git -C "$history_fixture" rev-parse HEAD > "$test_tmp/refs/$history_prefix-target"
    git -C "$history_fixture" checkout -q main
    for history_start in merge delete child-delete recreate; do
        git --no-optional-locks -c diff.autoRefreshIndex=false -C "$history_fixture" \
            log --first-parent --follow --raw -z --no-abbrev --no-ext-diff --no-textconv \
            --format='%x00H%x00%H%x00%an%x00%s%x00' \
            "$(cat "$test_tmp/refs/$history_prefix-$history_start")" -- 'src/new name.py' \
            > "$test_tmp/$history_prefix-file-$history_start.raw"
        git --no-optional-locks -C "$history_fixture" log --first-parent --follow --no-patch -z --format=%H \
            "$(cat "$test_tmp/refs/$history_prefix-$history_start")" -- 'src/new name.py' \
            > "$test_tmp/$history_prefix-file-$history_start.oids"
    done
    for history_range in 1,1 2,2 2,4 1,5; do
        git --no-optional-locks -C "$history_fixture" log --first-parent --no-patch --format=%H -z \
            "-L$history_range:src/new name.py" "$(cat "$test_tmp/refs/$history_prefix-merge")" \
            > "$test_tmp/$history_prefix-line-$history_range.oids"
    done
    history_counter=0
    for history_path in 'space 中文.txt' 'colon:name.txt' 'C:\literal.txt' ':leading.txt' '-leading.txt' \
        "$history_newline" "$history_tab" 'literal\n.txt' ':(glob)**' 'semi;$(touch HISTORY_INJECTED)|quote'; do
        history_counter=$((history_counter + 1))
        git --no-optional-locks --literal-pathspecs -C "$history_fixture" log --first-parent --no-patch \
            --format=%H -z "-L1,1:$history_path" "$(cat "$test_tmp/refs/$history_prefix-raw")" \
            > "$test_tmp/$history_prefix-line-raw-$history_counter.oids"
    done
    test "$(git -C "$history_fixture" merge-base --all merge-target main)" = \
        "$(cat "$test_tmp/refs/$history_prefix-root")"
    git -C "$history_fixture" rev-parse HEAD > "$test_tmp/refs/$history_prefix-tip"
    git -C "$history_fixture" rev-parse 'review-merge^{tree}' > "$test_tmp/refs/$history_prefix-tree"
    git -C "$history_fixture" rev-parse "$(cat "$test_tmp/refs/$history_prefix-root")^{tree}" \
        > "$test_tmp/refs/$history_prefix-root-tree"
    git --no-optional-locks -C "$history_fixture" show --no-ext-diff --no-textconv --no-color \
        --format='commit %H%n%B' --stat --patch \
        "$(cat "$test_tmp/refs/$history_prefix-rename")" -- src/old.py 'src/new name.py' \
        > "$test_tmp/$history_prefix-preview-broad.oracle"
    git --no-optional-locks -C "$history_fixture" show --follow --no-ext-diff --no-textconv --no-color \
        --format='commit %H%n%B' --stat --patch \
        "$(cat "$test_tmp/refs/$history_prefix-rename")" -- 'src/new name.py' \
        > "$test_tmp/$history_prefix-preview-follow.oracle"
    git --no-optional-locks -C "$history_fixture" show --sparse --no-ext-diff --no-textconv --no-color \
        --format='commit %H%n%B' --stat --patch \
        "$(cat "$test_tmp/refs/$history_prefix-root")" -- NO_PATH_MATCHES \
        > "$test_tmp/$history_prefix-preview-empty-prefix.oracle"
    git --no-optional-locks -C "$history_fixture" show --follow --no-ext-diff --no-textconv --no-color \
        --format='commit %H%n%B' --stat --patch \
        "$(cat "$test_tmp/refs/$history_prefix-delete")" -- 'src/new name.py' \
        > "$test_tmp/$history_prefix-preview-delete-broad.oracle"
    git --no-optional-locks -C "$history_fixture" show --follow --diff-filter=D --no-ext-diff --no-textconv --no-color \
        --format='commit %H%n%B' --stat --patch \
        "$(cat "$test_tmp/refs/$history_prefix-delete")" -- 'src/new name.py' \
        > "$test_tmp/$history_prefix-preview-delete-exact.oracle"
    test "$(git -C "$history_fixture" diff-tree -r --no-commit-id --name-only \
        "$(cat "$test_tmp/refs/$history_prefix-rename")" -- src/old.py/child.txt)" = src/old.py/child.txt
    printf 'DISK dirt excluded\n' > "$history_fixture/other.txt"
    git -C "$history_fixture" config diff.external "$test_tmp/history-forbidden-command"
    git -C "$history_fixture" config diff.hostile.textconv "$test_tmp/history-forbidden-command"
    git -C "$history_fixture" config core.pager "$test_tmp/history-forbidden-command"
    cp -R "$history_fixture" "$history_fixture-before"
}

GIT_DEFAULT_HASH=sha1 new_repo "$test_tmp/history review"
history_graph "$test_tmp/history review" history
GIT_DEFAULT_HASH=sha256 new_repo "$test_tmp/history-review256"
history_graph "$test_tmp/history-review256" history256
git clone -q --no-local --depth=1 "$test_tmp/history review" "$test_tmp/history-shallow"
git -C "$test_tmp/history-shallow" config core.hooksPath /dev/null
cp -R "$test_tmp/history-shallow" "$test_tmp/history-shallow-before"

# A local-only promisor clone retains commits/trees but no promised blob data.
git -c protocol.file.allow=always clone -q --filter=blob:none --no-checkout \
    --upload-pack='git -c uploadpack.allowFilter=true upload-pack' \
    "file://$test_tmp/history review" "$test_tmp/history-promisor"
GIT_NO_LAZY_FETCH=1 git -C "$test_tmp/history-promisor" rev-list --objects --missing=print HEAD \
    > "$test_tmp/history-promisor-missing.before"
git -C "$test_tmp/history-promisor" rev-parse HEAD:other.txt > "$test_tmp/refs/history-promisor-blob"
if GIT_NO_LAZY_FETCH=1 git -C "$test_tmp/history-promisor" cat-file -e \
    "$(cat "$test_tmp/refs/history-promisor-blob")" 2>/dev/null; then
    printf 'Invalid promisor fixture: promised blob is already present\n' >&2
    exit 1
fi
cp -R "$test_tmp/history-promisor" "$test_tmp/history-promisor-before"

# Deliberate criss-cross: both A and B are best bases; no virtual merge is allowed.
new_repo "$test_tmp/history-bases"
history_bases="$test_tmp/history-bases"
printf 'BASE DAG\n' > "$history_bases/dag.txt"
git -C "$history_bases" add .
git -C "$history_bases" commit -qm DAG_ROOT
history_tree=$(git -C "$history_bases" rev-parse 'HEAD^{tree}')
history_root=$(git -C "$history_bases" rev-parse HEAD)
history_a=$(printf 'DAG_A\n' | git -C "$history_bases" commit-tree "$history_tree" -p "$history_root")
history_b=$(printf 'DAG_B\n' | git -C "$history_bases" commit-tree "$history_tree" -p "$history_root")
history_ab=$(printf 'DAG_AB\n' | git -C "$history_bases" commit-tree "$history_tree" -p "$history_a" -p "$history_b")
history_ba=$(printf 'DAG_BA\n' | git -C "$history_bases" commit-tree "$history_tree" -p "$history_b" -p "$history_a")
history_unrelated=$(printf 'DAG_UNRELATED\n' | git -C "$history_bases" commit-tree "$history_tree")
git -C "$history_bases" update-ref refs/heads/cross-left "$history_ab"
git -C "$history_bases" update-ref refs/heads/cross-right "$history_ba"
git -C "$history_bases" update-ref refs/heads/unrelated "$history_unrelated"
git -C "$history_bases" merge-base --all cross-left cross-right > "$test_tmp/history-cross-bases.oracle"
test "$(wc -l < "$test_tmp/history-cross-bases.oracle")" -eq 2
if git -C "$history_bases" merge-base --all main unrelated > "$test_tmp/history-unrelated.oracle"; then
    printf 'Invalid fixture: unrelated commits had a common base\n' >&2
    exit 1
fi
cp -R "$history_bases" "$history_bases-before"
