vim9script

# Copyright (C) 2022 zeminzhou <zeminzhou_@outlook.com>
# Modified 2026-10-22. Licensed under AGPL-3.0-or-later; see LICENSE.

import autoload 'diffview/git.vim' as git
import autoload 'diffview/tree.vim' as tree

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
enddef

def Buffer(role: string): number
    var buf = bufnr()
    add(view.buffers, buf)
    execute 'silent file diffview://' .. view.token .. '/' .. role
    setlocal buftype=nofile bufhidden=hide noswapfile nobuflisted
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
    endfor
    view.selected = index
    if content.diff
        win_execute(view.windows[1], 'diffupdate')
    endif
enddef

def EmptyView()
    for side in [1, 2]
        Put(view.buffers[side], ['No changes'], true)
        win_execute(view.windows[side], 'diffoff')
        var location = win_id2tabwin(view.windows[side])
        settabwinvar(location[0], location[1], '&statusline', '[diffview] No changes')
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

export def Refresh()
    if !Usable()
        return
    endif
    try
        var model = git.Comparison(view.model.root, view.model.args, view.model.mode == 'commit')
        var selected = empty(model.entries) ? -1 : 0
        if view.selected >= 0
            var old = view.model.entries[view.selected]
            for i in range(len(model.entries))
                if model.entries[i].section == old.section && model.entries[i].path == old.path
                    selected = i
                    break
                endif
            endfor
        endif
        var content = selected < 0 ? {} : git.Read(model, model.entries[selected])
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
        else
            Show(selected, content, false)
        endif
    catch
        Error(v:exception)
    endtry
enddef

export def Open(args: list<string>, commit = false, root = '')
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
        var candidate = tree.Build(model)
        var content = empty(model.entries) ? {} : git.Read(model, model.entries[0])
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
            Show(0, content)
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

def SelectedCommit(root: string, source: list<string>, origin: dict<any>, lines: any)
    if get(origin, 'directoryScope', 0) == 2
        var pushed = getwinvar(origin.window, 'fzf_pushd', {})
        if get(pushed, 'origin', '') == origin.directory
            # Core treats tab-local cwd as window-local when preparing its sink.
            pushed.command = 'tcd'
        endif
    endif
    if type(lines) != v:t_list
        Error('Invalid fzf commit selection.')
        return
    elseif empty(lines)
        return
    endif
    if len(lines) != 1 || type(lines[0]) != v:t_string || index(source, lines[0]) < 0
        Error('Invalid fzf commit selection.')
        return
    endif
    var oid = matchstr(lines[0], '^\x\+\ze\t')
    if index([40, 64], strlen(oid)) < 0
        Error('Invalid fzf commit object ID.')
        return
    endif
    var cwd = getcwd(-1)
    Open([oid], true, root)
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
        job_stop(term_getjob(buffer), 'kill')
    endif
    if temporary && index(origin.windows, window) < 0
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

export def Commit(args: list<string>)
    if !empty(args)
        Open(args, true)
        return
    endif
    try
        tree.Check()
        if !exists('*fzf#run') || !exists('*fzf#wrap') || !exists('*fzf#exec') || !executable('fzf')
            throw '[diffview] Install junegunn/fzf and put fzf on PATH, or use DiffviewCommit HEAD.'
        endif
        # Do not let the dependency offer to download an incompatible binary.
        fzf#exec('0.0.0', 1)
        var root = git.Root()
        var source = git.Commits(root)
        if empty(source)
            throw '[diffview] No commits to select.'
        endif
        var hidden = &hidden
        var autowrite = &autowrite
        var autowriteall = &autowriteall
        var caller = bufnr()
        var bufferHidden = &l:bufhidden
        var origin = {window: win_getid(), buffer: caller, position: winsaveview(),
            layout: winrestcmd(), buffers: getbufinfo()->mapnew((_, b) => b.bufnr),
            windows: getwininfo()->mapnew((_, w) => w.winid), options: {}}
        for name in ['winfixwidth', 'winfixheight', 'number', 'spell', 'diff', 'scrollbind',
            'cursorbind', 'foldmethod', 'foldcolumn', 'wrap']
            origin.options[name] = getwinvar(origin.window, '&' .. name)
        endfor
        var picker = fzf#wrap({source: source,
            sinklist: (lines) => SelectedCommit(root, source, origin, lines),
            exit: (code) => PickerExit(origin, code),
            options: ['--no-multi', '--no-print-query', '--no-expect', '--no-print0', '--no-read0',
                '--accept-nth=..', '--delimiter=\t', '--with-nth=2..', '--nth=..', '--prompt=Commit> ']})
        try
            # An in-place fzf layout must retain the caller without saving it.
            set hidden noautowrite noautowriteall
            setbufvar(caller, '&bufhidden', 'hide')
            fzf#run(picker)
        catch
            var failure = v:exception
            RollbackPicker(origin)
            throw '[diffview] Cannot open fzf: ' .. failure
        finally
            &hidden = hidden
            &autowrite = autowrite
            &autowriteall = autowriteall
            if bufexists(caller)
                setbufvar(caller, '&bufhidden', bufferHidden)
            endif
        endtry
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
