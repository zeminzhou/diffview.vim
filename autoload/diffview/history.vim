vim9script

# Licensed under AGPL-3.0-or-later; see LICENSE.
import autoload 'diffview/git.vim' as git

export def File(root: string, commit: string, path: string, required = false): dict<any>
    var paths = git.Prefixes([path])
    if len(paths) != 1 || path =~ '/$'
        throw '[diffview] History requires exactly one literal file path.'
    endif
    var records = git.NulFields(git.Run(root, ['ls-tree', '-z', commit, '--', paths[0]]))
    for record in records
        var tab = stridx(record, "\t")
        var meta = split(strpart(record, 0, tab))
        if tab >= 0 && strpart(record, tab + 1) == paths[0] && len(meta) == 3
            if index(['100644', '100755'], meta[0]) < 0 || meta[1] != 'blob'
                throw '[diffview] History requires a regular committed file.'
            endif
            return {path: paths[0], oid: meta[2]}
        endif
    endfor
    if required || !empty(records)
        throw '[diffview] File is absent or not regular at the committed start.'
    endif
    return {path: paths[0], oid: ''}
enddef

export def Entries(root: string, start: string, path: string, range: list<number> = []): list<dict<any>>
    var file = File(root, start, path, !empty(range))
    var fields = git.NulFields(git.Run(root, ['log', '--first-parent', '--follow',
        '--diff-merges=first-parent', '--raw', '-z', '--no-abbrev', '-M', '--no-ext-diff', '--no-textconv',
        '--no-color', '--no-notes', '--no-show-signature', '--encoding=UTF-8', '--date=short',
        '--format=%x00%H%x00%ad%x00%an%x00%s%x00', start, '--', file.path]))
    var entries: list<dict<any>> = []
    var i = 0
    while i < len(fields)
        if fields[i] != '' || i + 4 >= len(fields)
            throw '[diffview] Malformed file-history framing.'
        endif
        var oid = fields[i + 1]
        if oid !~ '^\x\+$' || index([40, 64], strlen(oid)) < 0
            throw '[diffview] Malformed file-history commit.'
        endif
        var label = oid[0 : 11] .. ' ' .. fields[i + 2] .. ' ' .. fields[i + 3] .. ' ' .. fields[i + 4]
        i += 5
        if i < len(fields) && fields[i] == ''
            i += 1
        endif
        while i < len(fields) && (fields[i] =~ '^:' || fields[i] =~ '^\n:')
            # Only Git's fixed pretty/raw separator is removed; path bytes are untouched.
            var meta = split(substitute(fields[i], '^\n', '', ''))
            if len(meta) != 5 || i + 1 >= len(fields)
                throw '[diffview] Malformed file-history change.'
            endif
            var oldpath = fields[i + 1]
            var pathAtCommit = oldpath
            i += 2
            if meta[4][0] == 'R' || meta[4][0] == 'C'
                if i >= len(fields)
                    throw '[diffview] Missing historical rename path.'
                endif
                pathAtCommit = fields[i]
                i += 1
            endif
            add(entries, {oid: oid, path: pathAtCommit, oldpath: oldpath,
                row: json_encode([oid, oldpath, pathAtCommit]) .. "\t" .. git.Display(label)
                    .. ' | ' .. git.Display(pathAtCommit)})
        endwhile
    endwhile
    if !empty(range)
        var ids = git.NulFields(git.Run(root, ['log', '--first-parent', '--no-patch', '-z',
            '--format=%H', '-L' .. range[0] .. ',' .. range[1] .. ':' .. file.path, start]))
        var traced: list<dict<any>> = []
        for oid in ids
            var matches = filter(copy(entries), (_, entry) => entry.oid == oid)
            if len(matches) != 1
                throw '[diffview] Line history has no unique raw historical path association.'
            endif
            add(traced, matches[0])
        endfor
        entries = traced
    endif
    if empty(entries)
        throw '[diffview] No file history at this committed start.'
    endif
    return entries
enddef

export def Match(root: string, start: string, path: string, lines: list<string>, eol: bool, range: list<number>)
    var file = File(root, start, path, true)
    var blob = git.Blob(root, file.oid)
    if blob.binary || blob.lines != lines || blob.eol != eol
        throw '[diffview] Line history requires displayed content and EOL to match the committed blob exactly.'
    endif
    if len(range) != 2 || range[0] < 1 || range[1] < range[0] || range[1] > len(lines)
        throw '[diffview] Invalid committed line-history range.'
    endif
enddef
