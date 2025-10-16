-- Use leader key to enter visual block mode
vim.api.nvim_set_keymap('n', '<leader>vb', "<C-v>", { noremap = true, silent = true })

-- Clear search highlighting
vim.api.nvim_set_keymap('n', '<leader>n', ':nohlsearch<CR>', { noremap = true, silent = true })
