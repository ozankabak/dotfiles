" Plugins: {{{
call plug#begin() " Initialize the Plugin manager.
Plug 'wincent/terminus' " Play well with TMux, support mouse, change cursor etc.
Plug 'ntpeters/vim-better-whitespace' " Whitespace highlighting and trimming.
Plug 'myusuf3/numbers.vim' " Easy switching between relative/absolute line numbers.
Plug 'tpope/vim-surround' " Easy delimiter (parenthesis etc.) manipulation.
Plug 'tpope/vim-commentary' " Easy (un)commenting.
Plug 'flazz/vim-colorschemes' " Color schemes.
Plug 'sjl/gundo.vim', { 'on' : 'GundoToggle' } " Enhanced undo functionality.
Plug 'qpkorr/vim-bufkill' " Delete/wipeout buffers without affecting split panes.
Plug 'junegunn/vim-easy-align', { 'on' : '<Plug>(EasyAlign)' } " Easy alignment.
Plug 'Raimondi/delimitMate' " Automatic matching of delimiters, parenthesis etc.
Plug 'terryma/vim-multiple-cursors' " Support multiple cursors, a la Sublime Text.
Plug 'nathanaelkane/vim-indent-guides' " Show visual indentation markers.
Plug 'vim-airline/vim-airline' " Make status line play well other plugins.
Plug 'vim-airline/vim-airline-themes' " Status line themes.
Plug 'ludovicchabant/vim-gutentags' " Automatic tag generation and syntax highlighting.
Plug 'scrooloose/nerdtree', { 'on' : 'NERDTreeToggle' } " Browse files within VIM.
Plug 'scrooloose/syntastic' " Syntax checking.
Plug 'majutsushi/tagbar', { 'on' : 'TagbarToggle' } " Ctags-based object explorer.
Plug 'Rip-Rip/clang_complete' " C/C++ auto-completion via Clang.
Plug 'rhysd/vim-clang-format', { 'on' : 'ClangFormat' } " C/C++ auto-formatting.
Plug 'ervandew/supertab' " Use tab for auto-completion.
Plug 'Shougo/denite.nvim' " Search files, buffers, content etc.
Plug 'Shougo/neomru.vim' " Extend search to support MRU files.
Plug 'davidhalter/jedi-vim' " Python auto-completion via Jedi.
Plug 'idanarye/vim-vebugger', { 'on' : 'VBGstartGDB',
                              \ 'branch' : 'develop' } " IDE-like debugging.
Plug 'ryanoasis/vim-devicons' " Fancy icons!
Plug 'mhinz/vim-startify' " Change the splash screen to list MRU files, sessions...
call plug#end() " Launch the specified plugins.
" }}}

" Functions: {{{
function! s:IsMac()
    return has("Unix") && system("uname") == "Darwin\n"
endfunction

function! s:WriteVariable(var_name,file_name)
    call writefile(["let " . a:var_name . "='" . eval(a:var_name) . "'"], a:file_name)
endfunction

function! s:PaneSwitch(wcmd,system_command)
    let prev_winnr = winnr()
    execute "wincmd " . a:wcmd
    if winnr() == prev_winnr
        " If we are at the boundary, fall back to 'system_command'.
        call system(a:system_command)
    endif
endfunction
" }}}

" Settings: {{{
colorscheme badwolf
syntax enable " Enable syntax highlighting.
set encoding=utf-8 " Always default to using UTF-8 encoding.
set tabstop=4 " Number of spaces used to display tabs.
set expandtab " Substitute spaces for tabs.
set softtabstop=4 " Number of spaces substituted for tabs while typing.
set shiftwidth=4 " Number of spaces substituted for tabs during auto-indent.
set number " Show line numbers.
set showcmd " Show last command in bottom bar.
set cursorline " Highlight current line.
set autoindent " For unrecognized file types, use basic indentation.
set wildmenu " Turn on graphical auto-completion for commands.
set wildmode=longest:full,full " Graphical auto-completion settings for commands.
set lazyredraw " Turn off eager screen redraws. Might increase speed in some cases.
set showmatch " Highlight matching parenthesis.
set incsearch " Turn on incremental search (i.e. search as user types).
set hlsearch " Highlight matches when searching.
set foldenable " Enable folding.
set foldmethod=indent " Fold based on indentation.
set foldlevelstart=10   " When opening a file, fold content having a certain depth.
set foldnestmax=10 " Maximum fold nesting level.
set backspace=indent,eol,start " Make sure backspace always erases.
set colorcolumn=80 " Draw a vertical line at the 80-column mark.
set splitbelow " New horizontally-split panes spawn under the current pane.
set splitright " New vertically-split panes spawn next to the current pane.
set clipboard=unnamed " Use system clipboard.
set hidden " Do not abandon buffers when hidden.
set completeopt=longest,menuone " Make auto-completion progress one step at a time.
set title " Set the terminal title to show useful information.
set titleold= " Inhibit the useless 'Thanks for flying Vim' title.
set laststatus=2 " Always display status lines, even for a single (the last) pane.
set modelines=2 " Only check the last two lines of files for comment-instructions.
set backup " Turn back-ups on.
set writebackup " Always trigger a back-up before overwriting a file.
set backupdir=~/.vim-tmp,~/.tmp,~/tmp,/var/tmp,/tmp " Folders to use for back-ups.
set directory=~/.vim-tmp,~/.tmp,~/tmp,/var/tmp,/tmp " Same, for swap files.
set backupskip=/tmp/*,/private/tmp/* " Do not back up temporary files.
" These settings are handled by the Plugin Terminus:
"set autoread " Reload files after running shell commands from within VIM.
"set mouse=a " Enable mouse, make sure line numbers are not copied.
filetype plugin indent on " Specialize indentation logic for distinct file types.
" }}}

" Constants: {{{
let s:sidebar_width = 31
let s:horizontalbar_height = 12
" }}}

" Numbers: {{{
let g:enable_numbers = 0
" }}}

" BufKill: {{{
let g:BufKillCreateMappings = 0
" }}}

" EasyAlign: {{{
xmap ga <Plug>(EasyAlign)
nmap ga <Plug>(EasyAlign)
" }}}

" DelimitMate: {{{
let g:delimitMate_expand_space = 1
let g:delimitMate_expand_cr = 1
let g:delimitMate_jump_expansion = 1
" }}}

" IndentGuides: {{{
let g:indent_guides_enable_on_vim_startup = 1
let g:indent_guides_start_level = 2
let g:indent_guides_guide_size = 1
let g:indent_guides_auto_colors = 0
hi IndentGuidesOdd ctermbg = grey
hi IndentGuidesEven ctermbg = darkgrey
" }}}

" Airline: {{{
let g:airline_powerline_fonts = 1
let g:airline#extensions#tabline#enabled = 1
let g:airline#extensions#tabline#show_buffers = 1
let g:airline#extensions#tabline#buffer_nr_show = 1
" }}}

" NERDTree: {{{
let g:NERDTreeWinSize = s:sidebar_width
" }}}

" Syntastic: {{{
let g:syntastic_cpp_checkers = ["clang_check"]
let g:syntastic_always_populate_loc_list = 1
let g:syntastic_auto_loc_list = 1
let g:syntastic_loc_list_height = 3
let g:syntastic_check_on_open = 0
let g:syntastic_check_on_wq = 0
let g:syntastic_cpp_config_file = '~/.syntastic_includes'
let g:syntastic_mode_map = {'mode':'passive'}
let g:syntastic_error_symbol = "CE"
let g:syntastic_warning_symbol = "CW"
let g:syntastic_style_error_symbol = "SE"
let g:syntastic_style_warning_symbol = "SW"
" }}}

" Tagbar: {{{
let g:tagbar_width = s:sidebar_width
" }}}

" Clang: {{{
if s:IsMac()
    let file_name = $HOME . "/.vim_libclang"
    if filereadable(file_name)
        exec "source " . file_name
    else
        let libclang_location = system("mdfind -name libclang.dylib")
        let g:clang_library_path = fnamemodify(libclang_location, ":p:h")
        call s:WriteVariable("g:clang_library_path", file_name)
    endif
endif
let g:clang_complete_auto = 0
let g:clang_auto_select = 1
let g:clang_snippets = 1
let g:clang_user_options = "-std=c++17"
" }}}

" Supertab: {{{
" Make tabs perform user-defined (i.e. clang-based) auto-completion when sensible:
let g:SuperTabDefaultCompletionType = "context"
let g:SuperTabContextDefaultCompletionType = "<C-x><C-p>"
let g:SuperTabCompletionContexts = ['s:ContextText', 's:ContextDiscover']
let g:SuperTabContextDiscoverDiscovery = ["&completefunc:<C-x><C-u>",
                                         \"&omnifunc:<C-x><C-o>"]
let g:SuperTabLongestEnhanced = 1
let g:SuperTabLongestHighlight = 1
" }}}

" Denite: {{{
if executable('ag')
    " Use 'The Silver Searcher', if available.
    call denite#custom#var('file_rec, grep', 'command',
                          \['ag', '--nocolor', '--nogroup', '--line-numbers',
                           \'--silent', '--all-text', '--smart-case'])
else
    call denite#custom#var('file_rec, grep', 'command',
                          \['grep', '-H', '-I', '--ignore-case', '--line-number',
                          \'--no-messages'])
endif
call denite#custom#source('file, file_rec, line, grep', 'matchers', ['matcher/regexp'])
" }}}

" Jedi: {{{
let g:jedi#auto_vim_configuration = 0
let g:jedi#show_call_signatures = 0
let g:jedi#popup_on_dot = 0
let g:jedi#documentation_command = "<leader>K"
" }}}

" Vebugger: {{{
let g:vebugger_leader = "]"
" }}}

" Startify: {{{
let g:startify_session_dir = "~/.vim/sessions"
let g:startify_custom_header = [
\'   ___                             (")                    __   __   ___   __  __ ',
\'  / _ \     ___   __ _    _ _       \|     ___      o O O \ \ / /  |_ _| |  \/  |',
\' | (_) |   |_ /  / _` |  | '' \            (_-<     o       \ V /    | |  | |\/| |',
\'  \___/   _/__|  \__,_|  |_||_|   _____   /__/_   TS__[O]  _\_/_   |___| |_|__|_|',
\'_|"""""|_|"""""|_|"""""|_|"""""|_|     |_|"""""| {======|_| """"|_|"""""|_|"""""|',
\'"`-0-0-''"`-0-0-''"`-0-0-''"`-0-0-''"`-0-0-''"`-0-0-''./o--000''"`-0-0-''"`-0-0-''"`-0-0-''',
\'',
\''
\]
" }}}

" Remaps: {{{
" Move vertically according to visual lines; i.e. take wrapping into account:
noremap j gj
noremap k gk
" Easier page up/down keys:
noremap J <C-d>
noremap K <C-u>
" Easier beginning/end of line keys:
noremap H ^
noremap L $
if exists('$TMUX')
    " Make switches between VIM windows and TMux panes seamless:
    noremap <silent> <C-h> :call <SID>PaneSwitch('h', 'tmux select-pane -L')<CR>
    noremap <silent> <C-j> :call <SID>PaneSwitch('j', 'tmux select-pane -D')<CR>
    noremap <silent> <C-k> :call <SID>PaneSwitch('k', 'tmux select-pane -U')<CR>
    noremap <silent> <C-l> :call <SID>PaneSwitch('l', 'tmux select-pane -R')<CR>
else
    " Make switches between VIM windows easier:
    noremap <C-h> <C-w>h
    noremap <C-j> <C-w>j
    noremap <C-k> <C-w>k
    noremap <C-l> <C-w>l
endif
" }}}

" Shortcuts: {{{
" Switch between relative/absolute line numbers:
nnoremap <leader>n :NumbersToggle<CR>
" Easier buffer-deleting without messing up split-panes:
nnoremap <leader>q :BW<CR>
" Shortcut to turn off search-match highlighting:
nnoremap <leader><space> :nohlsearch<CR>
" Shortcut to open/close folds:
nnoremap <space> za
" Shortcut to trigger Gundo:
nnoremap <leader>gt :GundoToggle<CR>
" Shortcuts to save/load sessions:
nnoremap <leader>ls :SLoad<CR>
nnoremap <leader>ss :SSave!<CR>
" Shortcut to trigger NERDTree:
nnoremap <leader><Tab> :NERDTreeToggle<CR>
" Shortcuts to launch/hide Syntastic's syntax checker:
nnoremap <leader>sc :SyntasticCheck<CR>
nnoremap <leader>sr :SyntasticReset<CR>
" Shortcut to display the tag bar:
nnoremap <leader>tt :TagbarToggle<CR>
" Shortcuts to jump to/from C/C++ function definitions:
let g:clang_jumpto_declaration_key = "<leader>d"
let g:clang_jumpto_back_key = "<leader>p"
" Shortcuts to format C/C++ sources via clang-format:
nnoremap <leader>cf :ClangFormat<CR>
vnoremap <leader>cf :ClangFormat<CR>
" Shortcuts to launch Denite (i.e. VIM's Spotlight equivalent):
nnoremap <leader>dl :Denite line -winheight=10<CR>
nnoremap <leader>db :Denite buffer -winheright=10<CR>
nnoremap <leader>df :Denite file_rec -winheight=10<CR>
nnoremap <leader>dm :Denite file_mru -winheight=10<CR>
" Movement within the Denite window:
call denite#custom#map('insert', '<Down>', '<denite:move_to_next_line>', 'noremap')
call denite#custom#map('insert', '<Up>', '<denite:move_to_previous_line>', 'noremap')
" }}}

" Events: {{{
" Recognize C++ include files:
au BufRead,BufNewFile *.ihpp,*.icc,*.icpp set filetype=cpp
" Strip trailing whitespace after saves:
au FileType c,cpp,cs,java setlocal commentstring=//\ %s
au BufWritePre * StripWhitespace
" }}}

" vim:foldmethod=marker:foldlevel=1

