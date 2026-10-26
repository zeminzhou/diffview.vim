vim9script

# Licensed under AGPL-3.0-or-later; see LICENSE.

def Language(path: string, lines: list<string>): string
    var directory = tempname()
    var process: job
    try
        mkdir(directory, '', 0o700)
        writefile([json_encode({path: path, lines: lines})], directory .. '/input')
        writefile([
            'set nocompatible nomore noexrc nomodeline',
            'set runtimepath=$VIMRUNTIME packpath=',
            'filetype on',
            "let snapshot = json_decode(join(readfile('input'), '\\n'))",
            'noautocmd enew',
            'setlocal buftype=nofile noswapfile nomodeline',
            "execute 'noautocmd file diffview-detect://context/' . fnameescape(snapshot.path)",
            'call setline(1, snapshot.lines)',
            "execute 'doautocmd <nomodeline> filetypedetect BufRead ' . fnameescape(snapshot.path)",
            "call writefile([&filetype], 'result')",
            'qa!'], directory .. '/detect.vim')
        # Native detection runs alone: no user hooks or similarly named disk files.
        process = job_start([v:progpath, '-Nu', 'NONE', '-U', 'NONE', '-i', 'NONE', '--noplugin',
            '-n', '-es', '-S', directory .. '/detect.vim'], {cwd: directory,
            in_io: 'null', out_io: 'null', err_io: 'null'})
        var started = reltime()
        while job_status(process) == 'run' && reltimefloat(reltime(started)) < 5
            sleep 1m
        endwhile
        if job_status(process) != 'dead' || job_info(process).exitval != 0
            || !filereadable(directory .. '/result')
            throw '[diffview] Native syntax detection failed.'
        endif
        return get(readfile(directory .. '/result'), 0, '')
    finally
        if process != null_job && job_status(process) == 'run'
            job_stop(process, 'kill')
        endif
        delete(directory, 'rf')
    endtry
    return ''
enddef

export def Apply(window: number, path: string, text: bool)
    var buffer = winbufnr(window)
    var lines = getbufline(buffer, 1, '$')
    var eol = getbufvar(buffer, '&endofline')
    try
        win_execute(window, 'syntax clear | unlet! b:current_syntax | noautocmd setlocal syntax=')
        if !text || !has('syntax') || !exists('g:syntax_on') || lines == ['']
            return
        endif
        var language = Language(path, lines)
        if language =~ '^\w\+\%(\.\w\+\)*$'
            win_execute(window, 'setlocal syntax=' .. language)
        endif
    catch
        win_execute(window, 'syntax clear | unlet! b:current_syntax | noautocmd setlocal syntax=')
        echohl WarningMsg
        echomsg '[diffview] Syntax unavailable: ' .. v:exception
        echohl None
    finally
        if bufexists(buffer)
            if getbufline(buffer, 1, '$') != lines
                setbufvar(buffer, '&readonly', false)
                setbufvar(buffer, '&modifiable', true)
                setbufline(buffer, 1, lines)
                if len(getbufline(buffer, 1, '$')) > len(lines)
                    deletebufline(buffer, len(lines) + 1, '$')
                endif
            endif
            setbufvar(buffer, '&endofline', eol)
            setbufvar(buffer, '&modified', false)
            setbufvar(buffer, '&readonly', true)
            setbufvar(buffer, '&modifiable', false)
        endif
    endtry
enddef
