vim9script

# Licensed under AGPL-3.0-or-later; see LICENSE.
import autoload './git.vim' as git

var helper = expand('<sfile>:p')

def Native(mode: string, context: string): string
    var executable = exepath(v:progpath)
    return '/usr/bin/env ' .. shellescape('DIFFVIEW_PREVIEW_MODE=' .. mode) .. ' '
        .. shellescape('DIFFVIEW_PREVIEW_CONTEXT=' .. context) .. ' DIFFVIEW_PREVIEW_TOKEN={n} '
        .. join(mapnew([executable == '' ? v:progpath : executable, '-Nu', 'NONE', '-U', 'NONE', '-i', 'NONE', '--noplugin',
            '-n', '-es', '--cmd', 'let g:diffview_preview_worker=1', '-S', helper],
            (_, argument) => shellescape(argument)), ' ')
enddef

export def Prepare(root: string, members: list<dict<any>>): dict<string>
    var context = tempname()
    try
        if exepath(v:progpath) == '' || !executable('xargs')
            return {context: '', command: "printf '%s\\n' '[diffview] Preview unavailable: native Vim or xargs transport missing.'"}
        endif
        mkdir(context, '', 0o700)
        writefile([json_encode({root: root, members: members})], context .. '/source.json')
        setfperm(context .. '/source.json', 'rw-------')
        # Only fixed code crosses the shell; Git arguments arrive as NUL data.
        var command = '{ ' .. Native('args', context)
            .. ' | xargs -0 -s 65536 sh -c '
            .. shellescape('test "$#" -ge 2 && test "$1" = "$0" || exit 64; n="$2"; shift 2; '
                .. 'case "$n" in ""|*[!0-9]*) exit 64;; esac; test "$#" -eq "$n" || exit 64; GIT_SHALLOW_FILE=/dev/null exec git "$@"')
            .. ' ' .. shellescape(context) .. ' 2>&1; '
            .. 'printf ''\nDIFFVIEW_PREVIEW_STATUS:%s\n'' "$?"; } | ' .. Native('render', context)
        return {context: context, command: command}
    catch
        delete(context, 'rf')
        return {context: '', command: "printf '%s\\n' '[diffview] Preview unavailable: private context setup failed.'"}
    endtry
enddef

export def Cleanup(context: string)
    if context != ''
        delete(context, 'rf')
    endif
enddef

def Member(context: string, token: string): dict<any>
    if token !~ '^\d\+$' || getfperm(context) != 'rwx------'
        throw '[diffview] Invalid preview context or token.'
    endif
    var source = json_decode(join(readfile(context .. '/source.json'), "\n"))
    var index = str2nr(token)
    if type(source) != v:t_dict || type(get(source, 'root', 0)) != v:t_string
        || type(get(source, 'members', 0)) != v:t_list || index >= len(source.members)
        throw '[diffview] Unknown preview source member.'
    endif
    var member = source.members[index]
    if type(member) != v:t_dict || type(get(member, 'oid', 0)) != v:t_string
        || member.oid !~ '^\x\+$' || index([40, 64], strlen(member.oid)) < 0
        || type(get(member, 'paths', 0)) != v:t_list
        throw '[diffview] Invalid captured preview member.'
    endif
    for path in member.paths
        if type(path) != v:t_string
            throw '[diffview] Invalid captured preview path.'
        endif
    endfor
    if type(get(member, 'follow', false)) != v:t_bool || (get(member, 'follow', false) && len(member.paths) != 1)
        throw '[diffview] Historical preview requires one captured file.'
    endif
    return {root: source.root, member: member}
enddef

def Arguments(context: string, token: string)
    var request = Member(context, token)
    var member = request.member
    var format = '--format=commit %H%nAuthor: %an <%ae>%nDate: %aI%n%n%B%x00DIFFVIEW_HISTORY_PATCH:%H%x00'
    var args = git.Command(request.root, ['show', '--first-parent', '--diff-merges=first-parent', '--root', '--sparse', '-M',
        '--no-ext-diff', '--no-textconv', '--no-color', '--no-notes', '--no-show-signature',
        '--encoding=UTF-8', format, '--patch', '--raw', '--numstat', '--no-abbrev', '-z',
        '--ignore-submodules=none', member.oid, '--'])[1 :]
    var bytes = 0z
    for argument in [context, string(len(args))] + args
        for offset in range(strlen(argument))
            add(bytes, char2nr(strpart(argument, offset, 1)))
        endfor
        add(bytes, 0)
    endfor
    # Leave ample room under xargs' explicit size; never split one Git request.
    var size = len(bytes)
    for path in member.paths
        size += strlen(path) + 1
    endfor
    if len(args) + len(member.paths) > 256 || size > 8192
        throw '[diffview] Preview argument request exceeds the safe single-invocation limit.'
    endif
    writefile(bytes, '/dev/stdout')
enddef

def Field(bytes: blob, position: list<number>): string
    var start = position[0]
    while position[0] < len(bytes) && bytes[position[0]] != 0
        position[0] += 1
    endwhile
    if position[0] >= len(bytes)
        throw '[diffview] Incomplete historical preview field.'
    endif
    var value = position[0] == start ? '' : join(blob2str(bytes[start : position[0] - 1]), "\n")
    position[0] += 1
    return value
enddef

def Focused(lines: list<string>, member: dict<any>): list<string>
    var bytes = str2blob(lines)
    var name = 'DIFFVIEW_HISTORY_PATCH:' .. member.oid
    var marker = 0z00 + str2blob([name]) + 0z00
    var text = join(lines, "\n")
    var found: list<number> = []
    var at = stridx(text, "\n" .. name .. "\n")
    while at >= 0
        if bytes[at : at + len(marker) - 1] == marker
            add(found, at)
        endif
        at = stridx(text, "\n" .. name .. "\n", at + 1)
    endwhile
    if len(found) != 1
        throw '[diffview] Invalid historical preview framing.'
    endif
    var heading = blob2str(bytes[0 : found[0] - 1])
    var position = [found[0] + len(marker)]
    while position[0] < len(bytes) && index([0, 10], bytes[position[0]]) >= 0
        position[0] += 1
    endwhile
    var entries: list<dict<any>> = []
    var identities: dict<bool> = {}
    while position[0] < len(bytes) && bytes[position[0]] == 58
        var meta = split(Field(bytes, position))
        if len(meta) != 5
            throw '[diffview] Invalid historical raw change.'
        endif
        var oldpath = Field(bytes, position)
        var path = index(['R', 'C'], meta[4][0]) >= 0 ? Field(bytes, position) : oldpath
        var key = json_encode([oldpath, path])
        if has_key(identities, key)
            throw '[diffview] Duplicate historical raw change.'
        endif
        identities[key] = true
        add(entries, {oldpath: oldpath, path: path, status: meta[4][0]})
    endwhile
    var counts: dict<any> = {}
    while position[0] < len(bytes) && bytes[position[0]] != 0
        var record = Field(bytes, position)
        var first = stridx(record, "\t")
        var second = stridx(record, "\t", first + 1)
        if first < 0 || second < 0
            throw '[diffview] Invalid historical numstat.'
        endif
        var added = strpart(record, 0, first)
        var deleted = strpart(record, first + 1, second - first - 1)
        if !(added == '-' && deleted == '-') && (added !~ '^\d\+$' || deleted !~ '^\d\+$')
            throw '[diffview] Invalid historical numstat counts.'
        endif
        var path = strpart(record, second + 1)
        var oldpath = path == '' ? Field(bytes, position) : path
        if path == ''
            path = Field(bytes, position)
        endif
        var key = json_encode([oldpath, path])
        if !has_key(identities, key) || has_key(counts, key)
            throw '[diffview] Invalid historical count association.'
        endif
        counts[key] = '+' .. (added == '-' ? '?' : added) .. ' -' .. (deleted == '-' ? '?' : deleted)
    endwhile
    while position[0] < len(bytes) && index([0, 10], bytes[position[0]]) >= 0
        position[0] += 1
    endwhile
    var sections: list<list<string>> = []
    for line in position[0] >= len(bytes) ? [] : blob2str(bytes[position[0] :])
        if stridx(line, 'diff --git ') == 0
            add(sections, [line])
        elseif !empty(sections)
            add(sections[-1], line)
        endif
    endfor
    if len(sections) != len(entries) || len(counts) != len(entries)
        throw '[diffview] Historical raw/patch record count mismatch.'
    endif
    var selected: list<number> = []
    for i in range(len(entries))
        var entry = entries[i]
        var matches = get(member, 'follow', false) ? entry.path == member.paths[0]
            : empty(member.paths) || !empty(filter(copy(member.paths), (_, prefix) => entry.path == prefix
                || entry.oldpath == prefix || stridx(entry.path, prefix .. '/') == 0 || stridx(entry.oldpath, prefix .. '/') == 0))
        if matches
            if get(member, 'follow', false) && !empty(selected)
                throw '[diffview] Ambiguous historical file change.'
            endif
            add(selected, i)
        endif
    endfor
    if empty(selected)
        return heading + ['No matching first-parent file changes.']
    endif
    var summary: list<string> = []
    var patch: list<string> = []
    for i in selected
        var entry = entries[i]
        var count = get(counts, json_encode([entry.oldpath, entry.path]), '')
        if count == ''
            throw '[diffview] Historical count association missing.'
        endif
        add(summary, entry.oldpath .. (entry.oldpath == entry.path ? '' : ' -> ' .. entry.path)
            .. ' | ' .. count .. ' (' .. entry.status .. ')')
        extend(patch, sections[i])
    endfor
    # Identity/order comes from the same raw diff queue, never human path labels.
    return heading + summary + [''] + patch
enddef

def Render(context: string, token: string)
    var request = Member(context, token)
    var raw = readfile('/dev/stdin', 'b')
    if !empty(raw) && raw[-1] == ''
        remove(raw, -1)
    endif
    var status = empty(raw) ? '' : remove(raw, -1)
    var output: list<string> = []
    if status != 'DIFFVIEW_PREVIEW_STATUS:0' || empty(raw) || raw[0] != 'commit ' .. request.member.oid
        add(output, '[diffview] Preview failed: ' .. (status == 'DIFFVIEW_PREVIEW_STATUS:0'
            ? 'invalid or unavailable request/output.' : strtrans(status)))
    endif
    if empty(output)
        raw = Focused(raw, request.member)
    endif
    var truncated = len(raw) + len(output) > 2000
    for line in raw[0 : min([len(raw), 2000 - len(output) - (truncated ? 1 : 0)]) - 1]
        var safe = strtrans(line)
        if strlen(safe) > 4096
            var length = min([4000, strchars(safe)])
            var clipped = strcharpart(safe, 0, length)
            while strlen(clipped) > 4000
                length -= 1
                clipped = strcharpart(safe, 0, length)
            endwhile
            safe = clipped .. ' [diffview: line truncated at 4096 display bytes]'
        endif
        add(output, safe)
    endfor
    if truncated
        add(output, '[diffview] Preview truncated at 2000 lines.')
    endif
    writefile(output, '/dev/stdout')
enddef

if get(g:, 'diffview_preview_worker', false)
    set nocompatible nomore noexrc nomodeline
    &runtimepath = fnamemodify(helper, ':h:h:h') .. ',' .. $VIMRUNTIME
    set packpath=
    try
        if argc() != 0
            throw '[diffview] Invalid preview worker request.'
        endif
        if $DIFFVIEW_PREVIEW_MODE == 'args'
            Arguments($DIFFVIEW_PREVIEW_CONTEXT, $DIFFVIEW_PREVIEW_TOKEN)
        elseif $DIFFVIEW_PREVIEW_MODE == 'render'
            Render($DIFFVIEW_PREVIEW_CONTEXT, $DIFFVIEW_PREVIEW_TOKEN)
        else
            throw '[diffview] Unknown preview worker mode.'
        endif
    catch
        if $DIFFVIEW_PREVIEW_MODE == 'render'
            writefile(['[diffview] Preview error: ' .. strtrans(v:exception)], '/dev/stdout')
        else
            # Ensure an invalid request cannot become xargs' successful empty input.
            writefile(0z00, '/dev/stdout')
        endif
        cquit 1
    endtry
    qa!
endif
