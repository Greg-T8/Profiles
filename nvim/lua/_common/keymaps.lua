local opts = { noremap = true, silent = true }

local term_opts = { silent = true }

-- Modes
--   normal_mode = "n",
--   insert_mode = "i",
--   visual_mode = "v",
--   visual_block_mode = "x",
--   term_mode = "t",
--   command_mode = "c",
--   operator_pending_mode = "o",

-- Normal mode --
-- Add keymapping for saving with leader+s
vim.keymap.set('n', '<leader>w', ':w<CR>', { desc = 'Save file' })
vim.keymap.set("n", "<C-q>", "<C-v>", { desc = "Enter visual block mode", noremap = true, silent = true })

-- Change G to go to end of line
vim.keymap.set('n', 'G', 'G$', { desc = 'Go to end of line and center' })

-- Add keymapping for centering cursor
-- vim.keymap.set('n', '<C-u>', '<C-u>zz', { desc = 'Center cursor on screen' })
-- vim.keymap.set('n', '<C-d>', '<C-d>zz', { desc = 'Half page down and center' })
-- vim.keymap.set('n', '<C-f>', '<C-f>zz', { desc = 'Page down and center' })
-- vim.keymap.set('n', '<C-b>', '<C-b>zz', { desc = 'Page up and center' })

-- Insert mode --
vim.keymap.set("i", "jk", "<ESC>", { desc = "Quick exit from insert mode", noremap = true, silent = true })


-- Visual mode --
-- Stay in indent mode
vim.keymap.set("v", "<", "<gv", { desc = "Indent left and keep selection", noremap = true, silent = true })
vim.keymap.set("v", ">", ">gv", { desc = "Indent right and keep selection", noremap = true, silent = true })

-- Visual block mode --
-- Enter visual block mode using ctrl+q
vim.keymap.set('n', '<C-v>', '<C-q>', { desc = 'Enter visual block mode', noremap = true, silent = true })

-- Move text up and down
vim.keymap.set("v", "p", '"_dP', { desc = "Paste without yanking replaced text", noremap = true, silent = true })
