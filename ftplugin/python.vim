" This file contains the vim code for Cyfolds.  It does some one-time
" initialization and then defines the function which will be set as the
" foldeval value to compute the foldlevels.

if !exists('g:cyfolds')
   let g:cyfolds = 1
endif

if exists('g:loaded_cyfolds') || &cp || g:cyfolds == 0
    finish
endif
let g:loaded_cyfolds = 1


" ==============================================================================
" ==== Initialization. =========================================================
" ==============================================================================

if has('win32') || has ('win64')
    let vimhome = $VIM."/vimfiles"
else
    let vimhome = $HOME."/.vim"
endif

if !exists("g:cyfolds_hash_for_changes")
    let g:cyfolds_hash_for_changes = 0
endif

if !exists("g:cyfolds_fold_keywords")
    let g:cyfolds_fold_keywords = "class,def,async def"
endif

if !exists("g:cyfolds_start_in_manual_method")
    let g:cyfolds_start_in_manual_method = 1
endif

if !exists("g:cyfolds_lines_of_module_docstrings")
    let g:cyfolds_lines_of_module_docstrings = -1
endif

if !exists("g:cyfolds_lines_of_fun_and_class_docstrings")
    let g:cyfolds_lines_of_fun_and_class_docstrings = -1
endif

function! CyfoldsBufEnterInit()
    " Initialize upon entering a buffer.

    setlocal foldmethod=expr
    setlocal foldexpr=GetPythonFoldViaCython(v:lnum)

    " Map the keys zuz and z, to their commands.
    nnoremap <buffer> <silent> zuz :call CyfoldsForceFoldUpdate()<CR>
    nnoremap <buffer> <silent> z, :call CyfoldsToggleManualFolds()<CR>
    noremap <buffer> <silent> zuz :call CyfoldsForceFoldUpdate()<CR>
    nnoremap <buffer> <silent> z, :call CyfoldsToggleManualFolds()<CR>

    " Initialize variables.
    let b:suppress_insert_mode_switching = 0

    " Start with the chosen foldmethod.
    if g:cyfolds_start_in_manual_method == 1
        call DelayManualMethod()
    endif
endfunction

augroup cyfolds_buf_new_init
    " Using BufWinEnter, but BufEnter event seems to work, too; not sure which
    " is best or if it matters.  BufNew and BufAdd don't work.
    autocmd!
    "autocmd BufEnter *.py :call CyfoldsBufEnterInit()
    "autocmd BufEnter *.pyx :call CyfoldsBufEnterInit()
    autocmd BufWinEnter *.py :call CyfoldsBufEnterInit()
    autocmd BufWinEnter *.pyx :call CyfoldsBufEnterInit()
augroup END


python3 << ----------------------- PythonCode ----------------------------------
"""Python initialization code.  Import the function get_foldlevel."""
import sys
from os.path import normpath, join
import vim

# Put vim python3 directory on sys.path so the plugin can be imported.
vimhome = vim.eval("vimhome")
cyfolds_fold_keywords = vim.eval("cyfolds_fold_keywords")
python_root_dir = normpath(join(vimhome, 'python3'))
sys.path.insert(0, python_root_dir)

from cyfolds import get_foldlevel, delete_buffer_cache, setup_regex_pattern
setup_regex_pattern(cyfolds_fold_keywords)
----------------------- PythonCode ----------------------------------


" ==============================================================================
" ==== Define the function GetPythonFoldViaCython, set as foldexpr. ============
" ==============================================================================

function! GetPythonFoldViaCython(lnum)
    " This function is evaluated for each line and returns the folding level.
    " https://candidtim.github.io/vim/2017/08/11/write-vim-plugin-in-python.html
    " How to return Python values back to vim: https://stackoverflow.com/questions/17656320/

python3 << ----------------------- PythonCode ----------------------------------
"""Python code that calls the Cython function get_foldlevel and returns the
foldlevel in the global variable pyfoldlevel."""

# Set some Python variables from vim ones, to pass as args to get_foldlevel.
# Make sure the arguments to get_foldlevel are all ints.
lnum = int(vim.eval("a:lnum"))
shiftwidth = int(vim.eval("&shiftwidth"))
foldnestmax = int(vim.eval("&foldnestmax"))
cur_buffer_num = int(vim.eval("bufnr('%')"))
lines_of_module_docstrings = int(vim.eval("g:cyfolds_lines_of_module_docstrings"))
lines_of_fun_and_class_docstrings = int(vim.eval("g:cyfolds_lines_of_fun_and_class_docstrings"))

hash_for_changes = int(vim.eval("g:cyfolds_hash_for_changes"))
if hash_for_changes:
    cur_undo_sequence = -1 # Used like None.
else:
    cur_undo_sequence = int(vim.eval("undotree().seq_cur"))

# Call the Cython function to do the computation.
computed_foldlevel = get_foldlevel(lnum, cur_buffer_num, cur_undo_sequence,
                                   foldnestmax, shiftwidth, lines_of_module_docstrings,
                                   lines_of_fun_and_class_docstrings)

# Set the return value as a global vim variable, to pass it back to vim.
vim.command("let g:pyfoldlevel = {}".format(computed_foldlevel))
----------------------- PythonCode ----------------------------------

    return g:pyfoldlevel

endfunction


function! DeleteBufferCache(buffer_num)
" Free the cache memory when a buffer is deleted.
python3 << ----------------------- PythonCode ----------------------------------
buffer_num = int(vim.eval("a:buffer_num"))
delete_buffer_cache(buffer_num)
----------------------- PythonCode ----------------------------------
endfunction

" Call the delete function when the BufDelete event happens.
augroup cyfolds_delete_buffer_cache
    autocmd!
    autocmd BufDelete *.py call DeleteBufferCache(expand('<abuf>'))
    autocmd BufDelete *.pyx call DeleteBufferCache(expand('<abuf>'))
augroup END


" ==============================================================================
" ==== Turn off fold updating in insert mode, and update after TextChanged.  ===
" ==============================================================================

augroup cyfolds_unset_folding_in_insert_mode
    autocmd!
    "autocmd InsertEnter *.py setlocal foldmethod=marker " Bad: opens all folds.
    autocmd InsertEnter *.py if b:suppress_insert_mode_switching == 0 | 
                \ let b:oldfoldmethod = &l:foldmethod | setlocal foldmethod=manual | endif
    autocmd InsertLeave *.py if b:suppress_insert_mode_switching == 0 |
                \ let &l:foldmethod = b:oldfoldmethod  | endif

    autocmd InsertEnter *.pyx if b:suppress_insert_mode_switching == 0 | 
                \ let b:oldfoldmethod = &l:foldmethod | setlocal foldmethod=manual | endif
    autocmd InsertLeave *.pyx if b:suppress_insert_mode_switching == 0 |
                \ let &l:foldmethod = b:oldfoldmethod  | endif
augroup END


" ==============================================================================
" ==== Define function to force a foldupdate.  =================================
" ==============================================================================

function! DelayManualMethod() abort
    let timer=timer_start(500, { timer -> execute('setlocal foldmethod=manual') })
    "let timer=timer_start(100, { timer -> execute("let &l:foldmethod = b:update_saved_foldmethod") })
endfunction

function! CyfoldsForceFoldUpdate()
    " Force a fold update.  Unlike zx and zX this does not change the
    " open/closed state of any of the folds.  Can be mapped to a key like 'x,'
    let b:update_saved_foldmethod = &l:foldmethod
    setlocal foldmethod=manual
    if b:update_saved_foldmethod != 'manual' " All methods except manual update folds.
        let &l:foldmethod = b:update_saved_foldmethod
    else
       setlocal foldmethod=expr
       " I had restore to manual mode with a delayed timer command in order
       " for the change to expr method above to register with vim and invoke
       " its side-effect of updating all the folds.  Just setting to manual
       " here does not work.
       "doautocmd <nomodeline> cyfolds_set_manual_method User
       let timer=timer_start(500, { timer -> execute('setlocal foldmethod=manual') })
    endif
endfunction


" ==============================================================================
" ==== Define some general functions. ==========================================
" ==============================================================================

function! CyfoldsToggleManualFolds()
    " Toggle folding method between current one and manual.  Useful when
    " editing a lot and the slight delay on leaving insert mode becomes annoying.
    if &l:foldmethod != 'manual'
        setlocal foldmethod=manual
    else
        setlocal foldmethod=expr
        call CyfoldsForceFoldUpdate()
    endif
    echom "foldmethod=" . &l:foldmethod
endfunction


function! CyfoldsSetFoldKeywords(keyword_str)
   " Dynamically assign the folding keywords to those on the string `keyword_str`.
   let g:cyfolds_fold_keywords = a:keyword_str
python3 << ----------------------- PythonCode ----------------------------------
cyfolds_fold_keywords = vim.eval("a:keyword_str")
setup_regex_pattern(cyfolds_fold_keywords)
----------------------- PythonCode ----------------------------------
   call CyfoldsForceFoldUpdate()
endfunction


" ==============================================================================
" ==== Modify foldline to look good with folded Python. ========================
" ==============================================================================

set foldtext=CyfoldsFoldText()
function! CyfoldsFoldText()
    let num_lines = v:foldend - v:foldstart + 1
    let line = getline(v:foldstart)
    let line_indent = indent(v:foldstart-1)
    let sub = substitute(line, '/\*\|\*/\|{{{\d\=', '', 'g')
    return repeat(' ', line_indent) . '+---- ' . num_lines . ' lines ' . v:folddashes
endfunction


" Redefine search, maybe open:
" https://stackoverflow.com/questions/54657330/how-to-override-redefine-vim-search-command
"
" something like :g/egg/foldopen
" https://stackoverflow.com/questions/18805584/how-to-open-all-the-folds-containing-a-search-pattern-at-the-same-time

