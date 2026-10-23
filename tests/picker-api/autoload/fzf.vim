" API-boundary fixture only. Real UI cases load the external core plugin.
let g:loaded_fzf = 20260821
let g:diffview_test_picker_calls = 0

function! fzf#wrap(...) abort
    for argument in a:000
        if type(argument) == v:t_dict
            return copy(argument)
        endif
    endfor
    throw 'fixture fzf#wrap expected a dictionary'
endfunction

function! fzf#run(spec) abort
    let g:diffview_test_picker_calls += 1
    let g:diffview_test_picker_spec = copy(a:spec)
    if get(g:, 'diffview_test_picker_throw', 0)
        throw 'fixture fzf launch failure'
    endif
    return []
endfunction
