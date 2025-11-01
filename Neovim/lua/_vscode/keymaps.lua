-- ==============================================================================
-- VSCODE KEYMAPS (VSCode Neovim only)
-- ==============================================================================
-- Additional keybindings specific to VSCode Neovim environment
-- Common keybindings are defined in _common/keymaps.lua

-- ==============================================================================
-- VSCODE API
-- ==============================================================================
-- Load the VSCode API module for interacting with VSCode commands
local vscode = require('vscode')

-- ==============================================================================
-- WINDOW MANAGEMENT
-- ==============================================================================
-- Move editor to new window
vim.api.nvim_set_keymap('n', '<leader>dw',
    "<Cmd>call VSCodeNotify('workbench.action.moveEditorToNewWindow')<CR>",
    { noremap = true, silent = true })

-- ==============================================================================
-- TERMINAL KEYBINDINGS
-- ==============================================================================
-- Open in integrated terminal
vim.api.nvim_set_keymap('n', '<leader>tt',
    "<Cmd>call VSCodeNotify('openInIntegratedTerminal')<CR>",
    { noremap = true, silent = true })

-- Alternative binding for integrated terminal
vim.api.nvim_set_keymap('n', '<leader>at',
    "<Cmd>call VSCodeNotify('openInIntegratedTerminal')<CR>",
    { noremap = true, silent = true })

-- ==============================================================================
-- MARKDOWN KEYBINDINGS
-- ==============================================================================
-- Open markdown preview to the side
vim.api.nvim_set_keymap('n', '<leader>de',
    "<cmd>call VSCodeNotify('markdown-preview-enhanced.openPreviewToTheSide')<CR>",
    { noremap = true, silent = true })

-- Toggle code block in markdown
vim.api.nvim_set_keymap('n', '<leader>ic',
    "<Cmd>call VSCodeNotify('markdown.extension.editing.toggleCodeBlock')<CR>a",
    { noremap = true, silent = true })

-- ==============================================================================
-- COPILOT/CHAT KEYBINDINGS
-- ==============================================================================
-- Trigger inline voice chat
vim.api.nvim_set_keymap('n', '<leader>ic',
    "<Cmd>call VSCodeNotify('workbench.action.chat.inlineVoiceChat')<CR>",
    { noremap = true, silent = true })

-- Inline chat undo
vim.api.nvim_set_keymap('n', '<leader>icu',
    "<Cmd>call VSCodeNotify('undo')<CR>",
    { noremap = true, silent = true })

-- ==============================================================================
-- INTELLISENSE TOGGLES
-- ==============================================================================
-- Toggle inline suggestions
vim.api.nvim_set_keymap('n', '<leader>tis',
    "<Cmd>call VSCodeNotify('settings.cycle.inlineSuggestToggle')<CR>",
    { noremap = true, silent = true })

-- Toggle intellisense
vim.api.nvim_set_keymap('n', '<leader>tii',
    "<Cmd>call VSCodeNotify('settings.cycle.intellisenseToggle')<CR>",
    { noremap = true, silent = true })

-- Toggle next edit suggestions
vim.api.nvim_set_keymap('n', '<leader>nes',
    "<Cmd>call VSCodeNotify('settings.cycle.nextEditSuggestionsToggle')<CR>",
    { noremap = true, silent = true })

-- ==============================================================================
-- BUILD TASKS
-- ==============================================================================
-- GCC Build functionality with configuration check
_G.build_if_gccbuild_enabled = function()
    local enabled = vscode.get_config("workspaceKeybindings.gccbuild.enabled")
    if enabled then
        vim.cmd("call VSCodeNotify('workbench.action.tasks.runTask', 'GCC Build')")
    else
        print("GCC Build is disabled")
    end
end

-- Trigger GCC build task
vim.api.nvim_set_keymap('n', '<leader>bc',
    "<Cmd>lua build_if_gccbuild_enabled()<CR>",
    { noremap = true, silent = true })

-- ==============================================================================
-- SCROLLING BEHAVIOR
-- ==============================================================================
-- Custom scrolling that centers cursor and preserves visual selection
local win_h = function() return vim.api.nvim_win_get_height(0) end
local half  = function() return math.floor(win_h() / 2) end

-- Full page scrolling with centering
vim.keymap.set({'n', 'x'}, '<C-f>', function() vim.cmd('normal! ' .. win_h() .. 'jzz') end)
vim.keymap.set({'n', 'x'}, '<C-b>', function() vim.cmd('normal! ' .. win_h() .. 'kzz') end)

-- Half page scrolling with centering
vim.keymap.set({'n', 'x'}, '<C-d>', function() vim.cmd('normal! ' .. half() .. 'jzz') end)
vim.keymap.set({'n', 'x'}, '<C-u>', function() vim.cmd('normal! ' .. half() .. 'kzz') end)

-- ==============================================================================
-- NUMBER INCREMENT/DECREMENT
-- ==============================================================================
-- Restore Vim's increment/decrement functionality since Ctrl+A and Ctrl+X are
-- taken by VSCode for select all and cut
vim.keymap.set('n', '<leader>i', '<C-a>', { desc = "Increment number", noremap = true, silent = true })
vim.keymap.set('n', '<leader>d', '<C-x>', { desc = "Decrement number", noremap = true, silent = true })
vim.keymap.set('v', '<leader>i', '<C-a>', { desc = "Increment numbers in selection", noremap = true, silent = true })
vim.keymap.set('v', '<leader>d', '<C-x>', { desc = "Decrement numbers in selection", noremap = true, silent = true })
vim.keymap.set('v', 'g<leader>i', 'g<C-a>', { desc = "Increment numbers sequentially", noremap = true, silent = true })
vim.keymap.set('v', 'g<leader>d', 'g<C-x>', { desc = "Decrement numbers sequentially", noremap = true, silent = true })

-- ==============================================================================
-- MULTI-CURSOR
-- ==============================================================================
-- Select all highlights under cursor for multi-cursor editing
vim.keymap.set({ "n", "x", "i" }, "<C-S-l>", function()
  require("vscode-multi-cursor").selectHighlights()
end)

-- ==============================================================================
-- SEARCH NAVIGATION WITH CENTERING
-- ==============================================================================
-- Center screen when searching for word under cursor
vim.keymap.set('n', '*', function()
  vim.cmd('normal! *zz')
end, { noremap = true, silent = true })

vim.keymap.set('n', '#', function()
  vim.cmd('normal! #zz')
end, { noremap = true, silent = true })

-- Center screen when navigating search results
vim.keymap.set('n', 'n', function()
  vim.cmd('normal! nzz')
end, { noremap = true, silent = true })

vim.keymap.set('n', 'N', function()
  vim.cmd('normal! Nzz')
end, { noremap = true, silent = true })
