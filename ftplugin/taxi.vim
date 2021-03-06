" Set the omnifunc to be able to complete the aliases via <ctrl-x> <ctrl-o>
set omnifunc=TaxiAliases
set completeopt+=longest
let s:pat = '^\([a-zA-Z0-9_?]\+\)\s\+\([0-9:?-]\+\)\s\+\(.*\)$'
" TODO is this a good cache location?
let s:cache_file = $HOME."/.local/share/taxi/taxi_aliases"

autocmd BufNewFile,BufRead *.tks :call TaxiAssmbleAliases()
autocmd BufWritePost *.tks :call s:taxi_balance()
autocmd QuitPre      <buffer> :call s:taxi_balance_close()
autocmd BufWritePre  *.tks :call TaxiFormatFile()
autocmd InsertEnter  <buffer> :call TaxiInsertEnter()

let s:aliases = []
let s:aliases_raw = ""
let s:is_closing = 0


" TODO document and unclutter these callbacks
" TODO add some test for vim > 8
fun! s:nvim_process_aliases(job_id, data, event)
    call s:process_aliases(a:data)
endfun


fun! s:vim_process_aliases(channel, msg)
    let aliases = split(a:msg, "\n")
    call s:process_aliases(aliases)
endfun

fun! s:process_aliases(data)
    " Gather the aliases
    for alias in a:data
        if alias != ''
            let parts = split(alias)
            if len(parts) > 2
                let alias = parts[1]
                let text = join(parts[3:], ' ')
                let value = [alias, text]

                if index(s:aliases, value) == -1
                    call add(s:aliases, value)
                endif
            endif
        endif
    endfor
endfun

fun! s:cache_aliases(...)
    let cache_aliases = []
    for alias in s:aliases
        call add(cache_aliases, join(alias, "|"))
    endfor
    let directory = fnamemodify(s:cache_file, ":p:h")
    if !isdirectory(directory)
        call mkdir(directory)
    endif
    call writefile(cache_aliases,  s:cache_file)
endfun

fun! s:nvim_update_handler(job_id, data, event) dict
    let alias_callbacks = {
                \ 'on_stdout': function('s:nvim_process_aliases'),
                \ 'on_exit': function('s:cache_aliases')
                \ }
    " When taxi update is done, run taxi alias
    call jobstart(['taxi', 'alias'], alias_callbacks)
endfun

fun! s:vim_update_handler(channel, msg)
    let alias_callbacks = {
                \ 'out_cb': function('s:vim_process_aliases'),
                \ 'exit_cb': function('s:cache_aliases')
                \ }
    call job_start(['taxi', 'alias'], alias_callbacks)
endfun

fun! s:taxi_read_aliases()
    if filereadable(s:cache_file)
        let s:aliases = []
        let cached_aliases = readfile(s:cache_file)
        for alias in cached_aliases
            let parts = split(alias, "|")
            if len(parts) > 1
                call add(s:aliases, [parts[0], parts[1]])
            endif
        endfor
    endif
endfun

fun! TaxiAssmbleAliases()
    call s:taxi_read_aliases()
    " Run the taxi update
    if has('nvim')
        let s:update_callbacks = {
                    \    'on_exit': function('s:nvim_update_handler')
                    \ }

        call jobstart(['taxi', 'update'], s:update_callbacks)
    else
        let s:update_callbacks = {
                    \    'exit_cb': function('s:vim_update_handler')
                    \ }

        call job_start(['taxi', 'update'], s:update_callbacks)
    endif
endfun


fun! TaxiAliases(findstart, base)
    " Complete string under the cursor to the aliases available in taxi
    if a:findstart
        let line = getline('.')
        let start = col('.') - 1
        while start > 0 && line[start - 1 ] =~ '\w'
            let start -= 1
        endwhile
        return start
    else
        let res = []
        for alias in s:aliases
            if alias[0] =~ '^' . a:base
                call add(res, { 'word': alias[0], 'menu': alias[1] })
            endif
        endfor
        return res
    endif
endfun


fun! s:taxi_balance()
    " Create a scratch window below that contains the total line
    " of the taxi balance output
    if s:is_closing
        return
    endif

    let winnr = bufwinnr('^_taxibalance$')
    if ( winnr >  0 )
        execute winnr . 'wincmd w'
        execute 'normal ggdG'
    else
        setl splitbelow
        5new _taxibalance
        setlocal buftype=nofile bufhidden=wipe nobuflisted noswapfile nowrap
    endif

    let result = "Could not read the balance"
    let balance = systemlist('taxi zebra balance')

    call append(0, balance)
    wincmd k
endfun

fun! s:taxi_balance_close()
    let s:is_closing = 1
    " Close the balance scratch window
    let winnr = bufwinnr('^_taxibalance$')
    if ( winnr >  0 )
        execute winnr . 'wincmd w'
        execute 'wincmd q'
    endif
endfun


fun! s:str_pad(str, len)
    " Right pad a string with zeroes
    " Left pad it when it starts with -
    let indent = repeat(' ', 4)
    let str_len = len(a:str)
    let diff = a:len - str_len
    let space = repeat(' ', diff)

    if a:str[0] == "-"
        return space . a:str . indent
    else
        return a:str . space . indent
    endif
endfun

fun! s:taxi_format_line(lnum, col_sizes)
    " Format a line in taxi
    let line = getline(a:lnum)
    let parts = matchlist(line, s:pat)
    let alias = s:str_pad(parts[1], a:col_sizes[0])
    let time  = s:str_pad(parts[2], a:col_sizes[1])

    call setline(a:lnum, alias . time . parts[3])
endfun

fun! TaxiFormatFile()
    " Format the taxi file
    let data_lines = []
    let col_sizes = [0, 0, 0]
    for line_nr in range(1, line('$'))
        let line = getline(line_nr)
        let parts = matchlist(line, s:pat)
        if len(parts) > 0
            call add(data_lines, line_nr)
            for i in range(1, len(parts) - 1)
                let idx = i - 1
                if len(parts[i]) > 0
                    let col_sizes[idx] = max([col_sizes[idx], len(parts[i])])
                endif
            endfor
        endif
    endfor

    for line in data_lines
        call s:taxi_format_line(line, col_sizes)
    endfor
endfun

fun! TaxiInsertEnter()
    if col('.') == 1
        call feedkeys("\<c-x>\<c-o>", 'n')
    endif
endfun

" Call the function at least once when the script is loaded
call TaxiAssmbleAliases()
