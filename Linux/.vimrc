" Navigation in insert mode
" Ctrl+l moves cursor right, Ctrl+h moves cursor left
inoremap <C-l> <Right>
inoremap <C-h> <Left>

" Start in insert mode automatically
autocmd VimEnter * startinsert

" Visual settings
syntax on               " Enable syntax highlighting
set number              " Show line numbers
set relativenumber      " Show relative line numbers for easier motion commands
set showmode            " Display current mode in status line

" Indentation settings
set tabstop=4           " Display tabs as 4 spaces wide
set shiftwidth=4        " Use 4 spaces for each indentation level
set expandtab           " Insert spaces instead of tabs

" Cursor shape settings for xterm and rxvt terminals
if &term =~ 'xterm' || &term =~ 'rxvt'
  " Block cursor in normal mode
  autocmd VimEnter,InsertLeave * silent execute "!echo -ne '\e[2 q'"
  " Vertical bar cursor in insert mode
  autocmd InsertEnter * silent execute "!echo -ne '\e[6 q'"
  " Reset cursor to default on exit
  autocmd VimLeave * silent execute "!echo -ne '\e[ q'"
endif

" Cursor shape settings for Windows Terminal
if &term =~ 'win32'
  " Block cursor in normal mode
  let &t_EI = "\e[2 q"
  " Vertical bar cursor in insert mode
  let &t_SI = "\e[6 q"
endif

" Disable all notification bells
set noerrorbells        " No audible beep on errors
set novisualbell        " No screen flash on errors
set t_vb=               " Clear visual bell terminal code
set belloff=all         " Disable all bell triggers

" Reduce key code delays for faster cursor shape changes
set ttimeout            " Enable timeout on key codes
set ttimeoutlen=10      " Wait 10ms for key code sequences
set timeoutlen=1000     " Wait 1000ms for mapped sequences
