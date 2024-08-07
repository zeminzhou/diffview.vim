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

import autoload 'diffview/current.vim' as current

def g:ToggleDiffView()
    if v:version < 901
        echoerr '[diffview] requires a higher vim version'
        return
    endif
    if !get(g:, 'diffview_enabled', false)
        g:diffview_enabled = true
        current.Initialize()
    else
        g:diffview_enabled = false
        current.Deinitialize()
    endif
enddef

def g:DiffBranch(branch0: string)
    current.DiffBranch(branch0)
enddef

command! -nargs=1 DiffBranch :call g:DiffBranch('<args>')
