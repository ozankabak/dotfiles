" Functions: {{{
function! s:PaneSwitch(wcmd, system_command)
    let prev_winnr = winnr()
    execute "wincmd " . a:wcmd
    if winnr() == prev_winnr
        " If we are at the boundary, fall back to 'system_command'.
        silent call system(a:system_command)
    endif
endfunction
" }}}

" Plugins: {{{
if empty(glob('~/.vim/autoload/plug.vim'))
    let s:initializing_flag = 1
    silent !curl -fLo ~/.vim/autoload/plug.vim --create-dirs
        \ https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim
    autocmd VimEnter * PlugInstall --sync | source ${MYVIMRC}
else
    let s:initializing_flag = 0
endif

call plug#begin() " Initialize the Plugin manager.
Plug 'wincent/terminus' " Play well with TMux, support mouse, change cursor etc.
Plug 'ntpeters/vim-better-whitespace' " Whitespace highlighting and trimming.
Plug 'myusuf3/numbers.vim' " Easy switching between relative/absolute line numbers.
Plug 'tpope/vim-surround' " Easy delimiter (parenthesis etc.) manipulation.
Plug 'tpope/vim-commentary' " Easy comment handling.
Plug 'flazz/vim-colorschemes' " Color schemes.
Plug 'sjl/gundo.vim', { 'on' : 'GundoToggle' } " Enhanced undo functionality.
Plug 'qpkorr/vim-bufkill' " Delete/wipeout buffers without affecting split panes.
Plug 'junegunn/vim-easy-align', { 'on' : '<Plug>(EasyAlign)' } " Easy alignment.
Plug 'jiangmiao/auto-pairs' " Automatic matching of delimiters, parenthesis etc.
Plug 'terryma/vim-multiple-cursors' " Support multiple cursors, a la Sublime Text.
Plug 'Yggdroot/indentLine' " Show visual indentation markers.
Plug 'Vimjas/vim-python-pep8-indent' " Better auto-indent behavior for Python.
Plug 'vim-airline/vim-airline' " Make status line play well other plugins.
Plug 'vim-airline/vim-airline-themes' " Status line themes.
Plug 'ludovicchabant/vim-gutentags' " Automatic tag generation and syntax highlighting.
Plug 'scrooloose/nerdtree', { 'on' : 'NERDTreeToggle' } " Browse files within VIM.
let g:ale_completion_enabled = 1 " This variable needs to be set before the next line.
Plug 'w0rp/ale' " Asynchronous syntax checking and auto-completion via LSP servers.
Plug 'majutsushi/tagbar', { 'on' : 'TagbarToggle' } " Ctags-based object explorer.
Plug 'junegunn/fzf', { 'dir': '~/.fzf', 'do': './install --all' } " Fuzzy Finder.
Plug 'junegunn/fzf.vim' " Search files, buffers, content etc.
Plug 'airblade/vim-gitgutter' " Support version control via git.
Plug 'ryanoasis/vim-devicons' " Fancy icons!
Plug 'mhinz/vim-startify' " Change the splash screen to list MRU files, sessions...
call plug#end() " Launch the specified plugins.
" }}}

" Settings: {{{
if s:initializing_flag == 0
    colorscheme badwolf
endif
syntax enable " Enable syntax highlighting.
set syn=auto " Use automatic mode for syntax highlighting.
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
" Original completion settings:
" set completeopt=longest,menuone " Make auto-completion progress one step at a time.
set completeopt=longest,menuone,noselect,noinsert " Completion settings for ale
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

" AutoPairs: {{{
" }}}

" IndentLine: {{{
let g:indentLine_char = '┊'
autocmd Filetype json :IndentLinesDisable
" }}}

" Airline: {{{
let g:airline_powerline_fonts = 1
let g:airline#extensions#tabline#enabled = 1
let g:airline#extensions#tabline#show_buffers = 1
let g:airline#extensions#tabline#buffer_nr_show = 1
" }}}

" Gutentags: {{{
let g:gutentags_cache_dir = '~/tmp/tags'
" }}}

" NERDTree: {{{
let g:NERDTreeWinSize = s:sidebar_width
" }}}

" ALE: {{{
if executable('clang')
    let g:ale_linters = { 'cpp' : ['clang'] }
elseif executable('gcc')
    let g:ale_linters = { 'cpp' : ['gcc'] }
endif

if executable('pyls')
    let g:ale_linters.python = ['pyls']
    let g:ale_python_pyls_config = {
    \  'pyls': {
    \    'plugins': {
    \      'pycodestyle': {
    \        'enabled': v:true
    \      },
    \      'pyflakes': {
    \        'enabled': v:false
    \      }
    \    }
    \  }}
endif

if executable('clang-format')
    let g:ale_fixers = { 'cpp' : ['clang-format'] }
endif

let g:ale_completion_delay = 25
let g:ale_completion_max_suggestions = 10
let g:ale_sign_error = '!E'
let g:ale_sign_warning = '!W'
let g:ale_sign_style_error = '?E'
let g:ale_sign_style_warning = '?W'
let g:ale_warn_about_trailing_whitespace = 0
let g:ale_warn_about_trailing_blank_lines = 0
let g:ale_cpp_clang_options = '-std=c++17 -Wall'
let g:ale_cpp_gcc_options = '-std=c++17 -Wall'
let g:ale_c_parse_compile_commands = 1
let g:ale_c_parse_makefile = 1
" Use 'tab' key to cycle through completions. Arrow keys also work.
inoremap <expr> <Tab> pumvisible() ? "\<C-n>" : "\<Tab>"
inoremap <expr> <S-Tab> pumvisible() ? "\<C-p>" : "\<S-Tab>"
inoremap <expr> <CR> pumvisible() ? "\<C-y>" : "\<CR>"
" }}}

" Tagbar: {{{
let g:tagbar_width = s:sidebar_width
let g:tagbar_map_togglefold = '<Space>'
let g:tagbar_map_showproto = '<leader>p'
" }}}

" FZF: {{{
let g:fzf_layout = { 'down': '~20%' }
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
if exists('${TMUX}')
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
" Easier switching between buffers:
nnoremap <leader>] :bnext<CR>
nnoremap <leader>[ :bprevious<CR>
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
" Shortcuts to cycle through linting errors and warnings:
nmap <silent> <leader>ef <Plug>(ale_previous_wrap)
nmap <silent> <leader>er <Plug>(ale_next_wrap)
nmap <silent> <leader>jd <Plug>(ale_go_to_definition)
nmap <silent> <leader>ff <Plug>(ale_fix)
nmap <silent> <leader>fl <Plug>(ale_lint)
" Shortcut to display the tag bar:
nnoremap <leader>tt :TagbarToggle<CR>
" }}}

" Events: {{{
" Recognize C++ include files:
au BufRead,BufNewFile *.ihpp,*.icc,*.icpp set filetype=cpp
" Strip trailing whitespace after saves:
au BufWritePre * StripWhitespace
" Use preferable commenting tokens:
au FileType c,cpp,cs,java setlocal commentstring=//\ %s
au FileType tf setlocal commentstring=#\ %s
" Use two-space tabs in YAML files:
au FileType yaml,yml setlocal tabstop=2 softtabstop=2 shiftwidth=2
" }}}

" vim:foldmethod=marker:foldlevel=1

