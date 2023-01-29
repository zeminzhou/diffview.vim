## diffview.vim

A vim9 plugin show changed files

![Alt text](/doc/_static/current.jpg?raw=true "current branch changes")

![Alt text](/doc/_static/branch.jpg?raw=true "two branchs changes")

## Installation

### vim-plug

1. Add the following line to your `~/.vimrc`:

```vim
call plug#begin()
...
Plug 'zeminzhou/diffview.vim'
...
call plug#end()
```

2. Run `:PlugInstall`.

## Start

### current branch changes
You can use `:call ToggleDiffView()` to show current branch changes.

### two branchs changes
You can use `:DiffBranch $branch` to show two branch changes.

