-- ==============================================================================
-- LAZY.NVIM PLUGIN MANAGER CONFIGURATION
-- ==============================================================================
-- This configuration manages plugins with separate environments for:
-- - Native Neovim (full plugin ecosystem)
-- - VSCode Neovim (lightweight, VSCode-compatible plugins only)
--
-- Each environment has its own:
-- - Plugin installation directory
-- - State file
-- - Lockfile
--
-- See https://lazy.folke.io/configuration for full documentation

-- ==============================================================================
-- ENVIRONMENT DETECTION
-- ==============================================================================
-- Detect if running inside VSCode Neovim extension
local is_vscode = vim.g.vscode == 1 or vim.g.vscode == true

-- ==============================================================================
-- ENVIRONMENT-SPECIFIC PATHS
-- ==============================================================================
-- Derive separate paths for each environment to keep plugins isolated
local lazy_root  = vim.fn.stdpath("data")   .. (is_vscode and "/lazy-vscode" or "/lazy-nvim")
local lazy_state = vim.fn.stdpath("state")  .. (is_vscode and "/lazy-vscode" or "/lazy-nvim")
local lazy_lock  = vim.fn.stdpath("config") .. (is_vscode and "/lazy-lock.vscode.json" or "/lazy-lock.nvim.json")

-- ==============================================================================
-- LAZY.NVIM BOOTSTRAP
-- ==============================================================================
-- Install lazy.nvim if not already present
local lazypath = lazy_root .. "/lazy.nvim"
if not (vim.uv or vim.loop).fs_stat(lazypath) then
    local lazyrepo = "https://github.com/folke/lazy.nvim.git"
    local out = vim.fn.system({
        "git", "clone", "--filter=blob:none", "--branch=stable",
        lazyrepo, lazypath
    })

    -- Handle clone failure
    if vim.v.shell_error ~= 0 then
        vim.api.nvim_echo({
            { "Failed to clone lazy.nvim:\n", "ErrorMsg" },
            { out, "WarningMsg" },
            { "\nPress any key to exit..." },
        }, true, {})
        vim.fn.getchar()
        os.exit(1)
    end
end

-- Add lazy.nvim to runtime path
vim.opt.rtp:prepend(lazypath)

-- ==============================================================================
-- LAZY.NVIM SETUP
-- ==============================================================================
require("lazy").setup({
    -- Plugin specifications
    spec = {
        { import = "_common.plugins",  cond = true },                              -- Always load common plugins
        { import = "_nvim.plugins",    cond = (function() return not vim.g.vscode end) }, -- Native Neovim only
        { import = "_vscode.plugins",  cond = (function() return vim.g.vscode end) },     -- VSCode only
    },

    -- Default plugin behavior
    defaults = {
        lazy = false,           -- Load plugins immediately by default
        version = false,        -- Don't restrict to specific versions
    },

    -- Installation settings
    install = {
        colorscheme = { "habamax" }  -- Fallback colorscheme during installation
    },

    -- Plugin update checker
    checker = {
        enabled = true,         -- Check for plugin updates
        notify  = true,  		-- Show notification when updates are available
    },

    -- Environment-specific locations
    root     = lazy_root,                   -- Plugin installation directory
    state    = lazy_state .. "/state.json", -- Plugin state file
    lockfile = lazy_lock,                   -- Plugin version lockfile
})

-- ==============================================================================
-- UTILITY COMMANDS
-- ==============================================================================
-- Command to display which lockfile is currently in use
vim.api.nvim_create_user_command('LazyLockfile', function()
    local lockfile = require("lazy.core.config").options.lockfile
    vim.notify("Lockfile: " .. lockfile, vim.log.levels.INFO)
end, { desc = "Show current lazy.nvim lockfile path" })
