vim9script

# Copyright (C) 2022 zeminzhou <zeminzhou_@outlook.com>
# Modified 2026-10-22. Licensed under AGPL-3.0-or-later; see LICENSE.

def Run(root: string, args: list<string>, allowOne = false): list<string>
    var output = tempname()
    var errors = tempname()
    var process: job
    try
        # git diff's stat refresh can write the index even without optional locks.
        process = job_start(['git', '--no-optional-locks', '--literal-pathspecs',
            '-c', 'diff.autoRefreshIndex=false',
            '-C', root] + args, {in_io: 'null', out_io: 'file', out_name: output,
            err_io: 'file', err_name: errors})
        if job_status(process) == 'fail'
            throw '[diffview] Cannot start Git; check that git is installed.'
        endif
        while job_status(process) == 'run'
            sleep 1m
        endwhile
        var code = job_info(process).exitval
        if code != 0 && !(allowOne && code == 1)
            throw '[diffview] Git failed: ' .. join(readfile(errors), ' ')
        endif
        return readfile(output, 'b')
    finally
        if process != null_job && job_status(process) == 'run'
            job_stop(process, 'kill')
        endif
        delete(output)
        delete(errors)
    endtry
    return []
enddef

def Text(lines: list<string>): string
    return substitute(join(lines, "\n"), '\n$', '', '')
enddef

# readfile(..., 'b') preserves LF as list boundaries and NUL as in-line NL.
def NulFields(lines: list<string>): list<string>
    var fields: list<string> = []
    var pending = ''
    for i in range(len(lines))
        if i > 0
            pending ..= "\n"
        endif
        var parts = split(lines[i], "\n", true)
        pending ..= parts[0]
        for part in parts[1 :]
            add(fields, pending)
            pending = part
        endfor
    endfor
    if pending != ''
        throw '[diffview] Malformed NUL-delimited Git output.'
    endif
    return fields
enddef

export def Display(path: string): string
    return strtrans(path)
enddef

export def Root(): string
    var cwd = getcwd()
    if Text(Run(cwd, ['rev-parse', '--is-bare-repository'])) == 'true'
        throw '[diffview] Bare repositories are unsupported.'
    endif
    return Text(Run(cwd, ['rev-parse', '--show-toplevel']))
enddef

def DiffEntries(root: string, args: list<string>, section: string, rootCommit = false): list<dict<any>>
    # numstat filters stat-only raw records without refreshing the index.
    var command = rootCommit ? ['diff-tree', '--root', '--no-commit-id', '-r'] : ['diff']
    var fields = NulFields(Run(root, command + ['--raw', '--numstat', '-z', '--no-abbrev',
        '--no-ext-diff', '--no-textconv', '--ignore-submodules=none', '-M'] + args + ['--']))
    var entries: list<dict<any>> = []
    var seen: dict<bool> = {}
    var i = 0
    while i < len(fields) && fields[i] =~ '^:'
        var meta = split(fields[i])
        if len(meta) != 5 || meta[0][0] != ':' || i + 1 >= len(fields)
            throw '[diffview] Malformed Git diff record.'
        endif
        var status = meta[4][0]
        var oldpath = fields[i + 1]
        var path = oldpath
        i += 2
        if status == 'R' || status == 'C'
            if i >= len(fields)
                throw '[diffview] Missing renamed Git path.'
            endif
            path = fields[i]
            i += 1
        endif
        if has_key(seen, path)
            continue
        endif
        seen[path] = true
        add(entries, {section: section, status: status, oldpath: oldpath, path: path,
            oldmode: meta[0][1 :], newmode: meta[1], oldoid: meta[2], newoid: meta[3]})
    endwhile
    var changed: dict<bool> = {}
    while i < len(fields)
        var first = stridx(fields[i], "\t")
        var second = stridx(fields[i], "\t", first + 1)
        if first < 0 || second < 0
            throw '[diffview] Malformed Git numstat record.'
        endif
        var binary = strpart(fields[i], 0, second) == "-\t-"
        var path = strpart(fields[i], second + 1)
        i += 1
        if path == ''
            if i + 1 >= len(fields)
                throw '[diffview] Missing renamed numstat path.'
            endif
            path = fields[i + 1]
            i += 2
        endif
        changed[path] = binary
    endwhile
    filter(entries, (_, entry) => has_key(changed, entry.path))
    for entry in entries
        entry.binary = changed[entry.path]
    endfor
    if section == 'Unstaged'
        filter(entries, (_, entry) => !BinaryStatOnly(root, entry))
    endif
    return entries
enddef

export def Local(root: string): dict<any>
    var head = Text(Run(root, ['rev-parse', '--verify', '--quiet', 'HEAD'], true))
    var entries = DiffEntries(root, ['--cached'], 'Staged')
    extend(entries, DiffEntries(root, [], 'Unstaged'))
    for path in NulFields(Run(root, ['ls-files', '--others', '--exclude-standard', '-z']))
        add(entries, {section: 'Untracked', status: '?', oldpath: path, path: path,
            oldmode: '000000', newmode: '100644', oldoid: '', newoid: ''})
    endfor
    return {root: root, mode: 'local', args: [], entries: entries,
        head: head == '' ? 'EMPTY' : 'HEAD ' .. head[0 : 6]}
enddef

def Resolve(root: string, revision: string, kind: string): string
    if revision == '' || revision[0] == '-'
        throw '[diffview] Invalid revision: ' .. Display(revision)
    endif
    try
        var oid = Text(Run(root, ['rev-parse', '--verify', '--end-of-options', revision]))
        # --verify also accepts exclusion syntax and can return ^<oid>.
        if oid !~ '^\x\+$' || index([40, 64], strlen(oid)) < 0
            throw '[diffview] Expected one object revision: ' .. Display(revision)
        endif
        return Text(Run(root, ['rev-parse', '--verify', '--end-of-options',
            oid .. '^{' .. kind .. '}']))
    catch
        throw '[diffview] Cannot resolve ' .. Display(revision) .. ' as ' .. kind
            .. ': ' .. v:exception
    endtry
    return ''
enddef

export def Comparison(root: string, args: list<string>, commit: bool): dict<any>
    if !commit && empty(args)
        return Local(root)
    endif
    if commit
        var revision = empty(args) ? 'HEAD' : args[0]
        var oid = Resolve(root, revision, 'commit')
        var parent = ''
        # Read the real parent: rev-list hides parents at shallow boundaries.
        for line in Run(root, ['cat-file', 'commit', oid])
            if line == ''
                break
            endif
            if stridx(line, 'parent ') == 0
                parent = strpart(line, 7)
                break
            endif
        endfor
        var entries = parent == '' ? DiffEntries(root, [oid], 'Commit', true)
            : DiffEntries(root, [parent, oid], 'Commit')
        return {root: root, mode: 'commit', args: copy(args), entries: entries,
            leftSource: parent == '' ? 'EMPTY' : revision .. '^1 ' .. parent[0 : 6],
            rightSource: revision .. ' ' .. oid[0 : 6]}
    endif
    var left = Resolve(root, args[0], 'tree')
    var right = Resolve(root, args[1], 'tree')
    return {root: root, mode: 'trees', args: copy(args),
        entries: DiffEntries(root, [left, right], 'Trees'),
        leftSource: args[0] .. ' ' .. left[0 : 6], rightSource: args[1] .. ' ' .. right[0 : 6]}
enddef

def Empty(): dict<any>
    return {lines: [''], eol: false, binary: false}
enddef

def Snapshot(lines: list<string>): dict<any>
    var binary = false
    for line in lines
        if stridx(line, "\n") >= 0
            binary = true
            break
        endif
    endfor
    var content = copy(lines)
    var eol = len(content) > 1 && content[-1] == ''
    if eol
        remove(content, -1)
    endif
    return {lines: empty(content) ? [''] : content, eol: eol, binary: binary}
enddef

def Blob(root: string, oid: string): dict<any>
    if oid == '' || oid =~ '^0\+$'
        return Empty()
    endif
    return Snapshot(Run(root, ['cat-file', 'blob', oid]))
enddef

def Index(root: string, path: string): dict<any>
    var records = NulFields(Run(root, ['ls-files', '--stage', '-z', '--', path]))
    for record in records
        var tab = stridx(record, "\t")
        var meta = split(strpart(record, 0, tab))
        if tab < 0 || len(meta) != 3
            throw '[diffview] Malformed Git index entry.'
        endif
        if strpart(record, tab + 1) != path
            continue
        endif
        if meta[2] != '0'
            return {unsupported: 'Unmerged index entry; two-way conflict resolution is unsupported.'}
        endif
        if meta[0] == '120000' || meta[0] == '160000'
            return {unsupported: 'Symlink/submodule content is unsupported.'}
        endif
        return Blob(root, meta[1])
    endfor
    throw '[diffview] Index entry disappeared: ' .. Display(path) .. '; refresh the view.'
enddef

def Disk(root: string, path: string): dict<any>
    var filename = root
    # A leaf-only check follows links in parent directories.
    for component in split(path, '/')
        filename ..= '/' .. component
        if getftype(filename) == 'link'
            return {unsupported: 'Symlink content is unsupported; links are not followed.'}
        endif
    endfor
    var kind = getftype(filename)
    if kind == 'dir'
        return {unsupported: 'Submodule/directory content is unsupported.'}
    endif
    if kind != 'file' || !filereadable(filename)
        throw '[diffview] Cannot read worktree file: ' .. Display(path) .. '; refresh the view.'
    endif
    return Snapshot(readfile(filename, 'b'))
enddef

def BinaryStatOnly(root: string, entry: dict<any>): bool
    if !entry.binary || entry.status != 'M' || entry.oldmode != entry.newmode
            || index(['100644', '100755'], entry.oldmode) < 0
        return false
    endif
    var disk = Disk(root, entry.path)
    if has_key(disk, 'unsupported')
        return false
    endif
    var snapshot = tempname()
    try
        if writefile(disk.lines + (disk.eol ? [''] : []), snapshot, 'b') != 0
            throw '[diffview] Cannot create temporary content snapshot.'
        endif
        # Hash the checked snapshot with Git's clean rules, without writing objects.
        return Text(Run(root, ['hash-object', '--path=' .. entry.path, '--', snapshot])) == entry.oldoid
    finally
        delete(snapshot)
    endtry
    return false
enddef

export def Read(model: dict<any>, entry: dict<any>): dict<any>
    var localMode = model.mode == 'local'
    var leftSource = localMode ? (entry.section == 'Staged' ? model.head : 'INDEX') : model.leftSource
    var rightSource = localMode ? (entry.section == 'Staged' ? 'INDEX'
        : 'WORKTREE (disk; unsaved edits excluded)') : model.rightSource
    if entry.oldmode == '000000'
        leftSource = 'EMPTY'
    endif
    if entry.newmode == '000000'
        rightSource = 'EMPTY (absent)'
    endif
    var issue = ''
    if entry.status == 'U'
        issue = 'Unmerged index entry; two-way conflict resolution is unsupported.'
    elseif index([entry.oldmode, entry.newmode], '120000') >= 0
        issue = 'Symlink content is unsupported; links are not followed.'
    elseif index([entry.oldmode, entry.newmode], '160000') >= 0
        issue = 'Submodule content is unsupported.'
    endif
    var left: dict<any> = Empty()
    var right: dict<any> = Empty()
    if issue == ''
        if localMode
            left = entry.oldmode == '000000' ? Empty() : entry.section == 'Staged'
                ? Blob(model.root, entry.oldoid) : Index(model.root, entry.oldpath)
            right = entry.newmode == '000000' ? Empty() : entry.section == 'Staged'
                ? Index(model.root, entry.path) : Disk(model.root, entry.path)
        else
            left = Blob(model.root, entry.oldoid)
            right = Blob(model.root, entry.newoid)
        endif
        issue = get(left, 'unsupported', get(right, 'unsupported', ''))
        if issue == ''
            var attributes = NulFields(Run(model.root, ['check-attr', '-z', 'diff', '--', entry.path]))
            if len(attributes) != 3 || attributes[0] != entry.path || attributes[1] != 'diff'
                throw '[diffview] Malformed Git diff attribute record.'
            endif
            if get(entry, 'binary', false) || attributes[2] == 'unset' || left.binary || right.binary
                issue = 'Binary content; textual diff is unavailable.'
            endif
        endif
    endif
    if issue != ''
        left = {lines: ['[diffview] ' .. issue], eol: true}
        right = deepcopy(left)
    endif
    return {left: left, right: right, leftSource: leftSource,
        rightSource: rightSource, diff: issue == ''}
enddef
