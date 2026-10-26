#!/usr/bin/env python3
"""Developer smoke checks; independent acceptance tests belong in tests/."""
import hashlib
import json
import os
from pathlib import Path
import subprocess
import tempfile

PLUGIN = Path(__file__).resolve().parents[1]
NERDTREE = Path(os.environ.get("NERDTREE_RUNTIME", ""))
if not (NERDTREE / "plugin/NERD_tree.vim").is_file():
    raise SystemExit("Set NERDTREE_RUNTIME to a real preservim/nerdtree checkout (see README.md).")
TEST_ENV = {key: value for key, value in os.environ.items() if not key.startswith("GIT_")}
TEST_ENV.update(GIT_CONFIG_GLOBAL="/dev/null", GIT_CONFIG_NOSYSTEM="1", GIT_TERMINAL_PROMPT="0")


def quote(value):
    return "'" + str(value).replace("'", "''") + "'"


def git(repo, *args):
    return subprocess.run(["git", "-C", str(repo), *args], check=True,
                          capture_output=True, env=TEST_ENV).stdout


def vim(repo, script, directory):
    source = directory / "check.vim"
    (directory / "vim.log").unlink(missing_ok=True)
    source.write_text("set nomore\nlet &rtp = " + quote(str(NERDTREE) + "," + str(PLUGIN))
                      + " . ',' . &rtp\nlet g:NERDTreeHijackNetrw = 0\n"
                      "runtime plugin/NERD_tree.vim\nruntime plugin/main.vim\n"
                      + r'''
function! DiffviewNodes(node)
  let nodes = [a:node]
  for child in get(a:node, 'children', [])
    call extend(nodes, DiffviewNodes(child))
  endfor
  return nodes
endfunction
function! DiffviewEntries()
  let panel = filter(getbufinfo(), {_, b -> getbufvar(b.bufnr, 'diffview_role', '') == 'panel'})[0].bufnr
  let tree = getbufvar(panel, 'NERDTree')
  return filter(DiffviewNodes(tree.root), {_, n -> has_key(n, 'diffview_entry')})
endfunction
''' + script + "\n"
                      "if !empty(v:errors)\n  call writefile(v:errors, "
                      + quote(directory / "failures") + ")\n  cquit\nendif\nqa!\n")
    result = subprocess.run(["vim", "-Nu", "NONE", "-i", "NONE", "-n", "-es",
                             "-V1" + str(directory / "vim.log"), "-S", str(source)],
                            cwd=repo, capture_output=True, text=True, timeout=30, env=TEST_ENV)
    assert result.returncode == 0, (((directory / "failures").read_text()
                                    if (directory / "failures").exists() else "")
                                   + (directory / "vim.log").read_text()[-7000:])


with tempfile.TemporaryDirectory(prefix="diffview-check-") as temporary:
    directory = Path(temporary)
    repo = directory / "repo 空 间"
    repo.mkdir()
    git(repo, "init", "-q")
    git(repo, "config", "user.name", "Diffview Test")
    git(repo, "config", "user.email", "diffview@example.invalid")
    special = ["space name", "中文", "tab\tname", "line\nname", "-dash",
               "q'\" | $();%#[]*.txt", "soh\x01name"]
    for path in ["both.txt", *special]:
        (repo / path).write_text("HEAD\n")
    (repo / ".gitignore").write_text("ignored\n")
    git(repo, "add", ".")
    git(repo, "commit", "-qm", "base")
    for path in ["both.txt", *special]:
        (repo / path).write_text("INDEX\n")
    git(repo, "add", ".")
    for path in ["both.txt", *special]:
        (repo / path).write_text("DISK\n")
    (repo / "untracked").write_text("untracked")
    (repo / "ignored").write_text("ignored\n")
    index_before = hashlib.sha256((repo / ".git/index").read_bytes()).digest()
    disk_before = {path: (repo / path).read_bytes() for path in ["both.txt", *special]}
    vim(repo, r'''
function! Role(role)
  return filter(getbufinfo(), {_, b -> getbufvar(b.bufnr, 'diffview_role', '') == a:role})[0].bufnr
endfunction
function! Sides(left, right, section)
  call assert_equal(a:left, getbufline(Role('left'), 1, '$'))
  call assert_equal(a:right, getbufline(Role('right'), 1, '$'))
  call assert_equal(a:section, getbufvar(Role('right'), 'diffview_section'))
endfunction
edit both.txt
call setline(1, 'UNSAVED')
let userbuf = bufnr()
let origin = win_getid()
diffthis
let options = [&l:diff, &l:foldmethod, &l:scrollbind, &l:wrap]
call setreg('=', '40 + 2')
let expression = getreginfo('=')
DiffviewOpen
call assert_equal(expression, getreginfo('='), 'native renderer preserves expression register')
call assert_equal('nerdtree', &filetype)
call assert_true(g:NERDTreeFileNode.GetSelected() is b:NERDTree.diffview_entries[0])
call assert_equal(2, tabpagenr('$'))
call assert_equal(3, winnr('$'))
call assert_equal('panel', b:diffview_role)
let pane_buffers = [Role('panel'), Role('left'), Role('right')]
let files = DiffviewEntries()
call assert_equal(17, len(files))
let header = getline(1, 2)
call g:NERDTreeRender()
call assert_equal(header, getline(1, 2), 'native rerender preserves comparison headers')
call assert_equal(expression, getreginfo('='))
call assert_true(g:NERDTreeFileNode.GetSelected() is b:NERDTree.diffview_entries[0])
call Sides(['HEAD'], ['INDEX'], 'Staged')
normal o
call feedkeys("\<CR>", 'xt')
for i in range(17)
  if getbufvar(Role('right'), 'diffview_section') == 'Unstaged' && getbufvar(Role('right'), 'diffview_path') == 'both.txt'
    break
  endif
  normal ]f
endfor
call Sides(['INDEX'], ['DISK'], 'Unstaged')
call assert_equal('both.txt', getbufvar(Role('right'), 'diffview_path'))
call assert_equal(0, getbufvar(Role('right'), '&modifiable'))
call assert_equal(1, getbufvar(Role('right'), '&readonly'))
call feedkeys("\<Tab>", 'xt')
call assert_equal('left', b:diffview_role)
call feedkeys("\<S-Tab>", 'xt')
call assert_equal('panel', b:diffview_role)
call writefile(['REFRESHED'], 'both.txt')
let original_cwd = getcwd()
cd ..
normal r
call Sides(['INDEX'], ['REFRESHED'], 'Unstaged')
execute 'cd ' . fnameescape(original_cwd)
let tab = tabpagenr()
let active_buffers = [Role('panel'), Role('left'), Role('right')]
augroup DiffviewDevFailure
  autocmd FileType diffview throw '[diffview] synthetic layout failure'
augroup END
DiffviewOpen
augroup DiffviewDevFailure
  autocmd!
augroup END
call assert_match('synthetic layout failure', execute('messages'))
call assert_equal(active_buffers, [Role('panel'), Role('left'), Role('right')])
call assert_equal(tab, tabpagenr())
call Sides(['INDEX'], ['REFRESHED'], 'Unstaged')
DiffviewOpen invalid
call assert_equal(tab, tabpagenr())
call Sides(['INDEX'], ['REFRESHED'], 'Unstaged')
DiffviewClose
DiffviewClose
call assert_equal(origin, win_getid())
call assert_equal(1, tabpagenr('$'))
call assert_equal(options, [&l:diff, &l:foldmethod, &l:scrollbind, &l:wrap])
call assert_equal(['UNSAVED'], getbufline(userbuf, 1, '$'))
call assert_equal(1, getbufvar(userbuf, '&modified'))
call assert_equal([], filter(copy(pane_buffers), {_, b -> bufexists(b)}))
call g:ToggleDiffView()
call g:ToggleDiffView()
call assert_equal(origin, win_getid())
DiffviewOpen
close
sleep 20m
call assert_equal(1, tabpagenr('$'))
call assert_equal(v:false, get(g:, 'diffview_enabled', v:false))
DiffviewOpen
tabclose
sleep 20m
call assert_equal(1, tabpagenr('$'))
call assert_equal(v:false, get(g:, 'diffview_enabled', v:false))
DiffviewOpen
execute 'bwipeout! ' . Role('left')
sleep 20m
call assert_equal(1, tabpagenr('$'))
call assert_equal(v:false, get(g:, 'diffview_enabled', v:false))
DiffviewOpen
DiffviewOpen
call assert_equal(2, tabpagenr('$'))
call assert_equal(3, len(filter(getbufinfo(), {_, b -> getbufvar(b.bufnr, 'diffview_role', '') != ''})))
normal q
call assert_equal(1, tabpagenr('$'))
''', directory)
    assert hashlib.sha256((repo / ".git/index").read_bytes()).digest() == index_before
    disk_before["both.txt"] = b"REFRESHED\n"  # The check explicitly edits disk to test refresh.
    assert all((repo / path).read_bytes() == content for path, content in disk_before.items())
    edges = directory / "edges"
    edges.mkdir()
    git(edges, "init", "-q")
    git(edges, "config", "user.name", "Diffview Test")
    git(edges, "config", "user.email", "diffview@example.invalid")
    for path in ["delete staged", "delete disk", "rename from", "mode only", "binary", "forced.txt",
                 "forced-mode.txt", "forced-stale.txt", "conflict"]:
        (edges / path).write_text(path + "\n")
    (edges / ".gitattributes").write_text("forced*.txt -diff\n")
    git(edges, "add", ".")
    git(edges, "commit", "-qm", "base")
    branch = git(edges, "branch", "--show-current").decode().strip()
    git(edges, "checkout", "-qb", "side")
    (edges / "conflict").write_text("side\n")
    git(edges, "commit", "-qam", "side")
    git(edges, "checkout", "-q", branch)
    (edges / "conflict").write_text("main\n")
    git(edges, "commit", "-qam", "main")
    merged = subprocess.run(["git", "-C", str(edges), "merge", "side"], capture_output=True, env=TEST_ENV)
    assert merged.returncode == 1
    git(edges, "mv", "rename from", "rename to")
    git(edges, "rm", "delete staged")
    (edges / "delete disk").unlink()
    (edges / "mode only").chmod(0o755)
    (edges / "forced-mode.txt").chmod(0o755)
    (edges / "binary").write_bytes(b"a\0b\n")
    (edges / "forced.txt").write_text("forced staged\n")
    git(edges, "add", "mode only", "binary", "forced.txt", "forced-mode.txt")
    (edges / "forced-mode.txt").chmod(0o644)
    (edges / "forced.txt").write_text("forced disk\n")
    (edges / "forced-new.txt").write_text("forced new\n")
    (edges / "empty").write_bytes(b"")
    (edges / "vanish").write_text("vanish\n")
    os.symlink("binary", edges / "link")
    git(edges, "update-index", "--add", "--cacheinfo", "160000," + git(edges, "rev-parse", "HEAD").decode().strip() + ",submodule")
    os.utime(edges / "forced-stale.txt", (1600000000, 1600000000))
    edge_before = {str(p.relative_to(edges)): p.read_bytes() for p in edges.rglob("*") if p.is_file()}
    expected = {
        "Staged/binary": ["Binary", None],
        "Staged/conflict": ["Unmerged", None],
        "Staged/delete staged": [["delete staged"], [""]],
        "Staged/forced.txt": ["Binary", None],
        "Staged/forced-mode.txt": ["Binary", None],
        "Staged/mode only": [["mode only"], ["mode only"]],
        "Staged/rename to": [["rename from"], ["rename from"]],
        "Staged/submodule": ["Submodule", None],
        "Unstaged/conflict": ["Unmerged", None],
        "Unstaged/delete disk": [["delete disk"], [""]],
        "Unstaged/forced.txt": ["Binary", None],
        "Unstaged/forced-mode.txt": ["Binary", None],
        "Unstaged/submodule": ["Submodule", None],
        "Untracked/empty": [[""], [""]],
        "Untracked/forced-new.txt": ["Binary", None],
        "Untracked/link": ["Symlink", None],
        "Untracked/vanish": [[""], ["vanish"]],
    }
    vim(edges, "let expected = json_decode(" + quote(json.dumps(expected)) + ")\n" + r'''
function! Role(role)
  return filter(getbufinfo(), {_, b -> getbufvar(b.bufnr, 'diffview_role', '') == a:role})[0].bufnr
endfunction
DiffviewOpen
let entry_count = len(DiffviewEntries())
call assert_equal(len(expected), entry_count)
let seen = []
for i in range(entry_count)
  let left = Role('left')
  let right = Role('right')
  let key = getbufvar(right, 'diffview_section') . '/' . getbufvar(right, 'diffview_path')
  call add(seen, key)
  if has_key(expected, key)
    let pair = expected[key]
    if type(pair[0]) == v:t_string
      call assert_match(pair[0], getbufline(right, 1)[0], key)
    else
      call assert_equal(pair[0], getbufline(left, 1, '$'), key)
      call assert_equal(pair[1], getbufline(right, 1, '$'), key)
    endif
  else
    call assert_report('Unexpected entry ' . key)
  endif
  normal ]f
endfor
call assert_equal(sort(keys(expected)), sort(seen))
DiffviewClose
DiffviewOpen
belowright new
call setline(1, 'USER ADDED WINDOW')
let userwin = win_getid()
let userbuf = bufnr()
DiffviewClose
call assert_true(!empty(getwininfo(userwin)))
call assert_equal(['USER ADDED WINDOW'], getbufline(userbuf, 1, '$'))
call assert_equal(1, getbufvar(userbuf, '&modified'))
DiffviewOpen
enew
call setline(1, 'USER REPLACED PANEL')
let userwin = win_getid()
let userbuf = bufnr()
DiffviewClose
call assert_true(!empty(getwininfo(userwin)))
call assert_equal(['USER REPLACED PANEL'], getbufline(userbuf, 1, '$'))
call assert_equal(1, getbufvar(userbuf, '&modified'))
''', directory)
    assert edge_before == {str(p.relative_to(edges)): p.read_bytes() for p in edges.rglob("*") if p.is_file()}
    unborn = directory / "unborn"
    unborn.mkdir()
    git(unborn, "init", "-q")
    (unborn / "new").write_text("new\n")
    git(unborn, "add", ".")
    vim(unborn, r'''
DiffviewOpen
call assert_equal('panel', get(b:, 'diffview_role', ''))
call assert_match('EMPTY', getbufvar(bufnr('diffview://1/left'), 'diffview_source'))
call assert_equal(['new'], getbufline(bufnr('diffview://1/right'), 1, '$'))
DiffviewClose
''', directory)
    clean = directory / "clean"
    clean.mkdir()
    git(clean, "init", "-q")
    git(clean, "config", "user.name", "Diffview Test")
    git(clean, "config", "user.email", "diffview@example.invalid")
    (clean / "file").write_text("same\n")
    (clean / "marked.dat").write_text("same ASCII\n")
    (clean / "empty.dat").write_bytes(b"")
    (clean / "noeol.dat").write_bytes(b"same without final newline")
    (clean / "binary.bin").write_bytes(b"same\0binary\n")
    (clean / "normalized.dat").write_bytes(b"same CRLF\r\n")
    (clean / ".gitattributes").write_text("marked.dat -diff\nempty.dat -diff\nnoeol.dat -diff\nnormalized.dat -diff text eol=crlf\n")
    git(clean, "add", ".")
    git(clean, "commit", "-qm", "base")
    for name in ["file", "marked.dat", "empty.dat", "noeol.dat", "binary.bin", "normalized.dat"]:
        os.utime(clean / name, (1600000000, 1600000000))
    assert git(clean, "show", ":marked.dat") == (clean / "marked.dat").read_bytes()
    assert git(clean, "show", ":normalized.dat") == b"same CRLF\n"
    stale_index = (clean / ".git/index").read_bytes()
    (clean / "nested").mkdir()
    vim(clean / "nested", r'''
let original_cwd = getcwd()
DiffviewOpen
call assert_equal(original_cwd, getcwd())
call assert_true(index(getline(1, '$'), 'No changes') >= 0)
DiffviewRefresh
call assert_true(index(getline(1, '$'), 'No changes') >= 0)
DiffviewClose
call assert_equal(1, tabpagenr('$'))
''', directory)
    assert (clean / ".git/index").read_bytes() == stale_index
    bare = directory / "bare.git"
    git(directory, "init", "--bare", "-q", str(bare))
    vim(bare, r'''
DiffviewOpen
call assert_equal(1, tabpagenr('$'))
call assert_match('Bare repositories', execute('messages'))
''', directory)
    vim(directory, r'''
DiffviewOpen
call assert_equal(1, tabpagenr('$'))
call assert_equal(0, get(g:, 'diffview_enabled', 0))
''', directory)
    boundaries = directory / "boundaries"
    boundaries.mkdir()
    git(boundaries, "init", "-q")
    git(boundaries, "config", "user.name", "Diffview Test")
    git(boundaries, "config", "user.email", "diffview@example.invalid")
    (boundaries / "dir").mkdir()
    (boundaries / "dir/nested").write_text("BASE\n")
    (boundaries / "file.txt").write_text("BASE\n")
    git(boundaries, "add", ".")
    git(boundaries, "commit", "-qm", "base")
    (boundaries / "dir/nested").write_text("DISK\n")
    (boundaries / "file.txt").write_text("DISK\n")
    outside = directory / "outside"
    outside.mkdir()
    (outside / "nested").write_text("OUTSIDE\n")
    os.symlink(str(outside), boundaries / "outside-link")
    vim(boundaries, r'''
function! Role(role)
  return filter(getbufinfo(), {_, b -> getbufvar(b.bufnr, 'diffview_role', '') == a:role})[0].bufnr
endfunction
function! Window(role)
  return filter(getwininfo(), {_, w -> getbufvar(w.bufnr, 'diffview_role', '') == a:role})[0].winid
endfunction
function! Options(id)
  let location = win_id2tabwin(a:id)
  return map(['diff','scrollbind','cursorbind','foldmethod','foldcolumn','wrap'], {_, key -> gettabwinvar(location[0], location[1], '&' . key)})
endfunction
function! Label(id)
  let location = win_id2tabwin(a:id)
  return gettabwinvar(location[0], location[1], '&statusline')
endfunction
let origin = win_getid()
DiffviewOpen
call win_gotoid(Window('right'))
enew
call setline(1, 'UNSAVED USER')
let userwin = win_getid()
setlocal diff scrollbind cursorbind foldmethod=marker foldcolumn=3 wrap
let before_options = Options(userwin)
DiffviewClose
call assert_equal(before_options, Options(userwin), 'B02: user-owned window options survive')
call win_gotoid(userwin)
call assert_equal(['UNSAVED USER'], getline(1, '$'))
call assert_equal(1, &modified)
setlocal nomodified
tabclose
DiffviewOpen
call assert_equal('dir/nested', getbufvar(Role('right'), 'diffview_path'))
call rename('dir', 'saved-dir')
call rename('outside-link', 'dir')
normal o
call assert_false(index(getbufline(Role('right'), 1, '$'), 'OUTSIDE') >= 0, 'B03: ancestor symlinks are not followed')
call assert_match('\csymlink', join(getbufline(Role('right'), 1, '$'), "\n") . execute('messages'))
call rename('dir', 'outside-link')
call rename('saved-dir', 'dir')
call delete('outside-link')
DiffviewClose
DiffviewOpen
for i in range(5)
  if getbufvar(Role('right'), 'diffview_path') == 'file.txt'
    break
  endif
  normal ]f
endfor
let right = Window('right')
call delete('file.txt')
call win_gotoid(origin)
DiffviewRefresh
call assert_equal([''], getbufline(winbufnr(right), 1, '$'))
call assert_match('EMPTY', Label(right), 'B04: absent-side label refreshes across tabs')
call writefile(['BASE'], 'file.txt')
call writefile(['BASE'], 'dir/nested')
tabnew
DiffviewRefresh
call assert_equal(['No changes'], getbufline(winbufnr(right), 1, '$'))
call assert_match('No changes', Label(right), 'B04: empty-view label refreshes across tabs')
call writefile(['BACK'], 'file.txt')
DiffviewRefresh
let panel = getbufinfo(Role('panel'))[0].windows[0]
let focus = win_getid()
call win_gotoid(panel)
call assert_equal('file.txt', get(get(g:NERDTreeFileNode.GetSelected(), 'diffview_entry', {}), 'path', ''), 'empty-to-changed refresh reveals the first entry')
call win_gotoid(focus)
tabclose
DiffviewClose
''', directory)
    assert (outside / "nested").read_text() == "OUTSIDE\n"
    history = directory / "history"
    history.mkdir()
    git(history, "init", "-q")
    git(history, "config", "user.name", "Diffview Test")
    git(history, "config", "user.email", "diffview@example.invalid")
    for path, text in {"file.txt": "root\n", "deleted": "removed\n", "rename old": "rename\n",
                       "mode": "mode\n", "noeol": "old-noeol", "binary": "old\0",
                       "forced.txt": "forced root\n"}.items():
        (history / path).write_text(text)
    (history / ".gitattributes").write_text("forced.txt -diff\n")
    (history / "tree dir").mkdir()
    (history / "tree dir/nested").write_text("root nested\n")
    git(history, "add", ".")
    git(history, "commit", "-qm", "root")
    root_oid = git(history, "rev-parse", "HEAD").decode().strip()
    git(history, "tag", "left")
    weird_ref = "q'\";$(touch${IFS}INJECTED)|tag"
    git(history, "tag", weird_ref)
    git(history, "tag", "-a", "annotated", "-m", "root tag")
    (history / "file.txt").write_text("second\n")
    (history / "deleted").unlink()
    git(history, "mv", "rename old", "rename new")
    (history / "mode").chmod(0o755)
    (history / "added").write_text("added\n")
    (history / "noeol").write_text("new-noeol")
    (history / "binary").write_bytes(b"new\0")
    (history / "forced.txt").write_text("forced next\n")
    (history / "tree dir/nested").write_text("second nested\n")
    git(history, "add", ".")
    git(history, "commit", "-qm", "second")
    second_oid = git(history, "rev-parse", "HEAD").decode().strip()
    right_tree = git(history, "rev-parse", "HEAD^{tree}").decode().strip()
    git(history, "tag", "right")
    branch = git(history, "branch", "--show-current").decode().strip()
    git(history, "checkout", "-qb", "side")
    (history / "side file").write_text("side\n")
    git(history, "add", ".")
    git(history, "commit", "-qm", "side")
    git(history, "checkout", "-q", branch)
    (history / "file.txt").write_text("main\n")
    git(history, "commit", "-qam", "main")
    git(history, "merge", "--no-ff", "-qm", "merge", "side")
    (history / "file.txt").write_text("INDEX DIRTY\n")
    git(history, "add", "file.txt")
    (history / "file.txt").write_text("DISK DIRTY\n")
    before = {str(p.relative_to(history)): p.read_bytes() for p in history.rglob("*") if p.is_file()}
    invalid = ["DiffviewOpen only", "DiffviewOpen left right extra", "DiffviewOpen --help right",
               "DiffviewOpen HEAD..HEAD HEAD", "DiffviewOpen left ^right", "DiffviewOpen ^left right",
               "DiffviewCommit ^right", "DiffviewCommit left right",
               "DiffviewCommit left^{tree}", "DiffviewCommit does-not-exist"]
    vim(history, "let invalid = json_decode(" + quote(json.dumps(invalid)) + ")\n"
        + "let root_oid = " + quote(root_oid) + "\nlet second_oid = " + quote(second_oid)
        + "\nlet right_tree = " + quote(right_tree) + "\nlet weird_ref = " + quote(weird_ref) + "\n" + r'''
function! Role(role)
  return filter(getbufinfo(), {_, b -> getbufvar(b.bufnr, 'diffview_role', '') == a:role})[0].bufnr
endfunction
function! Check(path, left, right)
  let entry_count = len(DiffviewEntries())
  for i in range(entry_count)
    if getbufvar(Role('right'), 'diffview_path') == a:path
      break
    endif
    normal ]f
  endfor
  call assert_equal(a:path, getbufvar(Role('right'), 'diffview_path'))
  call assert_equal(a:left, getbufline(Role('left'), 1, '$'), a:path . ' left')
  call assert_equal(a:right, getbufline(Role('right'), 1, '$'), a:path . ' right')
  call assert_equal('panel', b:diffview_role, 'selection keeps panel focus')
endfunction
function! MoveRight(oid)
  let process = job_start(['git', 'update-ref', 'refs/tags/right', a:oid], {'in_io': 'null', 'out_io': 'null', 'err_io': 'null'})
  while job_status(process) == 'run'
    sleep 1m
  endwhile
  call assert_equal(0, job_info(process).exitval)
endfunction
let origin = win_getid()
for command in ['DiffviewOpen left right', 'DiffviewCommit right', 'DiffviewCommit annotated']
  execute command
  let entry_count = len(DiffviewEntries())
  for i in range(entry_count)
    if getbufvar(Role('right'), 'diffview_path') == 'forced.txt'
      break
    endif
    normal ]f
  endfor
  call assert_equal('forced.txt', getbufvar(Role('right'), 'diffview_path'))
  call assert_match('Binary', getbufline(Role('right'), 1)[0], command)
  call assert_match('Binary', getbufline(Role('left'), 1)[0], command)
endfor
DiffviewOpen left right
call Check('tree dir/nested', ['root nested'], ['second nested'])
let tree = b:NERDTree
let directory_node = filter(DiffviewEntries(), {_, n -> n.diffview_entry.path == 'tree dir/nested'})[0].parent
call cursor(tree.ui.getLineNum(directory_node), 1)
normal o
call assert_equal(0, directory_node.isOpen)
DiffviewRefresh
let directory_node = filter(DiffviewEntries(), {_, n -> n.diffview_entry.path == 'tree dir/nested'})[0].parent
call assert_equal(0, directory_node.isOpen, 'refresh keeps collapsed virtual directory')
normal o
call assert_equal(1, directory_node.isOpen)
let tree = b:NERDTree
let body = getline(1, '$')
let snapshot = getbufline(Role('right'), 1, '$')
let expression = getreginfo('=')
let Renderer = get(g:NERDTreeUI, 'render')
function! PartialTreeFailure() dict
  setlocal noreadonly modifiable
  call setline(1, 'partial renderer output')
  throw 'forced partial tree renderer failure'
endfunction
try
  let g:NERDTreeUI.render = function('PartialTreeFailure')
  DiffviewRefresh
  call assert_true(b:NERDTree is tree, 'failed refresh preserves exact tree object')
  call assert_equal(body, getline(1, '$'), 'partial tree output rolled back')
  call assert_equal(snapshot, getbufline(Role('right'), 1, '$'))
  call assert_equal(expression, getreginfo('='))
  call assert_true(&readonly && !&modifiable)
  let tabs = tabpagenr('$')
  DiffviewOpen left right
  call assert_equal(tabs, tabpagenr('$'), 'failed open removes candidate resources')
  call assert_true(b:NERDTree is tree)
finally
  let g:NERDTreeUI.render = Renderer
endtry
call Check('file.txt', ['root'], ['second'])
call assert_match(right_tree[0:6], getbufvar(Role('right'), 'diffview_source'))
call Check('added', [''], ['added'])
call Check('deleted', ['removed'], [''])
call Check('rename new', ['rename'], ['rename'])
call assert_equal('rename old', getbufvar(Role('left'), 'diffview_path'))
call Check('mode', ['mode'], ['mode'])
call Check('noeol', ['old-noeol'], ['new-noeol'])
call assert_equal(0, getbufvar(Role('left'), '&endofline'))
call assert_equal(0, getbufvar(Role('right'), '&endofline'))
call Check('file.txt', ['root'], ['second'])
let original_buffers = [Role('panel'), Role('left'), Role('right')]
for command in invalid
  execute command
  call assert_equal(original_buffers, [Role('panel'), Role('left'), Role('right')], command)
  call Check('file.txt', ['root'], ['second'])
endfor
let g:diffview_injected = 0
call g:DiffBranch("bad'|let g:diffview_injected=1")
call assert_equal(0, g:diffview_injected)
call assert_equal(original_buffers, [Role('panel'), Role('left'), Role('right')])
call MoveRight(root_oid)
normal o
call Check('file.txt', ['root'], ['second'])
let panel = getbufinfo(Role('panel'))[0].windows[0]
let right_location = win_id2tabwin(getbufinfo(Role('right'))[0].windows[0])
call win_gotoid(origin)
DiffviewRefresh
call assert_equal(['No changes'], getbufline(Role('right'), 1, '$'))
call assert_match('No changes', gettabwinvar(right_location[0], right_location[1], '&statusline'), 'B04: tree empty-view label from origin')
call win_gotoid(panel)
call assert_true(index(getline(1, '$'), 'No changes') >= 0)
DiffviewCommit right
call Check('file.txt', [''], ['root'])
call assert_equal('EMPTY', getbufvar(Role('left'), 'diffview_source'))
call MoveRight(second_oid)
normal o
call Check('file.txt', [''], ['root'])
let panel = getbufinfo(Role('panel'))[0].windows[0]
let left_location = win_id2tabwin(getbufinfo(Role('left'))[0].windows[0])
let right_location = win_id2tabwin(getbufinfo(Role('right'))[0].windows[0])
call win_gotoid(origin)
DiffviewRefresh
call assert_match(second_oid[0:6], gettabwinvar(right_location[0], right_location[1], '&statusline'), 'B04: commit label resolves new ref from origin')
call assert_match(root_oid[0:6], gettabwinvar(left_location[0], left_location[1], '&statusline'), 'B04: former EMPTY label becomes first parent')
call win_gotoid(panel)
call Check('file.txt', ['root'], ['second'])
DiffviewCommit annotated
call Check('file.txt', [''], ['root'])
DiffviewCommit HEAD
call assert_equal(1, len(DiffviewEntries()))
call Check('side file', [''], ['side'])
DiffBranch left
call Check('file.txt', ['root'], ['main'])
call ToggleDiffView()
call assert_equal(1, tabpagenr('$'))
call g:DiffBranch('left')
call Check('file.txt', ['root'], ['main'])
execute 'DiffBranch ' . weird_ref
call Check('file.txt', ['root'], ['main'])
call assert_false(filereadable('INJECTED'))
DiffviewOpen left:tree\ dir right:tree\ dir
call Check('nested', ['root nested'], ['second nested'])
DiffviewClose
''', directory)
    after = {str(p.relative_to(history)): p.read_bytes() for p in history.rglob("*") if p.is_file()}
    assert before == after, "Historical browsing must preserve all index/object/disk bytes"
    shallow = directory / "shallow"
    git(directory, "clone", "-q", "--depth", "1", "--no-local", "file://" + str(history), str(shallow))
    vim(shallow, r'''
DiffviewCommit HEAD
call assert_equal(1, tabpagenr('$'), 'missing parent is an error, not a root commit')
call assert_match('Git failed', execute('messages'))
''', directory)
    sha256 = directory / "sha256"
    sha256.mkdir()
    git(sha256, "init", "-q", "--object-format=sha256")
    git(sha256, "config", "user.name", "Diffview Test")
    git(sha256, "config", "user.email", "diffview@example.invalid")
    (sha256 / "file").write_text("root\n")
    git(sha256, "add", ".")
    git(sha256, "commit", "-qm", "root")
    (sha256 / "file").write_text("next\n")
    git(sha256, "commit", "-qam", "next")
    vim(sha256, r'''
DiffviewOpen HEAD^ HEAD
let panes = filter(getwininfo(), {_, w -> w.tabnr == tabpagenr()})
call sort(panes, {a, b -> a.wincol - b.wincol})
call assert_equal(['root'], getbufline(panes[1].bufnr, 1, '$'))
call assert_equal(['next'], getbufline(panes[2].bufnr, 1, '$'))
DiffviewCommit HEAD
DiffviewClose
call assert_equal(1, tabpagenr('$'))
''', directory)

    reading = directory / "reading"
    reading.mkdir()
    git(reading, "init", "-q")
    git(reading, "config", "user.name", "Diffview Test")
    git(reading, "config", "user.email", "diffview@example.invalid")
    (reading / "src").mkdir()
    (reading / "other").mkdir()
    (reading / "src/code.py").write_text("def greet():\n    return 1\n")
    (reading / "src/main.go").write_text("package main\nfunc main() {}\n")
    (reading / "old.py").write_text("def rename():\n    return 7\n")
    (reading / "other/code.py").write_text("def elsewhere():\n    return 3\n")
    (reading / "mode").write_text("mode\n")
    (reading / "opaque.unknown_diffview").write_text("opaque\n")
    git(reading, "add", ".")
    git(reading, "commit", "-qm", "reading root")
    (reading / "old.py").rename(reading / "new.go")
    (reading / "src/code.py").write_text("def greet():\n    return 2\n")
    (reading / "src/main.go").write_text("package main\nfunc main() {}\n// added\n")
    (reading / "mode").chmod(0o755)
    git(reading, "add", ".")
    git(reading, "commit", "-qm", "reading next")
    (reading / "src/code.py").write_text("def greet():\n    return 4\n")
    (reading / "untracked").write_text("untracked\n")
    (reading / "sample.c").write_text("int main(void) { return 0; }\n")
    (reading / "script").write_text("#!/usr/bin/env python3\n# vim: set tabstop=1:\nprint(42)\n")
    before_reading = {str(p.relative_to(reading)): p.read_bytes()
                      for p in reading.rglob("*") if p.is_file()}
    vim(reading, r'''
syntax enable
let g:language_filetypes = 0
augroup DiffviewReadingHooks
  autocmd FileType python,go,c let g:language_filetypes += 1
augroup END
function! ReadingRole(role)
  return filter(getbufinfo(), {_, b -> getbufvar(b.bufnr, 'diffview_role', '') == a:role})[0].bufnr
endfunction
function! ReadingChoose(path)
  let panel = ReadingRole('panel')
  let node = filter(DiffviewEntries(), {_, n -> n.diffview_entry.path == a:path})[0]
  call win_gotoid(getbufinfo(panel)[0].windows[0])
  call cursor(b:NERDTree.ui.getLineNum(node), 1)
  execute "normal \<CR>"
  return node
endfunction
edit src/code.py
call setline(1, 'UNSAVED target')
call deletebufline(bufnr(), 2, '$')
let target = bufnr()
let language_hooks = g:language_filetypes
let expression = getreginfo('=')
set nohidden autowrite autowriteall
DiffviewCommit HEAD -- src
call assert_equal('panel', b:diffview_role)
call assert_equal(2, len(DiffviewEntries()))
let node = ReadingChoose('src/code.py')
call assert_equal([1, 1], [node.diffview_entry.added, node.diffview_entry.deleted])
call assert_match('+1 -1', node.displayString())
call assert_match('2/4 entries | +2 -1', getline(3))
call assert_match('Filter: src', getline(4))
call assert_equal('python', getbufvar(ReadingRole('left'), '&syntax'))
call assert_equal('python', getbufvar(ReadingRole('right'), '&syntax'))
call assert_equal('diffview', getbufvar(ReadingRole('right'), '&filetype'))
call assert_equal(language_hooks, g:language_filetypes, 'snapshot detection never runs ordinary language hooks')
call assert_equal(expression, getreginfo('='))
let right = ReadingRole('right')
call win_gotoid(getbufinfo(right)[0].windows[0])
call assert_match('python', synIDattr(synID(1, 1, 1), 'name'))
let before_tick = getbufvar(right, 'changedtick')
let previous_path = $PATH
let $PATH = ''
DiffviewFilter ./src//.
let $PATH = previous_path
call assert_equal(before_tick, getbufvar(right, 'changedtick'), 'retained selection does not reload snapshot/Git')
DiffviewFilter nothing
call assert_equal(['No matching changes'], getbufline(right, 1, '$'))
call assert_equal('', getbufvar(right, '&syntax'))
DiffviewFilter
call assert_equal(4, len(DiffviewEntries()))
let mode_node = ReadingChoose('mode')
call assert_equal([0, 0], [mode_node.diffview_entry.added, mode_node.diffview_entry.deleted])
call ReadingChoose('new.go')
call assert_equal('python', getbufvar(ReadingRole('left'), '&syntax'))
call assert_equal('go', getbufvar(ReadingRole('right'), '&syntax'))
let previous_tree = b:NERDTree
let previous_body = getbufline(right, 1, '$')
let previous_path = $PATH
let $PATH = ''
DiffviewFilter src
let $PATH = previous_path
call assert_true(b:NERDTree is previous_tree, 'failed projection read keeps the previous tree')
call assert_equal(previous_body, getbufline(right, 1, '$'))
DiffviewFilter ../escape
call assert_true(b:NERDTree is previous_tree)
call assert_equal(previous_body, getbufline(right, 1, '$'))
call assert_match('traversal', execute('messages'))
DiffBranch --
call assert_true(b:NERDTree is previous_tree, 'legacy wrapper keeps revision validation')
function! ReadingRenderFailure() dict
  throw 'reading renderer failure'
endfunction
let NativeRender = get(g:NERDTreeDirNode, 'renderToString')
try
  let g:NERDTreeDirNode.renderToString = function('ReadingRenderFailure')
  DiffviewFilter src
  call assert_true(b:NERDTree is previous_tree)
  call assert_equal(previous_body, getbufline(right, 1, '$'))
finally
  let g:NERDTreeDirNode.renderToString = NativeRender
endtry
call ReadingChoose('src/code.py')
augroup DiffviewReadingSyntaxFailure
  autocmd Syntax python setlocal modifiable noreadonly | call setline(1, 'partial syntax damage') | syntax match ReadingPartial /./ | throw 'reading syntax failure'
augroup END
DiffviewRefresh
augroup DiffviewReadingSyntaxFailure
  autocmd!
augroup END
call assert_equal(['def greet():', '    return 2'], getbufline(right, 1, '$'))
call assert_equal('', getbufvar(right, '&syntax'))
call assert_false(getbufvar(right, '&modifiable'))
call assert_true(getbufvar(right, '&readonly'))
call assert_match('Syntax unavailable', execute('messages'))
let go_node = ReadingChoose('src/main.go')
let before_resources = [map(getbufinfo(), {_, b -> b.bufnr}), map(getwininfo(), {_, w -> w.winid})]
let invoking = win_getid()
augroup DiffviewReadingOpenFailure
  autocmd FileType go throw 'reading real file open failure'
augroup END
DiffviewGotoFile
augroup DiffviewReadingOpenFailure
  autocmd!
augroup END
call assert_equal(invoking, win_getid(), 'failed real open returns to its invoking window')
call assert_equal(before_resources, [map(getbufinfo(), {_, b -> b.bufnr}), map(getwininfo(), {_, w -> w.winid})])
call assert_match('reading real file open failure', execute('messages'))
call ReadingChoose('src/code.py')
let before_resources = [map(getbufinfo(), {_, b -> b.bufnr}), map(getwininfo(), {_, w -> w.winid})]
let invoking = win_getid()
augroup DiffviewReadingDirtyTargetFailure
  autocmd BufEnter */src/code.py call setline(1, 'HOOK dirty target remains') | throw 'reading dirty target BufEnter failure'
augroup END
DiffviewGotoFile
augroup DiffviewReadingDirtyTargetFailure
  autocmd!
augroup END
call assert_equal(invoking, win_getid())
call assert_equal(before_resources, [map(getbufinfo(), {_, b -> b.bufnr}), map(getwininfo(), {_, w -> w.winid})])
call assert_equal(['HOOK dirty target remains'], getbufline(target, 1, '$'))
call assert_true(bufloaded(target) && getbufvar(target, '&modified'))
call setbufline(target, 1, 'UNSAVED target')
let tabs = tabpagenr('$')
execute 'normal gf'
call assert_equal(tabs + 1, tabpagenr('$'))
call assert_equal(target, bufnr(), 'gf reuses the loaded dirty target')
call assert_equal(['UNSAVED target'], getline(1, '$'))
call assert_true(&modified)
call assert_false(exists('b:diffview_role'))
call assert_equal('python', &filetype)
call assert_equal([0, 1, 1], [&hidden, &autowrite, &autowriteall])
let user_window = win_getid()
DiffviewClose
call assert_false(empty(getwininfo(user_window)), 'closing comparison retains gf user tab')
DiffviewOpen HEAD~1:src HEAD:other
let right = ReadingRole('right')
let left = ReadingRole('left')
call win_gotoid(getbufinfo(left)[0].windows[0])
call cursor(2, 1)
DiffviewGotoFile
call assert_equal(target, bufnr(), 'left subtree prefix maps to src/code.py')
call assert_equal(1, line('.'), 'historical line is clamped to the dirty one-line target')
call win_gotoid(getbufinfo(right)[0].windows[0])
DiffviewGotoFile
call assert_match('/other/code.py$', expand('%:p'))
DiffviewClose
DiffviewOpen HEAD~1^{tree} HEAD^{tree}
let old_tabs = tabpagenr('$')
DiffviewGotoFile
call assert_equal(old_tabs, tabpagenr('$'), 'tree-only expression cannot guess a worktree mapping')
call assert_match('no proven', execute('messages'))
DiffviewClose
DiffviewCommit HEAD -- new.go
let right = ReadingRole('right')
call win_gotoid(getbufinfo(ReadingRole('left'))[0].windows[0])
let old_tabs = tabpagenr('$')
DiffviewGotoFile
call assert_equal(old_tabs, tabpagenr('$'), 'missing historical oldpath never creates a file')
DiffviewClose
DiffviewOpen -- sample.c script
let c_node = ReadingChoose('sample.c')
call assert_equal([-1, -1], [c_node.diffview_entry.added, c_node.diffview_entry.deleted])
let right = ReadingRole('right')
call assert_equal('c', getbufvar(right, '&syntax'))
call win_gotoid(getbufinfo(right)[0].windows[0])
call assert_match('cType', synIDattr(synID(1, 1, 1), 'name'))
call ReadingChoose('script')
call assert_equal('python', getbufvar(right, '&syntax'))
call assert_equal(8, getbufvar(right, '&tabstop'), 'snapshot modelines never execute')
DiffviewFilter untracked
call ReadingChoose('untracked')
call assert_equal('', getbufvar(right, '&syntax'), 'unknown filename/content clears prior syntax')
syntax off
DiffviewRefresh
call assert_equal('', getbufvar(right, '&syntax'))
DiffviewClose
augroup DiffviewReadingHooks
  autocmd!
augroup END
''', directory)
    after_reading = {str(p.relative_to(reading)): p.read_bytes()
                     for p in reading.rglob("*") if p.is_file()}
    assert before_reading == after_reading, "Reading/filter/gf must preserve every fixture byte"
    print("PASS: native syntax/isolation, numstat metadata and rows, literal projection/rollback, dirty gf and side subtree mappings")

    fzf_runtime = os.environ.get("FZF_RUNTIME")
    if fzf_runtime:
        if not (Path(fzf_runtime) / "plugin/fzf.vim").is_file():
            raise SystemExit("FZF_RUNTIME must point to the core junegunn/fzf checkout.")
        picker = directory / "picker repo"
        picker.mkdir()
        git(picker, "init", "-q", "-b", "main")
        git(picker, "config", "user.name", "Picker 作者 $();|'\tname")
        git(picker, "config", "user.email", "picker@example.invalid")
        (picker / "nested").mkdir()
        (picker / "file").write_text("ROOT\n")
        git(picker, "add", ".")
        git(picker, "commit", "-qm", "root-picker-key")
        root_commit = git(picker, "rev-parse", "HEAD").decode().strip()
        (picker / "file").write_text("NORMAL\n")
        git(picker, "commit", "-qam", "normal-picker-key 作者\t\x01\x1b $(touch INJECTED) | 'quote'")
        normal_commit = git(picker, "rev-parse", "HEAD").decode().strip()
        git(picker, "checkout", "-qb", "side")
        (picker / "side").write_text("SIDE\n")
        git(picker, "add", ".")
        git(picker, "commit", "-qm", "side-picker-key")
        git(picker, "checkout", "-q", "main")
        (picker / "file").write_text("MAIN\n")
        git(picker, "commit", "-qam", "main-picker-key")
        git(picker, "merge", "--no-ff", "-qm", "merge-picker-key", "side")
        merge_commit = git(picker, "rev-parse", "HEAD").decode().strip()
        before_picker = {str(p.relative_to(picker)): p.read_bytes()
                         for p in picker.rglob("*") if p.is_file()}
        vim(picker, "let fzf_runtime = " + quote(fzf_runtime)
            + "\nlet other_repo = " + quote(repo)
            + "\nlet root_commit = " + quote(root_commit)
            + "\nlet normal_commit = " + quote(normal_commit)
            + "\nlet merge_commit = " + quote(merge_commit) + "\n" + r'''
function! Role(role)
  return filter(getbufinfo(), {_, b -> getbufvar(b.bufnr, 'diffview_role', '') == a:role})[0].bufnr
endfunction
function! Buffers()
  return [Role('panel'), Role('left'), Role('right')]
endfunction
function! Pair(left, right, oid)
  call assert_equal(a:left, getbufline(Role('left'), 1, '$'))
  call assert_equal(a:right, getbufline(Role('right'), 1, '$'))
  call assert_match(a:oid, getbufvar(Role('right'), 'diffview_source'))
  call assert_equal('nerdtree', getbufvar(Role('panel'), '&filetype'))
  for role in ['left', 'right']
    call assert_true(getbufvar(Role(role), '&readonly'))
    call assert_false(getbufvar(Role(role), '&modifiable'))
  endfor
endfunction
function! WaitPickerQuery(buffer, query)
  let started = reltime()
  while reltimefloat(reltime(started)) < 5
    call term_wait(a:buffer, 30)
    let screen = join(map(range(1, term_getsize(a:buffer)[0]), {_, row -> term_getline(a:buffer, row)}), "\n")
    if stridx(screen, 'Commit> ' . a:query) >= 0 && (a:query == '' || screen =~ '\s1/\d\+')
      return
    endif
  endwhile
  call assert_report('fzf query/results did not become visible')
endfunction
function! WaitPicker()
  let started = reltime()
  let idle = 0
  while reltimefloat(reltime(started)) < 5
    sleep 10m
    if empty(filter(job_info(), {_, job -> job_status(job) == 'run'}))
        \ && empty(filter(getwininfo(), {_, w -> getbufvar(w.bufnr, '&filetype') == 'fzf'}))
      let idle += 1
      if idle == 2 | return | endif
    else
      let idle = 0
    endif
  endwhile
  call assert_report('fzf did not finish within 5 seconds')
endfunction
set nohidden autowriteall
edit file
call setline(1, 'UNSAVED picker buffer')
let userbuf = bufnr()
DiffviewCommit HEAD
let old_buffers = Buffers()
DiffviewCommit
call assert_equal(old_buffers, Buffers(), 'missing core fzf preserves explicit HEAD view')
call assert_match('junegunn/fzf', execute('messages'))
let &rtp = fzf_runtime . ',' . &rtp
runtime plugin/fzf.vim
let $FZF_DEFAULT_OPTS_FILE = ''
let g:fzf_layout = {'down': '40%'}
for [query, left, right, oid] in [
    \ ['normal-picker-key', ['ROOT'], ['NORMAL'], normal_commit],
    \ [root_commit[0:9], [''], ['ROOT'], root_commit],
    \ ['merge-picker-key', [''], ['SIDE'], merge_commit]]
  let $FZF_DEFAULT_OPTS = '--filter=' . query . ' --print-query --expect=ctrl-t --multi --accept-nth=2'
  DiffviewCommit
  call WaitPicker()
  call Pair(left, right, oid)
  DiffviewRefresh
  call Pair(left, right, oid)
  call assert_equal(['UNSAVED picker buffer'], getbufline(userbuf, 1, '$'))
  call assert_true(getbufvar(userbuf, '&modified'))
endfor
let $FZF_DEFAULT_OPTS = '--filter=merge-picker-key'
DiffviewCommit -- file
call WaitPicker()
call assert_equal(['No matching changes'], getbufline(Role('right'), 1, '$'))
call assert_equal(['Filter: file'], getbufline(Role('panel'), 4))
DiffviewRefresh
call assert_equal(['No matching changes'], getbufline(Role('right'), 1, '$'))
DiffviewFilter side
call Pair([''], ['SIDE'], merge_commit)
DiffviewFilter
call Pair([''], ['SIDE'], merge_commit)
DiffviewClose
setlocal bufhidden=wipe
let options = [&hidden, &autowrite, &autowriteall]
let g:fzf_layout = {'window': 'enew'}
let $FZF_DEFAULT_OPTS = '--filter=root-picker-key'
DiffviewCommit
call WaitPicker()
call Pair([''], ['ROOT'], root_commit)
call assert_equal(['UNSAVED picker buffer'], getbufline(userbuf, 1, '$'))
call assert_true(getbufvar(userbuf, '&modified'), 'in-place fzf never autosaves the caller')
call assert_equal(options, [&hidden, &autowrite, &autowriteall])
call assert_equal('wipe', getbufvar(userbuf, '&bufhidden'))
let old_buffers = Buffers()
let $FZF_DEFAULT_OPTS = '--filter=unmatched-picker-query'
DiffviewCommit
call WaitPicker()
call assert_equal(old_buffers, Buffers(), 'no match preserves existing view')
call Pair([''], ['ROOT'], root_commit)
let panel = win_getid()
let origin = getbufinfo(userbuf)[0].windows[0]
call win_gotoid(origin)
let resources = [map(getbufinfo(), {_, b -> b.bufnr}), map(getwininfo(), {_, w -> [w.winid, w.bufnr]})]
let options = [&winfixwidth, &winfixheight, &number, &spell, &hidden, &autowrite, &autowriteall]
let position = winsaveview()
let g:fzf_layout = {'window': 'enew | throw "forced after-enew initialization failure"'}
DiffviewCommit
call assert_equal(origin, win_getid(), 'initialization failure restores caller focus')
call assert_equal(userbuf, bufnr(), 'initialization failure restores caller buffer')
call assert_equal(resources, [map(getbufinfo(), {_, b -> b.bufnr}), map(getwininfo(), {_, w -> [w.winid, w.bufnr]})])
call assert_equal(options, [&winfixwidth, &winfixheight, &number, &spell, &hidden, &autowrite, &autowriteall])
call assert_equal(position, winsaveview())
call assert_equal('wipe', &bufhidden)
call assert_equal(['UNSAVED picker buffer'], getline(1, '$'))
call assert_true(&modified)
call win_gotoid(panel)
call Pair([''], ['ROOT'], root_commit)
call win_gotoid(origin)
for layout in ['enew', 'default']
  if layout == 'enew'
    let g:fzf_layout = {'window': 'enew'}
  else
    unlet! g:fzf_layout
  endif
  execute 'tcd ' . fnameescape(getcwd())
  let caller_directory = getcwd()
  call assert_equal(2, haslocaldir())
  let $FZF_DEFAULT_OPTS = '--filter=unmatched-picker-query'
  DiffviewCommit
  call WaitPicker()
  call assert_equal([caller_directory, 2], [getcwd(), haslocaldir()], 'creation preserves a preexisting tab-local cwd on no match')
  call assert_equal(resources, [map(getbufinfo(), {_, b -> b.bufnr}), map(getwininfo(), {_, w -> [w.winid, w.bufnr]})])
  execute 'tcd ' . fnameescape(caller_directory)
  let $FZF_DEFAULT_OPTS = ''
  augroup DiffviewPickerInitializationFailure
    autocmd FileType fzf let g:failed_picker_job = term_getjob(bufnr()) | let g:failed_picker_status = job_status(g:failed_picker_job) | throw 'forced fzf FileType initialization failure'
  augroup END
  DiffviewCommit
  augroup DiffviewPickerInitializationFailure
    autocmd!
  augroup END
  call WaitPicker()
  call assert_equal('run', g:failed_picker_status, 'FileType failure happens after the real terminal job starts')
  call assert_equal('dead', job_status(g:failed_picker_job), 'failed picker stops its owned terminal job')
  call assert_match('Cannot open fzf: forced fzf FileType initialization failure', execute('messages'))
  call assert_equal(origin, win_getid())
  call assert_equal(userbuf, bufnr())
  call assert_equal(resources, [map(getbufinfo(), {_, b -> b.bufnr}), map(getwininfo(), {_, w -> [w.winid, w.bufnr]})])
  call assert_equal(options, [&winfixwidth, &winfixheight, &number, &spell, &hidden, &autowrite, &autowriteall])
  call assert_equal(position, winsaveview())
  call assert_equal('wipe', &bufhidden)
  call assert_equal(['UNSAVED picker buffer'], getline(1, '$'))
  call assert_true(&modified)
  call assert_equal([caller_directory, 2], [getcwd(), haslocaldir()], 'FileType failure preserves the initial cwd scope')
  call win_gotoid(panel)
  call Pair([''], ['ROOT'], root_commit)
  call win_gotoid(origin)
endfor
let picker_cwd = getcwd()
let global_cwd = getcwd(-1)
let g:fzf_layout = {'window': 'enew'}
let $FZF_DEFAULT_OPTS = ''
DiffviewCommit
let terminal = filter(getbufinfo(), {_, b -> getbufvar(b.bufnr, '&filetype') == 'fzf'})[0].bufnr
execute 'tcd ' . fnameescape(other_repo)
let chosen_cwd = getcwd()
call assert_equal(2, haslocaldir())
call WaitPickerQuery(terminal, '')
call term_sendkeys(terminal, 'normal-picker-key')
call WaitPickerQuery(terminal, 'normal-picker-key')
call term_sendkeys(terminal, "\<CR>")
call WaitPicker()
call Pair(['ROOT'], ['NORMAL'], normal_commit)
let caller_location = win_id2tabwin(origin)
call assert_equal(chosen_cwd, getcwd(caller_location[1], caller_location[0]))
call assert_equal(2, haslocaldir(caller_location[1], caller_location[0]), 'real asynchronous selection retains latest caller tcd scope')
call assert_equal(global_cwd, getcwd(-1))
call assert_true(getbufvar(userbuf, '&modified'))
execute 'cd ' . fnameescape(picker_cwd)
let g:fzf_layout = {'down': '40%'}
function! fzf#run(spec) abort
  let g:picker_spec = a:spec
  let g:picker_calls = get(g:, 'picker_calls', 0) + 1
endfunction
DiffviewCommit -- file
let root_row = filter(copy(g:picker_spec.source), {_, row -> stridx(row, g:root_commit . "\t") == 0})[0]
execute 'cd ' . fnameescape(other_repo)
call g:picker_spec.sinklist([root_row])
call Pair([''], ['ROOT'], root_commit)
call assert_equal(resolve(other_repo), getcwd(), 'selection retains caller cwd while binding original repository')
call assert_equal(['Filter: file'], getbufline(Role('panel'), 4))
DiffviewRefresh
call assert_equal(1, g:picker_calls, 'refresh never relaunches fzf')
call Pair([''], ['ROOT'], root_commit)
let old_buffers = Buffers()
for output in [[], ['query', root_row], [root_row, root_row], ['bad selection'], 23, [23]]
  call g:picker_spec.sinklist(output)
  call assert_equal(old_buffers, Buffers(), 'malformed output preserves the old view')
  call Pair([''], ['ROOT'], root_commit)
endfor
call call(g:picker_spec.exit, [2])
call assert_match('\[diffview\].*fzf failed', execute('messages'))
call assert_equal(old_buffers, Buffers())
call Pair([''], ['ROOT'], root_commit)
DiffviewClose
call assert_equal(['UNSAVED picker buffer'], getbufline(userbuf, 1, '$'))
call assert_true(getbufvar(userbuf, '&modified'))
''', directory)
        after_picker = {str(p.relative_to(picker)): p.read_bytes()
                        for p in picker.rglob("*") if p.is_file()}
        assert before_picker == after_picker, "Commit search must preserve every fixture byte"
        print("PASS: real fzf filtered normal/root/merge, hostile display/defaults, short hash, no match; callback repo/OID binding, malformed output and refresh; dirty buffers and bytes")
    else:
        print("NOT RUN: optional fzf picker smoke (set FZF_RUNTIME to its core checkout)")

print("PASS: local sources/safety/lifecycle/paths; trees, root/normal/merge commits, ref refresh, invalid arguments, legacy wrappers; index/object/disk preservation")
