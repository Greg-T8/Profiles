-- ==============================================================================
-- COMMON KEYMAPS (Shared between Neovim and VSCode)
-- ==============================================================================
-- These keybindings apply to both native Neovim and VSCode Neovim
-- Mode abbreviations:
--   n  = normal_mode
--   i  = insert_mode
--   v  = visual_mode
--   x  = visual_block_mode
--   t  = term_mode
--   c  = command_mode
--   o  = operator_pending_mode

-- ==============================================================================
-- FILE OPERATIONS
-- ==============================================================================
-- Save and quit operations
vim.keymap.set('n', '<leader>w', ':w<CR>', { desc = 'Save file', noremap = true, silent = true })
vim.keymap.set('n', '<leader>wq', ':wq<CR>', { desc = 'Save and quit', noremap = true, silent = true })
vim.keymap.set('n', '<leader>q', ':q!<CR>', { desc = 'Force quit without saving', noremap = true, silent = true })

-- Make :q always force quit without confirmation
vim.api.nvim_create_user_command('Q', 'q!', {})
vim.cmd('cnoreabbrev q Q')
vim.cmd('cnoreabbrev wq wq!')

-- ==============================================================================
-- VISUAL BLOCK MODE
-- ==============================================================================
-- Enter visual block mode using Ctrl+Q (since Ctrl+V is remapped to paste)
vim.keymap.set("n", "<C-q>", "<C-v>", { desc = "Enter visual block mode", noremap = true, silent = true })

-- ==============================================================================
-- CURSOR MOVEMENT WITH CENTERING
-- ==============================================================================
-- Center cursor after large movements
vim.keymap.set('n', '<C-u>', '<C-u>zz', { desc = 'Half page up and center', noremap = true, silent = true })
vim.keymap.set('n', '<C-d>', '<C-d>zz', { desc = 'Half page down and center', noremap = true, silent = true })
vim.keymap.set('n', '<C-f>', '<C-f>zz', { desc = 'Full page down and center', noremap = true, silent = true })
vim.keymap.set('n', '<C-b>', '<C-b>zz', { desc = 'Full page up and center', noremap = true, silent = true })

-- Go to end of file and last character on line
vim.keymap.set('n', 'G', 'G$', { desc = 'Go to end of last line', noremap = true, silent = true })

-- ==============================================================================
-- SELECT ALL
-- ==============================================================================
-- Select all text in the buffer
vim.keymap.set("n", "<C-a>", "ggVG", { desc = "Select all text", noremap = true, silent = true })
vim.keymap.set("i", "<C-a>", "<Esc>ggVG", { desc = "Select all text", noremap = true, silent = true })

-- ==============================================================================
-- VISUAL MODE ENHANCEMENTS
-- ==============================================================================
-- Stay in indent mode after indenting
vim.keymap.set("v", "<", "<gv", { desc = "Indent left and keep selection", noremap = true, silent = true })
vim.keymap.set("v", ">", ">gv", { desc = "Indent right and keep selection", noremap = true, silent = true })

-- Paste without yanking replaced text
vim.keymap.set("v", "<leader>p", '"_dP', { desc = "Paste without yanking replaced text", noremap = true, silent = true })

-- ==============================================================================
-- TEXT MOVEMENT
-- ==============================================================================
-- Note: Line movement (Alt+j/k) is handled by vim-move plugin
-- See _common/plugins/vim-move.lua for configuration
