vim9script

#    Copyright (C) 2022  zeminzhou<zeminzhou_@outlook.com>
#
#    This program is free software: you can redistribute it and/or modify
#    it under the terms of the GNU Affero General Public License as published
#    by the Free Software Foundation, either version 3 of the License, or
#    (at your option) any later version.
#
#    This program is distributed in the hope that it will be useful,
#    but WITHOUT ANY WARRANTY; without even the implied warranty of
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#    GNU Affero General Public License for more details.
#
#    You should have received a copy of the GNU Affero General Public License
#    along with this program.  If not, see <https://www.gnu.org/licenses/>.

export def Initialize()
    echom '[diffview] init'
    augroup diffview
        autocmd!
        autocmd BufEnter * diffview.CloseIf()
        autocmd BufWritePost * diffview.UpdateModifiedFile()
    augroup END
    diffview.Initialize()
enddef

export def Deinitialize()
    echom '[diffview] close'
    augroup diffview
        autocmd!
    augroup END
    diffview.Close()
enddef

def FocusOn(bufname: string): number
    var winnr = bufwinnr(bufname)
    if winnr == winnr() || winnr == -1
        return winnr
    endif

    execute("normal! " .. winnr .. "\<c-w>\<c-w>")
    return winnr
enddef

def DisplayFiles(message: string, bufname: string)
    var winnr = FocusOn(bufname)
    if winnr == -1
        return
    endif

    var files = split(message)
    setlocal modifiable
    execute("normal! gg")
    execute("normal! dG")

    var size = len(files)
    append(0, bufname .. '(' .. size .. ')')
    append(1, '--------------------')

    for i in range(0, size - 1)
        append(i + 2, files[i])
    endfor

    execute("normal! gg")
    setlocal nomodifiable
enddef

var tmp_buf = ''

def g:DiffCurrentFile()
    ClearPreTmp()

    if line('.') == 0 || line('.') == 1
        return
    endif
    var filename = getline('.')
    var cmd = [
        'git',
        'rev-parse',
        '--abbrev-ref',
        'HEAD',
    ]
    var branch = ''
    if bufwinnr('modified') == winnr('#')
        branch = trim(system('git rev-parse --abbrev-ref HEAD'))
        if v:shell_error != 0
            return
        endif
    endif

    var tmp = tempname()
    system('git show ' .. branch .. ':' .. filename .. ' > ' .. tmp)
    if v:shell_error != 0
        return
    endif

    execute("normal! \<c-w>l")
    execute("edit " .. filename)
    execute("vertical diffsplit " .. tmp)
    tmp_buf = branch .. '://' .. filename
    execute("file " .. tmp_buf)
enddef

def ClearPreTmp()
    if tmp_buf == ''
        return
    endif

    if !buflisted(tmp_buf)
        tmp_buf = ''
        return
    endif

    var n = bufnr(tmp_buf)
    if n == -1
        tmp_buf = ''
        return
    endif

    execute('bdelete ' .. n)
    tmp_buf = ''
enddef

class DiffView
    this.initialized: bool
    this.tmp: string
    this.modifid_bufname: string
    this.staged_bufname: string

    def new()
        this.initialized = false
        this.modifid_bufname = 'modified'
        this.staged_bufname = 'staged'
    enddef

    def Layout(layout_cmd: string)
        execute('silent keepalt ' .. layout_cmd)
        setlocal winfixwidth
        setlocal winfixheight
        setlocal noswapfile
        setlocal buftype=nowrite
        setlocal bufhidden=delete
        setlocal nowrap
        setlocal foldcolumn=0
        setlocal nobuflisted
        setlocal nospell
        setlocal nonumber
        setlocal norelativenumber
        setlocal nomodifiable
        setfiletype diffview
        execute('nnoremap <silent> <buffer> o :call DiffCurrentFile()<cr>')
    enddef

    def UpdateModifiedFile()
        if !this.initialized
            return
        endif

        var output = trim(system('git diff --name-only'))
        if v:shell_error != 0
            return
        endif
        DisplayFiles(output, "modified")
    enddef

    def UpdateStagedFile()
        if !this.initialized
            return
        endif

        var output = trim(system('git diff --cached --name-only'))
        if v:shell_error != 0
            return
        endif
        DisplayFiles(output, "staged")
    enddef

    def Initialize()
        if this.initialized
            return
        endif
        system('git rev-parse --is-inside-work-tree')
        if v:shell_error != 0
            echoerr '[diffview] not a git repository'
            return
        endif
        this.Layouts()
        this.initialized = true

        this.UpdateModifiedFile()
        this.UpdateStagedFile()
    enddef

    def Layouts()
        const modified_layout = 'vertical topleft:30 split ' .. this.modifid_bufname
        const staged_layout = 'horizontal rightbelow split ' .. this.staged_bufname

        this.Layout(modified_layout)
        this.Layout(staged_layout)
    enddef

    def Close()
        if !this.initialized
            return
        endif
        var winnr = FocusOn(this.modifid_bufname)
        if winnr != -1
            execute("quit")
        endif
        winnr = FocusOn(this.staged_bufname)
        if winnr != -1
            execute("quit")
        endif
        this.initialized = false
    enddef

    def CloseIf()
        if bufwinnr(this.modifid_bufname) == -1 || 
                bufwinnr(this.staged_bufname) == -1
            this.Close()
        endif
    enddef
endclass

var diffview = DiffView.new()
