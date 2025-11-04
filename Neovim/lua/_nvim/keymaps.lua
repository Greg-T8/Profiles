-- ==============================================================================
-- NEOVIM KEYMAPS (Native Neovim only, not VSCode)
-- ==============================================================================
-- Additional keybindings specific to native Neovim environment
-- Common keybindings are defined in _common/keymaps.lua

-- ==============================================================================
-- WINDOW NAVIGATION
-- ==============================================================================
-- Navigate between windows using Ctrl+hjkl
vim.keymap.set("n", "<C-h>", "<C-w>h", { desc = "Move to left window", noremap = true, silent = true })
vim.keymap.set("n", "<C-j>", "<C-w>j", { desc = "Move to bottom window", noremap = true, silent = true })
vim.keymap.set("n", "<C-k>", "<C-w>k", { desc = "Move to top window", noremap = true, silent = true })
vim.keymap.set("n", "<C-l>", "<C-w>l", { desc = "Move to right window", noremap = true, silent = true })

-- ==============================================================================
-- WINDOW RESIZING
-- ==============================================================================
-- Resize windows using Ctrl+Arrow keys
vim.keymap.set("n", "<C-Up>", ":resize +2<CR>", { desc = "Increase window height", noremap = true, silent = true })
vim.keymap.set("n", "<C-Down>", ":resize -2<CR>", { desc = "Decrease window height", noremap = true, silent = true })
vim.keymap.set("n", "<C-Left>", ":vertical resize -2<CR>", { desc = "Decrease window width", noremap = true, silent = true })
vim.keymap.set("n", "<C-Right>", ":vertical resize +2<CR>", { desc = "Increase window width", noremap = true, silent = true })

-- ==============================================================================
-- BUFFER NAVIGATION
-- ==============================================================================
-- Navigate between buffers using Shift+hl
vim.keymap.set("n", "<S-l>", ":bnext<CR>", { desc = "Next buffer", noremap = true, silent = true })
vim.keymap.set("n", "<S-h>", ":bprevious<CR>", { desc = "Previous buffer", noremap = true, silent = true })

-- ==============================================================================
-- FILE EXPLORER
-- ==============================================================================
-- Open Neo-tree file explorer
vim.keymap.set("n", "<leader>e", ":Neotree<CR>", { desc = "Open Neotree", noremap = true, silent = true })

-- ==============================================================================
-- TERMINAL MODE NAVIGATION
-- ==============================================================================
-- Navigate to windows from terminal mode using Ctrl+hjkl
vim.keymap.set("t", "<C-h>", "<C-\\><C-N><C-w>h", { desc = "Navigate to left window from terminal", silent = true })
vim.keymap.set("t", "<C-j>", "<C-\\><C-N><C-w>j", { desc = "Navigate to bottom window from terminal", silent = true })
vim.keymap.set("t", "<C-k>", "<C-\\><C-N><C-w>k", { desc = "Navigate to top window from terminal", silent = true })
vim.keymap.set("t", "<C-l>", "<C-\\><C-N><C-w>l", { desc = "Navigate to right window from terminal", silent = true })

-- ==============================================================================
-- TEXT MOVEMENT (VISUAL MODE)
-- ==============================================================================
-- Move selected text up and down in visual mode
vim.keymap.set("v", "<A-j>", ":m .+1<CR>==", { desc = "Move selected text down", noremap = true, silent = true })
vim.keymap.set("v", "<A-k>", ":m .-2<CR>==", { desc = "Move selected text up", noremap = true, silent = true })

-- ==============================================================================
-- TEXT MOVEMENT (VISUAL BLOCK MODE)
-- ==============================================================================
-- Move visual blocks up and down
vim.keymap.set("x", "J", ":move '>+1<CR>gv-gv", { desc = "Move visual block down", noremap = true, silent = true })
vim.keymap.set("x", "K", ":move '<-2<CR>gv-gv", { desc = "Move visual block up", noremap = true, silent = true })
vim.keymap.set("x", "<A-j>", ":move '>+1<CR>gv-gv", { desc = "Move visual block down (Alt)", noremap = true, silent = true })
vim.keymap.set("x", "<A-k>", ":move '<-2<CR>gv-gv", { desc = "Move visual block up (Alt)", noremap = true, silent = true })

-- ==============================================================================
-- CLIPBOARD INTEGRATION
-- ==============================================================================
-- Copy current line to system clipboard in normal mode
vim.keymap.set('n', '<C-c>', '"+yy', { desc = "Copy line to system clipboard", noremap = true, silent = true })

-- Copy selection to system clipboard in visual mode
vim.keymap.set('v', '<C-c>', '"+y', { desc = "Copy selection to system clipboard", noremap = true, silent = true })

-- Make Ctrl+V paste from system clipboard instead of visual block mode
vim.keymap.set('n', '<C-v>', '"+p', { desc = "Paste from system clipboard", noremap = true, silent = true })
vim.keymap.set('i', '<C-v>', '<C-r>+', { desc = "Paste from system clipboard in insert mode", noremap = true, silent = true })
vim.keymap.set('c', '<C-v>', '<C-r>+', { desc = "Paste from system clipboard in command mode", noremap = true, silent = true })

-- ==============================================================================
-- SEARCH NAVIGATION WITH CENTERING
-- ==============================================================================
-- Center screen after completing a search with / or ?
vim.keymap.set('c', '<CR>', function()
  -- Check if we're in a search command (/ or ?)
  local cmdtype = vim.fn.getcmdtype()
  if cmdtype == '/' or cmdtype == '?' then
    return '<CR>zz'
  end
  return '<CR>'
end, { expr = true, desc = 'Execute command and center if search' })

-- Center screen when searching for word under cursor
vim.keymap.set('n', '*', '*zz', { desc = 'Search word under cursor (forward) and center', noremap = true, silent = true })
vim.keymap.set('n', '#', '#zz', { desc = 'Search word under cursor (backward) and center', noremap = true, silent = true })

-- Center screen when navigating search results
vim.keymap.set('n', 'n', 'nzz', { desc = 'Next search result and center', noremap = true, silent = true })
vim.keymap.set('n', 'N', 'Nzz', { desc = 'Previous search result and center', noremap = true, silent = true })
