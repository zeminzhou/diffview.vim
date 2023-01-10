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
    echom 'diffvew init'
    augroup diffview
        autocmd!
        autocmd BufEnter * diffview.CloseIf()
    augroup END
    diffview.Initialize()
enddef

export def Deinitialize()
    echom 'diffvew close'
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

    var size = len(files)
    append(0, bufname .. '(' .. size .. ')')
    append(1, '--------------------')

    for i in range(0, size - 1)
        append(i + 2, files[i])
    endfor

    execute("normal! gg")
    setlocal nomodifiable
enddef

var tmp = ''

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
    var branch = trim(system('git rev-parse --abbrev-ref HEAD'))
    tmp = tempname()
    system('git show ' .. branch .. ':' .. filename .. ' > ' .. tmp)

    execute("normal! \<c-w>l")
    execute("edit " .. filename)
    execute("vertical diffsplit " .. tmp)
    execute("file " .. branch .. '://' .. filename)
enddef

def ClearPreTmp()
    if tmp == ''
        return
    endif

    var n = bufnr(tmp)
    if n == -1
        return
    endif

    execute('bdelete ' .. n)
    delete(tmp)
    tmp = ''
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
        execute('nnoremap <buffer> o :call DiffCurrentFile()<cr>')
    enddef

    def UpdateModifiedFile()
        if !this.initialized
            return
        endif

        const cmd = [
            'git',
            'diff',
            '--name-only',
        ]
        job_start(cmd, {
            "out_cb": (channel, message) => DisplayFiles(message, "modified"),
            "mode": "raw"
        })
    enddef

    def UpdateStagedFile()
        if !this.initialized
            return
        endif

        const cmd = [
            'git',
            'diff',
            '--cached',
            '--name-only',
        ]
        job_start(cmd, {
            "out_cb": (channel, message) => DisplayFiles(message, "staged"),
            "mode": "raw"
        })
    enddef

    def Initialize()
        if this.initialized
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
