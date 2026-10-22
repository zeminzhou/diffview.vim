vim9script

# Copyright (C) 2022 zeminzhou <zeminzhou_@outlook.com>
# Modified 2026-10-22. Licensed under AGPL-3.0-or-later; see LICENSE.

import autoload 'diffview/git.vim' as git

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
    setlocal filetype=diffview
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

def Panel()
    var localMode = view.model.mode == 'local'
    var lines = ['[diffview] ' .. toupper(view.model.mode), git.Display(view.model.root),
        localMode ? 'Disk snapshots; unsaved edits excluded'
            : git.Display(view.model.leftSource .. ' -> ' .. view.model.rightSource), '']
    var rows: dict<number> = {}
    var sections = localMode ? ['Staged', 'Unstaged', 'Untracked']
        : [view.model.mode == 'commit' ? 'Commit' : 'Trees']
    for section in sections
        add(lines, section)
        for i in range(len(view.model.entries))
            var entry = view.model.entries[i]
            if entry.section != section
                continue
            endif
            var path = git.Display(entry.path)
            if entry.status == 'R' || entry.status == 'C'
                path = git.Display(entry.oldpath) .. ' -> ' .. path
            endif
            add(lines, '  ' .. entry.status .. ' ' .. path)
            rows[string(len(lines))] = i
        endfor
        add(lines, '')
    endfor
    if empty(view.model.entries)
        add(lines, 'No changes')
    endif
    view.rows = rows
    Put(view.buffers[0], lines, true)
enddef

def Show(index: number, content: dict<any>)
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
    for [row, item] in items(view.rows)
        if item == index
            win_execute(view.windows[0], 'call cursor(' .. row .. ', 1)')
            break
        endif
    endfor
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
    var row = string(line('.'))
    if !has_key(view.rows, row)
        return
    endif
    var index = view.rows[row]
    try
        var content = git.Read(view.model, view.model.entries[index])
        Show(index, content)
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
        view.model = model
        Panel()
        if selected < 0
            EmptyView()
        else
            Show(selected, content)
        endif
    catch
        Error(v:exception)
    endtry
enddef

export def Open(args: list<string>, commit = false)
    var creating = false
    var previous: dict<any> = {}
    var previousFocus = 0
    try
        if commit && len(args) > 1
            throw '[diffview] Usage: DiffviewCommit [revision]'
        elseif !commit && len(args) != 0 && len(args) != 2
            throw '[diffview] Usage: DiffviewOpen [left right]'
        endif
        var model = git.Comparison(git.Root(), args, commit)
        var content = empty(model.entries) ? {} : git.Read(model, model.entries[0])
        var origin = empty(view) ? win_getid() : view.origin
        previous = view
        previousFocus = win_getid()
        creating = true
        serial += 1
        view = {token: serial, origin: origin, model: model, buffers: [], windows: [],
            selected: -1, rows: {}, timer: -1}
        tabnew
        add(view.windows, win_getid())
        Buffer('panel')
        nnoremap <silent> <buffer> <CR> <ScriptCmd>Select()<CR>
        nnoremap <silent> <buffer> o <ScriptCmd>Select()<CR>
        rightbelow vnew
        add(view.windows, win_getid())
        Buffer('left')
        rightbelow vnew
        add(view.windows, win_getid())
        Buffer('right')
        win_execute(view.windows[0], 'vertical resize 36')
        win_execute(view.windows[0], 'setlocal winfixwidth')
        Panel()
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

export def Toggle()
    if empty(view)
        Open([])
    else
        Close()
    endif
enddef
