-- ==============================================================================
-- COMMON OPTIONS (Shared between Neovim and VSCode)
-- ==============================================================================
-- These settings and keybindings apply to both native Neovim and VSCode Neovim

-- ==============================================================================
-- VISUAL SELECTION
-- ==============================================================================
-- Include the character under the cursor in visual selection
-- 'inclusive' means the character at the cursor position is included when yanking
vim.opt.selection = "inclusive"

-- ==============================================================================
-- VISUAL BLOCK MODE
-- ==============================================================================
-- Use leader key to enter visual block mode (since Ctrl+V is remapped to paste)
vim.api.nvim_set_keymap('n', '<leader>vb', "<C-v>", { noremap = true, silent = true })

-- ==============================================================================
-- SEARCH HIGHLIGHTING
-- ==============================================================================
-- Clear search highlighting with leader+n
vim.api.nvim_set_keymap('n', '<leader><space>', ':nohlsearch<CR>', { noremap = true, silent = true })
