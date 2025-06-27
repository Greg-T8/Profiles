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
        'echasnovski/mini.surround',
        config = function()
            require('mini.surround').setup({
                mappings = {
                    add = "<leader>sa", -- Add surrounding in Normal and Visual modes
                    delete = "<leader>sd", -- Delete surrounding
                    find = "<leaderf>sf", -- Find surrounding (to the right)
                    find_left = "<leader>sF", -- Find surrounding (to the left)
                    highlight = "<leader>sh", -- Highlight surrounding
                    replace = "<leader>sr", -- Replace surrounding
                    update_n_lines = "<leader>sn", -- Update `n_lines`
                },
                -- Whether to respect selection type:
                -- - Place surroundings on separate lines in linewise mode.
                -- - Place surroundings on each line in blockwise mode.
                respect_selection_type = false,
            })
        end,
    },
}
