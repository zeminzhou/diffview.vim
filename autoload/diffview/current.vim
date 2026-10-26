vim9script

# Copyright (C) 2022 zeminzhou <zeminzhou_@outlook.com>
# Modified 2026-10-22. Licensed under AGPL-3.0-or-later; see LICENSE.

import autoload 'diffview/git.vim' as git
import autoload 'diffview/tree.vim' as tree
import autoload 'diffview/syntax.vim' as syntax
import autoload 'diffview/history.vim' as history
import autoload 'diffview/preview.vim' as preview

var view: dict<any> = {}
var serial = 0

def Error(message: string)
    echohl ErrorMsg
    echomsg message =~ '^\[diffview\]' ? message : '[diffview] ' .. message
    echohl None
enddef

def OwnedWindow(id: number): bool
    return !empty(getwininfo(id)) && index(view.buffers, winbufnr(id)) >= 0
enddef

export def Close()
    if empty(view)
        return
    endif
    var old = view
    view = {}
    g:diffview_enabled = false
    augroup DiffviewView
        autocmd!
    augroup END
    if old.timer != -1
        timer_stop(old.timer)
    endif
    var owned: list<number> = []
    for id in old.windows
        if !empty(getwininfo(id)) && index(old.buffers, winbufnr(id)) >= 0
            win_execute(id, 'diffoff')
            add(owned, id)
        endif
    endfor
    if !empty(owned)
        var tab = win_id2tabwin(owned[0])[0]
        var tabwins = gettabinfo(tab)[0].windows
        if len(owned) == len(tabwins) && tabpagenr('$') > 1
            win_gotoid(owned[0])
            tabclose
        else
            for id in owned
                if !empty(getwininfo(id))
                    win_execute(id, 'silent! close')
                endif
            endfor
        endif
    endif
    for buf in old.buffers
        if bufexists(buf)
            execute 'silent! bwipeout! ' .. buf
        endif
    endfor
    win_gotoid(old.origin)
enddef

def CloseLater(token: number)
    if !empty(view) && view.token == token
        Close()
    endif
enddef

export def LostWindow(id: number)
    if !empty(view) && index(view.windows, id) >= 0 && view.timer == -1
        var token = view.token
        view.timer = timer_start(0, (_) => CloseLater(token))
    endif
enddef

export def LostBuffer(buf: number)
    if !empty(view) && index(view.buffers, buf) >= 0
        LostWindow(view.windows[0])
    endif
enddef

def Events()
    augroup DiffviewView
        autocmd!
        autocmd WinClosed * LostWindow(str2nr(expand('<afile>')))
        autocmd BufWipeout * LostBuffer(str2nr(expand('<abuf>')))
    augroup END
enddef

def Mappings()
    nnoremap <silent> <buffer> q <ScriptCmd>Close()<CR>
    nnoremap <silent> <buffer> r <ScriptCmd>Refresh()<CR>
    nnoremap <silent> <buffer> ]f <ScriptCmd>Next(1)<CR>
    nnoremap <silent> <buffer> [f <ScriptCmd>Next(-1)<CR>
    nnoremap <silent> <buffer> <Tab> <ScriptCmd>Cycle(1)<CR>
    nnoremap <silent> <buffer> <S-Tab> <ScriptCmd>Cycle(-1)<CR>
    nnoremap <silent> <buffer> gf <ScriptCmd>GotoFile()<CR>
enddef

def Buffer(role: string): number
    var buf = bufnr()
    add(view.buffers, buf)
    execute 'silent file diffview://' .. view.token .. '/' .. role
    setlocal buftype=nofile bufhidden=hide noswapfile nobuflisted nomodeline
    setlocal nowrap nospell nomodifiable readonly
    setlocal nofoldenable foldcolumn=0 nonumber norelativenumber
    if role == 'panel'
        setlocal filetype=nerdtree
    else
        setlocal filetype=diffview
    endif
    b:diffview_role = role
    Mappings()
    return buf
enddef

def Put(buf: number, lines: list<string>, eol: bool)
    setbufvar(buf, '&readonly', false)
    setbufvar(buf, '&modifiable', true)
    try
        setbufline(buf, 1, lines)
        if len(getbufline(buf, 1, '$')) > len(lines)
            deletebufline(buf, len(lines) + 1, '$')
        endif
        setbufvar(buf, '&endofline', eol)
        setbufvar(buf, '&fixendofline', false)
        setbufvar(buf, '&modified', false)
    finally
        setbufvar(buf, '&modifiable', false)
        setbufvar(buf, '&readonly', true)
    endtry
enddef

def Show(index: number, content: dict<any>, reveal = true)
    if reveal
        tree.Reveal(view.windows[0], view.tree, index)
    endif
    var entry = view.model.entries[index]
    for side in [1, 2]
        var role = side == 1 ? 'left' : 'right'
        var path = side == 1 ? entry.oldpath : entry.path
        var source = content[role .. 'Source']
        var buf = view.buffers[side]
        var win = view.windows[side]
        Put(buf, content[role].lines, content[role].eol)
        setbufvar(buf, 'diffview_path', path)
        setbufvar(buf, 'diffview_section', entry.section)
        setbufvar(buf, 'diffview_source', source)
        var location = win_id2tabwin(win)
        settabwinvar(location[0], location[1], '&statusline', substitute(entry.section .. ' | ' .. git.Display(source)
            .. ' | ' .. git.Display(path), '%', '%%', 'g'))
        win_execute(win, content.diff ? 'diffthis' : 'diffoff')
        syntax.Apply(win, path, content.diff && (side == 1 ? entry.oldmode : entry.newmode) != '000000')
    endfor
    view.selected = index
    if content.diff
        win_execute(view.windows[1], 'diffupdate')
    endif
enddef

def EmptyView()
    var message = empty(get(view.model, 'fullEntries', [])) ? 'No changes' : 'No matching changes'
    for side in [1, 2]
        Put(view.buffers[side], [message], true)
        win_execute(view.windows[side], 'diffoff')
        syntax.Apply(view.windows[side], '', false)
        var location = win_id2tabwin(view.windows[side])
        settabwinvar(location[0], location[1], '&statusline', '[diffview] ' .. message)
        for name in ['path', 'section', 'source']
            setbufvar(view.buffers[side], 'diffview_' .. name, '')
        endfor
    endfor
    view.selected = -1
enddef

def Usable(): bool
    if empty(view)
        return false
    endif
    for id in view.windows
        if !OwnedWindow(id)
            Close()
            return false
        endif
    endfor
    return true
enddef

export def Select()
    if !Usable()
        return
    endif
    try
        var node = g:NERDTreeFileNode.GetSelected()
        if empty(node)
            return
        elseif !has_key(node, 'diffview_entry')
            tree.Navigate(view.windows[0], view.tree, 'toggle')
            return
        endif
        var index = node.diffview_index
        var content = git.Read(view.model, node.diffview_entry)
        Show(index, content)
    catch
        Error(v:exception)
    endtry
enddef

export def Navigate(action: string)
    if !Usable()
        return
    endif
    try
        tree.Navigate(view.windows[0], view.tree, action)
    catch
        Error(v:exception)
    endtry
enddef

export def Next(delta: number)
    if !Usable() || empty(view.model.entries)
        return
    endif
    var count = len(view.model.entries)
    var index = (view.selected + delta + count) % count
    try
        var content = git.Read(view.model, view.model.entries[index])
        Show(index, content)
    catch
        Error(v:exception)
    endtry
enddef

export def Cycle(delta: number)
    if !Usable()
        return
    endif
    var index = index(view.windows, win_getid())
    win_gotoid(view.windows[(index + delta + 3) % 3])
enddef

def Replace(model: dict<any>, projection = false)
    var selected = empty(model.entries) ? -1 : 0
    var retained = false
    if view.selected >= 0
        var old = view.model.entries[view.selected]
        for i in range(len(model.entries))
            if model.entries[i].section == old.section && model.entries[i].path == old.path
                selected = i
                retained = projection && model.entries[i] is old
                break
            endif
        endfor
    endif
    var content = selected < 0 || retained ? {} : git.Read(model, model.entries[selected])
    var key = tree.CursorKey(view.windows[0], view.tree)
    var candidate = tree.Build(model, tree.Expansion(view.tree))
    if view.selected < 0 || !has_key(candidate.diffview_nodes, key)
        key = 'root'
        if selected >= 0
            var node = candidate.diffview_entries[selected]
            tree.ExpandParents(node)
            key = node.diffview_key
        endif
    endif
    tree.Install(view.windows[0], candidate)
    view.model = model
    view.tree = candidate
    tree.Cursor(view.windows[0], candidate, key)
    if selected < 0
        EmptyView()
    elseif retained
        view.selected = selected
    else
        Show(selected, content, false)
    endif
enddef

export def Refresh()
    if !Usable()
        return
    endif
    try
        var model = git.Comparison(view.model.root, view.model.args, view.model.mode == 'commit')
        if has_key(view.model, 'branchLabels')
            model.branchLabels = view.model.branchLabels
            model.leftSource = model.branchLabels.left
            model.rightSource = model.branchLabels.right
        endif
        if has_key(view.model, 'historyPaths')
            model = git.HistoryScope(model, view.model.historyPaths, true)
        endif
        Replace(git.Project(model, view.model.paths))
    catch
        Error(v:exception)
    endtry
enddef

export def Filter(paths: list<string>)
    if !Usable()
        Error('No active comparison.')
        return
    endif
    try
        Replace(git.Project(view.model, git.Prefixes(paths)), true)
    catch
        Error(v:exception)
    endtry
enddef

export def GotoFile()
    if !Usable()
        Error('No active comparison.')
        return
    endif
    var caller = win_getid()
    var created = 0
    var target = -1
    var buffers = getbufinfo()->mapnew((_, info) => info.bufnr)
    var windows = getwininfo()->mapnew((_, info) => info.winid)
    var filename = ''
    try
        var selected = view.selected
        var side = caller == view.windows[1] ? 1 : 2
        var hint = index(view.windows[1 :], caller) < 0 ? 1 : line('.')
        if caller == view.windows[0]
            var node = g:NERDTreeFileNode.GetSelected()
            if empty(node) || !has_key(node, 'diffview_entry')
                throw '[diffview] Select a file node to open its worktree file.'
            endif
            selected = node.diffview_index
        endif
        if selected < 0
            throw '[diffview] No selected file.'
        endif
        var entry = view.model.entries[selected]
        var prefix = view.model[side == 1 ? 'leftPrefix' : 'rightPrefix']
        if type(prefix) != v:t_string
            throw '[diffview] This tree has no proven worktree path mapping.'
        endif
        var path = side == 1 ? entry.oldpath : entry.path
        filename = git.WorktreeFile(view.model.root, (prefix == '' ? '' : prefix .. '/') .. path)
        for info in getbufinfo()
            if info.loaded && info.name != '' && resolve(info.name) == resolve(filename)
                target = info.bufnr
                break
            endif
        endfor
        var tab = win_id2tabwin(view.windows[0])[0]
        if target >= 0
            execute ':' .. tab .. 'tab sbuffer ' .. target
        else
            execute ':' .. tab .. 'tabedit ' .. fnameescape(filename)
        endif
        created = win_getid()
        cursor(min([max([1, hint]), line('$')]), 1)
    catch
        var failure = v:exception
        if created == 0 && index(windows, win_getid()) < 0
            && (bufnr() == target || (filename != '' && resolve(bufname()) == resolve(filename)))
            created = win_getid()
        endif
        if created != 0 && !empty(getwininfo(created))
            var abandoned = winbufnr(created)
            var hidden = getbufvar(abandoned, '&bufhidden')
            setbufvar(abandoned, '&bufhidden', 'hide')
            try
                win_execute(created, 'noautocmd hide close')
            finally
                if bufexists(abandoned)
                    setbufvar(abandoned, '&bufhidden', hidden)
                endif
            endtry
        endif
        for info in getbufinfo()
            # Native first-load unwind can leave a record; never wipe a live real buffer.
            if index(buffers, info.bufnr) < 0 && !info.changed && !info.loaded && info.name == filename
                execute 'noautocmd bwipeout ' .. info.bufnr
            endif
        endfor
        win_gotoid(caller)
        Error(failure)
    endtry
enddef

def Arguments(args: list<string>, allowBase = false): dict<any>
    var separator = index(args, '--')
    var revisions = separator < 0 ? copy(args) : separator == 0 ? [] : args[0 : separator - 1]
    var base = allowBase && !empty(revisions) && revisions[0] == '--merge-base'
    if base
        remove(revisions, 0)
    endif
    if index(revisions, '--merge-base') >= 0
        throw '[diffview] --merge-base must occur once before the endpoints.'
    endif
    return {revisions: revisions, mergeBase: base,
        paths: separator < 0 ? [] : git.Prefixes(args[separator + 1 :])}
enddef

export def OpenRequest(args: list<string>)
    try
        var request = Arguments(args, true)
        if request.mergeBase
            if len(request.revisions) != 2
                throw '[diffview] Usage: DiffviewOpen --merge-base A B [-- paths...]'
            endif
            var root = git.Root()
            var left = git.Resolve(root, request.revisions[0], 'commit')
            var right = git.Resolve(root, request.revisions[1], 'commit')
            OpenBase(root, left, right, request.revisions[0], request.revisions[1], request.paths)
        else
            Open(request.revisions, false, '', request.paths)
        endif
    catch
        Error(v:exception)
    endtry
enddef

export def Open(args: list<string>, commit = false, root = '', paths: list<string> = [], labels: dict<string> = {}, selectedPath = '', historyPaths: list<string> = [])
    var creating = false
    var previous: dict<any> = {}
    var previousFocus = 0
    try
        if commit && len(args) > 1
            throw '[diffview] Usage: DiffviewCommit [revision]'
        elseif !commit && len(args) != 0 && len(args) != 2
            throw '[diffview] Usage: DiffviewOpen [left right]'
        endif
        tree.Check()
        var model = git.Comparison(root == '' ? git.Root() : root, args, commit)
        if !empty(labels)
            model.branchLabels = copy(labels)
            model.leftSource = labels.left
            model.rightSource = labels.right
        endif
        if !empty(historyPaths)
            model = git.HistoryScope(model, historyPaths)
        endif
        model = git.Project(model, paths)
        var initial = 0
        if selectedPath != ''
            initial = index(mapnew(model.entries, (_, entry) => entry.path), selectedPath)
            if initial < 0
                throw '[diffview] Historical file has no matching first-parent change.'
            endif
        endif
        var candidate = tree.Build(model)
        var content = empty(model.entries) ? {} : git.Read(model, model.entries[initial])
        var origin = empty(view) ? win_getid() : view.origin
        previous = view
        previousFocus = win_getid()
        creating = true
        serial += 1
        view = {token: serial, origin: origin, model: model, buffers: [], windows: [],
            selected: -1, tree: candidate, timer: -1}
        tabnew
        add(view.windows, win_getid())
        Buffer('panel')
        nnoremap <silent> <buffer> <CR> <ScriptCmd>Select()<CR>
        nnoremap <silent> <buffer> o <ScriptCmd>Select()<CR>
        nnoremap <silent> <buffer> p <ScriptCmd>Navigate('p')<CR>
        nnoremap <silent> <buffer> x <ScriptCmd>Navigate('x')<CR>
        nnoremap <silent> <buffer> O <ScriptCmd>Navigate('O')<CR>
        nnoremap <silent> <buffer> X <ScriptCmd>Navigate('X')<CR>
        rightbelow vnew
        add(view.windows, win_getid())
        Buffer('left')
        rightbelow vnew
        add(view.windows, win_getid())
        Buffer('right')
        win_execute(view.windows[0], 'vertical resize 36')
        win_execute(view.windows[0], 'setlocal winfixwidth')
        tree.Install(view.windows[0], candidate)
        if !empty(model.entries)
            Show(initial, content)
        else
            EmptyView()
        endif
        var created = view
        view = previous
        Close()
        view = created
        Events()
        win_gotoid(view.windows[0])
        g:diffview_enabled = true
    catch
        Error(v:exception)
        if creating
            Close()
            view = previous
            if !empty(view)
                Events()
            endif
            g:diffview_enabled = !empty(view)
            win_gotoid(previousFocus)
        endif
    endtry
enddef

def OpenBranch(snapshot: dict<any>, target: dict<any>, paths: list<string>)
    if get(snapshot, 'mergeBase', false)
        OpenBase(snapshot.root, target.oid, snapshot.head, target.label, snapshot.label, paths)
    else
        Open([target.oid, snapshot.head], false, snapshot.root, paths,
            {left: target.label .. ' ' .. target.oid[0 : 6], right: snapshot.label .. ' ' .. snapshot.head[0 : 6]})
    endif
enddef

def OpenBase(root: string, left: string, right: string, leftLabel: string, rightLabel: string, paths: list<string>)
    var base = git.MergeBase(root, left, right)
    Open([base, right], false, root, paths, {left: 'merge-base(' .. leftLabel .. ', ' .. rightLabel .. ') ' .. base[0 : 6],
        right: rightLabel .. ' ' .. right[0 : 6], base: base})
enddef

def Selected(root: string, source: list<string>, origin: dict<any>, paths: list<string>, lines: any, snapshot: dict<any>)
    if get(origin, 'directoryScope', 0) == 2
        var pushed = getwinvar(origin.window, 'fzf_pushd', {})
        if get(pushed, 'origin', '') == origin.directory
            # Core treats tab-local cwd as window-local when preparing its sink.
            pushed.command = 'tcd'
        endif
    endif
    if get(origin, 'failed', false)
        return
    endif
    var kind = get(snapshot, 'kind', empty(snapshot) ? 'commit' : 'branch')
    if type(lines) != v:t_list
        Error('Invalid fzf ' .. kind .. ' selection.')
        return
    elseif empty(lines)
        return
    endif
    if len(lines) != 1 || type(lines[0]) != v:t_string || index(source, lines[0]) < 0
        Error('Invalid fzf ' .. kind .. ' selection.')
        return
    endif
    var oid = empty(snapshot) ? matchstr(lines[0], '^\x\+\ze\t') : ''
    if empty(snapshot) && index([40, 64], strlen(oid)) < 0
        Error('Invalid fzf commit object ID.')
        return
    endif
    var cwd = getcwd(-1)
    if empty(snapshot)
        Open([oid], true, root, paths)
    elseif has_key(snapshot, 'kind')
        var target = snapshot.targets[index(source, lines[0])]
        Open([target.oid], true, root, [], {}, target.path, [target.oldpath, target.path])
    else
        OpenBranch(snapshot, snapshot.targets[index(source, lines[0])], paths)
    endif
    if getcwd(-1) != cwd
        # Closing a prior tab can restore the global cwd left by an in-place picker.
        var local = haslocaldir()
        var directory = getcwd()
        execute 'noautocmd cd ' .. fnameescape(cwd)
        if local != 0
            execute (local == 1 ? 'noautocmd lcd ' : 'noautocmd tcd ') .. fnameescape(directory)
        endif
    endif
enddef

def PickerExit(origin: dict<any>, code: number)
    preview.Cleanup(get(origin, 'preview', ''))
    var location = win_id2tabwin(origin.window)
    if location[0] != 0
        origin.directory = getcwd(location[1], location[0])
        origin.directoryScope = haslocaldir(location[1], location[0])
    endif
    if index([0, 1, 130], code) < 0
        Error('fzf failed (exit ' .. code .. '). Check :messages and your fzf installation.')
    endif
enddef

def RollbackPicker(origin: dict<any>)
    var window = win_getid()
    var buffer = bufnr()
    var temporary = index(origin.buffers, buffer) < 0
        && (&filetype == 'fzf' || (bufname() == '' && !&modified && getline(1, '$') == ['']))
    if temporary && &buftype == 'terminal'
        # Detach the owned terminal before restoring a caller over bufhidden=wipe.
        setbufvar(buffer, '&bufhidden', 'hide')
        var job = term_getjob(buffer)
        job_stop(job, 'term')
        var started = reltime()
        while job_status(job) == 'run' && reltimefloat(reltime(started)) < 2
            sleep 1m
        endwhile
        if job_status(job) == 'run'
            job_stop(job, 'kill')
        endif
    endif
    if temporary && index(popup_list(), window) >= 0
        popup_close(window)
    elseif temporary && !empty(getwininfo(window)) && winbufnr(window) == buffer
        && index(origin.windows, window) < 0 && win_gotoid(window)
        if winnr('$') == 1 && tabpagenr('$') > 1
            noautocmd tabclose
        else
            noautocmd close
        endif
    endif
    if bufexists(origin.buffer) && win_gotoid(origin.window)
        execute 'noautocmd keepalt keepjumps hide buffer ' .. origin.buffer
        for [name, value] in items(origin.options)
            setwinvar(origin.window, '&' .. name, value)
        endfor
        execute 'noautocmd ' .. origin.layout
        winrestview(origin.position)
    endif
    if temporary && bufexists(buffer)
        execute 'silent! noautocmd bwipeout! ' .. buffer
    endif
enddef

def Pick(commit: bool, paths: list<string>, mergeBase = false, historyContext: dict<any> = {})
    var prepared: dict<string> = {}
    try
        tree.Check()
        if !exists('*fzf#run') || !exists('*fzf#wrap') || !exists('*fzf#exec') || !executable('fzf')
            throw '[diffview] Install junegunn/fzf and put fzf on PATH, or use '
                .. (commit ? 'DiffviewCommit HEAD.' : 'DiffviewBranch {branch}.')
        endif
        # Do not let the dependency offer to download an incompatible binary.
        fzf#exec('0.0.0', 1)
        var root = empty(historyContext) ? git.Root() : historyContext.root
        var snapshot = !empty(historyContext) ? historyContext : commit ? {} : git.Branches(root)
        if !commit && empty(historyContext)
            snapshot.mergeBase = mergeBase
        endif
        var source: list<string> = commit && empty(historyContext) ? git.Commits(root)
            : mapnew(snapshot.targets, (_, target) => target.row)
        if empty(source)
            throw '[diffview] No ' .. (commit ? 'commits' : 'branches') .. ' to select.'
        endif
        var hidden = &hidden
        var autowrite = &autowrite
        var autowriteall = &autowriteall
        var caller = bufnr()
        var bufferHidden = &l:bufhidden
        var directory = getcwd()
        var directoryScope = haslocaldir()
        var origin = {window: win_getid(), buffer: caller, position: winsaveview(),
            layout: winrestcmd(), buffers: getbufinfo()->mapnew((_, b) => b.bufnr),
            windows: getwininfo()->mapnew((_, w) => w.winid), options: {}}
        for name in ['winfixwidth', 'winfixheight', 'number', 'spell', 'diff', 'scrollbind',
            'cursorbind', 'foldmethod', 'foldcolumn', 'wrap']
            origin.options[name] = getwinvar(origin.window, '&' .. name)
        endfor
        var options = ['--no-multi', '--no-print-query', '--no-expect', '--no-print0', '--no-read0',
            '--accept-nth=..', '--delimiter=\t', '--with-nth=2..', '--nth=..',
            '--prompt=' .. (!empty(historyContext) ? historyContext.kind .. '> ' : commit ? 'Commit> ' : 'Branch> ')]
        if !empty(historyContext)
            add(options, '--header=' .. git.Display(historyContext.kind .. ': first-parent, follows renames | '
                .. historyContext.start .. ' | ' .. historyContext.path
                .. (empty(historyContext.range) ? '' : ' | lines ' .. join(historyContext.range, ','))))
        endif
        if commit
            var members: list<dict<any>> = empty(historyContext)
                ? mapnew(source, (_, row) => ({oid: matchstr(row, '^\x\+\ze\t'), paths: copy(paths)}))
                : mapnew(snapshot.targets, (_, target) => ({oid: target.oid, paths: [target.path], follow: true}))
            prepared = preview.Prepare(root, members)
            origin.preview = prepared.context
            add(options, '--preview=' .. prepared.command)
            add(options, '--preview-window=right,50%,wrap')
            add(options, '--bind=ctrl-/:toggle-preview')
        endif
        var picker = fzf#wrap({source: source,
            sinklist: (lines) => Selected(root, source, origin, paths, lines, snapshot),
            exit: (code) => PickerExit(origin, code),
            options: options})
        try
            # An in-place fzf layout must retain the caller without saving it.
            set hidden noautowrite noautowriteall
            setbufvar(caller, '&bufhidden', 'hide')
            fzf#run(picker)
        catch
            var failure = v:exception
            origin.failed = true
            RollbackPicker(origin)
            throw '[diffview] Cannot open fzf: ' .. failure
        finally
            var location = win_id2tabwin(origin.window)
            if directoryScope == 2 && location[0] != 0
                && getcwd(location[1], location[0]) == directory
                && getcwd(-1, location[0]) == directory
                # Core's synchronous creation also mistakes an initial tcd for lcd.
                if haslocaldir(location[1], location[0]) == 1
                    win_execute(origin.window, 'noautocmd tcd ' .. fnameescape(directory))
                endif
                var pushed = getwinvar(origin.window, 'fzf_pushd', {})
                if get(pushed, 'origin', '') == directory && get(pushed, 'dir', '') == directory
                    win_execute(origin.window, 'unlet! w:fzf_pushd')
                endif
            endif
            &hidden = hidden
            &autowrite = autowrite
            &autowriteall = autowriteall
            if bufexists(caller)
                setbufvar(caller, '&bufhidden', bufferHidden)
            endif
        endtry
    catch
        preview.Cleanup(get(prepared, 'context', ''))
        Error(v:exception)
    endtry
enddef

export def Commit(args: list<string>)
    try
        var request = Arguments(args)
        if !empty(request.revisions)
            Open(request.revisions, true, '', request.paths)
        else
            Pick(true, request.paths)
        endif
    catch
        Error(v:exception)
    endtry
enddef

export def Branch(args: list<string>)
    try
        var request = Arguments(args, true)
        if len(request.revisions) > 1
            throw '[diffview] Usage: DiffviewBranch [branch] [-- paths...]'
        endif
        if empty(request.revisions)
            Pick(false, request.paths, request.mergeBase)
            return
        endif
        tree.Check()
        var name = request.revisions[0]
        if name == '' || name[0] == '-'
            throw '[diffview] Invalid branch name: ' .. git.Display(name)
        endif
        var snapshot = git.Branches(git.Root())
        snapshot.mergeBase = request.mergeBase
        var refs = stridx(name, 'refs/') == 0 ? [name] : ['refs/heads/' .. name, 'refs/remotes/' .. name]
        for ref in refs
            for target in snapshot.targets
                if target.ref == ref
                    OpenBranch(snapshot, target, request.paths)
                    return
                endif
            endfor
        endfor
        throw '[diffview] Branch not found: ' .. git.Display(name)
    catch
        Error(v:exception)
    endtry
enddef

def HistoryContext(revision: string, explicitPath: string, lineMode: bool): dict<any>
    var root = ''
    var path = explicitPath
    var start = ''
    if explicitPath != ''
        root = git.Root()
    elseif !empty(view) && index(view.windows, win_getid()) >= 0 && Usable()
        var selected = view.selected
        var side = win_getid() == view.windows[1] ? 'left' : 'right'
        if win_getid() == view.windows[0]
            if lineMode
                throw '[diffview] Line history requires a content pane or ordinary file.'
            endif
            var node = g:NERDTreeFileNode.GetSelected()
            if empty(node) || !has_key(node, 'diffview_entry')
                throw '[diffview] Select a file node for file history.'
            endif
            selected = node.diffview_index
        endif
        if selected < 0 || type(view.model[side .. 'Prefix']) != v:t_string
            throw '[diffview] No proven committed history context.'
        endif
        var entry = view.model.entries[selected]
        if (side == 'left' ? entry.oldmode : entry.newmode) == '000000'
            throw '[diffview] EMPTY has no history start.'
        endif
        path = side == 'left' ? entry.oldpath : entry.path
        var prefix = view.model[side .. 'Prefix']
        path = (prefix == '' ? '' : prefix .. '/') .. path
        root = view.model.root
        start = view.model[side .. 'Commit']
        if start == ''
            throw '[diffview] No proven committed history start.'
        endif
    else
        if &buftype != '' || bufname() == ''
            throw '[diffview] History requires an ordinary file or an explicit file path.'
        endif
        var filename = expand('%:p')
        root = git.Root(fnamemodify(filename, ':h'))
        if stridx(filename, root .. '/') != 0
            throw '[diffview] File is outside its repository root.'
        endif
        path = strpart(filename, strlen(root) + 1)
    endif
    start = git.Resolve(root, revision != '' ? revision : start != '' ? start : 'HEAD', 'commit')
    if explicitPath == ''
        history.File(root, start, path, true)
    endif
    return {root: root, start: start, path: path}
enddef

export def FileHistory(args: list<string>)
    try
        var separator = index(args, '--')
        var revisions = separator < 0 ? copy(args) : separator == 0 ? [] : args[0 : separator - 1]
        var paths = separator < 0 ? [] : args[separator + 1 :]
        if len(revisions) > 1 || (separator >= 0 && (len(paths) != 1 || paths[0] == ''))
            throw '[diffview] Usage: DiffviewFileHistory [revision] [-- one-file]'
        endif
        var context = HistoryContext(get(revisions, 0, ''), get(paths, 0, ''), false)
        context.kind = 'file history'
        context.range = []
        context.targets = history.Entries(context.root, context.start, context.path)
        Pick(true, [], false, context)
    catch
        Error(v:exception)
    endtry
enddef

export def LineHistory(args: list<string>, first: number, last: number)
    try
        if len(args) > 1 || index(args, '--') >= 0
            throw '[diffview] Usage: [range]DiffviewLineHistory [revision]'
        endif
        var context = HistoryContext(get(args, 0, ''), '', true)
        context.kind = 'line history'
        context.range = [first, last]
        history.Match(context.root, context.start, context.path, getline(1, '$'), &endofline, context.range)
        context.targets = history.Entries(context.root, context.start, context.path, context.range)
        Pick(true, [], false, context)
    catch
        Error(v:exception)
    endtry
enddef

export def Toggle()
    if empty(view)
        Open([])
    else
        Close()
    endif
enddef
