" ==============================================================================
" VIM CONFIGURATION
" ==============================================================================
" This configuration provides a customized vi/vim environment with:
" - Visual enhancements (line numbers, status line, color column)
" - Vi mode cursor shapes
" - Improved search and navigation
" - Consistent indentation settings

" ==============================================================================
" LEADER KEY
" ==============================================================================
" Set leader key to spacebar for custom key mappings
let mapleader = " "

" ==============================================================================
" LEADER KEY MAPPINGS
" ==============================================================================
" Save and quit with leader+wq
nnoremap <leader>w :w<CR>
nnoremap <leader>wq :wq<CR>
nnoremap <leader>q :q!<CR>

" ==============================================================================
" INSERT MODE NAVIGATION
" ==============================================================================
" Enable cursor movement in insert mode without leaving insert mode
inoremap <C-l> <Right>              " Ctrl+L: move cursor right
inoremap <C-h> <Left>               " Ctrl+H: move cursor left

" ==============================================================================
" SELECT ALL KEYBINDINGS
" ==============================================================================
" Select all text with Ctrl+A
nnoremap <C-a> ggVG                 " Normal mode: select all text
inoremap <C-a> <Esc>ggVG            " Insert mode: select all text

" ==============================================================================
" VISUAL MODE KEYBINDINGS
" ==============================================================================
" Paste without yanking replaced text (matches Neovim behavior)
xnoremap <leader>p "_dP

" ==============================================================================
" STARTUP BEHAVIOR
" ==============================================================================
" Start in insert mode automatically when vim launches
autocmd VimEnter * startinsert

" ==============================================================================
" COMMAND MODE SHORTCUTS
" ==============================================================================
" Allow :q to quit without saving (behaves like :q!)
cnoreabbrev q q!

" ==============================================================================
" VISUAL SETTINGS
" ==============================================================================
" ------------------------------------------------------------------------------
" Syntax and Display
" ------------------------------------------------------------------------------
syntax on                           " Enable syntax highlighting
colorscheme slate                   " Use slate color scheme
set number                          " Show absolute line numbers
set relativenumber                  " Show relative line numbers for easier motion
set showmode                        " Display current mode (INSERT, VISUAL, etc.)
set scrolloff=8                     " Keep 8 lines visible above/below cursor
set showcmd                         " Show partial command in bottom right

" ------------------------------------------------------------------------------
" Line Wrapping
" ------------------------------------------------------------------------------
set nowrap                          " Don't wrap long lines
set cpoptions+=n                    " Display line breaks in line number column

" ------------------------------------------------------------------------------
" Command-line Completion
" ------------------------------------------------------------------------------
set wildmenu                        " Enhanced command-line completion
set wildmode=longest:full,full      " Completion mode: longest match, then full

" ------------------------------------------------------------------------------
" Status Line Configuration
" ------------------------------------------------------------------------------
set laststatus=2                    " Always show status line
set statusline=%f                   " Filename
set statusline+=\ %m                " Modified flag [+]
set statusline+=\ %r                " Read-only flag [RO]
set statusline+=\ %y                " File type [vim]
set statusline+=%=                  " Switch to right side
set statusline+=%{&fileencoding?&fileencoding:&encoding}  " Encoding
set statusline+=\ [%{&fileformat}]  " File format (unix/dos/mac)
set statusline+=\ [%l:%c]           " Line:column position
set statusline+=\ %p%%              " Percentage through file
set statusline+=\ %L                " Total lines in file

" ------------------------------------------------------------------------------
" Cursor Line (commented out by default)
" ------------------------------------------------------------------------------
" set cursorline                    " Highlight the current line

" ==============================================================================
" SEARCH SETTINGS
" ==============================================================================
set hlsearch                        " Highlight all search matches
set incsearch                       " Show matches as you type
set ignorecase                      " Case-insensitive search by default
set smartcase                       " Case-sensitive if search contains uppercase

" ==============================================================================
" MATCHING BRACKETS
" ==============================================================================
set showmatch                       " Briefly jump to matching bracket when inserted
set matchtime=2                     " Show matching bracket for 0.2 seconds

" ==============================================================================
" VISUAL GUIDES
" ==============================================================================
set colorcolumn=80                  " Show vertical line at column 80

" ==============================================================================
" COLOR CUSTOMIZATION
" ==============================================================================
" ------------------------------------------------------------------------------
" Status Line Colors
" ------------------------------------------------------------------------------
" Subtle gray colors for less distraction
highlight StatusLine cterm=NONE ctermbg=236 ctermfg=250    " Active window status line
highlight StatusLineNC cterm=NONE ctermbg=234 ctermfg=242  " Inactive window status line

" ------------------------------------------------------------------------------
" Color Column
" ------------------------------------------------------------------------------
" Subtle dark gray for column guide
highlight ColorColumn ctermbg=237 guibg=#3a3a3a

" ------------------------------------------------------------------------------
" Line Numbers
" ------------------------------------------------------------------------------
" Dark gray for line numbers, slightly brighter for current line
highlight LineNr ctermfg=244 ctermbg=NONE                  " Regular line numbers
highlight CursorLineNr ctermfg=252 ctermbg=NONE            " Current line number

" ==============================================================================
" INDENTATION SETTINGS
" ==============================================================================
set tabstop=4                       " Display tabs as 4 spaces wide
set shiftwidth=4                    " Use 4 spaces for each indentation level
set expandtab                       " Insert spaces instead of tabs

" ==============================================================================
" CURSOR SHAPE CONFIGURATION
" ==============================================================================
" ------------------------------------------------------------------------------
" xterm and rxvt Terminals
" ------------------------------------------------------------------------------
" Change cursor shape based on mode
if &term =~ 'xterm' || &term =~ 'rxvt'
  " Block cursor in normal mode
  autocmd VimEnter,InsertLeave * silent execute "!echo -ne '\e[2 q'"
  " Vertical bar cursor in insert mode
  autocmd InsertEnter * silent execute "!echo -ne '\e[6 q'"
  " Reset cursor to default on exit
  autocmd VimLeave * silent execute "!echo -ne '\e[ q'"
endif

" ------------------------------------------------------------------------------
" Windows Terminal
" ------------------------------------------------------------------------------
" Use terminal escape codes for cursor shape
if &term =~ 'win32'
  let &t_EI = "\e[2 q"              " Block cursor in normal mode
  let &t_SI = "\e[6 q"              " Vertical bar cursor in insert mode
endif

" ==============================================================================
" BELL CONFIGURATION
" ==============================================================================
" Disable all notification bells (audible and visual)
set noerrorbells                    " No audible beep on errors
set novisualbell                    " No screen flash on errors
set t_vb=                           " Clear visual bell terminal code
set belloff=all                     " Disable all bell triggers

" ==============================================================================
" TIMEOUT SETTINGS
" ==============================================================================
" Reduce delays for key codes and cursor shape changes
set ttimeout                        " Enable timeout on key codes
set ttimeoutlen=10                  " Wait 10ms for key code sequences
set timeoutlen=1000                 " Wait 1000ms for mapped sequences
