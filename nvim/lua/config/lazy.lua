-- Detect VSCode-Neovim early
local is_vscode = vim.g.vscode == 1 or vim.g.vscode == true

-- Derive per-environment paths
local lazy_root  = vim.fn.stdpath("data")  .. (is_vscode and "/lazy-vscode" or "/lazy-nvim")
local lazy_state = vim.fn.stdpath("state") .. (is_vscode and "/lazy-vscode" or "/lazy-nvim")
local lazy_lock  = vim.fn.stdpath("config") .. (is_vscode and "/lazy-lock.vscode.json" or "/lazy-lock.nvim.json")

-- Bootstrap lazy.nvim from per-environment root
local lazypath = lazy_root .. "/lazy.nvim"
if not (vim.uv or vim.loop).fs_stat(lazypath) then
    local lazyrepo = "https://github.com/folke/lazy.nvim.git"
    local out = vim.fn.system({ "git", "clone", "--filter=blob:none", "--branch=stable", lazyrepo, lazypath })
    if vim.v.shell_error ~= 0 then
        vim.api.nvim_echo({
            { "Failed to clone lazy.nvim:\n", "ErrorMsg" },
            { out,                            "WarningMsg" },
            { "\nPress any key to exit..." },
        }, true, {})
        vim.fn.getchar()
        os.exit(1)
    end
end
vim.opt.rtp:prepend(lazypath)

-- Show which lockfile is being used
vim.notify("Using lockfile: " .. lazy_lock, vim.log.levels.INFO)

-- Setup lazy.nvim
-- See https://lazy.folke.io/configuration for options
require("lazy").setup({
    spec = {
        -- import your plugins
        { import = "_common.plugins", cond = true },
        { import = "_nvim.plugins",   cond = (function() return not vim.g.vscode end) },
        { import = "_vscode.plugins", cond = (function() return vim.g.vscode end) },
    },
    defaults = {
        lazy = false,
        version = false,
    },
    install = { colorscheme = { "habamax" } },
    checker = {
        enabled = true,
        notify  = true,
    },
    -- Add per-env locations
    root     = lazy_root,                -- where plugins install
    state    = lazy_state .. "/state.json",
    lockfile = lazy_lock,                -- separate lockfiles
})

-- Create command to check lockfile
vim.api.nvim_create_user_command('LazyLockfile', function()
    local lockfile = require("lazy.core.config").options.lockfile
    vim.notify("Lockfile: " .. lockfile, vim.log.levels.INFO)
end, {})
