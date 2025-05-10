-- Normal mode --
-- Better window navigation
vim.keymap.set("n", "<C-h>", "<C-w>h", { desc = "Move to left window", noremap = true, silent = true })
vim.keymap.set("n", "<C-j>", "<C-w>j", { desc = "Move to bottom window", noremap = true, silent = true })
vim.keymap.set("n", "<C-k>", "<C-w>k", { desc = "Move to top window", noremap = true, silent = true })
vim.keymap.set("n", "<C-l>", "<C-w>l", { desc = "Move to right window", noremap = true, silent = true })

-- Resize windows
vim.keymap.set("n", "<C-Up>", ":resize +2<CR>", { desc = "Increase window height", noremap = true, silent = true })
vim.keymap.set("n", "<C-Down>", ":resize -2<CR>", { desc = "Decrease window height", noremap = true, silent = true })
vim.keymap.set("n", "<C-Left>", ":vertical resize -2<CR>", { desc = "Decrease window width", noremap = true, silent = true })
vim.keymap.set("n", "<C-Right>", ":vertical resize +2<CR>", { desc = "Increase window width", noremap = true, silent = true })

-- Buffer navigation
vim.keymap.set("n", "<S-l>", ":bnext<CR>", { desc = "Next buffer", noremap = true, silent = true })
vim.keymap.set("n", "<S-h>", ":bprevious<CR>", { desc = "Previous buffer", noremap = true, silent = true })

-- File explorer
vim.keymap.set("n", "<leader>e", ":Neotree<CR>", { desc = "Open Neotree", noremap = true, silent = true })

-- Visual Block mode --
-- Move text up and down
vim.keymap.set("v", "<A-j>", ":m .+1<CR>==", { desc = "Move selected text down", noremap = true, silent = true })
vim.keymap.set("v", "<A-k>", ":m .-2<CR>==", { desc = "Move selected text up", noremap = true, silent = true })

-- Move text up and down
vim.keymap.set("x", "J", ":move '>+1<CR>gv-gv", { desc = "Move visual block down", noremap = true, silent = true })
vim.keymap.set("x", "K", ":move '<-2<CR>gv-gv", { desc = "Move visual block up", noremap = true, silent = true })
vim.keymap.set("x", "<A-j>", ":move '>+1<CR>gv-gv", { desc = "Move visual block down (Alt)", noremap = true, silent = true })
vim.keymap.set("x", "<A-k>", ":move '<-2<CR>gv-gv", { desc = "Move visual block up (Alt)", noremap = true, silent = true })

-- Terminal mode --
-- Better terminal navigation
vim.keymap.set("t", "<C-h>", "<C-\\><C-N><C-w>h", { desc = "Navigate to left window from terminal", silent = true })
vim.keymap.set("t", "<C-j>", "<C-\\><C-N><C-w>j", { desc = "Navigate to bottom window from terminal", silent = true })
vim.keymap.set("t", "<C-k>", "<C-\\><C-N><C-w>k", { desc = "Navigate to top window from terminal", silent = true })
vim.keymap.set("t", "<C-l>", "<C-\\><C-N><C-w>l", { desc = "Navigate to right window from terminal", silent = true })