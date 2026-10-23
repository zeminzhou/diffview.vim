" API-boundary fixture only; real core wrap/exec stay loaded and unmodified.
let g:diffview_test_picker_calls = 0

function! fzf#run(spec) abort
    let g:diffview_test_picker_calls += 1
    let g:diffview_test_picker_spec = copy(a:spec)
    if get(g:, 'diffview_test_picker_throw', 0)
        throw 'fixture fzf launch failure'
    endif
    return []
endfunction
