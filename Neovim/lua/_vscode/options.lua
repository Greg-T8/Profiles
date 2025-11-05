-- ==============================================================================
-- VSCODE NEOVIM OPTIONS
-- ==============================================================================
-- VSCode-specific configuration
-- This file is only loaded when running Neovim inside VSCode
-- Keybindings are defined in _vscode/keymaps.lua

-- ==============================================================================
-- EDITOR SETTINGS
-- ==============================================================================
vim.opt.columns = 400               -- Set editor column width
vim.opt.scrolloff = 999             -- Keep cursor centered vertically

-- ==============================================================================
-- VISUAL SELECTION FIX
-- ==============================================================================
-- Fix visual selection cutting off last character in VSCode
-- 
-- Problem: When highlighting and yanking text in VSCode, the last character was
--          excluded from the selection due to VSCode's cursor-position model
--          conflicting with Neovim's selection-based model
-- 
-- Solution: 
--   1. selection = "inclusive" - Character under cursor is included in selection
--   2. selectmode = "mouse,key" - Enables select mode for mouse and keyboard
--   3. virtualedit = "onemore" - Allows cursor to move one past end of line,
--                                 helping VSCode's selection model align with Neovim
vim.opt.selection = "inclusive"
vim.opt.selectmode = "mouse,key"
vim.opt.virtualedit = "onemore"
