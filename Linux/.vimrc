" Allow Ctrl+l to move right and Ctrl+h to move left in insert mode
inoremap <C-l> <Right>
inoremap <C-h> <Left>

" Enable syntax highlighting
syntax on
" Show absolute line numbers
set number
" Show relative line numbers (useful for motions like 5j or 10k)
set relativenumber
" Set tab width to 4 spaces
set tabstop=4
" Set indent width to 4 spaces
set shiftwidth=4
" Convert tabs to spaces
set expandtab
" Display current mode (INSERT, VISUAL, etc.)
set showmode

" For xterm and rxvt terminal emulators
if &term =~ 'xterm' || &term =~ 'rxvt'
  " Change cursor to block in normal mode
  autocmd VimEnter,InsertLeave * silent execute "!echo -ne '\e[2 q'"
  " Change cursor to vertical bar in insert mode
  autocmd InsertEnter * silent execute "!echo -ne '\e[6 q'"
  " Reset cursor to default shape on exit
  autocmd VimLeave * silent execute "!echo -ne '\e[ q'"
endif

" For Windows terminal
if &term =~ 'win32'
  " Change cursor to block in normal mode
  let &t_EI = "\e[2 q"
  " Change cursor to vertical bar in insert mode
  let &t_SI = "\e[6 q"
endif

" Disable all bells (audible and visual)
set noerrorbells    " Disable audible error beeps
set novisualbell    " Disable visual bell (screen flash)
set t_vb=           " Clear the visual bell terminal code (prevents screen flash even if visualbell is enabled)
set belloff=all     " Disable all bell triggers (errors, warnings, etc.)
