vim9script

const test_tmp = $DIFFVIEW_TEST_TMP
const case_name = $DIFFVIEW_TEST_CASE
const harness_root = expand('<sfile>:p:h:h')
const user_registers = ['"', '0', '1', '2', '3', '4', '5', '6', '7', '8', '9', 'a', '-', '/', '=']

def RegisterState(): dict<any>
  var registers: dict<any> = {}
  for name in user_registers
    # getreginfo preserves the raw expression and unnamed-register identity.
    registers[name] = getreginfo(name)
  endfor
  return registers
enddef

def SeedRegisters()
  for name in user_registers
    setreg(name, ['USER register ' .. name], name == 'a' ? 'V' : 'v')
  endfor
  setreg('=', '6 * 7')
enddef

def Panel(): number
  var panes = getwininfo()->filter((_, w) => w.tabnr == tabpagenr())
  sort(panes, (a, b) => a.wincol - b.wincol)
  assert_equal(3, len(panes), 'dedicated tab has list and two panes')
  assert_equal(['panel', 'left', 'right'],
    mapnew(panes, (_, w) => getbufvar(w.bufnr, 'diffview_role', '')), 'pane roles match visual direction')
  assert_equal('nerdtree', getbufvar(panes[0].bufnr, '&filetype'), 'real NERDTree left pane')
  var tree = getbufvar(panes[0].bufnr, 'NERDTree', {})
  assert_false(empty(tree), 'left pane owns a NERDTree instance')
  assert_true(has_key(tree, 'root') && has_key(tree, 'ui'), 'real node and renderer objects')
  assert_equal(get(g:NERDTreeFileNode.renderToString, 'name'), get(tree.root.renderToString, 'name'),
    'upstream node renderer is retained')
  for pane in panes[1 : 2]
    assert_equal('diffview', getbufvar(pane.bufnr, '&filetype'))
    assert_match('^diffview://\d\+/' .. getbufvar(pane.bufnr, 'diffview_role') .. '$', bufname(pane.bufnr))
  endfor
  return panes[0].winid
enddef

def Nodes(node: dict<any>): list<dict<any>>
  var nodes = [node]
  for child in get(node, 'children', [])
    extend(nodes, Nodes(child))
  endfor
  return nodes
enddef

def Entries(): list<dict<any>>
  var tree = getbufvar(winbufnr(Panel()), 'NERDTree')
  return Nodes(tree.root)->filter((_, node) => !empty(get(node, 'diffview_entry', {})))
enddef

def Node(section: string, path: string): dict<any>
  var found = Entries()->filter((_, node) => node.diffview_entry.path == path
    && (section == '' || node.diffview_entry.section == section))
  assert_equal(1, len(found), 'one raw entry: ' .. section .. '/' .. string(path))
  if len(found) != 1
    throw 'Missing or ambiguous raw tree entry: ' .. section .. '/' .. string(path)
  endif
  return found[0]
enddef

def TreeCursor(node: dict<any>)
  win_gotoid(Panel())
  var row = b:NERDTree.ui.getLineNum(node)
  assert_true(row > 0, 'node has a visible real NERDTree row')
  if row <= 0
    throw 'Tree node is not visible'
  endif
  cursor(row, 1)
  assert_true(g:NERDTreeFileNode.GetSelected() is node,
    'upstream selected-node API returns the exact node, not a parsed label')
enddef

def Labels(entry: dict<any>)
  var section = entry.section
  var panes = getwininfo()->filter((_, w) => w.tabnr == tabpagenr())
  sort(panes, (a, b) => a.wincol - b.wincol)
  var left = getwinvar(panes[1].winid, '&statusline')
  var right = getwinvar(panes[2].winid, '&statusline')
  for label in [left, right]
    assert_equal(0, stridx(label, section .. ' | '), 'visible section label')
  endfor
  assert_true(stridx(left, strtrans(entry.oldpath)) >= 0, 'left label identifies the original path')
  assert_true(stridx(right, strtrans(entry.path)) >= 0, 'right label identifies the destination path')
  if entry.oldmode == '000000'
    assert_match(' | EMPTY | ', left)
  elseif section == 'Staged'
    assert_match(' | HEAD [0-9a-f]\+ | ', left)
  else
    assert_match(' | INDEX | ', left)
  endif
  if entry.newmode == '000000'
    assert_match(' | EMPTY (absent) | ', right)
  elseif section == 'Staged'
    assert_match(' | INDEX | ', right)
  else
    assert_match(' | WORKTREE (disk; unsaved edits excluded) | ', right)
  endif
enddef

def Select(section: string, path: string)
  var node = Node(section, path)
  TreeCursor(node)
  feedkeys("\<CR>", 'xt')
  assert_equal(Panel(), win_getid(), 'file selection retains tree focus')
  if section != ''
    Labels(node.diffview_entry)
  endif
enddef

def Pair(left: list<string>, right: list<string>)
  var panes = getwininfo()->filter((_, w) => w.tabnr == tabpagenr())
  sort(panes, (a, b) => a.wincol - b.wincol)
  assert_equal(3, len(panes))
  assert_equal(left, getbufline(panes[1].bufnr, 1, '$'), 'left content')
  assert_equal(right, getbufline(panes[2].bufnr, 1, '$'), 'right content')
  for pane in panes[1 : 2]
    assert_true(getbufvar(pane.bufnr, '&readonly'), 'snapshot is readonly')
    assert_false(getbufvar(pane.bufnr, '&modifiable'), 'snapshot is nonmodifiable')
    assert_true(index(['nofile', 'nowrite'], getbufvar(pane.bufnr, '&buftype')) >= 0)
    assert_true(getwinvar(pane.winid, '&diff'), 'actual Vim diff is enabled')
  endfor
enddef

def Local()
  execute 'cd ' .. fnameescape(test_tmp .. '/local repo 中文/nested/subdir')
  var cwd = getcwd()
  execute 'edit ' .. fnameescape('../../both.txt')
  setline(1, ['UNSAVED user edits'])
  var userbuf = bufnr()
  var origin = win_getid()
  var initial_buffers = getbufinfo()->mapnew((_, b) => b.bufnr)
  var initial_autocmds = execute('autocmd')
  var initial_tabs = tabpagenr('$')

  DiffviewOpen
  assert_equal(initial_tabs + 1, tabpagenr('$'))
  assert_equal(cwd, getcwd(), 'opening preserves cwd')
  assert_equal(Panel(), win_getid(), 'initial focus is file panel')
  assert_match('Disk snapshots; unsaved edits excluded', join(getline(1, '$'), "\n"))
  assert_false(join(getbufline(winbufnr(Panel()), 1, '$'), "\n") =~ 'ignored.txt')
  assert_false(join(getbufline(winbufnr(Panel()), 1, '$'), "\n") =~ 'same.txt', 'no stat-only row beside real changes')
  Select('Staged', 'both.txt')
  Pair(['HEAD both'], ['INDEX both'])
  Select('Unstaged', 'both.txt')
  Pair(['INDEX both'], ['DISK both'])
  Select('Staged', 'staged.txt')
  Pair(['HEAD staged'], ['INDEX staged'])
  Select('Unstaged', 'unstaged.txt')
  Pair(['HEAD unstaged'], ['DISK unstaged'])
  Select('Unstaged', 'mode.txt')
  Pair(['same mode bytes'], ['same mode bytes'])
  Select('Untracked', 'untracked 空格.txt')
  Pair([''], ['DISK untracked'])

  Select('Unstaged', 'both.txt')
  var before = getbufline(winbufnr(Panel()), 1, '$')
  execute 'cd ' .. fnameescape(test_tmp .. '/nonrepo')
  DiffviewRefresh
  assert_equal(before, getbufline(winbufnr(Panel()), 1, '$'), 'refresh retains repository')
  Pair(['INDEX both'], ['DISK both'])
  assert_equal(['UNSAVED user edits'], getbufline(userbuf, 1, '$'))
  assert_true(getbufvar(userbuf, '&modified'))
  DiffviewClose
  assert_equal(initial_tabs, tabpagenr('$'))
  assert_equal(origin, win_getid(), 'close returns to origin')
  assert_equal(initial_buffers, getbufinfo()->mapnew((_, b) => b.bufnr), 'no scratch buffers leak')
  assert_equal(initial_autocmds, execute('autocmd'), 'no active autocmds leak')
  assert_false(&diff, 'origin window has no leaked diff')
  assert_equal(['UNSAVED user edits'], getline(1, '$'))
  assert_true(&modified)
  DiffviewClose

  execute 'cd ' .. fnameescape(cwd)
  call g:ToggleDiffView()
  assert_equal(initial_tabs + 1, tabpagenr('$'))
  call g:ToggleDiffView()
  assert_equal(initial_tabs, tabpagenr('$'))
  assert_true(getbufvar(userbuf, '&modified'))
enddef

def Clean()
  execute 'cd ' .. fnameescape(test_tmp .. '/clean')
  DiffviewOpen
  var rows = join(getbufline(winbufnr(Panel()), 1, '$'), "\n")
  assert_match('No changes', rows)
  assert_false(rows =~ 'file.txt', 'stale stat produces no false M row')
  DiffviewRefresh
  rows = join(getbufline(winbufnr(Panel()), 1, '$'), "\n")
  assert_match('No changes', rows)
  assert_false(rows =~ 'file.txt', 'refresh still omits stat-only row')
  DiffviewClose
  assert_equal(1, tabpagenr('$'))
enddef

def Unborn()
  execute 'cd ' .. fnameescape(test_tmp .. '/unborn')
  DiffviewOpen
  Select('Staged', 'first.txt')
  Pair([''], ['INDEX unborn'])
  Select('Unstaged', 'first.txt')
  Pair(['INDEX unborn'], ['DISK unborn'])
  Select('Untracked', 'new.txt')
  Pair([''], ['DISK new'])
  DiffviewClose
enddef

def Nonrepo()
  execute 'cd ' .. fnameescape(test_tmp .. '/nonrepo')
  var initial_buffers = getbufinfo()->mapnew((_, b) => b.bufnr)
  var error = ''
  try
    DiffviewOpen
  catch
    error = v:exception
  endtry
  var messages = error .. execute('messages') .. v:errmsg
  assert_match('\[diffview\]', messages, 'nonrepo reports tagged error')
  assert_equal(1, tabpagenr('$'), 'failure creates no tab')
  assert_equal(1, winnr('$'), 'failure creates no split')
  assert_equal(initial_buffers, getbufinfo()->mapnew((_, b) => b.bufnr))
enddef

def Special()
  execute 'cd ' .. fnameescape(test_tmp .. '/special')
  DiffviewOpen
  var rows = getbufline(winbufnr(Panel()), 1, '$')
  assert_false(join(rows, "\n") =~ "\t", 'tab in filename is escaped for display')
  assert_false(join(rows, "\n") =~ nr2char(1), 'SOH in filename is escaped for display')
  var names = ['space 中文.txt', '-leading.txt', "semi;$(touch INJECTED)|quote'\".txt",
    "tab\tname.txt", "line\nname.txt", "ctrl\x01name.txt", 'literal\n.txt', ':(glob)**']
  for i in range(len(names))
    assert_equal(2, len(Entries()->filter((_, node) => node.diffview_entry.path == names[i])),
      'one node per section for raw special path ' .. string(names[i]))
    Select('Staged', names[i])
    Pair(['HEAD special ' .. (i + 1)], ['INDEX special ' .. (i + 1)])
    Select('Unstaged', names[i])
    Pair(['INDEX special ' .. (i + 1)], ['DISK special ' .. (i + 1)])
  endfor
  assert_false(filereadable('INJECTED'), 'filename was never executed as shell code')
  DiffviewClose
enddef

def Refresh()
  execute 'cd ' .. fnameescape(test_tmp .. '/refresh')
  DiffviewOpen
  Select('Unstaged', 'file.txt')
  Pair(['HEAD refresh'], ['DISK before refresh'])
  writefile(['DISK refreshed'], 'file.txt')
  writefile(['NEW after open'], 'new.txt')
  Pair(['HEAD refresh'], ['DISK before refresh'])
  assert_false(join(getbufline(winbufnr(Panel()), 1, '$'), "\n") =~ 'new.txt',
    'no automatic file-list refresh')
  win_gotoid(Panel())
  normal r
  Pair(['HEAD refresh'], ['DISK refreshed'])
  Select('Untracked', 'new.txt')
  Pair([''], ['NEW after open'])
  win_gotoid(Panel())
  normal q
  assert_equal(1, tabpagenr('$'), 'q closes view')
  assert_false(&diff)
enddef

def WindowOptions(id: number): list<any>
  var tabwin = win_id2tabwin(id)
  return ['diff', 'scrollbind', 'cursorbind', 'foldmethod', 'foldcolumn', 'wrap', 'winfixwidth', 'winfixheight', 'number', 'spell']->mapnew(
    (_, option) => gettabwinvar(tabwin[0], tabwin[1], '&' .. option))
enddef

def PluginBuffers(): list<number>
  return getbufinfo()->filter((_, b) => getbufvar(b.bufnr, 'diffview_role', '') != '')
    ->mapnew((_, b) => b.bufnr)
enddef

def WaitForCleanup()
  var started = reltime()
  while !empty(PluginBuffers()) && reltimefloat(reltime(started)) < 1.0
    sleep 10m
  endwhile
  assert_equal([], PluginBuffers(), 'manual cleanup completes within 1 second')
enddef

def WaitForTimers(ids: list<number>)
  var started = reltime()
  while !empty(filter(copy(ids), (_, id) => !empty(timer_info(id))))
      && reltimefloat(reltime(started)) < 1.0
    sleep 10m
  endwhile
  assert_equal([], filter(copy(ids), (_, id) => !empty(timer_info(id))), 'old timers finish within 1 second')
enddef

def Lifecycle()
  execute 'cd ' .. fnameescape(test_tmp .. '/lifecycle')
  set nohidden autowriteall
  edit original.txt
  var origin = win_getid()
  var original = bufnr()
  vsplit replacement.txt
  var unrelated = win_getid()
  var replacement = bufnr()
  setlocal diff scrollbind cursorbind foldmethod=manual nowrap
  var options = WindowOptions(unrelated)
  setline(1, ['UNSAVED replacement'])
  win_gotoid(origin)
  setline(1, ['UNSAVED original'])

  DiffviewOpen
  var left = getwininfo()->filter((_, w) => getbufvar(w.bufnr, 'diffview_role', '') == 'left')[0].winid
  win_execute(left, 'close')
  WaitForCleanup()
  DiffviewClose
  assert_equal(['UNSAVED original'], getbufline(original, 1, '$'))
  assert_true(getbufvar(original, '&modified'), 'manual closure keeps original dirty')
  assert_equal(['UNSAVED replacement'], getbufline(replacement, 1, '$'))
  assert_true(getbufvar(replacement, '&modified'), 'manual closure keeps other buffer dirty')
  assert_equal(options, WindowOptions(unrelated), 'unrelated window options survive manual close')

  win_gotoid(origin)
  DiffviewOpen
  var right = getwininfo()->filter((_, w) => getbufvar(w.bufnr, 'diffview_role', '') == 'right')[0].winid
  win_gotoid(right)
  execute 'buffer ' .. replacement
  var lefts = getwininfo()->filter((_, w) => getbufvar(w.bufnr, 'diffview_role', '') == 'left')
  if !empty(lefts)
    win_execute(lefts[0].winid, 'close')
  endif
  WaitForCleanup()
  assert_true(win_id2tabwin(right)[0] > 0, 'inserted dirty user pane remains open')
  assert_equal(replacement, winbufnr(right), 'inserted pane still shows user buffer')
  var tabs_before_error = tabpagenr('$')
  var error = ''
  try
    execute 'DiffviewOpen invalid-test-revision HEAD'
  catch
    error = v:exception
  endtry
  assert_match('\[diffview\]', error .. execute('messages') .. v:errmsg)
  assert_equal(tabs_before_error, tabpagenr('$'), 'invalid replacement creates no extra tab')
  try
    DiffviewRefresh
  catch
    assert_match('\[diffview\]', v:exception)
  endtry
  DiffviewClose
  win_gotoid(origin)
  DiffviewOpen
  DiffviewClose

  # A pending callback for the old view must not clean up its replacement.
  win_gotoid(origin)
  DiffviewOpen
  var existing_timers = timer_info()->mapnew((_, timer) => timer.id)
  left = getwininfo()->filter((_, w) => getbufvar(w.bufnr, 'diffview_role', '') == 'left')[0].winid
  win_execute(left, 'close')
  var old_timers = timer_info()->mapnew((_, timer) => timer.id)
    ->filter((_, id) => index(existing_timers, id) < 0)
  assert_false(empty(old_timers), 'fixture reaches a pending old-cleanup timer before reopening')
  DiffviewOpen
  var new_buffers = PluginBuffers()
  assert_equal(3, len(new_buffers))
  WaitForTimers(old_timers)
  assert_equal(new_buffers, PluginBuffers(), 'old timer preserves replacement view buffers')
  Pair([''], ['DISK tracked change'])
  DiffviewClose
  WaitForCleanup()

  win_gotoid(origin)
  DiffviewOpen
  tabclose
  WaitForCleanup()
  assert_equal(['UNSAVED original'], getbufline(original, 1, '$'))
  assert_true(getbufvar(original, '&modified'))
  assert_equal(['UNSAVED replacement'], getbufline(replacement, 1, '$'))
  assert_true(getbufvar(replacement, '&modified'))
  assert_equal(options, WindowOptions(unrelated), 'unrelated window options survive replacement')
  assert_equal(['DISK original'], readfile('original.txt'), 'autowriteall never saves original')
  assert_equal(['DISK replacement'], readfile('replacement.txt'), 'autowriteall never saves replacement')
enddef

def Ownership()
  execute 'cd ' .. fnameescape(test_tmp .. '/lifecycle')
  set nohidden autowriteall
  DiffviewOpen
  var right = getwininfo()->filter((_, w) => getbufvar(w.bufnr, 'diffview_role', '') == 'right')[0].winid
  win_gotoid(right)
  enew
  setline(1, ['UNSAVED user-owned pane'])
  var userbuf = bufnr()
  setlocal diff scrollbind cursorbind foldmethod=marker foldcolumn=3 wrap
  var before = WindowOptions(right)
  DiffviewClose
  assert_true(win_id2tabwin(right)[0] > 0, 'user-owned pane survives close')
  var after = WindowOptions(right)
  writefile([json_encode({before: before, after: after,
    content: getbufline(userbuf, 1, '$'), modified: getbufvar(userbuf, '&modified')})],
    test_tmp .. '/ownership.facts.json')
  assert_equal(before, after, 'close preserves options of pane now owned by user')
  assert_equal(['UNSAVED user-owned pane'], getbufline(userbuf, 1, '$'))
  assert_true(getbufvar(userbuf, '&modified'))
  WaitForCleanup()
enddef

def Ancestor()
  execute 'cd ' .. fnameescape(test_tmp .. '/ancestor')
  DiffviewOpen
  Select('Unstaged', 'dir/file.txt')
  Pair(['HEAD inside'], ['DISK inside'])
  Select('Unstaged', 'dir/forced.dat')
  Unavailable('\cBinary')
  Select('Unstaged', 'dir/file.txt')
  var panel = Panel()
  var rightbuf = getwininfo()->filter((_, w) => getbufvar(w.bufnr, 'diffview_role', '') == 'right')[0].bufnr
  try
    assert_equal(0, rename('dir', 'saved-dir'))
    var link = job_start(['ln', '-s', test_tmp .. '/outside', 'dir'],
      {in_io: 'null', out_io: 'null', err_io: 'file', err_name: test_tmp .. '/ancestor.link.log'})
    var started = reltime()
    while job_status(link) == 'run' && reltimefloat(reltime(started)) < 1.0
      sleep 10m
    endwhile
    assert_equal('dead', job_status(link))
    assert_equal(0, job_info(link).exitval)
    assert_equal('link', getftype('dir'), 'fixture installs a symlink ancestor')
    win_gotoid(panel)
    normal o
    var observed = getbufline(rightbuf, 1, '$')
    var messages = execute('messages') .. v:errmsg
    writefile([json_encode({observed: observed, messages: messages})],
      test_tmp .. '/ancestor.facts.json')
    assert_false(index(observed, 'OUTSIDE fixture marker') >= 0,
      'selection must not follow a symlink ancestor outside repository')
    assert_match('\c\%(symlink\|unsupported\|cannot read\)', join(observed, "\n") .. messages,
      'symlink ancestor is an explicit error or unsupported entry')
    Select('Unstaged', 'dir/forced.dat')
    Unavailable('\csymlink\|unsupported')
    assert_false(index(getbufline(rightbuf, 1, '$'), 'OUTSIDE fixture marker') >= 0,
      'binary classification must not bypass ancestor checks')
  finally
    DiffviewClose
    if getftype('dir') == 'link'
      delete('dir')
    endif
    if isdirectory('saved-dir')
      assert_equal(0, rename('saved-dir', 'dir'))
    endif
  endtry
enddef

def Ref(name: string): string
  return readfile(test_tmp .. '/refs/' .. name)[0]
enddef

def Role(role: string): dict<any>
  var windows = getwininfo()->filter((_, w) => getbufvar(w.bufnr, 'diffview_role', '') == role)
  assert_equal(1, len(windows), 'one visible ' .. role .. ' pane')
  return windows[0]
enddef

def PaneOption(role: string, option: string): any
  var tabwin = win_id2tabwin(Role(role).winid)
  return gettabwinvar(tabwin[0], tabwin[1], '&' .. option)
enddef

def HistoricalIds(left: list<string>, right: list<string>)
  var expected = [left, right]
  for i in range(2)
    var label = PaneOption(i == 0 ? 'left' : 'right', 'statusline')
    if empty(expected[i])
      assert_match('EMPTY', label)
    else
      assert_false(empty(filter(copy(expected[i]), (_, oid) => stridx(label, oid[0 : 6]) >= 0)),
        'visible resolved object ID in ' .. label)
    endif
  endfor
enddef

def NoChanges()
  assert_match('No changes', join(getbufline(Role('panel').bufnr, 1, '$'), "\n"))
  for side in ['left', 'right']
    assert_equal(['No changes'], getbufline(Role(side).bufnr, 1, '$'))
    assert_equal('', getbufvar(Role(side).bufnr, 'diffview_source'), 'empty view clears old source metadata')
    assert_match('No changes', PaneOption(side, 'statusline'))
    assert_false(PaneOption(side, 'diff'))
  endfor
enddef

def Unavailable(pattern: string)
  for side in ['left', 'right']
    assert_match(pattern, join(getbufline(Role(side).bufnr, 1, '$'), "\n"))
    assert_true(getbufvar(Role(side).bufnr, '&readonly'))
    assert_false(getbufvar(Role(side).bufnr, '&modifiable'))
    assert_false(PaneOption(side, 'diff'), 'unsupported content is not a fake text diff')
  endfor
enddef

def Reject(command: string)
  messages clear
  v:errmsg = ''
  var error = ''
  try
    execute command
  catch
    error = v:exception
  endtry
  assert_match('\[diffview\]', error .. execute('messages') .. v:errmsg, command)
enddef

def Trees()
  execute 'cd ' .. fnameescape(test_tmp .. '/history repo 中文/nested')
  DiffviewOpen left right
  Select('', 'shared.txt')
  Pair(['LEFT shared'], ['RIGHT shared'])
  HistoricalIds([Ref('left'), Ref('left-tree')], [Ref('right'), Ref('right-tree')])
  assert_match('left', PaneOption('left', 'statusline'))
  assert_match('right', PaneOption('right', 'statusline'))
  assert_false(join(getbufline(Role('panel').bufnr, 1, '$'), "\n") =~ 'local-only.txt')
  Select('', 'left-only.txt')
  Pair(['LEFT only'], [''])
  Select('', 'added.txt')
  Pair([''], ['RIGHT added'])
  Select('', 'deleted.txt')
  Pair(['ROOT deleted'], [''])
  Select('', 'new 名称.txt')
  Pair(['stable rename content'], ['stable rename content'])
  assert_equal('old name.txt', getbufvar(Role('left').bufnr, 'diffview_path'))
  assert_equal('new 名称.txt', getbufvar(Role('right').bufnr, 'diffview_path'))
  Select('', 'mode.txt')
  Pair(['stable mode content'], ['stable mode content'])
  Select('', 'empty-added.txt')
  Pair([''], [''])
  assert_match('EMPTY', PaneOption('left', 'statusline'))
  for path in ['binary.bin', 'marked.dat']
    Select('', path)
    Unavailable('\cBinary')
  endfor
  DiffviewClose

  for alias in ["quote'branch", 'dollar$(touch${IFS}INJECTED_REF)', 'pipe|branch']
    execute 'DiffviewOpen left ' .. alias
    Select('', 'shared.txt')
    Pair(['LEFT shared'], ['RIGHT shared'])
    assert_false(filereadable('INJECTED_REF') || filereadable('../INJECTED_REF'),
      'revision is never evaluated by a shell')
    DiffviewClose
  endfor
  execute 'DiffviewOpen left:tree\ dir right:tree\ dir'
  Select('', 'nested.txt')
  Pair(['BASE subtree'], ['RIGHT subtree'])
  HistoricalIds([Ref('left-subtree')], [Ref('right-subtree')])
  DiffviewClose

  DiffviewOpen root^{tree} right^{tree}
  Select('', 'shared.txt')
  Pair(['BASE shared'], ['RIGHT shared'])
  HistoricalIds([Ref('root-tree')], [Ref('right-tree')])
  DiffviewOpen left left
  NoChanges()
  DiffviewRefresh
  NoChanges()
  DiffviewClose

  DiffviewOpen left HEAD
  Select('', 'shared.txt')
  Pair(['LEFT shared'], ['MERGED shared'])
  call g:ToggleDiffView()
  assert_equal([], PluginBuffers(), 'legacy Toggle closes a historical view')
  execute 'DiffviewOpen left HEAD'
  Select('', 'shared.txt')
  Pair(['LEFT shared'], ['MERGED shared'])
  DiffviewClose
enddef

def Commits()
  execute 'cd ' .. fnameescape(test_tmp .. '/history repo 中文')
  execute 'DiffviewCommit left'
  Select('', 'shared.txt')
  Pair(['BASE shared'], ['LEFT shared'])
  HistoricalIds([Ref('root')], [Ref('left')])
  Select('', 'left-only.txt')
  Pair([''], ['LEFT only'])
  execute 'DiffviewCommit right'
  Select('', 'marked.dat')
  Unavailable('\cBinary')
  execute 'DiffviewCommit root'
  Select('', 'shared.txt')
  Pair([''], ['BASE shared'])
  HistoricalIds([], [Ref('root')])
  Select('', 'marked.dat')
  Unavailable('\cBinary')
  execute 'DiffviewCommit merged'
  Select('', 'shared.txt')
  Pair(['RIGHT shared'], ['MERGED shared'])
  HistoricalIds([Ref('right')], [Ref('merge')])
  Select('', 'left-only.txt')
  Pair([''], ['LEFT only'])
  assert_false(join(getbufline(Role('panel').bufnr, 1, '$'), "\n") =~ 'deleted.txt',
    'merge view compares parent 1, not root/merge base')
  execute 'DiffviewCommit HEAD'
  Select('', 'shared.txt')
  Pair(['RIGHT shared'], ['MERGED shared'])
  HistoricalIds([Ref('right')], [Ref('merge')])
  assert_match('HEAD', PaneOption('right', 'statusline'))
  DiffviewClose
enddef

def HistoricalRefresh()
  var history = test_tmp .. '/history repo 中文'
  execute 'cd ' .. fnameescape(history)
  var origin = win_getid()
  DiffviewOpen left moving
  Select('', 'shared.txt')
  Pair(['LEFT shared'], ['RIGHT shared'])
  try
    writefile([Ref('merge')], history .. '/.git/refs/heads/moving')
    Select('', 'shared.txt')
    Pair(['LEFT shared'], ['RIGHT shared'])
    win_gotoid(origin)
    execute 'cd ' .. fnameescape(test_tmp .. '/nonrepo')
    DiffviewRefresh
    assert_equal(['MERGED shared'], getbufline(Role('right').bufnr, 1, '$'))
    assert_equal('shared.txt', getbufvar(Role('right').bufnr, 'diffview_path'))
    assert_match('moving', PaneOption('right', 'statusline'))
    HistoricalIds([Ref('left'), Ref('left-tree')], [Ref('merge'), Ref('merge-tree')])
  finally
    writefile([Ref('right')], history .. '/.git/refs/heads/moving')
    DiffviewClose
  endtry

  execute 'cd ' .. fnameescape(history)
  execute 'DiffviewCommit moving'
  Select('', 'shared.txt')
  Pair(['BASE shared'], ['RIGHT shared'])
  try
    writefile([Ref('merge')], history .. '/.git/refs/heads/moving')
    Select('', 'shared.txt')
    Pair(['BASE shared'], ['RIGHT shared'])
    DiffviewRefresh
    Pair(['RIGHT shared'], ['MERGED shared'])
    HistoricalIds([Ref('right')], [Ref('merge')])
    assert_match('moving', PaneOption('right', 'statusline'))
  finally
    writefile([Ref('right')], history .. '/.git/refs/heads/moving')
    DiffviewClose
  endtry
enddef

def Errors()
  var history = test_tmp .. '/history repo 中文'
  execute 'cd ' .. fnameescape(history)
  DiffviewOpen left right
  Select('', 'shared.txt')
  var buffers = PluginBuffers()
  var tabs = tabpagenr('$')
  for command in ['DiffviewOpen HEAD', 'DiffviewOpen left right HEAD',
      'DiffviewOpen left..right HEAD', 'DiffviewOpen left...right HEAD',
      'DiffviewOpen missing-test-revision HEAD', 'DiffviewOpen --help HEAD',
      'DiffviewOpen ' .. Ref('blob') .. ' HEAD', 'DiffviewCommit missing-test-revision',
      'DiffviewCommit HEAD HEAD', 'DiffviewCommit left..right',
      'DiffviewCommit --help', 'DiffviewCommit root^{tree}', 'DiffviewCommit ' .. Ref('blob')]
    Reject(command)
    assert_equal(buffers, PluginBuffers(), 'error preserves view buffers: ' .. command)
    assert_equal(tabs, tabpagenr('$'))
    Pair(['LEFT shared'], ['RIGHT shared'])
  endfor
  for directory in ['nonrepo', 'bare.git']
    execute 'cd ' .. fnameescape(test_tmp .. '/' .. directory)
    Reject('DiffviewOpen')
    assert_equal(buffers, PluginBuffers())
    Pair(['LEFT shared'], ['RIGHT shared'])
  endfor
  execute 'cd ' .. fnameescape(test_tmp .. '/shallow')
  Reject('DiffviewCommit HEAD')
  assert_equal(buffers, PluginBuffers(), 'missing shallow parent preserves previous view')
  Pair(['LEFT shared'], ['RIGHT shared'])
  DiffviewClose
enddef

def Exclusions()
  execute 'cd ' .. fnameescape(test_tmp .. '/history repo 中文')
  for command in ['DiffviewOpen ^left right', 'DiffviewOpen left ^right',
      'DiffviewOpen ^left ^right', 'DiffviewCommit ^HEAD']
    DiffviewOpen left right
    Select('', 'shared.txt')
    var buffers = PluginBuffers()
    var labels = [PaneOption('left', 'statusline'), PaneOption('right', 'statusline')]
    var tabs = tabpagenr('$')
    Reject(command)
    assert_equal(buffers, PluginBuffers(), 'exclusion preserves old view: ' .. command)
    assert_equal(labels, [PaneOption('left', 'statusline'), PaneOption('right', 'statusline')],
      'exclusion preserves visible source labels: ' .. command)
    assert_equal(tabs, tabpagenr('$'))
    Pair(['LEFT shared'], ['RIGHT shared'])
    DiffviewClose
  endfor
  DiffviewOpen merged^1 merged
  Select('', 'shared.txt')
  Pair(['RIGHT shared'], ['MERGED shared'])
  DiffviewClose
  execute 'DiffviewCommit HEAD^1'
  Select('', 'shared.txt')
  Pair(['BASE shared'], ['RIGHT shared'])
  HistoricalIds([Ref('root')], [Ref('right')])
  DiffviewClose
enddef

def Edges()
  execute 'cd ' .. fnameescape(test_tmp .. '/edges')
  DiffviewOpen
  Select('', 'deleted.txt')
  Pair(['HEAD deleted'], [''])
  assert_match('EMPTY', PaneOption('right', 'statusline'))
  Select('Staged', 'empty-added.txt')
  Pair([''], [''])
  Select('', 'new.txt')
  Pair(['unchanged rename'], ['unchanged rename'])
  assert_equal('old.txt', getbufvar(Role('left').bufnr, 'diffview_path'))
  assert_equal('new.txt', getbufvar(Role('right').bufnr, 'diffview_path'))
  Select('Unstaged', 'mode.txt')
  Pair(['unchanged mode'], ['unchanged mode'])
  Select('Unstaged', 'noeol.txt')
  Pair(['HEAD no final newline'], ['DISK no final newline'])
  assert_false(getbufvar(Role('left').bufnr, '&endofline'))
  assert_false(getbufvar(Role('right').bufnr, '&endofline'))
  for path in ['binary.bin', 'marked.dat']
    Select('Unstaged', path)
    Unavailable('\cBinary')
  endfor
  Select('Staged', 'marked-staged.dat')
  Unavailable('\cBinary')
  Select('Untracked', 'marked-untracked.dat')
  Unavailable('\cBinary')
  for path in ['leaf-link', 'untracked-link']
    Select('', path)
    Unavailable('\csymlink\|unsupported')
    assert_false(join(getbufline(Role('right').bufnr, 1, '$'), "\n") =~ 'OUTSIDE fixture marker')
  endfor
  Select('', 'submodule')
  Unavailable('\csubmodule\|unsupported')
  for section in ['Staged', 'Unstaged']
    Select(section, 'conflict.txt')
    Unavailable('\cunmerged\|conflict')
  endfor
  DiffviewClose
enddef

def CrossTab()
  execute 'cd ' .. fnameescape(test_tmp .. '/cross-tab')
  var origin = win_getid()
  DiffviewOpen
  Select('Unstaged', 'file.txt')
  Pair(['HEAD cross'], ['DISK cross'])
  var unrelated = -1
  try
    assert_equal(0, delete('file.txt'))
    win_gotoid(origin)
    DiffviewRefresh
    assert_equal([''], getbufline(Role('right').bufnr, 1, '$'))
    assert_match('EMPTY', PaneOption('right', 'statusline'), 'cross-tab absent-side label')
    assert_match('EMPTY', getbufvar(Role('right').bufnr, 'diffview_source'))
    tabnew
    unrelated = bufnr()
    setline(1, ['UNSAVED unrelated tab'])
    writefile(['HEAD cross'], 'file.txt')
    DiffviewRefresh
    NoChanges()
    writefile(['DISK cross'], 'file.txt')
    var refresh_origin = win_getid()
    DiffviewRefresh
    assert_equal(refresh_origin, win_getid(), 'empty-to-changed refresh keeps the unrelated dirty tab focused')
    assert_equal(['DISK cross'], getbufline(Role('right').bufnr, 1, '$'))
    assert_equal(['HEAD cross'], getbufline(Role('left').bufnr, 1, '$'))
    assert_match('INDEX', getbufvar(Role('left').bufnr, 'diffview_source'))
    assert_match('INDEX', PaneOption('left', 'statusline'))
    assert_match('WORKTREE', getbufvar(Role('right').bufnr, 'diffview_source'))
    assert_match('WORKTREE', PaneOption('right', 'statusline'), 'cross-tab label restored with changes')
    var panel = Role('panel')
    var cursor_row = getcurpos(panel.winid)[1]
    try
      win_gotoid(panel.winid)
      var node = Node('Unstaged', 'file.txt')
      var row = b:NERDTree.ui.getLineNum(node)
      assert_true(row > 0)
      assert_equal(row, cursor_row, 'empty-to-changed refresh reveals the selected leaf, not a header')
      assert_true(stridx(getline(row), node.displayString()) >= 0, 'refreshed selected row matches the actual rendered leaf')
      assert_true(g:NERDTreeFileNode.GetSelected() is node)
      # Do not reposition the cursor before Enter: that would hide the regression.
      feedkeys("\<CR>", 'xt')
      Pair(['HEAD cross'], ['DISK cross'])
    finally
      win_gotoid(refresh_origin)
    endtry
  finally
    writefile(['DISK cross'], 'file.txt')
    DiffviewClose
  endtry
  assert_equal(['UNSAVED unrelated tab'], getbufline(unrelated, 1, '$'))
  assert_true(getbufvar(unrelated, '&modified'), 'cross-tab refresh preserves unrelated dirty tab')
enddef

def ReadFailure()
  execute 'cd ' .. fnameescape(test_tmp .. '/read-failure')
  DiffviewOpen
  Select('Unstaged', 'file.txt')
  var saved_path = $PATH
  try
    assert_equal(0, rename('file.txt', 'saved.txt'))
    Reject('normal o')
    Pair(['HEAD readable'], ['DISK readable'])
    assert_equal(0, rename('saved.txt', 'file.txt'))
    setenv('PATH', test_tmp .. '/no-tools')
    Reject('DiffviewRefresh')
    Pair(['HEAD readable'], ['DISK readable'])
    setenv('PATH', saved_path)
    Select('Unstaged', 'forced.dat')
    Unavailable('\cBinary')
    var previous = getbufline(Role('right').bufnr, 1, '$')
    assert_equal(0, rename('forced.dat', 'saved-forced.dat'))
    Reject('normal o')
    assert_equal(previous, getbufline(Role('right').bufnr, 1, '$'),
      'missing forced-binary file reports error and preserves old comparison')
  finally
    setenv('PATH', saved_path)
    if filereadable('saved.txt')
      rename('saved.txt', 'file.txt')
    endif
    if filereadable('saved-forced.dat')
      rename('saved-forced.dat', 'forced.dat')
    endif
    DiffviewClose
  endtry
enddef

def Navigation()
  execute 'cd ' .. fnameescape(test_tmp .. '/local repo 中文')
  DiffviewOpen
  Select('Staged', 'both.txt')
  normal ]f
  Pair(['HEAD staged'], ['INDEX staged'])
  normal [f
  Pair(['HEAD both'], ['INDEX both'])
  normal [f
  Pair([''], ['DISK untracked'])
  normal ]f
  Pair(['HEAD both'], ['INDEX both'])
  var panel = Panel()
  feedkeys("\<Tab>", 'xt')
  assert_equal('left', b:diffview_role)
  feedkeys("\<S-Tab>", 'xt')
  assert_equal(panel, win_getid())
  for i in range(3)
    feedkeys("\<Tab>", 'xt')
  endfor
  assert_equal(panel, win_getid(), 'pane navigation wraps')
  var section = Node('Staged', 'both.txt').parent
  TreeCursor(section)
  feedkeys("\<CR>", 'xt')
  assert_false(section.isOpen, 'section Enter collapses the real directory')
  Pair(['HEAD both'], ['INDEX both'])
  feedkeys("\<CR>", 'xt')
  assert_true(section.isOpen, 'section Enter expands the real directory')
  normal q
  for key in [']f', '[f', 'r', 'q', '<Tab>']
    assert_equal({}, maparg(key, 'n', false, true), 'mapping is local: ' .. key)
  endfor
enddef

def BinaryClean()
  execute 'cd ' .. fnameescape(test_tmp .. '/binary-clean')
  DiffviewOpen
  NoChanges()
  DiffviewRefresh
  NoChanges()
  DiffviewClose
enddef

def BinaryMixed()
  execute 'cd ' .. fnameescape(test_tmp .. '/binary-mixed')
  DiffviewOpen
  var rows = getbufline(Role('panel').bufnr, 1, '$')
  for path in ['forced.dat', 'noeol.dat', 'crlf.txt']
    assert_equal(-1, stridx(join(rows, "\n"), path), 'binary stale-stat row omitted: ' .. path)
  endfor
  assert_equal(9, len(Entries()), 'nine real changes retained')
  assert_equal(2, len(Entries()->filter((_, node) => node.diffview_entry.path == 'mode.dat')),
    'both mode-only groups retained')
  for section in ['Staged', 'Unstaged']
    Select(section, 'real.dat')
    Unavailable('\cBinary')
    Select(section, 'mode.dat')
    Unavailable('\cBinary')
  endfor
  Select('Unstaged', 'text.txt')
  Pair(['HEAD ordinary text'], ['DISK ordinary text'])
  Select('Unstaged', 'nul.bin')
  Unavailable('\cBinary')
  Select('Staged', 'added.dat')
  Unavailable('\cBinary')
  Select('', 'empty.dat')
  assert_equal('Unstaged', getbufvar(Role('right').bufnr, 'diffview_section'))
  Unavailable('\cBinary')
  Select('', 'rename-new.dat')
  assert_equal('rename-old.dat', getbufvar(Role('left').bufnr, 'diffview_path'))
  assert_equal('rename-new.dat', getbufvar(Role('right').bufnr, 'diffview_path'))
  Unavailable('\cBinary')
  DiffviewRefresh
  assert_equal(rows, getbufline(Role('panel').bufnr, 1, '$'), 'binary refresh retains real rows and omits false ones')
  Unavailable('\cBinary')
  DiffviewClose
enddef

def Large()
  execute 'cd ' .. fnameescape(test_tmp .. '/large')
  var started = reltime()
  DiffviewOpen
  var opened = reltimefloat(reltime(started))
  var content = getbufline(Role('right').bufnr, 1, '$')
  assert_equal(20000, len(content))
  assert_equal(sha256(join(readfile('000-large.txt'), "\n")), sha256(join(content, "\n")))
  started = reltime()
  Select('Untracked', 'item-200.txt')
  Pair([''], ['item 200'])
  var selected = reltimefloat(reltime(started))
  started = reltime()
  DiffviewRefresh
  var refreshed = reltimefloat(reltime(started))
  Pair([''], ['item 200'])
  started = reltime()
  DiffviewClose
  writefile([json_encode({files: 201, bytes: getfsize('000-large.txt'),
    open_seconds: opened, select_seconds: selected, refresh_seconds: refreshed,
    close_seconds: reltimefloat(reltime(started))})], test_tmp .. '/large.metrics.json')
enddef

def EmptyStart()
  assert_equal(1, len(getbufinfo()), 'fresh Vim has only its unnamed buffer')
  assert_equal('', bufname(), 'no file was edited before DiffviewOpen')
  assert_true(bufnr('#') <= 0, 'fresh Vim has no alternate buffer')
  assert_equal([''], getline(1, '$'))
  assert_false(&modified)
  var origin = win_getid()
  var buffers = getbufinfo()->mapnew((_, b) => b.bufnr)
  execute 'cd ' .. fnameescape(test_tmp .. '/tree repo')
  v:errmsg = ''
  DiffviewOpen
  assert_equal('', v:errmsg, 'direct empty-session open must not trigger Creator E194')
  assert_equal(Panel(), win_getid(), 'direct open focuses the real tree')
  Select('Staged', 'src/deep/both.txt')
  Pair(['HEAD nested'], ['INDEX nested'])
  DiffviewRefresh
  Pair(['HEAD nested'], ['INDEX nested'])
  DiffviewClose
  assert_equal(origin, win_getid())
  assert_equal(buffers, getbufinfo()->mapnew((_, b) => b.bufnr), 'empty-session open leaves no tree/snapshot buffers')
  assert_equal('', bufname())
  assert_equal([''], getline(1, '$'))
  assert_false(&modified)
enddef

def TreeNodes()
  execute 'cd ' .. fnameescape(test_tmp .. '/tree repo')
  SeedRegisters()
  var registers = RegisterState()
  DiffviewOpen
  assert_equal(registers, RegisterState(), 'successful native render preserves expression/search/yank registers')
  var tree = getbufvar(winbufnr(Panel()), 'NERDTree')
  for node in Nodes(tree.root)->filter((_, n) => has_key(n, 'children'))
    assert_true(node.isOpen, 'sections and nested directories start expanded')
  endfor
  var staged = Node('Staged', 'src/deep/both.txt')
  var unstaged = Node('Unstaged', 'src/deep/both.txt')
  assert_true(staged isnot unstaged, 'same path has two independent nodes')
  for node in [staged, unstaged, unstaged.parent, unstaged.parent.parent]
    assert_false(empty(node.path.flagSet._flagsForScope('diffview')),
      'file and ancestor directories carry comparison flags')
    TreeCursor(node)
    assert_true(stridx(getline('.'), node.path.flagSet.renderToString()) >= 0,
      'real FlagSet indicators appear in the native rendered row')
  endfor
  assert_match('M', staged.path.flagSet.renderToString())
  assert_match('M', unstaged.parent.path.flagSet.renderToString(), 'directory aggregates modified descendants')
  var removed = Node('Unstaged', 'gone/leaf.txt')
  assert_equal('D', removed.diffview_entry.status)
  assert_match('D', removed.path.flagSet.renderToString())
  assert_match('D', removed.parent.path.flagSet.renderToString(), 'deleted descendants remain indicated')
  var renamed = Node('Staged', 'new name.txt')
  assert_equal('R', renamed.diffview_entry.status)
  assert_match('R', renamed.path.flagSet.renderToString())
  var untracked = Node('Untracked', 'new deep/leaf.txt')
  assert_equal('?', untracked.diffview_entry.status)
  assert_true(stridx(untracked.path.flagSet.renderToString(), '?') >= 0)
  Select('Staged', 'src/deep/both.txt')
  Pair(['HEAD nested'], ['INDEX nested'])
  Select('Unstaged', 'src/deep/both.txt')
  Pair(['INDEX nested'], ['DISK nested'])
  Select('Unstaged', 'src/same.txt')
  Pair(['HEAD src same'], ['DISK src same'])
  Select('Unstaged', 'other/same.txt')
  Pair(['HEAD other same'], ['DISK other same'])
  Select('Unstaged', '.hidden/change.txt')
  Pair(['HEAD hidden'], ['DISK hidden'])
  Select('Unstaged', 'gone/leaf.txt')
  Pair(['HEAD deleted'], [''])
  Select('Untracked', 'new deep/leaf.txt')
  Pair([''], ['DISK nested untracked'])
  Select('Staged', 'new name.txt')
  Pair(['stable tree rename'], ['stable tree rename'])
  assert_equal('old dir/old.txt', getbufvar(Role('left').bufnr, 'diffview_path'))

  Select('Staged', 'src/sibling.txt')
  Pair(['HEAD sibling'], ['INDEX sibling'])
  var native_node = Node('Staged', 'src/sibling.txt')
  var headers = getline(1, 2)
  assert_equal(['[diffview] LOCAL', 'Disk snapshots; unsaved edits excluded'], headers)
  g:NERDTreeRender()
  assert_equal(headers, getline(1, 2), 'public native rerender preserves comparison headers')
  assert_equal(registers, RegisterState(), 'public native rerender preserves the raw expression register')
  var native_row = tree.ui.getLineNum(native_node)
  assert_true(native_row > 0)
  assert_true(stridx(getline(native_row), native_node.displayString()) >= 0,
    'native row identity agrees with actual screen text, independently of GetSelected')
  TreeCursor(native_node)
  feedkeys("\<CR>", 'xt')
  Pair(['HEAD sibling'], ['INDEX sibling'])

  var names = ["tab\tname.txt", "line\nname.txt", "ctrl\x01name.txt",
    'line^@name.txt', 'literal\n.txt', ':(glob)**', "bell\x07name.txt", 'bell^Gname.txt']
  assert_equal(strtrans(names[1]), strtrans(names[3]), 'fixture includes colliding newline display text')
  assert_equal(strtrans(names[6]), strtrans(names[7]), 'fixture includes colliding NERDTree delimiter display text')
  for i in range(len(names))
    for section in ['Staged', 'Unstaged']
      Select(section, 'weird/' .. names[i])
      assert_equal('weird/' .. names[i], getbufvar(Role('right').bufnr, 'diffview_path'))
      Pair([(section == 'Staged' ? 'HEAD' : 'INDEX') .. ' identity ' .. (i + 1)],
        [(section == 'Staged' ? 'INDEX' : 'DISK') .. ' identity ' .. (i + 1)])
    endfor
  endfor
  Select('Unstaged', 'src/deep/both.txt')
  var deep = Node('Unstaged', 'src/deep/both.txt').parent
  var calls = readfile($DIFFVIEW_TEST_GIT_LOG, 'b')
  TreeCursor(deep)
  normal o
  assert_false(deep.isOpen)
  assert_equal(-1, tree.ui.getLineNum(Node('Unstaged', 'src/deep/change.txt')))
  normal o
  assert_true(deep.isOpen)
  TreeCursor(Node('Unstaged', 'src/deep/both.txt'))
  normal p
  assert_true(g:NERDTreeFileNode.GetSelected() is deep, 'p selects the actual parent directory')
  normal X
  normal O
  assert_true(deep.isOpen, 'recursive expansion is available')
  assert_equal(calls, readfile($DIFFVIEW_TEST_GIT_LOG, 'b'), 'tree-only navigation does not run Git')
  assert_equal(registers, RegisterState(), 'folding and native re-render preserve user registers')
  TreeCursor(deep)
  normal o
  assert_false(deep.isOpen)
  normal ]f
  Pair(['HEAD change'], ['DISK change'])
  assert_true(deep.isOpen, 'next file opens its ancestors')
  assert_true(g:NERDTreeFileNode.GetSelected() is Node('Unstaged', 'src/deep/change.txt'),
    'next file reveals and focuses the selected node')
  var other = Node('Unstaged', 'other/same.txt').parent
  TreeCursor(other)
  normal o
  assert_false(other.isOpen)
  DiffviewRefresh
  assert_equal(registers, RegisterState(), 'refresh render preserves user registers')
  assert_false(Node('Unstaged', 'other/same.txt').parent.isOpen,
    'refresh retains surviving unrelated directory collapse')
  assert_true(Node('Unstaged', 'src/deep/change.txt').parent.isOpen)
  Pair(['HEAD change'], ['DISK change'])
  Select('Staged', 'src/deep/both.txt')
  Pair(['HEAD nested'], ['INDEX nested'])
  Select('Unstaged', 'src/deep/both.txt')
  Pair(['INDEX nested'], ['DISK nested'])
  for key in ['m', 'i', 's', 't', 'T', 'C', 'cd', 'CD', 'u', 'U', 'B', 'D', 'gb']
    assert_false(get(maparg(key, 'n', false, true), 'rhs', '') =~ 'nerdtree#ui_glue#invokeKeyMap',
      'comparison tree has no native filesystem/open/root action: ' .. key)
  endfor
  DiffviewClose
  assert_equal(registers, RegisterState(), 'closing preserves user registers')
enddef

def TreeHistory()
  execute 'cd ' .. fnameescape(test_tmp .. '/tree-history')
  for command in ['DiffviewOpen nt-left nt-right', 'DiffviewCommit nt-right']
    execute command
    assert_equal(6, len(Entries()), 'both file/directory collision directions retain every entry')
    Select('', 'swap')
    Pair(['LEFT file to directory'], [''])
    Select('', 'swap/child.txt')
    Pair([''], ['RIGHT directory child'])
    Select('', 'flip')
    Pair([''], ['RIGHT directory to file'])
    Select('', 'flip/old.txt')
    Pair(['LEFT directory child'], [''])
    Select('', 'deleted/deep/only.txt')
    Pair(['LEFT historical only'], [''])
    assert_false(isdirectory('deleted'), 'virtual historical ancestors create no disk placeholders')
    Select('', 'sub tree/child.txt')
    Pair(['LEFT subtree'], ['RIGHT subtree'])
    DiffviewRefresh
    Pair(['LEFT subtree'], ['RIGHT subtree'])
    assert_equal(6, len(Entries()), 'refresh retains virtual and collision entries')
    Select('', 'deleted/deep/only.txt')
    Pair(['LEFT historical only'], [''])
    DiffviewClose
  endfor
  execute 'DiffviewOpen nt-left:sub\ tree nt-right:sub\ tree'
  assert_equal(1, len(Entries()), 'subtree model has comparison-relative paths')
  Select('', 'child.txt')
  Pair(['LEFT subtree'], ['RIGHT subtree'])
  assert_equal('child.txt', getbufvar(Role('right').bufnr, 'diffview_path'))
  assert_match('nt-right:sub tree', PaneOption('right', 'statusline'))
  DiffviewClose
enddef

def NerdGlobals(): dict<any>
  var options: dict<any> = {}
  for name in ['NERDTreeWinPos', 'NERDTreeWinSize', 'NERDTreeMinimalUI', 'NERDTreeShowHidden',
      'NERDTreeShowBookmarks', 'NERDTreeShowFiles', 'NERDTreeIgnore', 'NERDTreeChDirMode', 'NERDTreeUseTCD',
      'NERDTreeCascadeSingleChildDir', 'NERDTreeDirArrowExpandable', 'NERDTreeDirArrowCollapsible']
    options[name] = deepcopy(get(g:, name))
  endfor
  return {options: options, prototypes: deepcopy([g:NERDTree, g:NERDTreeUI,
      g:NERDTreeFileNode, g:NERDTreeDirNode, g:NERDTreePath, g:NERDTreeFlagSet]),
    maps: deepcopy(g:NERDTreeKeyMap.All()), listeners: deepcopy(g:NERDTreePathNotifier.GetListenersMap())}
enddef

def UserTreeState(buf: number, win: number): dict<any>
  var tree = getbufvar(buf, 'NERDTree')
  var location = win_id2tabwin(win)
  return {lines: getbufline(buf, 1, '$'), root: tree.root.path.str(),
    nodes: Nodes(tree.root)->mapnew((_, node) => [node.path.str(), get(node, 'isOpen', -1),
      node.path.flagSet.renderToString()]), cursor: getcurpos(win),
    options: WindowOptions(win), statusline: gettabwinvar(location[0], location[1], '&statusline')}
enddef

def WaitForJobs()
  var started = reltime()
  var idle_ticks = 0
  while reltimefloat(reltime(started)) < 2.0
    var pending = job_info()->filter((_, job) => job_status(job) == 'run'
      || index(['open', 'buffered'], ch_status(job_getchannel(job))) >= 0)
    idle_ticks = empty(pending) ? idle_ticks + 1 : 0
    if idle_ticks >= 2
      return
    endif
    sleep 10m
  endwhile
  assert_true(false, 'dependency jobs and close callbacks finish within 2 seconds')
enddef

def TreeIsolation()
  execute 'cd ' .. fnameescape(test_tmp .. '/user-tree')
  set nohidden autowriteall
  edit open/file.txt
  setline(1, ['UNSAVED ordinary user buffer'])
  var userbuf = bufnr()
  execute 'NERDTree ' .. fnameescape(test_tmp .. '/user-tree')
  b:NERDTree.root.openRecursively()
  g:NERDTreeRender()
  WaitForJobs()
  var usertree = b:NERDTree
  var treebuf = bufnr()
  var treewin = win_getid()
  nnoremap <silent> <buffer> zx :let g:diffview_test_user_map = 1<CR>
  var usermap = maparg('zx', 'n', false, true)
  usertree.root.path.flagSet.addFlag('fixture', 'USER')
  g:NERDTreeRender()
  tabnew
  execute 'NERDTreeMirror'
  assert_equal(treebuf, bufnr(), 'fixture mirrors the same ordinary NERDTree buffer')
  var mirror = win_getid()
  WaitForJobs()
  win_gotoid(treewin)
  WaitForJobs()
  var original = UserTreeState(treebuf, treewin)
  var globals = NerdGlobals()
  var autocmds = execute('autocmd')
  var cwd = getcwd()
  SeedRegisters()
  var registers = RegisterState()
  var tabs = tabpagenr('$')

  execute 'cd ' .. fnameescape(test_tmp .. '/tree repo')
  var request_cwd = getcwd()
  DiffviewOpen
  assert_equal(registers, RegisterState(), 'Open preserves raw register information')
  assert_true(getbufvar(winbufnr(Panel()), 'NERDTree') isnot usertree, 'comparison owns a separate tree instance')
  Select('Staged', 'src/deep/both.txt')
  Pair(['HEAD nested'], ['INDEX nested'])
  if case_name == 'tree_git'
    assert_equal(original, UserTreeState(treebuf, treewin), 'Open preserves the settled user tree before external events')
    assert_equal(registers, RegisterState())
    var comparison_win = Role('panel').winid
    var flags = Entries()->mapnew((_, node) => node.path.flagSet.renderToString())
    var calls = getfsize($DIFFVIEW_TEST_GIT_LOG)
    var userwin = getwininfo()->filter((_, w) => w.bufnr == userbuf)[0].winid
    try
      writefile(['temporary coexistence event'], test_tmp .. '/user-tree/open/closed/deep.txt')
      win_execute(userwin, 'doautocmd CursorHold')
      win_gotoid(Panel())
      WaitForJobs()
      assert_true(getfsize($DIFFVIEW_TEST_GIT_LOG) > calls, 'real git-status callback executed')
      assert_equal(flags, Entries()->mapnew((_, node) => node.path.flagSet.renderToString()),
        'asynchronous worktree status cannot replace comparison node flags')
      Pair(['HEAD nested'], ['INDEX nested'])
    finally
      writefile(['USER deep file'], test_tmp .. '/user-tree/open/closed/deep.txt')
      win_execute(userwin, 'doautocmd CursorHold')
      win_gotoid(Panel())
      WaitForJobs()
    endtry
    # Let the ordinary tree apply its own status update before the next baseline.
    win_gotoid(treewin)
    WaitForJobs()
    var updated = UserTreeState(treebuf, treewin)
    for key in ['root', 'cursor', 'options', 'statusline']
      assert_equal(original[key], updated[key], 'external status preserves user-tree structure: ' .. key)
    endfor
    assert_equal(original.nodes->mapnew((_, node) => node[0 : 1]),
      updated.nodes->mapnew((_, node) => node[0 : 1]), 'external status keeps paths and expansion state')
    var after_event = RegisterState()
    for name in user_registers->copy()->filter((_, reg) => reg != '=')
      assert_equal(registers[name], after_event[name], 'ordinary status render preserves register ' .. name)
    endfor
    original = updated
    setreg('=', '6 * 7')
    registers = RegisterState()
    win_gotoid(comparison_win)
    assert_equal(flags, Entries()->mapnew((_, node) => node.path.flagSet.renderToString()),
      'ordinary tree updates remain separate from comparison flags')
    Pair(['HEAD nested'], ['INDEX nested'])
  endif
  Reject('DiffviewOpen missing-tree-revision HEAD')
  Pair(['HEAD nested'], ['INDEX nested'])
  DiffviewRefresh
  assert_equal(registers, RegisterState(), 'Refresh preserves raw register information')
  Pair(['HEAD nested'], ['INDEX nested'])
  DiffviewClose
  assert_equal(registers, RegisterState(), 'Close preserves raw register information')
  assert_equal(request_cwd, getcwd(), 'comparison never changes cwd')
  assert_equal(tabs, tabpagenr('$'))
  assert_true(win_id2tabwin(mirror)[0] > 0, 'mirrored user tree window survives')
  assert_equal(original, UserTreeState(treebuf, treewin), 'ordinary tree contents/state/options survive')
  assert_equal(globals, NerdGlobals(), 'no global prototypes/options/listeners/maps changed')
  assert_equal(autocmds, execute('autocmd'), 'no global user/dependency autocommands changed')
  assert_equal(registers, RegisterState(), 'expression/search/anonymous/numeric/named registers survive')
  win_gotoid(treewin)
  assert_equal(usermap, maparg('zx', 'n', false, true), 'ordinary tree buffer map remains')
  normal zx
  assert_equal(1, g:diffview_test_user_map)
  assert_equal(['UNSAVED ordinary user buffer'], getbufline(userbuf, 1, '$'))
  assert_true(getbufvar(userbuf, '&modified'))
  assert_equal(['USER tree disk change'], readfile(test_tmp .. '/user-tree/open/file.txt'))

  call g:ToggleDiffView()
  assert_equal(registers, RegisterState(), 'Toggle opening preserves raw register information')
  Panel()
  call g:ToggleDiffView()
  assert_equal(registers, RegisterState(), 'Toggle closing preserves raw register information')
  assert_equal(original, UserTreeState(treebuf, treewin), 'Toggle preserves the independent tree')

  DiffviewOpen
  win_execute(Role('left').winid, 'close')
  WaitForCleanup()
  assert_equal(original, UserTreeState(treebuf, treewin), 'manual comparison cleanup leaves user tree alone')
  assert_equal(globals, NerdGlobals())
  assert_equal(['UNSAVED ordinary user buffer'], getbufline(userbuf, 1, '$'))
  execute 'cd ' .. fnameescape(cwd)
enddef

def Dependency()
  execute 'cd ' .. fnameescape(test_tmp .. '/tree repo')
  assert_equal(0, exists(':NERDTree'), 'fixture truly omits NERDTree')
  edit src/deep/both.txt
  setline(1, ['UNSAVED missing-dependency buffer'])
  var userbuf = bufnr()
  var buffers = getbufinfo()->mapnew((_, b) => b.bufnr)
  var windows = gettabinfo()
  Reject('DiffviewOpen')
  assert_match('\cNERDTree', execute('messages') .. v:errmsg, 'missing dependency names the installation requirement')
  assert_equal(buffers, getbufinfo()->mapnew((_, b) => b.bufnr))
  assert_equal(windows, gettabinfo(), 'dependency failure preserves original layout')
  assert_true(&modified)
  assert_equal(['UNSAVED missing-dependency buffer'], getbufline(userbuf, 1, '$'))
  &runtimepath = $NERDTREE_RUNTIME .. ',' .. &runtimepath
  runtime plugin/NERD_tree.vim
  DiffviewOpen
  Select('Unstaged', 'src/deep/both.txt')
  Pair(['INDEX nested'], ['DISK nested'])
  DiffviewClose
  assert_true(getbufvar(userbuf, '&modified'), 'install/retry keeps the original dirty buffer')
enddef

def RenderFailure()
  g:diffview_test_render_failures += 1
  throw 'fixture NERDTree renderer failure'
enddef

def ComparisonState(): dict<any>
  var focus = win_getid()
  var panel = Role('panel')
  var tree = getbufvar(panel.bufnr, 'NERDTree')
  win_gotoid(panel.winid)
  var selected = g:NERDTreeFileNode.GetSelected()
  var nodes = Nodes(tree.root)->mapnew((_, node) => [deepcopy(get(node, 'diffview_entry', {})),
    get(node, 'isOpen', -1), tree.ui.getLineNum(node), node.path.flagSet.renderToString()])
  var cursor = getcurpos()
  win_gotoid(focus)
  var panes = [panel, Role('left'), Role('right')]
  return {focus: focus, cursor: cursor, selected: deepcopy(get(selected, 'diffview_entry', {})),
    rows: getbufline(panel.bufnr, 1, '$'), nodes: nodes,
    resources: [getbufinfo()->mapnew((_, b) => b.bufnr),
      getwininfo()->mapnew((_, w) => [w.winid, w.bufnr, w.tabnr]), tabpagenr('$')],
    timers: timer_info()->mapnew((_, timer) => timer.id), autocmds: execute('autocmd'),
    bodies: panes->mapnew((_, w) => getbufline(w.bufnr, 1, '$')),
    readonly: panes->mapnew((_, w) => [getbufvar(w.bufnr, '&readonly'), getbufvar(w.bufnr, '&modifiable')]),
    options: panes->mapnew((_, w) => WindowOptions(w.winid)),
    sources: panes[1 : 2]->mapnew((_, w) => [getbufvar(w.bufnr, 'diffview_section'),
      getbufvar(w.bufnr, 'diffview_path'), getbufvar(w.bufnr, 'diffview_source')]),
    labels: [PaneOption('left', 'statusline'), PaneOption('right', 'statusline')],
    registers: RegisterState()}
enddef

def TreeRollback()
  execute 'cd ' .. fnameescape(test_tmp .. '/tree repo')
  set nohidden autowriteall
  edit src/deep/both.txt
  setline(1, ['UNSAVED tree rollback buffer'])
  var userbuf = bufnr()
  SeedRegisters()
  var registers = RegisterState()
  DiffviewOpen
  assert_equal(registers, RegisterState(), 'initial render preserves registers')
  Select('Unstaged', 'src/deep/both.txt')
  var buffers = PluginBuffers()
  var tree = getbufvar(Role('panel').bufnr, 'NERDTree')
  var tabs = tabpagenr('$')
  var globals = NerdGlobals()
  win_gotoid(Role('left').winid)
  var original = ComparisonState()
  augroup DiffviewTestTreeFailure
    autocmd FileType nerdtree throw 'fixture NERDTree FileType failure'
  augroup END
  try
    Reject('DiffviewOpen')
  finally
    augroup DiffviewTestTreeFailure
      autocmd!
    augroup END
  endtry
  assert_equal(buffers, PluginBuffers(), 'tree FileType failure retains old buffers')
  assert_equal(tabs, tabpagenr('$'))
  Pair(['INDEX nested'], ['DISK nested'])
  assert_equal(original, ComparisonState(), 'FileType failure preserves the complete comparison state')
  for command in ['DiffviewOpen HEAD HEAD', 'DiffviewRefresh']
    var original_nodes = Nodes(tree.root)
    var FileRender = get(g:NERDTreeFileNode, 'renderToString')
    var DirRender = get(g:NERDTreeDirNode, 'renderToString')
    var InstanceRender = get(tree.root, 'renderToString')
    g:diffview_test_render_failures = 0
    try
      if command == 'DiffviewRefresh'
        writefile(['DISK changed during failed refresh'], 'src/deep/both.txt')
        writefile(['NEW during failed refresh'], 'rollback-added.txt')
      endif
      # Throw inside native UI.render, after it has cleared/unlocked its buffer.
      g:NERDTreeFileNode.renderToString = RenderFailure
      g:NERDTreeDirNode.renderToString = RenderFailure
      tree.root.renderToString = RenderFailure
      Reject(command)
      assert_true(g:diffview_test_render_failures > 0, 'fixture reached the native mid-render failure: ' .. command)
      assert_equal(original, ComparisonState(), 'mid-render failure preserves full state: ' .. command)
      var current = getbufvar(Role('panel').bufnr, 'NERDTree')
      assert_true(current is tree, 'rollback retains the original tree instance')
      var current_nodes = Nodes(current.root)
      assert_equal(len(original_nodes), len(current_nodes))
      for i in range(min([len(original_nodes), len(current_nodes)]))
        assert_true(original_nodes[i] is current_nodes[i], 'rollback retains original node identities')
      endfor
    finally
      g:NERDTreeFileNode.renderToString = FileRender
      g:NERDTreeDirNode.renderToString = DirRender
      tree.root.renderToString = InstanceRender
      if command == 'DiffviewRefresh'
        writefile(['DISK nested'], 'src/deep/both.txt')
        delete('rollback-added.txt')
      endif
    endtry
    assert_equal(globals, NerdGlobals(), 'failed rendering does not change global NERDTree APIs/options/maps/listeners')
  endfor
  Select('Unstaged', 'src/deep/change.txt')
  Pair(['HEAD change'], ['DISK change'])
  DiffviewRefresh
  Pair(['HEAD change'], ['DISK change'])
  DiffviewClose
  WaitForCleanup()
  assert_equal(['UNSAVED tree rollback buffer'], getbufline(userbuf, 1, '$'))
  assert_true(getbufvar(userbuf, '&modified'), 'tree errors never save or discard original edits')
enddef

def WaitPicker()
  var started = reltime()
  var idle = 0
  while reltimefloat(reltime(started)) < 5.0
    var ui = getbufinfo()->filter((_, b) => getbufvar(b.bufnr, '&filetype') == 'fzf')
    var jobs = job_info()->filter((_, job) => job_status(job) == 'run'
      || index(['open', 'buffered'], ch_status(job_getchannel(job))) >= 0)
    idle = empty(ui) && empty(jobs) ? idle + 1 : 0
    if idle >= 2
      return
    endif
    sleep 10m
  endwhile
  throw 'Real fzf picker did not finish and clean its UI within 5 seconds'
enddef

def PickerFilter(query: string)
  $FZF_DEFAULT_OPTS = '--filter=' .. shellescape(query)
  DiffviewCommit
  WaitPicker()
enddef

def PickerGitCalls(): list<string>
  return filereadable($DIFFVIEW_TEST_GIT_LOG)
    ? readfile($DIFFVIEW_TEST_GIT_LOG, 'b')->filter((_, line) => line != '') : []
enddef

def PickerOidUsed(oid: string, first_call: number)
  var calls = PickerGitCalls()[first_call : ]
  assert_true(!empty(filter(calls, (_, line) => index(split(line, "\n", true), 'rev-parse') >= 0
    && index(split(line, "\n", true), oid .. '^{commit}') >= 0)),
    'selected/refreshed commit is resolved using its full immutable OID')
enddef

def PickerReal()
  execute 'cd ' .. fnameescape(test_tmp .. '/picker repo 中文/nested')
  var cwd = getcwd()
  edit ../change.txt
  setline(1, ['UNSAVED picker user buffer'])
  var userbuf = bufnr()
  set nohidden autowriteall
  var layout = deepcopy(g:fzf_layout)
  var calls = len(PickerGitCalls())
  PickerFilter('PICK_OLDER')
  Select('', 'change.txt')
  Pair(['PICK ROOT'], ['PICK OLDER'])
  HistoricalIds([Ref('picker-root')], [Ref('picker-older')])
  PickerOidUsed(Ref('picker-older'), calls)
  assert_equal(cwd, getcwd(), 'picker does not permanently change nested cwd')
  calls = len(PickerGitCalls())
  DiffviewRefresh
  Pair(['PICK ROOT'], ['PICK OLDER'])
  PickerOidUsed(Ref('picker-older'), calls)
  PickerFilter('META_AUTHOR_NEEDLE')
  Select('', 'change.txt')
  Pair(['PICK ROOT'], ['PICK OLDER'])
  PickerFilter('ROOT_AUTHOR_NEEDLE')
  Select('', 'change.txt')
  Pair([''], ['PICK ROOT'])
  HistoricalIds([], [Ref('picker-root')])
  PickerFilter('PICK_MERGE')
  assert_equal(1, len(Entries()), 'merge selection uses only first-parent changes')
  Select('', 'side.txt')
  Pair([''], ['PICK SIDE'])
  HistoricalIds([], [Ref('picker-merge')])
  PickerFilter('PICK_SIDE')
  Select('', 'side.txt')
  Pair([''], ['PICK SIDE'])
  HistoricalIds([], [Ref('picker-side')])
  PickerFilter(Ref('picker-normal')[0 : 6])
  Select('', 'change.txt')
  Pair(['PICK OLDER'], ['PICK NORMAL'])
  HistoricalIds([Ref('picker-older')], [Ref('picker-normal')])
  # User defaults must not turn a query or an expected key into a revision.
  $FZF_DEFAULT_OPTS = '--print-query --expect=enter --multi --filter=PICK_OLDER'
  DiffviewCommit
  WaitPicker()
  Select('', 'change.txt')
  Pair(['PICK ROOT'], ['PICK OLDER'])
  assert_equal(layout, g:fzf_layout, 'core layout preference is preserved')
  assert_equal(['UNSAVED picker user buffer'], getbufline(userbuf, 1, '$'))
  assert_true(getbufvar(userbuf, '&modified'))
  for path in ['FZF_INJECTED', 'FZF_AUTHOR_INJECTED', '../FZF_INJECTED', '../FZF_AUTHOR_INJECTED']
    assert_false(filereadable(path), 'metadata is never executed')
  endfor
  writefile([json_encode({scope: 'real core+binary filtered execution; not terminal UI',
    path_binary: exepath('fzf'), core_binary: fzf#exec(), layout: g:fzf_layout})],
    test_tmp .. '/picker-real.facts.json')
  DiffviewClose
  assert_true(getbufvar(userbuf, '&modified'))
enddef

def PickerNoMatch()
  execute 'cd ' .. fnameescape(test_tmp .. '/picker repo 中文')
  edit change.txt
  setline(1, ['UNSAVED no-match user'])
  var userbuf = bufnr()
  execute 'NERDTree ' .. fnameescape(getcwd())
  var usertreebuf = bufnr()
  var usertreewin = win_getid()
  var usertree = UserTreeState(usertreebuf, usertreewin)
  DiffviewCommit HEAD
  Select('', 'change.txt')
  Pair(['PICK NORMAL'], ['PICK TIP'])
  win_gotoid(Role('left').winid)
  SeedRegisters()
  var state = ComparisonState()
  PickerFilter('NO_COMMIT_MATCH_0f962372')
  assert_equal(state, ComparisonState(), 'real fzf no match preserves the prior view and caller focus')
  assert_equal(usertree, UserTreeState(usertreebuf, usertreewin), 'picker leaves ordinary NERDTree untouched')
  assert_equal(['UNSAVED no-match user'], getbufline(userbuf, 1, '$'))
  assert_true(getbufvar(userbuf, '&modified'))
  DiffviewClose
enddef

def PickerFileTypeFailure()
  g:diffview_test_started_picker_jobs = job_info()->filter((_, job) =>
    index(g:diffview_test_prior_jobs, job) < 0 && job_status(job) == 'run')
  throw 'fixture picker post-terminal FileType failure'
enddef

def PickerEnew()
  execute 'cd ' .. fnameescape(test_tmp .. '/picker repo 中文')
  edit change.txt
  setline(1, ['UNSAVED enew picker user'])
  set nohidden autowrite autowriteall
  setlocal number spell nowinfixwidth nowinfixheight
  var userbuf = bufnr()
  var dirty_before = &modified
  var origin = win_getid()
  var disk = readfile('change.txt', 'b')
  var options = [&hidden, &autowrite, &autowriteall]
  var caller_options = WindowOptions(origin)
  DiffviewCommit HEAD
  Select('', 'change.txt')
  win_gotoid(origin)
  SeedRegisters()
  g:diffview_test_picker_windows = []
  g:diffview_test_picker_popups = []
  augroup DiffviewPickerObservation
    autocmd FileType fzf call add(g:diffview_test_picker_windows, win_getid())
    autocmd FileType fzf call add(g:diffview_test_picker_popups, popup_list())
  augroup END
  var state = ComparisonState()
  execute 'tcd ' .. fnameescape(getcwd())
  var initial_cwd = [getcwd(), getcwd(-1), haslocaldir()]
  assert_equal(2, initial_cwd[2], 'caller is already tab-local before the picker starts')
  g:fzf_layout = {window: 'enew'}
  assert_equal(userbuf, bufnr(), 'real in-place picker starts in the dirty user buffer')
  assert_true(&modified)
  PickerFilter('NO_COMMIT_MATCH_0f962372')
  var no_match_cwd = [getcwd(), getcwd(-1), haslocaldir()]
  assert_equal(initial_cwd, no_match_cwd, 'normal no match preserves pre-existing tcd path and scope')
  assert_equal([origin], g:diffview_test_picker_windows, 'real fzf terminal reused caller window')
  assert_equal(state, ComparisonState(), 'in-place no match restores caller and old view')
  assert_equal(caller_options, WindowOptions(origin), 'no match preserves caller window options')
  assert_equal(userbuf, bufnr())
  assert_equal({window: 'enew'}, g:fzf_layout)
  assert_equal(options, [&hidden, &autowrite, &autowriteall])
  assert_equal(disk, readfile('change.txt', 'b'), 'in-place picker never autosaves dirty caller')
  assert_equal(['UNSAVED enew picker user'], getbufline(userbuf, 1, '$'))
  assert_true(getbufvar(userbuf, '&modified'))
  PickerFilter('PICK_OLDER')
  assert_equal([origin, origin], g:diffview_test_picker_windows, 'selection used the requested enew layout')
  Select('', 'change.txt')
  Pair(['PICK ROOT'], ['PICK OLDER'])
  assert_equal(caller_options, WindowOptions(origin), 'selection preserves caller window options')
  assert_equal(options, [&hidden, &autowrite, &autowriteall])
  assert_equal(disk, readfile('change.txt', 'b'))
  assert_true(getbufvar(userbuf, '&modified'))
  win_gotoid(origin)
  assert_equal(userbuf, bufnr())
  state = ComparisonState()
  # Binary-generated abort covers the real exit path; physical keys remain a PTY gate.
  $FZF_DEFAULT_OPTS = '--bind=start:abort'
  DiffviewCommit
  WaitPicker()
  assert_equal([origin, origin, origin], g:diffview_test_picker_windows, 'abort used the requested enew layout')
  assert_equal(state, ComparisonState(), 'real binary abort restores caller and old view')
  assert_equal(caller_options, WindowOptions(origin), 'abort preserves caller window options')
  assert_equal(userbuf, bufnr())
  assert_equal(options, [&hidden, &autowrite, &autowriteall])
  assert_equal({window: 'enew'}, g:fzf_layout)
  assert_equal(disk, readfile('change.txt', 'b'))
  assert_equal(['UNSAVED enew picker user'], getbufline(userbuf, 1, '$'))
  assert_true(getbufvar(userbuf, '&modified'))
  # Real core executes this user layout before it starts its terminal job.
  g:diffview_test_layout_window = 0
  g:fzf_layout = {window: 'enew | let g:diffview_test_layout_window = win_getid() | throw "fixture picker layout failure"'}
  Reject('DiffviewCommit')
  WaitPicker()
  assert_equal(origin, g:diffview_test_layout_window, 'failure occurred after executing the real enew layout')
  assert_equal(state, ComparisonState(), 'real layout initialization error preserves old view and caller')
  assert_equal(caller_options, WindowOptions(origin), 'initialization failure preserves caller winfix and other options')
  assert_equal(userbuf, bufnr())
  assert_equal(options, [&hidden, &autowrite, &autowriteall])
  assert_equal(disk, readfile('change.txt', 'b'))
  assert_equal(['UNSAVED enew picker user'], getbufline(userbuf, 1, '$'))
  assert_true(getbufvar(userbuf, '&modified'))
  # Fault jobs must keep waiting for input, without the preceding start:abort.
  $FZF_DEFAULT_OPTS = ''
  var user_job = job_start(['/bin/sleep', '30'], {in_io: 'null', out_io: 'null', err_io: 'null'})
  var picker_quiet = true
  var user_job_preserved = true
  var picker_jobs_started = 0
  var post_fault_cwd: list<any> = []
  var fault_results: list<any> = []
  try
    assert_equal('run', job_status(user_job), 'an unrelated user job is really running before the fault')
    augroup DiffviewPickerLiveFailure
      execute 'autocmd FileType fzf legacy call ' .. expand('<SID>') .. 'PickerFileTypeFailure()'
    augroup END
    for layout in ['enew', 'default']
      if layout == 'enew'
        g:fzf_layout = {window: 'enew'}
      else
        unlet! g:fzf_layout
      endif
      g:diffview_test_prior_jobs = job_info()
      g:diffview_test_started_picker_jobs = []
      var prior_popups = popup_list()
      var popup_event_start = len(g:diffview_test_picker_popups)
      state = ComparisonState()
      execute 'tcd ' .. fnameescape(initial_cwd[0])
      assert_equal(initial_cwd, [getcwd(), getcwd(-1), haslocaldir()], layout .. ' fault starts with tab-local scope=2')
      Reject('DiffviewCommit')
      assert_match('fixture picker post-terminal FileType failure', execute('messages') .. v:errmsg,
        layout .. ' cleanup preserves the original FileType error')
      var started_jobs = len(g:diffview_test_started_picker_jobs)
      picker_jobs_started += started_jobs
      assert_true(started_jobs > 0, layout .. ' FileType fault occurs after a real picker job starts')
      if layout == 'default'
        var observed = flattennew(g:diffview_test_picker_popups[popup_event_start : ])
        assert_true(!empty(filter(observed, (_, id) => index(prior_popups, id) < 0)),
          'default FileType fault occurs inside a real new popup')
      endif
      var quiet_ticks = 0
      var started = reltime()
      while quiet_ticks < 3 && reltimefloat(reltime(started)) < 5.0
        sleep 20m
        var pending = filter(copy(g:diffview_test_started_picker_jobs), (_, job) => job_status(job) == 'run'
          || index(['open', 'buffered'], ch_status(job_getchannel(job))) >= 0)
        quiet_ticks = empty(pending) ? quiet_ticks + 1 : 0
      endwhile
      var quiet = quiet_ticks >= 3
      picker_quiet = picker_quiet && quiet
      assert_true(quiet, layout .. ' owned picker jobs and channels become quiet within five seconds')
      var fault_message = execute('messages') .. v:errmsg
      assert_match('\[diffview\][^\n]*fixture picker post-terminal FileType failure', fault_message,
        layout .. ' reports the original fault even after exit callbacks')
      assert_notmatch('E948\|E994', fault_message, layout .. ' cleanup cannot replace the fault with a window/job error')
      assert_equal(prior_popups, popup_list(), layout .. ' fault cleans its owned popup')
      assert_equal(state, ComparisonState(), layout .. ' post-terminal fault restores caller, old view and all resources')
      post_fault_cwd = [getcwd(), getcwd(-1), haslocaldir()]
      assert_equal(initial_cwd, post_fault_cwd, layout .. ' fault preserves pre-existing tcd path and scope')
      assert_equal(caller_options, WindowOptions(origin), layout .. ' fault restores all caller window options')
      assert_equal(userbuf, bufnr())
      assert_equal(options, [&hidden, &autowrite, &autowriteall])
      assert_equal(disk, readfile('change.txt', 'b'))
      assert_equal(['UNSAVED enew picker user'], getbufline(userbuf, 1, '$'))
      assert_true(getbufvar(userbuf, '&modified'))
      var user_running = job_status(user_job) == 'run'
      user_job_preserved = user_job_preserved && user_running
      assert_true(user_running, layout .. ' rollback leaves the pre-existing user job running')
      add(fault_results, {layout: layout, jobs_started: started_jobs, owned_jobs_quiet: quiet,
        user_job_running: user_running, cwd_after: post_fault_cwd})
    endfor
  finally
    augroup DiffviewPickerLiveFailure
      autocmd!
    augroup END
    # Only the test-created background sleeper is ours to stop.
    if job_status(user_job) == 'run'
      job_stop(user_job)
    endif
  endtry
  state = ComparisonState()
  execute 'tcd ' .. fnameescape(initial_cwd[0])
  assert_equal(initial_cwd, [getcwd(), getcwd(-1), haslocaldir()])
  unlet! g:fzf_layout
  var popup_start = len(g:diffview_test_picker_popups)
  PickerFilter('NO_COMMIT_MATCH_0f962372')
  assert_true(!empty(filter(copy(g:diffview_test_picker_popups[popup_start : ]), (_, ids) => !empty(ids))),
    'default core layout really creates a popup')
  win_gotoid(Role('panel').winid)
  win_gotoid(origin)
  sleep 40m
  assert_equal(state, ComparisonState(), 'default popup no match retains the old view and caller')
  var popup_no_match_cwd = [getcwd(), getcwd(-1), haslocaldir()]
  assert_equal(initial_cwd, popup_no_match_cwd, 'default popup preserves initial tcd after deferred WinEnter')
  assert_equal([], popup_list(), 'normal no-match popup is cleaned')
  assert_equal(caller_options, WindowOptions(origin))
  execute 'tcd ' .. fnameescape(initial_cwd[0])
  assert_equal(initial_cwd, [getcwd(), getcwd(-1), haslocaldir()])
  popup_start = len(g:diffview_test_picker_popups)
  PickerFilter('PICK_OLDER')
  assert_true(!empty(filter(copy(g:diffview_test_picker_popups[popup_start : ]), (_, ids) => !empty(ids))))
  Select('', 'change.txt')
  Pair(['PICK ROOT'], ['PICK OLDER'])
  win_gotoid(origin)
  sleep 40m
  var popup_selected_cwd = [getcwd(), getcwd(-1), haslocaldir()]
  assert_equal(initial_cwd, popup_selected_cwd, 'default popup selection retains caller initial tcd after WinEnter')
  assert_equal(userbuf, bufnr())
  assert_equal(caller_options, WindowOptions(origin))
  assert_equal(options, [&hidden, &autowrite, &autowriteall])
  assert_equal(disk, readfile('change.txt', 'b'))
  assert_true(getbufvar(userbuf, '&modified'))
  assert_equal([], popup_list(), 'successful popup is cleaned')
  augroup DiffviewPickerObservation
    autocmd!
  augroup END
  writefile([json_encode({scope: 'real core/binary enew; generated abort, not physical cancel keys',
    origin: origin, terminal_windows: g:diffview_test_picker_windows,
    initialization_window: g:diffview_test_layout_window, dirty_before: dirty_before,
    dirty_after: getbufvar(userbuf, '&modified'), options_before: options,
    options_after: [&hidden, &autowrite, &autowriteall], caller_options_before: caller_options,
    caller_options_after: WindowOptions(origin), post_terminal_jobs_started: picker_jobs_started,
    owned_jobs_quiet: picker_quiet, unrelated_user_job_preserved: user_job_preserved,
    initial_cwd: initial_cwd, no_match_cwd: no_match_cwd, post_fault_cwd: post_fault_cwd,
    popup_events: g:diffview_test_picker_popups, popup_no_match_cwd: popup_no_match_cwd,
    popup_selected_cwd: popup_selected_cwd, filetype_faults: fault_results})], test_tmp .. '/picker-enew.facts.json')
  DiffviewClose
enddef

def PickerAsync()
  execute 'cd ' .. fnameescape(test_tmp .. '/picker repo 中文')
  var repo = getcwd()
  var elsewhere = resolve(test_tmp .. '/picker-elsewhere')
  edit change.txt
  setline(1, ['UNSAVED asynchronous picker user'])
  set nohidden autowrite autowriteall
  var userbuf = bufnr()
  var origin = win_getid()
  var disk = readfile(repo .. '/change.txt', 'b')
  var options = [&hidden, &autowrite, &autowriteall]
  var caller_options = WindowOptions(origin)
  DiffviewCommit HEAD
  Select('', 'change.txt')
  win_gotoid(origin)
  g:fzf_layout = {window: 'enew'}
  $FZF_DEFAULT_OPTS = ''
  var calls = len(PickerGitCalls())
  DiffviewCommit
  var terminals = getbufinfo()->filter((_, b) => getbufvar(b.bufnr, '&filetype') == 'fzf')
  if len(terminals) != 1
    throw 'Expected one real asynchronous fzf terminal'
  endif
  var picker = terminals[0].bufnr
  assert_equal(origin, win_getid(), 'async actor operates in the original enew caller window')
  assert_equal(picker, bufnr())
  execute 'tcd ' .. fnameescape(elsewhere)
  var expected_cwd = [getcwd(), getcwd(-1), haslocaldir()]
  assert_equal(2, expected_cwd[2], 'actor really establishes a new tab-local directory')
  term_wait(picker, 100)
  term_sendkeys(picker, 'PICK_OLDER')
  var stable = 0
  var started = reltime()
  var screen: list<string> = []
  while stable < 2 && reltimefloat(reltime(started)) < 5.0
    term_wait(picker, 20)
    screen = mapnew(range(1, term_getsize(picker)[0]), (_, row) => term_getline(picker, row))
    var query_seen = !empty(filter(copy(screen), (_, line) => line =~ 'PICK_OLDER\s*$'))
    var one_match = !empty(filter(copy(screen), (_, line) => line =~ '\<1/6\>'))
    stable = query_seen && one_match ? stable + 1 : 0
  endwhile
  writefile(screen, test_tmp .. '/picker-async.screen')
  if stable < 2
    throw 'Typed fzf query and unique result did not settle before Enter'
  endif
  term_sendkeys(picker, "\<CR>")
  WaitPicker()
  Select('', 'change.txt')
  Pair(['PICK ROOT'], ['PICK OLDER'])
  HistoricalIds([Ref('picker-root')], [Ref('picker-older')])
  PickerOidUsed(Ref('picker-older'), calls)
  var model_root = getbufvar(Role('panel').bufnr, 'NERDTree').root.path.str()
  assert_equal(resolve(repo), resolve(model_root), 'real async selection remains bound to the launch repository')
  var location = win_id2tabwin(origin)
  var actual_cwd = [getcwd(location[1], location[0]), getcwd(-1), haslocaldir(location[1], location[0])]
  assert_equal(expected_cwd, actual_cwd, 'selection preserves latest caller path AND tab-local scope')
  assert_equal(expected_cwd[0 : 1], [getcwd(), getcwd(-1)], 'selection preserves latest current/global paths')
  assert_equal(options, [&hidden, &autowrite, &autowriteall])
  assert_equal(caller_options, WindowOptions(origin))
  calls = len(PickerGitCalls())
  DiffviewRefresh
  WaitPicker()
  Pair(['PICK ROOT'], ['PICK OLDER'])
  PickerOidUsed(Ref('picker-older'), calls)
  assert_equal([], filter(PickerGitCalls()[calls : ], (_, line) => index(split(line, "\n", true), 'log') >= 0),
    'refresh reuses the full selected OID without loading picker history')
  DiffviewClose
  assert_true(win_gotoid(origin))
  assert_equal(userbuf, bufnr())
  assert_equal([elsewhere, 2], [getcwd(), haslocaldir()], 'close preserves the latest tab-local directory too')
  assert_equal(['UNSAVED asynchronous picker user'], getbufline(userbuf, 1, '$'))
  assert_true(&modified)
  assert_equal(disk, readfile(repo .. '/change.txt', 'b'))
  writefile([json_encode({scope: 'real core/binary term_sendkeys; headless, not outer PTY',
    before_exit: expected_cwd, caller_after_selection: actual_cwd, model_root: model_root,
    stable_query_ticks: stable, selected_oid: Ref('picker-older'), core_binary: fzf#exec()})],
    test_tmp .. '/picker-async.facts.json')
  execute 'cd ' .. fnameescape(repo)
enddef

def PickerSha256()
  execute 'cd ' .. fnameescape(test_tmp .. '/picker-sha256')
  assert_equal(64, strlen(Ref('picker256-older')))
  var calls = len(PickerGitCalls())
  PickerFilter('PICK_OLDER')
  Select('', 'change.txt')
  Pair(['PICK ROOT'], ['PICK OLDER'])
  HistoricalIds([Ref('picker256-root')], [Ref('picker256-older')])
  PickerOidUsed(Ref('picker256-older'), calls)
  calls = len(PickerGitCalls())
  DiffviewRefresh
  PickerOidUsed(Ref('picker256-older'), calls)
  Pair(['PICK ROOT'], ['PICK OLDER'])
  DiffviewClose
enddef

def PickerMissing()
  execute 'cd ' .. fnameescape(test_tmp .. '/picker repo 中文')
  assert_false(exists('*fzf#run'), 'missing-plugin fixture actually omits core fzf')
  DiffviewOpen
  Select('Staged', 'change.txt')
  var state = ComparisonState()
  Reject('DiffviewCommit')
  assert_match('\cfzf', execute('messages') .. v:errmsg)
  assert_match('HEAD', execute('messages') .. v:errmsg, 'dependency error offers explicit HEAD')
  assert_equal(state, ComparisonState())
  var saved_path = $PATH
  try
    $PATH = test_tmp .. '/no-fzf-bin'
    assert_false(executable('fzf'), 'missing-binary fixture retains Git but has no PATH fzf')
    DiffviewCommit HEAD
    Select('', 'change.txt')
    Pair(['PICK NORMAL'], ['PICK TIP'])
    assert_false(exists('*fzf#run'), 'explicit HEAD does not require/loading core fzf')
    &runtimepath = $FZF_RUNTIME .. ',' .. &runtimepath
    runtime plugin/fzf.vim
    assert_true(exists('*fzf#run'))
    state = ComparisonState()
    Reject('DiffviewCommit')
    assert_match('\cfzf', execute('messages') .. v:errmsg)
    assert_match('HEAD', execute('messages') .. v:errmsg)
    assert_equal(state, ComparisonState(), 'missing binary preserves the existing comparison')
    DiffviewCommit HEAD
    Select('', 'change.txt')
    Pair(['PICK NORMAL'], ['PICK TIP'])
  finally
    $PATH = saved_path
    DiffviewClose
  endtry
enddef

def PickerErrors()
  execute 'cd ' .. fnameescape(test_tmp .. '/picker repo 中文')
  DiffviewCommit HEAD
  Select('', 'change.txt')
  var state = ComparisonState()
  $FZF_DEFAULT_OPTS = '--filter=NO_COMMIT_MATCH_0f962372'
  for directory in ['unborn', 'nonrepo', 'bare.git']
    execute 'cd ' .. fnameescape(test_tmp .. '/' .. directory)
    var cwd = getcwd()
    Reject('DiffviewCommit')
    WaitPicker()
    assert_equal(state, ComparisonState(), 'history failure preserves the old view: ' .. directory)
    assert_equal(cwd, getcwd())
  endfor
  execute 'cd ' .. fnameescape(test_tmp .. '/picker repo 中文')
  try
    $DIFFVIEW_TEST_FAIL_LOG = '1'
    Reject('DiffviewCommit')
    WaitPicker()
    assert_equal(state, ComparisonState(), 'Git log failure cannot create an empty picker/view')
  finally
    $DIFFVIEW_TEST_FAIL_LOG = ''
    DiffviewClose
  endtry
enddef

def PickerOldBinary()
  execute 'cd ' .. fnameescape(test_tmp .. '/picker repo 中文')
  edit change.txt
  setline(1, ['UNSAVED incompatible binary user'])
  var userbuf = bufnr()
  set nohidden autowriteall
  DiffviewCommit HEAD
  Select('', 'change.txt')
  var state = ComparisonState()
  var saved_path = $PATH
  try
    $PATH = test_tmp .. '/old-fzf-bin:' .. test_tmp .. '/no-fzf-bin'
    assert_true(executable('fzf'), 'old-binary dependency probe has an executable')
    # A forbidden input() consumes this safe refusal; never consent to a download.
    feedkeys("n\<CR>", 'nt')
    Reject('DiffviewCommit')
    assert_equal(char2nr('n'), getchar(0), 'dependency check must not prompt')
    assert_equal(13, getchar(0), 'dependency check leaves typeahead intact')
    assert_match('\cfzf', execute('messages') .. v:errmsg)
    assert_equal(state, ComparisonState(), 'incompatible binary preserves the old view')
    assert_true(filereadable(test_tmp .. '/picker-old-version.calls'), 'version was actually checked')
    assert_false(filereadable(test_tmp .. '/picker-old-executed'))
    assert_false(filereadable(test_tmp .. '/picker-old-install'))
    DiffviewCommit HEAD
    Select('', 'change.txt')
    Pair(['PICK NORMAL'], ['PICK TIP'])
    assert_equal(['UNSAVED incompatible binary user'], getbufline(userbuf, 1, '$'))
    assert_true(getbufvar(userbuf, '&modified'))
  finally
    $PATH = saved_path
    DiffviewClose
  endtry
enddef

def PickerRow(query: string): string
  var rows = g:diffview_test_picker_spec.source
  assert_equal(v:t_list, type(rows), 'history source is an argv-produced List, not a shell pipeline')
  var found = filter(copy(rows), (_, row) => stridx(row, query) >= 0)
  assert_equal(1, len(found), 'one supplied picker row for ' .. query)
  return found[0]
enddef

def PickerOutput(lines: any, expect_error = false)
  messages clear
  v:errmsg = ''
  var error = ''
  var spec = g:diffview_test_picker_spec
  try
    # Dispatch exactly like core fzf; this is API injection, not real UI evidence.
    if has_key(spec, 'sink')
      var Sink = spec.sink
      for line in lines
        call(Sink, [line])
      endfor
    endif
    if has_key(spec, 'sink*')
      call(spec['sink*'], [lines])
    elseif has_key(spec, 'sinklist')
      call(spec.sinklist, [lines])
    endif
  catch
    error = v:exception
  endtry
  if expect_error
    assert_match('\[diffview\]', error .. execute('messages') .. v:errmsg, 'fresh tagged callback error')
  else
    assert_equal('', error, 'unexpected callback exception')
  endif
enddef

def PickerApi()
  execute 'cd ' .. fnameescape(test_tmp .. '/picker repo 中文')
  var repo = getcwd()
  DiffviewOpen
  Select('Staged', 'change.txt')
  Pair(['PICK TIP'], ['INDEX picker dirt'])
  var state = ComparisonState()
  DiffviewCommit
  assert_equal(state, ComparisonState(), 'API capture itself leaves the old view intact')
  var row = PickerRow('PICK_OLDER')
  assert_equal(6, len(g:diffview_test_picker_spec.source), 'HEAD reachable history includes merged side, not hidden branch')
  PickerRow('PICK_SIDE')
  assert_equal([], filter(copy(g:diffview_test_picker_spec.source), (_, line) => stridx(line, 'PICK_UNREACHABLE') >= 0))
  assert_true(stridx(row, 'META_AUTHOR_NEEDLE') >= 0 && stridx(row, '2023') >= 0)
  assert_false(stridx(row, "TABBEFORE\tTABAFTER") >= 0, 'metadata tab is escaped independently of column delimiters')
  for code in [1, 7, 10, 13, 27]
    assert_true(stridx(row, nr2char(code)) < 0, 'metadata control bytes are escaped')
  endfor
  try
    execute 'cd ' .. fnameescape(test_tmp .. '/picker-elsewhere')
    var cwd = getcwd()
    writefile([Ref('picker-root')], repo .. '/.git/refs/heads/main')
    var calls = len(PickerGitCalls())
    PickerOutput([row])
    Select('', 'change.txt')
    Pair(['PICK ROOT'], ['PICK OLDER'])
    assert_equal(repo, getbufvar(Role('panel').bufnr, 'NERDTree').root.path.str(), 'callback stays in the launch repository')
    assert_equal(cwd, getcwd(), 'callback does not permanently change the newer cwd')
    PickerOidUsed(Ref('picker-older'), calls)
    var picker_calls = g:diffview_test_picker_calls
    calls = len(PickerGitCalls())
    DiffviewRefresh
    Pair(['PICK ROOT'], ['PICK OLDER'])
    PickerOidUsed(Ref('picker-older'), calls)
    assert_equal(picker_calls, g:diffview_test_picker_calls, 'refresh never reopens picker')
  finally
    writefile([Ref('picker-tip')], repo .. '/.git/refs/heads/main')
    DiffviewClose
  endtry
  execute 'cd ' .. fnameescape(repo)
  DiffviewOpen
  Select('Staged', 'change.txt')
  DiffviewCommit
  row = PickerRow('PICK_OLDER')
  state = ComparisonState()
  PickerOutput([])
  assert_equal(state, ComparisonState(), 'empty callback leaves the view intact')
  var invalid_outputs: list<any> = [0, row, [1], ['not a supplied row'], [row, row], ['typed query', row], ['ctrl-x', row],
      [row .. ' tampered'], [Ref('picker-hidden') .. ' forged metadata']]
  for output in invalid_outputs
    PickerOutput(output, true)
    assert_equal(state, ComparisonState(), 'unexpected/multiple picker output is not a commit request')
  endfor
  for code in [0, 1, 130]
    messages clear
    v:errmsg = ''
    call(g:diffview_test_picker_spec.exit, [code])
    assert_equal('', v:errmsg)
    assert_equal(state, ComparisonState(), 'normal/no-match/cancel exit preserves the comparison')
  endfor
  Reject('legacy call g:diffview_test_picker_spec.exit(2)')
  assert_equal(state, ComparisonState(), 'failed fzf exit reports an error and preserves the comparison')
  try
    g:diffview_test_picker_throw = 1
    Reject('DiffviewCommit')
    assert_equal(state, ComparisonState(), 'fzf API launch failure preserves the view')
  finally
    g:diffview_test_picker_throw = 0
  endtry
  var oid = Ref('picker-older')
  var object = repo .. '/.git/objects/' .. oid[0 : 1] .. '/' .. oid[2 : ]
  try
    assert_equal(0, rename(object, test_tmp .. '/picker-object'))
    PickerOutput([row], true)
    assert_equal(state, ComparisonState(), 'selected commit read failure preserves the old view')
  finally
    assert_equal(0, rename(test_tmp .. '/picker-object', object))
  endtry
  augroup DiffviewPickerFailure
    autocmd FileType nerdtree throw 'fixture picker selected-view render failure'
  augroup END
  try
    PickerOutput([row], true)
  finally
    augroup DiffviewPickerFailure
      autocmd!
    augroup END
  endtry
  assert_equal(state, ComparisonState(), 'selected comparison render error preserves old buffers and focus')
  PickerOutput([row])
  Select('', 'change.txt')
  Pair(['PICK ROOT'], ['PICK OLDER'])
  DiffviewClose
enddef

def SyntaxToken(side: string, row: number, column: number): string
  var focus = win_getid()
  win_gotoid(Role(side).winid)
  syntax sync fromstart
  var name = synIDattr(synID(row, column, 1), 'name')
  win_gotoid(focus)
  return name
enddef

def PlainSyntax(side: string)
  assert_equal('', getbufvar(Role(side).bufnr, '&syntax'), side .. ' clears stale syntax')
  assert_equal('', SyntaxToken(side, 1, 1), side .. ' has no stale token groups')
enddef

def ReadingSyntax()
  execute 'cd ' .. fnameescape(test_tmp .. '/reading repo')
  syntax enable
  set modeline tabstop=8
  g:diffview_test_read_hooks = 0
  g:diffview_test_language_hooks = 0
  augroup DiffviewReadingHooks
    autocmd BufRead,BufNewFile * g:diffview_test_read_hooks += 1
    autocmd FileType python,c,sh g:diffview_test_language_hooks += 1
  augroup END
  SeedRegisters()
  var registers = RegisterState()
  var buffers = getbufinfo()->mapnew((_, b) => b.bufnr)
  var windows = getwininfo()->mapnew((_, w) => w.winid)
  var cwd = [getcwd(), getcwd(-1), haslocaldir()]
  try
    DiffviewOpen
    Select('Unstaged', 'code.py')
    Pair(['def indexed():', '    return 2'], ['def worktree():', '    return 3'])
    for side in ['left', 'right']
      assert_equal('diffview', getbufvar(Role(side).bufnr, '&filetype'))
      assert_match('^python', SyntaxToken(side, 1, 1), 'real Python token')
    endfor
    Select('Unstaged', 'code.c')
    Pair(['int amount = 1;'], ['int amount = 2;'])
    assert_match('^c', SyntaxToken('right', 1, 1), 'real C type token')
    Select('Staged', 'move.c')
    Pair(['# rename comment', 'int amount = 1;', 'def renamed():', '    return 1'],
      ['# rename comment', 'int amount = 1;', 'def renamed():', '    return 1'])
    assert_match('^python', SyntaxToken('left', 3, 1), 'left syntax follows old .py name')
    assert_match('^c', SyntaxToken('right', 2, 1), 'right syntax follows new .c name')
    Select('Unstaged', 'script')
    assert_match('^python', SyntaxToken('right', 2, 1), 'native shebang detection uses snapshot content')
    Select('Unstaged', 'model.py')
    assert_equal(8, getbufvar(Role('right').bufnr, '&tabstop'), 'snapshot modeline is not evaluated')
    Select('Unstaged', 'noeol.py')
    Pair(['return 0'], ['return 1'])
    assert_false(getbufvar(Role('right').bufnr, '&endofline'), 'syntax preserves absent final newline')
    Select('Unstaged', 'empty.py')
    Pair(['def empty_later():', '    return 1'], [''])
    assert_match('^python', SyntaxToken('left', 1, 1))
    PlainSyntax('right')
    Select('Unstaged', 'unknown.diffview_unknown')
    PlainSyntax('left')
    PlainSyntax('right')
    var literal_drive = 'C:' .. nr2char(92) .. 'literal.txt'
    Select('Unstaged', literal_drive)
    Pair(['HEAD literal drive'], ['DISK literal drive'])
    assert_equal(literal_drive, getbufvar(Role('left').bufnr, 'diffview_path'))
    assert_equal(literal_drive, getbufvar(Role('right').bufnr, 'diffview_path'), 'POSIX backslash stays a raw filename byte')
    for path in ['binary.py', 'forced.py', 'link.py']
      Select('Unstaged', path)
      Unavailable('\cBinary\|unsupported\|symlink')
      PlainSyntax('left')
      PlainSyntax('right')
    endfor
    DiffviewCommit reading-right
    Select('', 'historical.py')
    Pair(['def historical():', '    return 1'], [''])
    assert_false(filereadable('historical.py'), 'historical logical filename is absent on disk')
    assert_match('^python', SyntaxToken('left', 1, 1), 'deleted historical syntax')
    PlainSyntax('right')
    DiffviewOpen
    Select('Unstaged', 'code.py')
    syntax off
    assert_false(exists('g:syntax_on'), 'control really disables global syntax')
    DiffviewRefresh
    PlainSyntax('left')
    PlainSyntax('right')
    assert_false(exists('g:syntax_on'), 'the product does not enable global syntax')
    syntax enable
    DiffviewRefresh
    assert_match('^python', SyntaxToken('right', 1, 1))
    Select('Unstaged', 'unknown.diffview_unknown')
    var original_rtp = &runtimepath
    var fault = test_tmp .. '/reading-syntax-fault'
    mkdir(fault .. '/syntax', 'p')
    writefile(['syntax match DiffviewPartial /def/', "throw 'fixture partial syntax failure'"],
      fault .. '/syntax/python.vim')
    try
      &runtimepath = fault .. ',' .. &runtimepath
      messages clear
      Select('Unstaged', 'code.py')
      Pair(['def indexed():', '    return 2'], ['def worktree():', '    return 3'])
      PlainSyntax('left')
      PlainSyntax('right')
      assert_match('\[diffview\].*\csyntax', execute('messages'), 'syntax fault is a tagged plain fallback')
      assert_match('fixture partial syntax failure', execute('messages'), 'fixture reached the syntax resource')
    finally
      &runtimepath = original_rtp
    endtry
    execute 'DiffviewOpen HEAD HEAD'
    NoChanges()
    PlainSyntax('left')
    PlainSyntax('right')
    assert_equal(0, g:diffview_test_read_hooks, 'syntax never opens a real similarly named file')
    assert_equal(0, g:diffview_test_language_hooks, 'snapshot detection bypasses user language FileType hooks')
    assert_equal(registers, RegisterState())
    assert_equal(cwd, [getcwd(), getcwd(-1), haslocaldir()])
    DiffviewClose
    assert_equal(buffers, getbufinfo()->mapnew((_, b) => b.bufnr), 'owned detection buffers cleaned')
    assert_equal(windows, getwininfo()->mapnew((_, w) => w.winid), 'owned detection windows cleaned')
  finally
    augroup DiffviewReadingHooks
      autocmd!
    augroup END
    DiffviewClose
  endtry
enddef

def ReadingView(): dict<any>
  return ComparisonState()->filter((key, _) =>
    index(['rows', 'nodes', 'bodies', 'readonly', 'options', 'sources', 'labels', 'registers'], key) >= 0)
enddef

def GotoCheck(path: string, hint: number, key: bool = true): number
  var comparison = Role('panel')
  var state = ReadingView()
  var tabs = tabpagenr('$')
  if key
    feedkeys('gf', 'xt')
  else
    execute 'DiffviewGotoFile'
  endif
  assert_equal(tabs + 1, tabpagenr('$'), 'gf opens one ordinary tab')
  assert_equal(comparison.tabnr + 1, tabpagenr(), 'user tab is adjacent to the comparison')
  assert_equal(resolve(path), resolve(expand('%:p')), 'gf uses the mapped raw path')
  assert_equal(hint, line('.'), 'numeric line hint is clamped to the loaded target')
  var target = bufnr()
  assert_equal('', &buftype)
  assert_true(&modifiable)
  assert_false(&readonly)
  assert_false(&diff, 'ordinary navigation tab does not inherit snapshot diff')
  if path =~ '\.py$'
    assert_equal('python', &filetype, 'normal real-file filetype detection runs')
  elseif path =~ '\.c$'
    assert_equal('c', &filetype, 'normal real-file filetype detection runs')
  endif
  assert_equal('', get(b:, 'diffview_role', ''), 'ordinary target never becomes plugin owned')
  for lhs in ['q', 'r', 'gf']
    assert_false(get(maparg(lhs, 'n', false, true), 'buffer', false), 'no Diffview map on user target: ' .. lhs)
  endfor
  tabprevious
  assert_equal(comparison.tabnr, tabpagenr(), 'native tab navigation returns to the comparison')
  assert_equal(state, ReadingView(), 'opening a real file leaves the selected comparison unchanged')
  return target
enddef

def LoadedGotoFailure()
  if bufnr() == g:diffview_test_goto_loaded_target && g:diffview_test_goto_loaded_faults == 0
      && win_getid() != g:diffview_test_goto_original_window
    g:diffview_test_goto_loaded_faults += 1
    setline(1, ['UNSAVED target from real open hook'])
    throw 'fixture loaded target BufEnter failure'
  endif
enddef

def ReadingGoto()
  execute 'cd ' .. fnameescape(test_tmp .. '/reading repo')
  var repo = getcwd()
  filetype on
  edit code.py
  setline(1, ['UNSAVED navigation caller'])
  deletebufline(bufnr(), 2, '$')
  var caller = bufnr()
  var origin = win_getid()
  vsplit nav/target.py
  setline(1, ['UNSAVED target one', 'UNSAVED target two', 'UNSAVED target three', 'UNSAVED target four'])
  var target = bufnr()
  var targetwin = win_getid()
  set nohidden autowrite autowriteall
  win_gotoid(origin)
  var caller_options = WindowOptions(origin)
  var target_options = WindowOptions(targetwin)
  var cwd = [getcwd(), getcwd(-1), haslocaldir()]
  SeedRegisters()
  var registers = RegisterState()
  DiffviewOpen
  Select('Unstaged', 'nav/target.py')
  Pair(['HEAD one', 'HEAD two', 'HEAD three', 'HEAD four', 'HEAD five', 'HEAD six'],
    ['CURRENT first', 'CURRENT second'])
  win_gotoid(Role('left').winid)
  cursor(6, 1)
  assert_equal(target, GotoCheck(repo .. '/nav/target.py', 4), 'reuse the already loaded dirty target')
  assert_equal(['UNSAVED target one', 'UNSAVED target two', 'UNSAVED target three', 'UNSAVED target four'],
    getbufline(target, 1, '$'))
  assert_true(getbufvar(target, '&modified'))
  win_gotoid(Role('right').winid)
  cursor(2, 1)
  assert_equal(target, GotoCheck(repo .. '/nav/target.py', 2))
  Select('Staged', 'new dir/same.c')
  win_gotoid(Role('left').winid)
  var oldbuf = GotoCheck(repo .. '/old dir/same.py', 1)
  assert_equal(['OLDPATH current'], getbufline(oldbuf, 1, '$'), 'left uses oldpath, not the rename destination')
  win_gotoid(Role('right').winid)
  var newbuf = GotoCheck(repo .. '/new dir/same.c', min([line('.'), 2]))
  TreeCursor(Node('Staged', 'new dir/same.c'))
  assert_equal(newbuf, GotoCheck(repo .. '/new dir/same.c', 1), 'panel gf uses destination')
  win_gotoid(origin)
  assert_equal(newbuf, GotoCheck(repo .. '/new dir/same.c', 1, false), 'command from another window uses selection')

  for node in [Node('Unstaged', 'src/keep.py').parent]
    TreeCursor(node)
    var state = ComparisonState()
    Reject('DiffviewGotoFile')
    assert_equal(state, ComparisonState(), 'directory is not a file-navigation target')
  endfor
  win_gotoid(Panel())
  cursor(1, 1)
  var state = ComparisonState()
  Reject('DiffviewGotoFile')
  assert_equal(state, ComparisonState(), 'header has no raw file target')
  for path in ['gone.txt', 'nav/nonregular.py', 'link.py']
    Select('Unstaged', path)
    state = ComparisonState()
    Reject('DiffviewGotoFile')
    assert_equal(state, ComparisonState(), 'missing/nonregular/symlink navigation preserves view: ' .. path)
  endfor
  Select('Unstaged', 'nav/target.py')
  for replacement in [{path: 'nav', external: 'reading-outside'},
      {path: 'nav/target.py', external: 'reading-outside/target.py'}, {path: 'nav/target.py', external: ''}]
    var mapped = repo .. '/' .. replacement.path
    var saved = test_tmp .. '/reading-goto.saved'
    try
      assert_equal(0, rename(mapped, saved))
      if replacement.external != ''
        system('ln -s ' .. shellescape(test_tmp .. '/' .. replacement.external) .. ' ' .. shellescape(mapped))
        assert_equal('link', getftype(mapped), 'use-time symlink replacement is real')
      else
        assert_equal('', getftype(mapped), 'use-time missing target is real')
      endif
      state = ComparisonState()
      Reject('DiffviewGotoFile')
      assert_equal(state, ComparisonState(), 'use-time safe-path check precedes dirty-buffer reuse')
      assert_equal(-1, bufnr(test_tmp .. '/reading-outside/target.py'), 'outside fixture is not opened')
    finally
      if getftype(mapped) == 'link'
        delete(mapped)
      endif
      if getftype(saved) != ''
        assert_equal(0, rename(saved, mapped))
      endif
    endtry
  endfor
  Select('Unstaged', 'code.c')
  g:diffview_test_goto_ft_faults = 0
  augroup DiffviewGotoFailure
    autocmd FileType c g:diffview_test_goto_ft_faults += 1 | throw 'fixture real-file FileType failure'
  augroup END
  try
    win_gotoid(Role('right').winid)
    state = ComparisonState()
    Reject('DiffviewGotoFile')
    assert_equal(1, g:diffview_test_goto_ft_faults, 'failure happens in the actual real-file open')
    assert_equal(state, ComparisonState(), 'open FileType fault rolls back only new user resources')
  finally
    augroup DiffviewGotoFailure
      autocmd!
    augroup END
  endtry
  Select('Unstaged', 'nav/target.py')
  win_gotoid(Role('right').winid)
  g:diffview_test_goto_loaded_target = target
  g:diffview_test_goto_original_window = targetwin
  g:diffview_test_goto_loaded_faults = 0
  var target_body = getbufline(target, 1, '$')
  augroup DiffviewGotoLoadedFailure
    autocmd BufEnter * LoadedGotoFailure()
  augroup END
  try
    state = ComparisonState()
    Reject('DiffviewGotoFile')
    assert_equal(1, g:diffview_test_goto_loaded_faults, 'actual loaded-target open reaches the user hook')
    assert_equal(state, ComparisonState(), 'loaded-target failure restores invoking focus and owned resources')
    assert_true(bufloaded(target) && getbufvar(target, '&modified'), 'never wipe or unload the dirty user target')
    assert_equal(['UNSAVED target from real open hook'] + target_body[1 : ], getbufline(target, 1, '$'),
      'hook edits survive failed navigation')
  finally
    augroup DiffviewGotoLoadedFailure
      autocmd!
    augroup END
    setbufline(target, 1, target_body)
  endtry
  var literal_drive = 'C:' .. nr2char(92) .. 'literal.txt'
  Select('Unstaged', literal_drive)
  Pair(['HEAD literal drive'], ['DISK literal drive'])
  win_gotoid(Role('right').winid)
  var literalbuf = GotoCheck(repo .. '/' .. literal_drive, 1)
  assert_equal(['DISK literal drive'], getbufline(literalbuf, 1, '$'), 'actual gf reads the exact POSIX drive-shaped filename')
  execute 'cd ' .. fnameescape(test_tmp .. '/special')
  DiffviewOpen
  for path in ['space 中文.txt', '-leading.txt', "semi;$(touch INJECTED)|quote'\".txt",
      "line\nname.txt", "ctrl\x01name.txt", 'literal\n.txt', ':(glob)**']
    Select('Unstaged', path)
    win_gotoid(Role('right').winid)
    GotoCheck(test_tmp .. '/special/' .. path, 1)
  endfor
  assert_false(filereadable('INJECTED'), 'gf never executes raw shell/Ex filename punctuation')
  execute 'cd ' .. fnameescape(repo)
  execute 'DiffviewOpen reading-left:one\ part reading-right:two\ part'
  Select('', 'common.py')
  Pair(['LEFT subtree'], ['RIGHT subtree'])
  var calls = PickerGitCalls()
  var tag = repo .. '/.git/refs/tags/reading-left'
  try
    assert_equal(0, rename(tag, test_tmp .. '/reading-left.saved'))
    win_gotoid(Role('left').winid)
    GotoCheck(repo .. '/one part/common.py', 1)
    win_gotoid(Role('right').winid)
    GotoCheck(repo .. '/two part/common.py', 1)
    assert_equal(calls, PickerGitCalls(), 'gf uses captured subtree mapping without resolving a ref again')
  finally
    assert_equal(0, rename(test_tmp .. '/reading-left.saved', tag))
  endtry
  execute 'DiffviewOpen reading-left:colon:dir reading-right:colon:dir'
  Select('', 'common.py')
  Pair(['LEFT colon subtree'], ['RIGHT colon subtree'])
  win_gotoid(Role('right').winid)
  GotoCheck(repo .. '/colon:dir/common.py', 1)
  execute 'DiffviewOpen reading-clock@{2020-06-01T00:00:00Z}:one\ part reading-right:two\ part'
  Select('', 'common.py')
  Pair(['LEFT subtree'], ['RIGHT subtree'])
  win_gotoid(Role('left').winid)
  state = ComparisonState()
  var previous_tabs = tabpagenr('$')
  messages clear
  v:errmsg = ''
  var mapping_error = ''
  try
    execute 'DiffviewGotoFile'
  catch
    mapping_error = v:exception
  endtry
  if tabpagenr('$') == previous_tabs
    var notice = mapping_error .. execute('messages') .. v:errmsg
    assert_match('\[diffview\]', notice)
    assert_match('\cunsupported\|mapping\|unknown', notice, 'refusal explains the unproven worktree mapping')
    assert_equal(state, ComparisonState(), 'ambiguous mapping must explicitly refuse, not guess')
  else
    assert_equal(previous_tabs + 1, tabpagenr('$'))
    assert_equal(resolve(repo .. '/one part/common.py'), resolve(expand('%:p')),
      'colon inside reflog is not mistaken for the subtree separator')
    tabprevious
  endif
  execute 'DiffviewOpen ' .. Ref('reading-left-tree') .. ' ' .. Ref('reading-right-tree')
  Select('', 'one part/common.py')
  state = ComparisonState()
  Reject('DiffviewGotoFile')
  assert_equal(state, ComparisonState(), 'raw tree ID cannot guess a matching current file')
  assert_equal(cwd, [getcwd(), getcwd(-1), haslocaldir()])
  assert_equal(registers, RegisterState())
  assert_equal(caller_options, WindowOptions(origin))
  assert_equal(target_options, WindowOptions(targetwin))
  assert_equal([false, true, true], [&hidden, &autowrite, &autowriteall])
  assert_equal(['UNSAVED navigation caller'], getbufline(caller, 1, '$'))
  assert_true(getbufvar(caller, '&modified'))
  assert_true(getbufvar(target, '&modified'))
  win_gotoid(getwininfo()->filter((_, w) => w.bufnr == newbuf)[0].winid)
  execute 'DiffviewClose'
  assert_true(bufexists(newbuf) && bufexists(oldbuf) && bufexists(literalbuf), 'Close never wipes normal navigation buffers')
  assert_true(!empty(getwininfo()->filter((_, w) => w.bufnr == newbuf)), 'Close keeps the user navigation tab')
  assert_equal(['CURRENT first', 'CURRENT second'], readfile(repo .. '/nav/target.py'))
  assert_equal(['def worktree():', '    return 3'], readfile(repo .. '/code.py'))
enddef

def SetProjection(paths: list<string>)
  # <f-args> needs space/backslash escaping, not fnameescape's literal glob/newline backslashes.
  execute 'DiffviewFilter ' .. join(mapnew(paths, (_, path) => escape(path, " \t\\")), ' ')
enddef

def GitSubcommand(record: string): string
  var argv = split(record, "\n", true)
  # The shared argv runner places the subcommand after its -C root pair.
  var directory = index(argv, '-C')
  if directory < 0 || directory + 2 >= len(argv)
    throw 'Malformed logged Git argv'
  endif
  return argv[directory + 2]
enddef

def NoMetadataReload(first: number)
  for command in PickerGitCalls()[first : ]
    assert_equal(-1, index(['diff', 'diff-tree', 'rev-parse', 'log'], GitSubcommand(command)),
      'projection does not reload Git comparison/history/refs')
  endfor
enddef

def EntryKeys(): list<string>
  return Entries()->mapnew((_, node) => node.diffview_entry.section .. ':' .. node.diffview_entry.path)
    ->sort()
enddef

def ReadingFilter()
  execute 'cd ' .. fnameescape(test_tmp .. '/reading repo')
  var repo = getcwd()
  syntax enable
  SeedRegisters()
  var registers = RegisterState()
  DiffviewOpen
  var full = EntryKeys()
  var literal_drive = 'C:' .. nr2char(92) .. 'literal.txt'
  SetProjection([literal_drive])
  assert_equal(['Unstaged:' .. literal_drive], EntryKeys(), 'valid POSIX drive-shaped prefix remains literal')
  Select('Unstaged', literal_drive)
  Pair(['HEAD literal drive'], ['DISK literal drive'])
  execute 'DiffviewOpen -- ' .. escape(literal_drive, " \t\\")
  assert_equal(['Unstaged:' .. literal_drive], EntryKeys(), 'initial Open accepts the same literal prefix')
  assert_equal(literal_drive, Node('Unstaged', literal_drive).diffview_entry.path)
  DiffviewOpen
  assert_equal(full, EntryKeys())
  var invalid_revision_state = ComparisonState()
  Reject('DiffviewOpen --version HEAD')
  assert_equal(invalid_revision_state, ComparisonState(), 'invalid revision option preserves the current projection/view')
  Select('Unstaged', 'code.py')
  var snapshots = [getbufline(Role('left').bufnr, 1, '$'), getbufline(Role('right').bufnr, 1, '$')]
  var disk = readfile('code.py', 'b')
  try
    writefile(['DISK changed but not refreshed'], 'code.py')
    var first = len(PickerGitCalls())
    SetProjection(['./code.py//', 'code.c'])
    assert_equal(['Staged:code.py', 'Unstaged:code.c', 'Unstaged:code.py'], EntryKeys())
    assert_equal(snapshots, [getbufline(Role('left').bufnr, 1, '$'), getbufline(Role('right').bufnr, 1, '$')],
      'visible selected entry retains its existing disk snapshot')
    assert_equal('Unstaged', getbufvar(Role('right').bufnr, 'diffview_section'))
    assert_equal('code.py', getbufvar(Role('right').bufnr, 'diffview_path'))
    assert_equal(first, len(PickerGitCalls()), 'same selected projection needs no Git reads')
    SetProjection([])
    assert_equal(full, EntryKeys(), 'clear restores the retained full model')
    NoMetadataReload(first)
  finally
    writefile(disk, 'code.py', 'b')
  endtry
  var first = len(PickerGitCalls())
  SetProjection(['src'])
  for node in Entries()
    assert_match('^src/', node.diffview_entry.path, 'segment prefix does not include src2')
  endfor
  assert_equal(2, len(Entries()))
  Select('Unstaged', 'src/deep/keep.py')
  Pair(['HEAD deep'], ['DISK deep'])
  var deep = Node('Unstaged', 'src/deep/keep.py').parent
  TreeCursor(deep)
  normal o
  assert_false(deep.isOpen)
  SetProjection(['src', 'code.c'])
  assert_false(Node('Unstaged', 'src/deep/keep.py').parent.isOpen, 'surviving directory expansion is retained')
  NoMetadataReload(first)
  for path in ['move.py', 'move.c']
    SetProjection([path])
    assert_equal(['Staged:move.c'], EntryKeys(), 'rename matches either raw side exactly once')
    assert_equal('move.py', Node('Staged', 'move.c').diffview_entry.oldpath)
  endfor
  for invalid in ['../code.py', 'src/../code.py', '/code.py']
    var state = ComparisonState()
    Reject('DiffviewFilter ' .. fnameescape(invalid))
    assert_equal(state, ComparisonState(), 'invalid filter is transactional')
  endfor
  for paths in [['.', '../code.py'], ['../code.py', '.']]
    var state = ComparisonState()
    Reject('DiffviewFilter ' .. join(paths, ' '))
    assert_equal(state, ComparisonState(), 'dot does not bypass validation of the whole prefix list')
  endfor
  SetProjection(['NO_MATCH'])
  assert_equal([], Entries())
  assert_match('No matching changes', join(getbufline(Role('panel').bufnr, 1, '$'), "\n"))
  for side in ['left', 'right']
    assert_match('No matching changes', join(getbufline(Role(side).bufnr, 1, '$'), "\n"))
    assert_equal('', getbufvar(Role(side).bufnr, 'diffview_source'))
    assert_equal('', getbufvar(Role(side).bufnr, 'diffview_path'))
    assert_false(PaneOption(side, 'diff'))
    PlainSyntax(side)
  endfor
  var empty_state = ComparisonState()
  Reject('DiffviewGotoFile')
  assert_equal(empty_state, ComparisonState(), 'no-match view cannot navigate an old path')
  SetProjection(['.'])
  assert_equal(full, EntryKeys())
  Select('Unstaged', 'code.py')
  var state = ComparisonState()
  try
    assert_equal(0, rename('src/keep.py', test_tmp .. '/reading-filter.saved'))
    Reject('DiffviewFilter src/keep.py')
    assert_equal(state, ComparisonState(), 'filter selection read failure preserves prior filter/model/snapshots')
  finally
    assert_equal(0, rename(test_tmp .. '/reading-filter.saved', 'src/keep.py'))
  endtry
  var tree = getbufvar(Role('panel').bufnr, 'NERDTree')
  var FileRender = get(g:NERDTreeFileNode, 'renderToString')
  var DirRender = get(g:NERDTreeDirNode, 'renderToString')
  var InstanceRender = get(tree.root, 'renderToString')
  g:diffview_test_render_failures = 0
  try
    g:NERDTreeFileNode.renderToString = RenderFailure
    g:NERDTreeDirNode.renderToString = RenderFailure
    tree.root.renderToString = RenderFailure
    Reject('DiffviewFilter code.c')
    assert_true(g:diffview_test_render_failures > 0, 'filter reached actual native partial render')
    assert_equal(state, ComparisonState())
    assert_true(tree is getbufvar(Role('panel').bufnr, 'NERDTree'), 'failed filter retains old native instance')
  finally
    g:NERDTreeFileNode.renderToString = FileRender
    g:NERDTreeDirNode.renderToString = DirRender
    tree.root.renderToString = InstanceRender
  endtry
  execute 'DiffviewOpen -- src'
  assert_equal(2, len(Entries()), 'Open separator applies initial literal prefix')
  DiffviewOpen
  assert_equal(full, EntryKeys(), 'new unfiltered Open resets projection')
  execute 'DiffviewOpen HEAD HEAD -- missing'
  NoChanges()

  execute 'cd ' .. fnameescape(test_tmp .. '/tree repo')
  execute 'DiffviewOpen -- weird'
  for path in ["weird/line\nname.txt", 'weird/line^@name.txt', "weird/bell\x07name.txt",
      'weird/bell^Gname.txt', 'weird/:(glob)**', 'weird/literal\n.txt']
    SetProjection([path])
    assert_equal(2, len(Entries()), 'literal raw filter distinguishes display twins')
    for node in Entries()
      assert_equal(path, node.diffview_entry.path, 'literal path is not parsed as glob/regex/display text')
    endfor
    var node = Node('Unstaged', path)
    win_gotoid(Panel())
    var headers = getline(1, 2)
    g:NERDTreeRender()
    assert_equal(headers, getline(1, 2))
    var tree_row = b:NERDTree.ui.getLineNum(node)
    assert_true(stridx(getline(tree_row), node.displayString()) >= 0, 'dynamic headers map to the actual screen row')
    TreeCursor(node)
    feedkeys("\<CR>", 'xt')
    assert_equal(path, getbufvar(Role('right').bufnr, 'diffview_path'))
  endfor
  execute 'cd ' .. fnameescape(repo)
  execute 'DiffviewOpen reading-left reading-right -- one\ part'
  Select('', 'one part/common.py')
  Pair(['LEFT subtree'], ['NEXT first subtree'])
  var right_ref = repo .. '/.git/refs/tags/reading-right'
  try
    execute 'cd ' .. fnameescape(test_tmp .. '/nonrepo')
    writefile([Ref('reading-left')], right_ref)
    first = len(PickerGitCalls())
    SetProjection([])
    Pair(['LEFT subtree'], ['NEXT first subtree'])
    NoMetadataReload(first)
    SetProjection(['one part'])
    DiffviewRefresh
    NoChanges()
    writefile([Ref('reading-right')], right_ref)
    DiffviewRefresh
    assert_equal(['Trees:one part/common.py'], EntryKeys(), 'Refresh remembers literal filters and original repository')
  finally
    writefile([Ref('reading-right')], right_ref)
  endtry
  execute 'cd ' .. fnameescape(repo)
  execute 'DiffviewCommit reading-right -- historical.py'
  assert_equal(['Commit:historical.py'], EntryKeys())
  Pair(['def historical():', '    return 1'], [''])
  $FZF_DEFAULT_OPTS = '--filter=READING_NEXT'
  execute 'DiffviewCommit -- one\ part'
  WaitPicker()
  assert_equal(['Commit:one part/common.py'], EntryKeys(), 'real fzf callback retains prefixes')
  Pair(['LEFT subtree'], ['NEXT first subtree'])
  try
    execute 'cd ' .. fnameescape(test_tmp .. '/nonrepo')
    writefile([Ref('reading-left')], right_ref)
    first = len(PickerGitCalls())
    DiffviewRefresh
    Pair(['LEFT subtree'], ['NEXT first subtree'])
    PickerOidUsed(Ref('reading-right'), first)
    assert_equal([], filter(PickerGitCalls()[first : ], (_, command) => GitSubcommand(command) == 'log'))
    assert_equal(['Commit:one part/common.py'], EntryKeys(), 'fzf Refresh retains original repo/fullOID/filter')
  finally
    writefile([Ref('reading-right')], right_ref)
  endtry
  assert_equal(registers, RegisterState(), 'filter/native rendering preserves all raw registers')
  DiffviewClose
enddef

def NumstatOracle(name: string): dict<list<number>>
  var fields: list<string> = []
  var field = ''
  for byte in blob2list(readblob(test_tmp .. '/reading-' .. name .. '.numstat'))
    if byte == 0
      add(fields, field)
      field = ''
    else
      assert_true(byte < 128, 'independent count fixture uses ASCII raw paths')
      field ..= nr2char(byte)
    endif
  endfor
  assert_equal('', field, 'numstat oracle is NUL terminated')
  var result: dict<list<number>> = {}
  var i = 0
  while i < len(fields)
    var parts = split(fields[i], "\t", true)
    assert_equal(3, len(parts), 'Git numstat record has two counts and a path')
    if len(parts) != 3
      throw 'Malformed fixture numstat'
    endif
    var counts = parts[0] == '-' && parts[1] == '-' ? [-1, -1] : [str2nr(parts[0]), str2nr(parts[1])]
    assert_true(parts[0] == '-' || parts[0] =~ '^\d\+$')
    assert_true(parts[1] == '-' || parts[1] =~ '^\d\+$')
    var path = parts[2]
    if path == ''
      assert_true(i + 2 < len(fields), 'rename has both raw NUL path fields')
      path = fields[i + 2]
      i += 2
    endif
    result[path] = counts
    i += 1
  endwhile
  return result
enddef

def StatsHeader(full: number)
  var added = 0
  var deleted = 0
  var unknown = 0
  for node in Entries()
    var entry = node.diffview_entry
    assert_equal(v:t_number, type(entry.added))
    assert_equal(v:t_number, type(entry.deleted))
    assert_true(entry.added >= -1 && entry.deleted >= -1)
    if entry.added < 0 || entry.deleted < 0
      assert_equal([-1, -1], [entry.added, entry.deleted], 'unknown is explicit, not zero')
      unknown += 1
    else
      added += entry.added
      deleted += entry.deleted
    endif
    var row = getbufvar(Role('panel').bufnr, 'NERDTree').ui.getLineNum(node)
    var suffix = entry.added < 0 ? '+? -?' : '+' .. entry.added .. ' -' .. entry.deleted
    assert_true(stridx(getbufline(Role('panel').bufnr, row)[0], suffix) >= 0,
      'native leaf displays actual known/unknown counts')
  endfor
  var summary = getbufline(Role('panel').bufnr, 3)[0]
  assert_match(len(Entries()) .. '/' .. full .. '\s\+entries', summary)
  assert_true(stridx(summary, '+' .. added .. ' -' .. deleted) >= 0, 'summary sums known visible counts')
  if unknown > 0
    assert_match(unknown .. '\s\+unknown', summary)
  else
    assert_false(summary =~ 'unknown', 'known zero is not an unknown counter')
  endif
enddef

def ReadingStats()
  execute 'cd ' .. fnameescape(test_tmp .. '/reading repo')
  var expected = {Staged: NumstatOracle('staged'), Unstaged: NumstatOracle('unstaged')}
  var first = len(PickerGitCalls())
  DiffviewOpen
  var diffs = PickerGitCalls()[first : ]->filter((_, command) => GitSubcommand(command) == 'diff')
  assert_equal(2, len(diffs), 'stats reuse the two existing local diff queries')
  for command in diffs
    var argv = split(command, "\n", true)
    assert_true(index(argv, '--raw') >= 0 && index(argv, '--numstat') >= 0, 'raw and counts come from the same query')
  endfor
  for node in Entries()
    var entry = node.diffview_entry
    var counts = entry.section == 'Untracked' || entry.oldmode == '120000' || entry.newmode == '120000'
      ? [-1, -1] : expected[entry.section][entry.path]
    assert_equal(counts, [entry.added, entry.deleted], 'metadata matches independent Git numstat: ' .. entry.path)
  endfor
  for path in ['move.c', 'empty-added.py']
    var entry = Node('Staged', path).diffview_entry
    assert_equal([0, 0], [entry.added, entry.deleted], 'pure rename/empty add is known zero')
  endfor
  assert_equal([0, 0], [Node('Unstaged', 'mode.txt').diffview_entry.added, Node('Unstaged', 'mode.txt').diffview_entry.deleted])
  var full = len(Entries())
  StatsHeader(full)
  var original = ComparisonState()
  try
    for malformed in ["oops\t1", "1\toops", "-2\t1", "-\t1", "1\t-"]
      $DIFFVIEW_TEST_BAD_NUMSTAT = malformed
      Reject('DiffviewRefresh')
      assert_equal(original, ComparisonState(), 'malformed count is not silently accepted as zero')
    endfor
  finally
    $DIFFVIEW_TEST_BAD_NUMSTAT = ''
  endtry
  var original_headers = getbufline(Role('panel').bufnr, 1, 2)
  SetProjection(['code.py', 'new.py'])
  StatsHeader(full)
  assert_equal(3, len(Entries()), 'same-path staged and unstaged count as two entries')
  var node = Node('Unstaged', 'code.py')
  var filtered_headers = getbufline(Role('panel').bufnr, 1, 4)
  assert_match('Filter:', filtered_headers[3])
  assert_equal(original_headers, filtered_headers[0 : 1])
  g:NERDTreeRender()
  assert_equal(filtered_headers, getbufline(Role('panel').bufnr, 1, 4), 'public native rerender retains summary and filter')
  var row = b:NERDTree.ui.getLineNum(node)
  assert_true(stridx(getline(row), node.displayString()) >= 0, 'stats/filter header height drives real screen lookup')
  TreeCursor(node)
  feedkeys("\<CR>", 'xt')
  Pair(['def indexed():', '    return 2'], ['def worktree():', '    return 3'])
  SetProjection([])
  StatsHeader(full)
  SetProjection(['NO_MATCH'])
  StatsHeader(full)
  SetProjection([])
  execute 'DiffviewOpen reading-left reading-right'
  var history = NumstatOracle('history')
  for entry in Entries()->mapnew((_, n) => n.diffview_entry)
    assert_equal(history[entry.path], [entry.added, entry.deleted], 'tree stats')
  endfor
  StatsHeader(len(Entries()))
  DiffviewCommit reading-right
  for entry in Entries()->mapnew((_, n) => n.diffview_entry)
    assert_equal(history[entry.path], [entry.added, entry.deleted], 'first-parent commit stats')
  endfor
  DiffviewCommit reading-left
  var root = NumstatOracle('root')
  for entry in Entries()->mapnew((_, n) => n.diffview_entry)
    var counts = entry.newmode == '120000' ? [-1, -1] : root[entry.path]
    assert_equal(counts, [entry.added, entry.deleted], 'root commit stats')
  endfor
  StatsHeader(len(Entries()))
  execute 'cd ' .. fnameescape(test_tmp .. '/edges')
  DiffviewOpen
  for entry in Entries()->mapnew((_, n) => n.diffview_entry)
    if entry.status == 'U' || index(['120000', '160000'], entry.oldmode) >= 0
        || index(['120000', '160000'], entry.newmode) >= 0 || entry.section == 'Untracked'
      assert_equal([-1, -1], [entry.added, entry.deleted], 'unsupported/untracked stats are unknown')
    endif
  endfor
  DiffviewClose
  execute 'cd ' .. fnameescape(test_tmp .. '/reading repo')
  execute 'DiffviewOpen HEAD HEAD'
  NoChanges()
  StatsHeader(0)
  DiffviewClose
enddef

def BranchStart(target = '', paths: list<string> = [])
  var command = 'DiffviewBranch'
  if target != ''
    command ..= ' ' .. escape(target, " \t\\")
  endif
  if !empty(paths)
    command ..= ' -- ' .. join(mapnew(paths, (_, path) => escape(path, " \t\\")), ' ')
  endif
  execute command
enddef

def BranchSources(name: string, prefix = 'branch', current = 'main')
  var left = PaneOption('left', 'statusline')
  var right = PaneOption('right', 'statusline')
  var display_name = substitute(name, '^refs/\%(heads\|remotes\)/', '', '')
  assert_true(stridx(left, display_name) >= 0, 'target branch label is visible')
  assert_true(stridx(left, Ref(prefix .. '-target')[0 : 6]) >= 0, 'left identifies the captured target commit')
  assert_true(stridx(right, current) >= 0, 'invoking branch label is visible')
  assert_true(stridx(right, Ref(prefix .. '-head')[0 : 6]) >= 0, 'right identifies the captured HEAD commit')
enddef

def BranchNoReload(first: number)
  for record in PickerGitCalls()[first : ]
    assert_equal(-1, index(['for-each-ref', 'symbolic-ref', 'log', 'fetch', 'pull', 'ls-remote', 'checkout', 'update-ref'],
      GitSubcommand(record)), 'frozen branch refresh does not enumerate/follow refs or contact/mutate branches')
  endfor
enddef

def BranchNoWrites(first: number)
  for record in PickerGitCalls()[first : ]
    assert_equal(-1, index(['fetch', 'pull', 'ls-remote', 'checkout', 'switch', 'update-ref', 'reset', 'add', 'commit', 'merge'],
      GitSubcommand(record)), 'branch browsing never contacts a remote or mutates Git state')
  endfor
enddef

def BranchFiltered(query: string, paths: list<string> = [])
  $FZF_DEFAULT_OPTS = '--filter=' .. shellescape(query)
  BranchStart('', paths)
  WaitPicker()
enddef

def BranchDirect()
  assert_equal(0, exists(':DiffBranch'), 'retired command has no alias or warning stub in a fresh plugin session')
  assert_equal(0, exists('*g:DiffBranch'), 'retired global function is absent')
  var first_call = len(PickerGitCalls())
  execute 'cd ' .. fnameescape(test_tmp .. '/branch repo')
  var repo = getcwd()
  edit shared.txt
  setline(1, ['UNSAVED direct branch caller'])
  set nohidden autowrite autowriteall
  var userbuf = bufnr()
  SeedRegisters()
  var registers = RegisterState()
  assert_false(exists('*fzf#run'), 'direct branch case starts without core fzf')
  for name in ['BR_LOCAL_PICK', 'refs/heads/BR_LOCAL_PICK', 'origin/collision', Ref('branch-punctuation')]
    BranchStart(name)
    Select('', 'shared.txt')
    Pair(['TARGET shared'], ['MAIN shared'])
    BranchSources(name)
    Select('', 'target-only.txt')
    Pair(['TARGET only'], [''])
    assert_equal('D', Node('', 'target-only.txt').diffview_entry.status, 'direct endpoints, not merge-base diff')
    Select('', 'current-only.txt')
    Pair([''], ['MAIN only'])
    assert_false(filereadable('BRANCH_INJECTED'))
  endfor
  BranchStart('refs/remotes/origin/collision')
  Select('', 'shared.txt')
  Pair(['BASE shared'], ['MAIN shared'])
  assert_match('origin/collision', PaneOption('left', 'statusline'))
  assert_true(stridx(PaneOption('left', 'statusline'), Ref('branch-root')[0 : 6]) >= 0)
  assert_equal([], filter(Entries(), (_, node) => node.diffview_entry.path == 'target-only.txt'),
    'full remote ref disambiguates the same short name')
  BranchStart('origin/BR_REMOTE_PICK', ['src'])
  assert_equal(['src/choice.txt'], Entries()->mapnew((_, node) => node.diffview_entry.path))
  Pair(['TARGET src'], ['MAIN src'])
  BranchSources('origin/BR_REMOTE_PICK')
  BranchStart('main')
  NoChanges()
  var head_path = repo .. '/.git/HEAD'
  var head_bytes = readfile(head_path, 'b')
  try
    writefile([Ref('branch-head')], head_path)
    BranchStart('BR_LOCAL_PICK')
    Select('', 'shared.txt')
    Pair(['TARGET shared'], ['MAIN shared'])
    assert_match('\cdetached', PaneOption('right', 'statusline'))
  finally
    writefile(head_bytes, head_path, 'b')
  endtry
  BranchStart('BR_LOCAL_PICK')
  Select('', 'shared.txt')
  var state = ComparisonState()
  for command in ['DiffviewBranch absent', 'DiffviewBranch HEAD', 'DiffviewBranch main^',
      'DiffviewBranch BR_TAG_NOT_BRANCH', 'DiffviewBranch refs/tags/BR_TAG_NOT_BRANCH',
      'DiffviewBranch BR_LOCAL_ALIAS', 'DiffviewBranch refs/remotes/origin/HEAD',
      'DiffviewBranch --version', 'DiffviewBranch ^BR_LOCAL_PICK', 'DiffviewBranch main BR_LOCAL_PICK',
      'DiffviewBranch main..BR_LOCAL_PICK', 'DiffviewBranch main -- ../outside']
    Reject(command)
    assert_equal(state, ComparisonState(), 'invalid branch input preserves the old view: ' .. command)
  endfor
  var saved_path = $PATH
  try
    $PATH = test_tmp .. '/no-fzf-bin'
    assert_false(executable('fzf'))
    BranchStart('BR_LOCAL_PICK')
    Select('', 'shared.txt')
    Pair(['TARGET shared'], ['MAIN shared'])
    state = ComparisonState()
    Reject('DiffviewBranch')
    assert_match('\cfzf', execute('messages'))
    assert_equal(state, ComparisonState())
    &runtimepath = $FZF_RUNTIME .. ',' .. &runtimepath
    runtime plugin/fzf.vim
    assert_true(exists('*fzf#exec'))
    state = ComparisonState()
    Reject('DiffviewBranch')
    assert_equal(state, ComparisonState(), 'missing binary cannot replace the old view')
    BranchStart('BR_LOCAL_PICK')
    Select('', 'shared.txt')
    Pair(['TARGET shared'], ['MAIN shared'])
  finally
    $PATH = saved_path
  endtry
  for directory in ['unborn', 'nonrepo', 'bare.git']
    execute 'cd ' .. fnameescape(test_tmp .. '/' .. directory)
    for command in ['DiffviewBranch BR_LOCAL_PICK', 'DiffviewBranch']
      state = ComparisonState()
      $FZF_DEFAULT_OPTS = '--filter=NO_BRANCH_MATCH_96b5'
      Reject(command)
      WaitPicker()
      assert_equal(state, ComparisonState(), 'invalid repository/current HEAD preserves the view')
    endfor
  endfor
  BranchNoWrites(first_call)
  assert_equal(registers, RegisterState())
  assert_true(getbufvar(userbuf, '&modified'))
  assert_equal(['UNSAVED direct branch caller'], getbufline(userbuf, 1, '$'))
  assert_equal(['DISK branch dirt'], readfile(repo .. '/shared.txt'))
  DiffviewClose
enddef

def BranchReal()
  var first_call = len(PickerGitCalls())
  for item in [['branch repo', 'branch'], ['branch-sha256', 'branch256']]
    tabnew
    execute 'cd ' .. fnameescape(test_tmp .. '/' .. item[0])
    var repo = getcwd()
    edit shared.txt
    setline(1, ['UNSAVED real branch caller'])
    var userbuf = bufnr()
    set nohidden autowrite autowriteall
    SeedRegisters()
    BranchFiltered('BR_LOCAL_PICK', ['src'])
    assert_equal(['src/choice.txt'], Entries()->mapnew((_, node) => node.diffview_entry.path))
    Pair(['TARGET src'], ['MAIN src'])
    BranchSources('BR_LOCAL_PICK', item[1])
    assert_equal(item[1] == 'branch' ? 40 : 64, strlen(Ref(item[1] .. '-target')))
    var state = ComparisonState()
    BranchFiltered('NO_BRANCH_MATCH_96b5')
    assert_equal(state, ComparisonState(), 'real binary no-match leaves the view and focus intact')
    for alias in ['origin/HEAD', 'BR_LOCAL_ALIAS']
      BranchFiltered(alias)
      assert_equal(state, ComparisonState(), 'symbolic branch alias is not selectable: ' .. alias)
    endfor
    BranchFiltered('origin/BR_REMOTE_PICK', ['src'])
    Pair(['TARGET src'], ['MAIN src'])
    BranchSources('origin/BR_REMOTE_PICK', item[1])
    var expected = ReadingView()
    var head_path = repo .. '/.git/HEAD'
    var main_path = repo .. '/.git/refs/heads/main'
    var target_path = repo .. '/.git/refs/remotes/origin/BR_REMOTE_PICK'
    var files = [head_path, main_path, target_path]
    var original = files->mapnew((_, file) => readfile(file, 'b'))
    try
      for file in files
        writefile([Ref(item[1] .. '-root')], file)
      endfor
      execute 'cd ' .. fnameescape(test_tmp .. '/nonrepo')
      var first = len(PickerGitCalls())
      DiffviewRefresh
      WaitPicker()
      Pair(['TARGET src'], ['MAIN src'])
      BranchSources('origin/BR_REMOTE_PICK', item[1])
      assert_equal(expected, ReadingView(), 'immutable branch labels, prefixes and both tips survive moved refs/HEAD')
      assert_equal(resolve(repo), resolve(getbufvar(Role('panel').bufnr, 'NERDTree').root.path.str()))
      BranchNoReload(first)
    finally
      for i in range(len(files))
        writefile(original[i], files[i], 'b')
      endfor
    endtry
    assert_true(getbufvar(userbuf, '&modified'))
    assert_equal(['UNSAVED real branch caller'], getbufline(userbuf, 1, '$'))
    assert_equal(['DISK branch dirt'], readfile(repo .. '/shared.txt'))
    DiffviewClose
  endfor
  BranchNoWrites(first_call)
  writefile([json_encode({scope: 'real core/binary filtered selection, not physical terminal input',
    core_binary: fzf#exec('0.0.0', 1), formats: ['sha1', 'sha256']})], test_tmp .. '/branch-real.facts.json')
enddef

def BranchApi()
  var first_call = len(PickerGitCalls())
  execute 'cd ' .. fnameescape(test_tmp .. '/branch repo')
  var repo = getcwd()
  DiffviewOpen
  Select('Staged', 'shared.txt')
  BranchStart('', ['src'])
  var row = PickerRow('BR_LOCAL_PICK')
  var rows = g:diffview_test_picker_spec.source
  assert_equal(7, len(rows), 'all ordinary local/remote refs, including same-OID aliases, appear once')
  assert_equal([], filter(copy(rows), (_, line) => stridx(line, 'origin/HEAD') >= 0))
  assert_equal([], filter(copy(rows), (_, line) => stridx(line, 'BR_LOCAL_ALIAS') >= 0))
  assert_equal([], filter(copy(rows), (_, line) => stridx(line, 'BR_TAG_NOT_BRANCH') >= 0))
  var collision = filter(copy(rows), (_, line) => stridx(line, 'origin/collision') >= 0)
  assert_equal(2, len(collision), 'local and remote collision rows are distinct')
  assert_true(!empty(filter(copy(collision), (_, line) => line =~ '\clocal\|refs/heads/')))
  assert_true(!empty(filter(copy(collision), (_, line) => line =~ '\cremote')))
  PickerRow('alias-target')
  var head_path = repo .. '/.git/HEAD'
  var files = [head_path, repo .. '/.git/refs/heads/main', repo .. '/.git/refs/heads/BR_LOCAL_PICK']
  var original = files->mapnew((_, file) => readfile(file, 'b'))
  try
    SetProjection(['shared.txt'])
    for file in files
      writefile([Ref('branch-root')], file)
    endfor
    execute 'cd ' .. fnameescape(test_tmp .. '/picker-elsewhere')
    var cwd = getcwd()
    PickerOutput([row])
    assert_equal(['src/choice.txt'], Entries()->mapnew((_, node) => node.diffview_entry.path),
      'callback retains the launch prefixes, not a later projection')
    Pair(['TARGET src'], ['MAIN src'])
    BranchSources('BR_LOCAL_PICK')
    assert_equal(resolve(repo), resolve(getbufvar(Role('panel').bufnr, 'NERDTree').root.path.str()))
    assert_equal(cwd, getcwd(), 'callback keeps newer cwd')
    var calls = g:diffview_test_picker_calls
    var first = len(PickerGitCalls())
    DiffviewRefresh
    Pair(['TARGET src'], ['MAIN src'])
    BranchSources('BR_LOCAL_PICK')
    assert_equal(calls, g:diffview_test_picker_calls, 'refresh never opens another picker')
    BranchNoReload(first)
  finally
    for i in range(len(files))
      writefile(original[i], files[i], 'b')
    endfor
  endtry
  execute 'cd ' .. fnameescape(repo)
  BranchStart('', ['src'])
  row = PickerRow('BR_LOCAL_PICK')
  var state = ComparisonState()
  PickerOutput([])
  assert_equal(state, ComparisonState())
  for output in [0, row, [1], ['not a row'], [row, row], ['query', row], ['ctrl-x', row],
      [row .. ' forged'], [row[0 : strlen(row) - 2]], [Ref('branch-target')]]
    PickerOutput(output, true)
    assert_equal(state, ComparisonState(), 'branch callback rejects malformed/non-source output as a whole')
  endfor
  g:diffview_test_picker_throw = 1
  var captured_spec = g:diffview_test_picker_spec
  try
    Reject('DiffviewBranch')
    assert_equal(state, ComparisonState(), 'branch picker creation failure preserves old state')
  finally
    g:diffview_test_picker_throw = 0
    g:diffview_test_picker_spec = captured_spec
  endtry
  var oid = Ref('branch-target')
  var object = repo .. '/.git/objects/' .. oid[0 : 1] .. '/' .. oid[2 : ]
  try
    assert_equal(0, rename(object, test_tmp .. '/branch-object.saved'))
    PickerOutput([row], true)
    assert_equal(state, ComparisonState(), 'captured target read error cannot replace old view')
  finally
    assert_equal(0, rename(test_tmp .. '/branch-object.saved', object))
  endtry
  augroup DiffviewBranchRenderFailure
    autocmd FileType nerdtree throw 'fixture branch selected render failure'
  augroup END
  try
    state = ComparisonState()
    PickerOutput([row], true)
    assert_equal(state, ComparisonState(), 'branch selected-view renderer failure rolls back')
  finally
    augroup DiffviewBranchRenderFailure
      autocmd!
    augroup END
  endtry
  PickerOutput([row])
  Pair(['TARGET src'], ['MAIN src'])
  BranchSources('BR_LOCAL_PICK')
  BranchNoWrites(first_call)
  DiffviewClose
enddef

def BranchOwnedJobsQuiet(): bool
  var quiet = 0
  var started = reltime()
  while quiet < 3 && reltimefloat(reltime(started)) < 5.0
    sleep 20m
    var pending = filter(copy(g:diffview_test_started_picker_jobs), (_, job) => job_status(job) == 'run'
      || index(['open', 'buffered'], ch_status(job_getchannel(job))) >= 0)
    quiet = empty(pending) ? quiet + 1 : 0
  endwhile
  return quiet >= 3
enddef

def BranchLifecycle()
  var first_call = len(PickerGitCalls())
  execute 'cd ' .. fnameescape(test_tmp .. '/branch repo')
  var repo = getcwd()
  var elsewhere = resolve(test_tmp .. '/picker-elsewhere')
  edit shared.txt
  setline(1, ['UNSAVED branch lifecycle caller'])
  set nohidden autowrite autowriteall
  setlocal bufhidden=wipe number spell nowinfixwidth nowinfixheight
  var userbuf = bufnr()
  var origin = win_getid()
  var options = WindowOptions(origin)
  BranchStart('BR_LOCAL_PICK', ['src'])
  Pair(['TARGET src'], ['MAIN src'])
  SeedRegisters()
  var records: list<any> = []
  for layout in ['default', 'enew']
    win_gotoid(origin)
    execute 'tcd ' .. fnameescape(repo)
    var cwd = [getcwd(), getcwd(-1), haslocaldir()]
    assert_equal(2, cwd[2])
    if layout == 'enew'
      g:fzf_layout = {window: 'enew'}
    else
      unlet! g:fzf_layout
    endif
    var state = ComparisonState()
    BranchFiltered('NO_BRANCH_MATCH_96b5', ['src'])
    win_gotoid(Role('panel').winid)
    win_gotoid(origin)
    sleep 40m
    assert_equal(state, ComparisonState(), layout .. ' no match preserves caller/view/resources')
    assert_equal(cwd, [getcwd(), getcwd(-1), haslocaldir()], layout .. ' initial tcd remains tab-local')
    $FZF_DEFAULT_OPTS = '--bind=start:abort'
    BranchStart('', ['src'])
    WaitPicker()
    assert_equal(state, ComparisonState(), layout .. ' binary abort leaves old view and dirty caller')
    $FZF_DEFAULT_OPTS = ''
    BranchStart('', ['src'])
    var terminals = getbufinfo()->filter((_, b) => getbufvar(b.bufnr, '&filetype') == 'fzf')
    assert_equal(1, len(terminals), 'one actual branch picker terminal')
    var picker = terminals[0].bufnr
    if layout == 'default'
      assert_false(empty(popup_list()), 'default branch picker is a real popup')
    else
      assert_equal(origin, win_getid(), 'enew branch picker is in the caller')
    endif
    win_execute(origin, 'tcd ' .. fnameescape(elsewhere))
    var location = win_id2tabwin(origin)
    var expected_global = getcwd(-1)
    assert_equal([elsewhere, 2], [getcwd(location[1], location[0]), haslocaldir(location[1], location[0])])
    term_sendkeys(picker, 'BR_LOCAL_PICK')
    var stable = 0
    var started = reltime()
    while stable < 2 && reltimefloat(reltime(started)) < 5.0
      term_wait(picker, 20)
      var screen = mapnew(range(1, term_getsize(picker)[0]), (_, row) => term_getline(picker, row))
      var query = !empty(filter(copy(screen), (_, line) => line =~ 'BR_LOCAL_PICK[ │]*$'))
      var one = !empty(filter(copy(screen), (_, line) => line =~ '\<1/7\>'))
      stable = query && one ? stable + 1 : 0
    endwhile
    assert_true(stable >= 2, 'real branch query and unique match are visible before Enter')
    term_sendkeys(picker, "\<CR>")
    WaitPicker()
    Pair(['TARGET src'], ['MAIN src'])
    BranchSources('BR_LOCAL_PICK')
    location = win_id2tabwin(origin)
    assert_equal([elsewhere, 2], [getcwd(location[1], location[0]), haslocaldir(location[1], location[0])],
      layout .. ' keeps latest user tcd while selecting in original repo')
    assert_equal([elsewhere, expected_global], [getcwd(), getcwd(-1)], layout .. ' post-Open keeps current/global cwd')
    win_gotoid(origin)
    execute 'tcd ' .. fnameescape(repo)
    $FZF_DEFAULT_OPTS = ''
    var sleeper = job_start(['/bin/sleep', '30'], {in_io: 'null', out_io: 'null', err_io: 'null'})
    try
      g:diffview_test_prior_jobs = job_info()
      g:diffview_test_started_picker_jobs = []
      var prior_popups = popup_list()
      augroup DiffviewBranchLiveFailure
        execute 'autocmd FileType fzf legacy call ' .. expand('<SID>') .. 'PickerFileTypeFailure()'
      augroup END
      state = ComparisonState()
      Reject('DiffviewBranch -- src')
      assert_true(len(g:diffview_test_started_picker_jobs) > 0, 'fault follows an actual live branch job')
      assert_true(BranchOwnedJobsQuiet())
      assert_equal('run', job_status(sleeper), 'branch rollback leaves unrelated user job running')
      assert_equal(prior_popups, popup_list(), 'only the owned popup is removed')
      var messages = execute('messages') .. v:errmsg
      assert_match('fixture picker post-terminal FileType failure', messages)
      assert_notmatch('E948\|E994', messages)
      assert_equal(state, ComparisonState(), layout .. ' live-job fault restores full state')
      assert_equal(cwd, [getcwd(), getcwd(-1), haslocaldir()])
      add(records, {layout: layout, actual_jobs_started: len(g:diffview_test_started_picker_jobs),
        latest_tcd_preserved: true, owned_jobs_quiet: true, unrelated_job_running: true})
    finally
      augroup DiffviewBranchLiveFailure
        autocmd!
      augroup END
      if job_status(sleeper) == 'run'
        job_stop(sleeper)
      endif
    endtry
    assert_equal(options, WindowOptions(origin))
    assert_equal([false, true, true], [&hidden, &autowrite, &autowriteall])
    assert_true(getbufvar(userbuf, '&modified'))
    assert_equal(['UNSAVED branch lifecycle caller'], getbufline(userbuf, 1, '$'))
    assert_equal(['DISK branch dirt'], readfile(repo .. '/shared.txt'))
  endfor
  g:fzf_layout = {window: 'enew | throw "fixture branch layout failure"'}
  var state = ComparisonState()
  Reject('DiffviewBranch')
  WaitPicker()
  assert_equal(state, ComparisonState(), 'branch pre-terminal creation failure restores old state')
  BranchNoWrites(first_call)
  writefile([json_encode({scope: 'real core/binary headless actor and abort, not outer PTY', layouts: records})],
    test_tmp .. '/branch-lifecycle.facts.json')
  DiffviewClose
enddef

try
  assert_true(has('vim9script'))
  assert_true(has('diff'))
  assert_true(has('windows'))
  assert_true(has('job'))
  assert_true(has('timers'))
  &runtimepath = $DIFFVIEW_TEST_RUNTIME .. ',' .. $VIMRUNTIME
  g:NERDTreeBookmarksFile = test_tmp .. '/bookmarks'
  g:NERDTreeHijackNetrw = 0
  if case_name != 'dependency'
    &runtimepath = $NERDTREE_RUNTIME .. ',' .. &runtimepath
    if case_name == 'tree_isolation' || case_name == 'tree_git'
      g:NERDTreeWinPos = 'right'
      g:NERDTreeWinSize = 27
      g:NERDTreeMinimalUI = 1
      g:NERDTreeShowHidden = 1
      g:NERDTreeShowBookmarks = 1
      g:NERDTreeShowFiles = 0
      g:NERDTreeIgnore = ['\.txt$']
      g:NERDTreeChDirMode = 2
      g:NERDTreeDirArrowExpandable = '++'
      g:NERDTreeDirArrowCollapsible = 'vv'
    endif
    if case_name == 'tree_git'
      &runtimepath = $NERDTREE_GIT_RUNTIME .. ',' .. &runtimepath
    endif
    runtime plugin/NERD_tree.vim
    assert_equal(2, exists(':NERDTree'), 'real NERDTree commands are loaded')
  endif
  if (case_name =~ '^picker_' || case_name == 'reading_filter' || case_name =~ '^branch_')
      && index(['picker_missing', 'branch_direct'], case_name) < 0
    if case_name == 'picker_api' || case_name == 'branch_api'
      &runtimepath = $FZF_RUNTIME .. ',' .. &runtimepath
      runtime plugin/fzf.vim
      &runtimepath = harness_root .. '/tests/picker-api,' .. &runtimepath
      runtime autoload/fzf.vim
    elseif case_name == 'picker_old_binary'
      &runtimepath = test_tmp .. '/old-fzf-core,' .. &runtimepath
      runtime plugin/fzf.vim
    else
      &runtimepath = $FZF_RUNTIME .. ',' .. &runtimepath
      runtime plugin/fzf.vim
      assert_true(has('terminal'), 'filtered core integration uses a real Vim terminal job')
    endif
  endif
  if case_name =~ '^picker_' || case_name == 'reading_filter' || case_name =~ '^branch_'
    g:fzf_layout = {down: 8}
  endif
  runtime plugin/main.vim
  if exists(':DiffviewOpen') != 2
    throw 'DiffviewOpen command unavailable in the candidate runtime'
  endif
  defcompile
  if case_name == 'local'
    Local()
  elseif case_name == 'clean'
    Clean()
  elseif case_name == 'unborn'
    Unborn()
  elseif case_name == 'nonrepo'
    Nonrepo()
  elseif case_name == 'special'
    Special()
  elseif case_name == 'refresh'
    Refresh()
  elseif case_name == 'lifecycle'
    Lifecycle()
  elseif case_name == 'ownership'
    Ownership()
  elseif case_name == 'ancestor'
    Ancestor()
  elseif case_name == 'trees'
    Trees()
  elseif case_name == 'commits'
    Commits()
  elseif case_name == 'historical_refresh'
    HistoricalRefresh()
  elseif case_name == 'errors'
    Errors()
  elseif case_name == 'exclusions'
    Exclusions()
  elseif case_name == 'edges'
    Edges()
  elseif case_name == 'cross_tab'
    CrossTab()
  elseif case_name == 'read_failure'
    ReadFailure()
  elseif case_name == 'navigation'
    Navigation()
  elseif case_name == 'binary_clean'
    BinaryClean()
  elseif case_name == 'binary_mixed'
    BinaryMixed()
  elseif case_name == 'large'
    Large()
  elseif case_name == 'empty_start'
    EmptyStart()
  elseif case_name == 'tree_nodes'
    TreeNodes()
  elseif case_name == 'tree_history'
    TreeHistory()
  elseif case_name == 'tree_isolation' || case_name == 'tree_git'
    TreeIsolation()
  elseif case_name == 'dependency'
    Dependency()
  elseif case_name == 'tree_rollback'
    TreeRollback()
  elseif case_name == 'picker_real'
    PickerReal()
  elseif case_name == 'picker_no_match'
    PickerNoMatch()
  elseif case_name == 'picker_enew'
    PickerEnew()
  elseif case_name == 'picker_async'
    PickerAsync()
  elseif case_name == 'picker_sha256'
    PickerSha256()
  elseif case_name == 'picker_missing'
    PickerMissing()
  elseif case_name == 'picker_old_binary'
    PickerOldBinary()
  elseif case_name == 'picker_errors'
    PickerErrors()
  elseif case_name == 'picker_api'
    PickerApi()
  elseif case_name == 'reading_syntax'
    ReadingSyntax()
  elseif case_name == 'reading_goto'
    ReadingGoto()
  elseif case_name == 'reading_filter'
    ReadingFilter()
  elseif case_name == 'reading_stats'
    ReadingStats()
  elseif case_name == 'branch_direct'
    BranchDirect()
  elseif case_name == 'branch_real'
    BranchReal()
  elseif case_name == 'branch_api'
    BranchApi()
  elseif case_name == 'branch_lifecycle'
    BranchLifecycle()
  else
    throw 'Unknown test case: ' .. case_name
  endif
catch
  add(v:errors, v:exception .. ' at ' .. v:throwpoint)
endtry

if !empty(v:errors)
  writefile(v:errors, test_tmp .. '/' .. case_name .. '.errors')
  cquit 1
endif
writefile(['PASS: ' .. case_name], test_tmp .. '/' .. case_name .. '.result')
qa!
