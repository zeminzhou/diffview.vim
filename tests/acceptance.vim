vim9script

const test_tmp = $DIFFVIEW_TEST_TMP
const case_name = $DIFFVIEW_TEST_CASE
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
  return ['diff', 'scrollbind', 'cursorbind', 'foldmethod', 'foldcolumn', 'wrap']->mapnew(
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

  DiffBranch left
  Select('', 'shared.txt')
  Pair(['LEFT shared'], ['MERGED shared'])
  call g:ToggleDiffView()
  assert_equal([], PluginBuffers(), 'legacy Toggle closes a historical view')
  call g:DiffBranch('left')
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
  execute 'DiffviewCommit'
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
    DiffviewRefresh
    assert_equal(['DISK cross'], getbufline(Role('right').bufnr, 1, '$'))
    assert_equal(['HEAD cross'], getbufline(Role('left').bufnr, 1, '$'))
    assert_match('INDEX', getbufvar(Role('left').bufnr, 'diffview_source'))
    assert_match('INDEX', PaneOption('left', 'statusline'))
    assert_match('WORKTREE', getbufvar(Role('right').bufnr, 'diffview_source'))
    assert_match('WORKTREE', PaneOption('right', 'statusline'), 'cross-tab label restored with changes')
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
