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
        mkdir(context, '', 0o700)
        writefile([json_encode({root: root, members: members})], context .. '/source.json')
        setfperm(context .. '/source.json', 'rw-------')
        # Only fixed code crosses the shell; Git arguments arrive as NUL data.
        var command = '{ ' .. Native('args', context)
            .. ' | xargs -0 -s 65536 sh -c '
            .. shellescape('test "$#" -ge 2 && test "$1" = "$0" || exit 64; n="$2"; shift 2; '
                .. 'case "$n" in ""|*[!0-9]*) exit 64;; esac; test "$#" -eq "$n" || exit 64; exec git "$@"')
            .. ' ' .. shellescape(context) .. ' 2>&1; '
            .. 'printf ''\nDIFFVIEW_PREVIEW_STATUS:%s\n'' "$?"; } | ' .. Native('render', context)
        return {context: context, command: command}
    catch
        delete(context, 'rf')
        throw '[diffview] Cannot prepare preview: ' .. v:exception
    endtry
    return {}
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
    return {root: source.root, member: member}
enddef

def Arguments(context: string, token: string)
    var request = Member(context, token)
    var member = request.member
    var args = git.Command(request.root, ['show', '--first-parent', '--diff-merges=first-parent', '--root',
        '--no-ext-diff', '--no-textconv', '--no-color', '--no-notes', '--no-show-signature',
        '--encoding=UTF-8', '--format=commit %H%nAuthor: %an <%ae>%nDate: %aI%n%n%B',
        '--stat', '--patch', member.oid, '--'] + member.paths)[1 :]
    var bytes = 0z
    for argument in [context, string(len(args))] + args
        for offset in range(strlen(argument))
            add(bytes, char2nr(strpart(argument, offset, 1)))
        endfor
        add(bytes, 0)
    endfor
    # Leave ample room under xargs' explicit size; never split one Git request.
    if len(args) > 256 || len(bytes) > 8192
        throw '[diffview] Preview argument request exceeds the safe single-invocation limit.'
    endif
    writefile(bytes, '/dev/stdout')
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
