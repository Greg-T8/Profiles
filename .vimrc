inoremap <C-l> <Right>
inoremap <C-h> <Left>
syntax on
set number
set relativenumber
set tabstop=4
set shiftwidth=4
set expandtab

if &term =~ 'xterm' || &term =~ 'rxvt'
  " Change cursor to block in normal mode
  autocmd VimEnter,InsertLeave * silent execute "!echo -ne '\e[2 q'"
  " Change cursor to underline in insert mode
  autocmd InsertEnter * silent execute "!echo -ne '\e[4 q'"
  " Reset cursor to default shape on exit
  autocmd VimLeave * silent execute "!echo -ne '\e[ q'"
endif

if &term =~ 'win32'
  " Change cursor to block in normal mode
  let &t_EI = "\e[2 q"
  " Change cursor to underline in insert mode
  let &t_SI = "\e[4 q"
endif


" copied from Vim 7.3's mswin.vim:

" CTRL-X and SHIFT-Del are Cut
vnoremap <C-X> "+x
vnoremap <S-Del> "+x

" CTRL-C and CTRL-Insert are Copy
vnoremap <C-C> "+y
vnoremap <C-Insert> "+y

" CTRL-V and SHIFT-Insert are Paste
map <C-V>		"+gP
map <S-Insert>		"+gP
imap <C-V>		<Esc>"+gpa

cmap <C-V>		<C-R>+
cmap <S-Insert>		<C-R>+


imap <S-Insert>		<C-V>
vmap <S-Insert>		<C-V>

" Use CTRL-Q to do what CTRL-V used to do
noremap <C-Q>		<C-V>
" set 'selection', 'selectmode', 'mousemodel' and 'keymodel' for MS-Windows
behave mswin

" backspace and cursor keys wrap to previous/next line
set backspace=indent,eol,start whichwrap+=<,>,[,]

" backspace in Visual mode deletes selection
vnoremap <BS> d

" Use CTRL-S for saving, also in Insert mode
noremap <C-S>		:update<CR>
vnoremap <C-S>		<C-C>:update<CR>
inoremap <C-S>		<C-O>:update<CR>

" CTRL-Z is Undo; not in cmdline though
noremap <C-Z> u
inoremap <C-Z> <C-O>u

" CTRL-Y is Redo (although not repeat); not in cmdline though
noremap <C-Y> <C-R>
inoremap <C-Y> <C-O><C-R>

" CTRL-A is Select all
noremap <C-A> gggH<C-O>G
inoremap <C-A> <C-O>gg<C-O>gH<C-O>G
cnoremap <C-A> <C-C>gggH<C-O>G
onoremap <C-A> <C-C>gggH<C-O>G
snoremap <C-A> <C-C>gggH<C-O>G
xnoremap <C-A> <C-C>ggVG
