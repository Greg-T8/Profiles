-- ==============================================================================
-- NEOVIM INITIALIZATION
-- ==============================================================================
-- Main entry point for Neovim configuration
-- This file orchestrates loading order for all configuration modules
--
-- Load order is critical:
-- 1. Leader keys (must be set before lazy.nvim loads plugins)
-- 2. Plugin manager (lazy.nvim bootstrap and setup)
-- 3. Common options and keymaps (shared between Neovim and VSCode)
-- 4. Environment-specific configuration (native Neovim vs VSCode)

-- ==============================================================================
-- LEADER KEY CONFIGURATION
-- ==============================================================================
-- Set leader keys before any plugins or keymaps that reference them
require("config.keymaps")

-- ==============================================================================
-- PLUGIN MANAGER
-- ==============================================================================
-- Bootstrap and configure lazy.nvim plugin manager
require("config.lazy")

-- ==============================================================================
-- COMMON CONFIGURATION (Shared)
-- ==============================================================================
-- Options and keymaps that apply to both native Neovim and VSCode Neovim
require("_common.options")
require("_common.keymaps")

-- ==============================================================================
-- ENVIRONMENT-SPECIFIC CONFIGURATION
-- ==============================================================================
-- Load configuration based on runtime environment
if vim.g.vscode then
    -- VSCode Neovim extension
    require("_vscode.options")
else
    -- Native Neovim
    require("_nvim.options")
    require("_nvim.keymaps")
end
