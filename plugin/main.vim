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
#    Modified 2026-10-22: native read-only diff browser.

if get(g:, 'loaded_diffview', false)
    finish
endif
if v:version < 901 || !has('diff') || !has('windows') || !has('job') || !has('timers')
    echoerr '[diffview] Requires Vim 9.1 with +diff, +windows, +job and +timers.'
    finish
endif
g:loaded_diffview = true

import autoload 'diffview/current.vim' as current

def g:ToggleDiffView()
    current.Toggle()
enddef

def g:DiffBranch(branch0: string)
    current.Open([branch0, 'HEAD'])
enddef

command! -nargs=* DiffviewOpen call current.OpenRequest([<f-args>])
command! -nargs=* DiffviewCommit call current.Commit([<f-args>])
command! -nargs=0 DiffviewRefresh call current.Refresh()
command! -nargs=0 DiffviewClose call current.Close()
command! -nargs=* DiffviewFilter call current.Filter([<f-args>])
command! -nargs=0 DiffviewGotoFile call current.GotoFile()
command! -nargs=1 DiffBranch call g:DiffBranch(<f-args>)
