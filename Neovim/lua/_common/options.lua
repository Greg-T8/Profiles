-- ==============================================================================
-- COMMON OPTIONS (Shared between Neovim and VSCode)
-- ==============================================================================
-- These settings and keybindings apply to both native Neovim and VSCode Neovim

-- ==============================================================================
-- VISUAL BLOCK MODE
-- ==============================================================================
-- Use leader key to enter visual block mode (since Ctrl+V is remapped to paste)
vim.api.nvim_set_keymap('n', '<leader>vb', "<C-v>", { noremap = true, silent = true })

-- ==============================================================================
-- SEARCH HIGHLIGHTING
-- ==============================================================================
-- Clear search highlighting with leader+n
vim.api.nvim_set_keymap('n', '<leader>n', ':nohlsearch<CR>', { noremap = true, silent = true })
