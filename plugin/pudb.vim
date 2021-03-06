" File: pudb.vim
" Author: Christophe Simonis, Michael van der Kamp
" Description: Manage pudb breakpoints directly from vim
" Last Modified: March 07, 2020


if exists('g:loaded_pudb_plugin') || &cp
    finish
endif
let g:loaded_pudb_plugin = 1

if !has("pythonx")
    echoerr "vim-pudb requires vim compiled with +python and/or +python3"
    finish
endif

if !has("signs")
    echoerr "vim-pudb requires vim compiled with +signs"
    finish
endif


"
" Load options and set defaults
"
let g:pudb_sign       = get(g:, 'pudb_sign',       'B>')
let g:pudb_highlight  = get(g:, 'pudb_highlight',  'error')
let g:pudb_priority   = get(g:, 'pudb_priority',   100)
let g:pudb_sign_group = get(g:, 'pudb_sign_group', 'pudb_sign_group')

call sign_define('PudbBreakPoint', {
            \   'text':   g:pudb_sign,
            \   'texthl': g:pudb_highlight
            \ })


"
" Loads the pudb breakpoint file and Updates the breakpoint signs for all
" breakpoints in all buffers.
"
function! s:Update()

    " first remove existing signs
    call sign_unplace(g:pudb_sign_group)

pythonx << EOF
import vim
from pudb.settings import load_breakpoints
from pudb import NUM_VERSION

args = () if NUM_VERSION >= (2013, 1) else (None,)

for bp_file, bp_lnum, temp, cond, funcname in load_breakpoints(*args):
    try:
        opts = '{"lnum": %d, "priority": %d}' % (bp_lnum, vim.vars['pudb_priority'])

        # Critical to use vim.eval here instead of vim.vars[] to get sign group
        vim.eval('sign_place(0, "%s", "PudbBreakPoint", "%s", %s)'
                 '' % (vim.eval('g:pudb_sign_group'), bp_file, opts))
    except vim.error:
        # Buffer for the given file isn't loaded.
        continue
EOF

endfunction


"
" Toggles a breakpoint on the current line.
"
function! s:Toggle()

pythonx << EOF
import vim
from pudb.settings import load_breakpoints, save_breakpoints
from pudb import NUM_VERSION
from bdb import Breakpoint

args = () if NUM_VERSION >= (2013, 1) else (None,)
bps = {(bp.file, bp.line): bp
       for bp in map(lambda values: Breakpoint(*values), load_breakpoints(*args))}

filename = vim.eval('expand("%:p")')
row, col = vim.current.window.cursor

bp_key = (filename, row)
if bp_key in bps:
    bps.pop(bp_key)
else:
    bps[bp_key] = Breakpoint(filename, row)

save_breakpoints(bps.values())
EOF

    call s:Update()
endfunction


"
" Edit the condition of a breakpoint on the current line.
" If no such breakpoint exists, creates one.
"
function! s:Edit()

pythonx << EOF
import vim
from pudb.settings import load_breakpoints, save_breakpoints
from pudb import NUM_VERSION
from bdb import Breakpoint

args = () if NUM_VERSION >= (2013, 1) else (None,)
bps = {(bp.file, bp.line): bp
       for bp in map(lambda values: Breakpoint(*values), load_breakpoints(*args))}

filename = vim.eval('expand("%:p")')
row, col = vim.current.window.cursor

bp_key = (filename, row)
if bp_key not in bps:
    bps[bp_key] = Breakpoint(filename, row)
bp = bps[bp_key]

old_cond = '' if bp.cond is None else bp.cond
vim.command('echo "Current condition: %s"' % old_cond)
vim.command('echohl Question')
vim.eval('inputsave()')
bp.cond = vim.eval('input("New Condition: ", "%s")' % old_cond)
vim.eval('inputrestore()')
vim.command('echohl None')

save_breakpoints(bps.values())
EOF

    call s:Update()
endfunction


"
" Clears all pudb breakpoints from all files.
"
function! s:ClearAll()

pythonx << EOF
from pudb.settings import save_breakpoints
save_breakpoints([])
EOF

    call s:Update()
endfunction


"
" Prints a list of all the breakpoints in all files.
" Shows the full file path, line number, and condition of each breakpoint.
"
function! s:List()
    call s:Update()

pythonx << EOF
import vim
from pudb.settings import load_breakpoints
from pudb import NUM_VERSION

vim.command('echomsg "Listing all pudb breakpoints:"')

args = () if NUM_VERSION >= (2013, 1) else (None,)
for bp_file, bp_lnum, temp, cond, funcname in load_breakpoints(*args):
    vim.command('echomsg "%s:%d:%s"' % (
        bp_file, bp_lnum, '' if not bool(cond) else ' %s' % cond
    ))
EOF

endfunction


"
" Calls the given vim command with a list of the breakpoints as strings in
" quickfix format.
"
function! s:PopulateList(list_command)

pythonx << EOF
import vim
from pudb.settings import load_breakpoints
from pudb import NUM_VERSION

qflist = []
args = () if NUM_VERSION >= (2013, 1) else (None,)
for bp_file, bp_lnum, temp, cond, funcname in load_breakpoints(*args):
    try:
        line = vim.eval('getbufline(bufname("%s"), %s)' % (bp_file, bp_lnum))[0]
        if line.strip() == '':
            line = '<blank line>'
    except LookupError:
        line = '<buffer not loaded>'
    qflist.append(':'.join(map(str, [bp_file, bp_lnum, line])))

vim.command('%s %s' % (vim.eval('a:list_command'), qflist))
EOF

endfunction


"
" Populate the quickfix list with the breakpoint locations.
"
function! s:QuickfixList()
    call s:Update()
    call s:PopulateList('cgetexpr')
endfunction


"
" Populate the location list with the breakpoint locations.
"
function! s:LocationList()
    call s:Update()
    call s:PopulateList('lgetexpr')
endfunction


"
" Clear the python line cache for the given file if it has changed
"
function! s:ClearLineCache(filename)
pythonx << EOF
import linecache
import vim
linecache.checkcache(vim.eval('a:filename'))
EOF
endfunction


" Define ex commands for all the above functions so they are user-accessible.
command! PudbClearAll call s:ClearAll()
command! PudbEdit     call s:Edit()
command! PudbList     call s:List()
command! PudbLocList  call s:LocationList()
command! PudbQfList   call s:QuickfixList()
command! PudbToggle   call s:Toggle()
command! PudbUpdate   call s:Update()

command! -nargs=1 -complete=command PudbPopulateList call s:Update() <bar> call s:PopulateList("<args>")


" If we were loaded lazily, update immediately.
if &filetype == 'python'
    call s:Update()
endif


augroup pudb
    " Also update when the file is first read.
    autocmd BufReadPost *.py call s:Update()

    " Force a linecache update after writes so the breakpoints can be parsed
    " correctly.
    autocmd BufWritePost *.py call s:ClearLineCache(expand('%:p'))
augroup end
