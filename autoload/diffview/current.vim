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
        autocmd WinClosed * diffview.OnWinClosed()
        autocmd BufWinEnter * diffview.OnBufWinEnter()
        autocmd BufWritePost * diffview.UpdateModifiedFile()
    augroup END
    diffview.Initialize("current")
enddef

export def DiffBranch(branch0: string)
    echom '[diffview] diffbranch init'
    augroup diffbranch
        autocmd!
        autocmd BufEnter * diffview.CloseIf()
        autocmd WinClosed * diffview.OnWinClosed()
        autocmd BufWinEnter * diffview.OnBufWinEnter()
        autocmd BufWritePost * diffbranch.UpdateModifiedFile()
    augroup END
    diffbranch.Initialize(branch0)
enddef

def DiffBranchEnd()
    echom '[diffview] diffbranch close'
    augroup diffbranch
        autocmd!
    augroup END
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

def g:DiffCurrentFile(branch0: string)
    CleanUpPreTmp()

    if line('.') == 0 || line('.') == 1
        return
    endif
    var filename = getline('.')

    var tmp = tempname()
    system('git show ' .. branch0 .. ':' .. filename .. ' > ' .. tmp)
    if v:shell_error != 0
        return
    endif

    execute("normal! \<c-w>l")
    execute("edit " .. filename)
    execute("vertical diffsplit " .. tmp)
    tmp_buf = branch0 .. '://' .. filename
    execute("file " .. tmp_buf)
enddef

def CleanUpPreTmp()
    if tmp_buf == ''
        return
    endif

    if !bufexists(tmp_buf)
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
    var branch: string
    var initialized: bool
    var modifid_bufname: string
    var staged_bufname: string

    def new()
        this.initialized = false
        this.modifid_bufname = 'modified'
        this.staged_bufname = 'staged'
    enddef

    def Layout(layout_cmd: string, branch0: string)
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
        execute('nnoremap <silent> <buffer> o :call DiffCurrentFile("' .. branch0 .. '")<cr>')
    enddef

    def UpdateModifiedFile()
        if !this.initialized
            return
        endif

        var branch0 = this.branch
        if branch0 == "current"
            branch0 = ""
        endif
        var output = trim(system('git diff ' .. branch0 .. ' --name-only'))
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

    def Initialize(branch0: string)
        if this.initialized
            return
        endif
        var root = trim(system('git rev-parse --show-toplevel'))
        if v:shell_error != 0
            echoerr '[diffview] not a git repository'
            return
        endif
        var pwd = trim(system('pwd'))
        if root != pwd
            echoerr '[diffview] not in the root directory of git'
            return
        endif

        this.Layouts(branch0)
        this.initialized = true
        this.branch = branch0

        this.UpdateModifiedFile()
        if branch0 == "current"
            this.UpdateStagedFile()
            execute("normal! \<c-w>k")
        endif
    enddef

    def Layouts(branch0: string)
        const modified_layout = 'vertical topleft:30 split ' .. this.modifid_bufname
        const staged_layout = 'horizontal rightbelow split ' .. this.staged_bufname

        var branch1 = branch0
        if branch1 == "current"
            branch1 = trim(system('git rev-parse --abbrev-ref HEAD'))
            if v:shell_error != 0
                return
            endif
        endif

        this.Layout(modified_layout, branch1)
        if branch0 == "current"
            this.Layout(staged_layout, '')
        endif
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
        this.branch = ""
    enddef

    def CloseIf()
        if bufwinnr(this.modifid_bufname) == -1 || 
                bufwinnr(this.staged_bufname) == -1
            this.Close()
        endif
    enddef

    def OnWinClosed()
        if bufwinnr("%") == bufwinnr(this.modifid_bufname) 
            this.Close()
            DiffBranchEnd()
        endif
        if tmp_buf == ''
            return
        endif
        if bufwinnr(tmp_buf) == winnr()
            CleanUpPreTmp()
        endif
    enddef

    def OnBufWinEnter()
        if tmp_buf == ''
            return
        endif
        if bufwinnr(tmp_buf) == -1
            CleanUpPreTmp()
        endif
    enddef
endclass

var diffview = DiffView.new()
var diffbranch = DiffView.new()

