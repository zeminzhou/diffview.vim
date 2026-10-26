vim9script

# Modified 2026-10-22. Licensed under AGPL-3.0-or-later; see LICENSE.

export def Check()
    for [name, methods] in items({NERDTree: ['New'], NERDTreeUI: ['New', 'render'],
        NERDTreePath: ['New', 'equals', 'str', 'displayString'],
        NERDTreeFileNode: ['New', 'GetSelected', 'renderToString'],
        NERDTreeDirNode: ['New', 'toggleOpen', 'openRecursively', 'closeChildren',
            'getVisibleChildren', 'findNode', 'close'],
        NERDTreeFlagSet: ['New', 'addFlag']})
        var api = get(g:, name, {})
        for method in methods
            if type(api) != v:t_dict || !has_key(api, method) || type(api[method]) != v:t_func
                throw '[diffview] Install a compatible preservim/nerdtree on runtimepath (see :help diffview).'
            endif
        endfor
    endfor
enddef

def Label(value: string): string
    var encoded = json_encode(value)
    return strpart(encoded, 1, strlen(encoded) - 2)
enddef

def Zero(...args: list<any>): number
    return 0
enddef

def Minimal(): number
    return 1
enddef

# NERDTree's cyclic legacy objects stay any to avoid recursive Vim9 type propagation.
def Virtual(node: any)
    # Physical refresh and path listeners cannot describe comparison-only nodes.
    node.path.ignore = Zero
    node.path.refresh = Zero
    node.path.refreshFlags = Zero
    node.refresh = Zero
    node.refreshFlags = Zero
    if node.path.isDirectory
        node.isOpen = 1
        node.isCascadable = Zero
        node._initChildren = Zero
    endif
enddef

def Child(tree: any, parent: any, name: string, key: string, directory: bool): any
    var path = copy(parent.path)
    # Opaque components avoid upstream case folding and file/directory collisions.
    path.pathSegments = parent.path.pathSegments + [string(len(tree.diffview_nodes))]
    path.isDirectory = directory ? 1 : 0
    path.isExecutable = 0
    path.isSymLink = 0
    path.isReadOnly = 0
    path.cachedDisplayString = g:NERDTreeNodeDelimiter .. name
        .. (directory ? '/' : '') .. g:NERDTreeNodeDelimiter
    path.flagSet = g:NERDTreeFlagSet.New()
    var node = g:NERDTreeFileNode.New(path, tree)
    node.parent = parent
    node.diffview_key = key
    Virtual(node)
    add(parent.children, node)
    tree.diffview_nodes[key] = node
    return node
enddef

def Row(tree: any, node: any): number
    var key = get(node, 'diffview_key', '')
    return get(tree.diffview_nodes, key, {}) is node ? get(tree.diffview_lines, key, -1) : -1
enddef

def PathAt(tree: any, row: number): dict<any>
    return get(get(tree.diffview_rows, string(row), {}), 'path', {})
enddef

def IndexRows(tree: any)
    var rows: dict<any> = {}
    var lines: dict<number> = {}
    var pending = [tree.root]
    var row = len(tree.diffview_header) + 1
    while !empty(pending)
        var node = remove(pending, -1)
        rows[string(row)] = node
        lines[node.diffview_key] = row
        row += 1
        # Virtual nodes are unfiltered and never cascaded, matching native render order.
        if node.path.isDirectory && node.isOpen
            extend(pending, reverse(copy(node.children)))
        endif
    endwhile
    tree.diffview_rows = rows
    tree.diffview_lines = lines
enddef

export def Expansion(tree: any): dict<number>
    var expanded: dict<number> = {}
    for [key, node] in items(tree.diffview_nodes)
        if node.path.isDirectory
            expanded[key] = node.isOpen
        endif
    endfor
    return expanded
enddef

export def Build(model: dict<any>, expanded: dict<number> = {}): dict<any>
    diffview#tree#Check()
    var path = g:NERDTreePath.New(model.root)
    path._strForUI = function(Label, [model.root])
    var tree = g:NERDTree.New(path, 'window')
    tree.diffview_nodes = {}
    tree.diffview_entries = []
    tree.diffview_rows = {}
    tree.diffview_lines = {}
    tree.diffview_no_match = empty(model.entries) && !empty(get(model, 'fullEntries', []))
    tree.diffview_header = ['[diffview] ' .. toupper(model.mode), model.mode == 'local'
        ? 'Disk snapshots; unsaved edits excluded' : Label(model.leftSource .. ' -> ' .. model.rightSource)]
    var added = 0
    var deleted = 0
    var unknown = 0
    for entry in model.entries
        if entry.added < 0 || entry.deleted < 0
            unknown += 1
        else
            added += entry.added
            deleted += entry.deleted
        endif
    endfor
    add(tree.diffview_header, len(model.entries) .. '/' .. len(get(model, 'fullEntries', model.entries))
        .. ' entries | +' .. added .. ' -' .. deleted .. (unknown > 0 ? ' | ' .. unknown .. ' unknown' : ''))
    if !empty(get(model, 'paths', []))
        add(tree.diffview_header, 'Filter: ' .. join(mapnew(model.paths, (_, value) => Label(value)), ', '))
    endif
    tree.root.diffview_key = 'root'
    tree.diffview_nodes.root = tree.root
    Virtual(tree.root)
    tree.ui.isMinimal = Minimal
    tree.ui.getShowBookmarks = Zero
    tree.ui.getPath = function(PathAt, [tree])
    tree.ui.getLineNum = function(Row, [tree])
    tree.render = function(RenderHere, [tree])
    var sections = model.mode == 'local' ? ['Staged', 'Unstaged', 'Untracked']
        : [model.mode == 'commit' ? 'Commit' : 'Trees']
    for section in sections
        Child(tree, tree.root, section, json_encode(['dir', section, '']), true)
    endfor
    for i in range(len(model.entries))
        var entry = model.entries[i]
        var parent = tree.diffview_nodes[json_encode(['dir', entry.section, ''])]
        var components = split(entry.path, '/')
        var directory = ''
        for component in components[0 : -2]
            directory ..= (directory == '' ? '' : '/') .. component
            var key = json_encode(['dir', entry.section, directory])
            if !has_key(tree.diffview_nodes, key)
                Child(tree, parent, Label(component), key, true)
            endif
            parent = tree.diffview_nodes[key]
        endfor
        var label = Label(components[-1])
        if entry.status == 'R' || entry.status == 'C'
            label ..= ' <- ' .. Label(entry.oldpath)
        endif
        label ..= ' +' .. (entry.added < 0 ? '?' : string(entry.added))
            .. ' -' .. (entry.deleted < 0 ? '?' : string(entry.deleted))
        var node = Child(tree, parent, label, json_encode(['entry', entry.section, entry.path]), false)
        node.diffview_entry = entry
        node.diffview_index = i
        add(tree.diffview_entries, node)
        while !empty(node)
            node.path.flagSet.addFlag('diffview', entry.status)
            node = node.parent
        endwhile
    endfor
    for [key, isOpen] in items(expanded)
        if has_key(tree.diffview_nodes, key)
            tree.diffview_nodes[key].isOpen = isOpen
        endif
    endfor
    return tree
enddef

def Restore(lines: list<string>)
    setlocal noreadonly modifiable
    setline(1, lines)
    if line('$') > len(lines)
        deletebufline(bufnr(), len(lines) + 1, '$')
    endif
enddef

def RenderHere(tree: any)
    var body = getline(1, '$')
    var position = winsaveview()
    var expression = getreg('=', true, true)
    var globalScroll = &g:scrolloff
    var localScroll = &l:scrolloff
    try
        tree.ui.render()
        setlocal noreadonly modifiable
        append(0, tree.diffview_header)
        if empty(tree.diffview_entries)
            append(line('$'), tree.diffview_no_match ? 'No matching changes' : 'No changes')
        endif
        IndexRows(tree)
        winrestview(position)
    catch
        Restore(body)
        winrestview(position)
        throw '[diffview] NERDTree: ' .. v:exception
    finally
        setreg('=', expression)
        &g:scrolloff = globalScroll
        &l:scrolloff = localScroll
        setlocal readonly nomodifiable nomodified
    endtry
enddef

export def Install(win: number, tree: any)
    var buf = winbufnr(win)
    var previous = getbufvar(buf, 'NERDTree', {})
    setbufvar(buf, 'NERDTree', tree)
    try
        win_execute(win, 'legacy call b:NERDTree.render()')
    catch
        setbufvar(buf, 'NERDTree', previous)
        throw '[diffview] NERDTree: ' .. v:exception
    endtry
enddef

export def Cursor(win: number, tree: any, key: string)
    if has_key(tree.diffview_nodes, key)
        var row = tree.ui.getLineNum(tree.diffview_nodes[key])
        if row > 0
            win_execute(win, 'call cursor(' .. row .. ', 1)')
        endif
    endif
enddef

export def CursorKey(win: number, tree: any): string
    var path = tree.ui.getPath(getcurpos(win)[1])
    return empty(path) ? '' : tree.root.findNode(path).diffview_key
enddef

export def ExpandParents(node: any): bool
    var parent = node.parent
    var changed = false
    while !empty(parent)
        changed = changed || !parent.isOpen
        parent.isOpen = 1
        parent = parent.parent
    endwhile
    return changed
enddef

export def Reveal(win: number, tree: any, index: number)
    var expanded = diffview#tree#Expansion(tree)
    var node = tree.diffview_entries[index]
    var changed = diffview#tree#ExpandParents(node)
    try
        if changed
            diffview#tree#Install(win, tree)
        endif
        diffview#tree#Cursor(win, tree, node.diffview_key)
    catch
        for [key, isOpen] in items(expanded)
            tree.diffview_nodes[key].isOpen = isOpen
        endfor
        throw '[diffview] NERDTree: ' .. v:exception
    endtry
enddef

export def Navigate(win: number, tree: any, action: string)
    var node = g:NERDTreeFileNode.GetSelected()
    if empty(node)
        return
    endif
    if action == 'p'
        if !empty(node.parent)
            diffview#tree#Cursor(win, tree, node.parent.diffview_key)
        endif
        return
    endif
    var expanded = diffview#tree#Expansion(tree)
    if !node.path.isDirectory
        node = node.parent
    endif
    try
        if action == 'O'
            node.openRecursively()
        elseif action == 'X'
            node.closeChildren()
        elseif action == 'x'
            node.close()
        else
            node.toggleOpen()
        endif
        diffview#tree#Install(win, tree)
        diffview#tree#Cursor(win, tree, node.diffview_key)
    catch
        for [key, isOpen] in items(expanded)
            tree.diffview_nodes[key].isOpen = isOpen
        endfor
        throw '[diffview] NERDTree: ' .. v:exception
    endtry
enddef
