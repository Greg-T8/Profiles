return {
    {
        'ggandor/leap.nvim',
        config = function()
            local leap = require("leap")
            leap.opts.case_sensitive = false
            vim.keymap.set('n', 's', '<Plug>(leap-anywhere)')
            vim.keymap.set('x', 's', '<Plug>(leap)')
            vim.keymap.set('o', 's', '<Plug>(leap-forward)')
            vim.keymap.set('o', 'S', '<Plug>(leap-backward)')
        end,
    },
    {
        "kylechui/nvim-surround",
        version = "^3.0.0", -- Use for stability; omit to use `main` branch for the latest features
        event = "VeryLazy",
        config = function()
            require("nvim-surround").setup({
                -- Configuration here, or leave empty to use defaults
            })
        end
    }
}
