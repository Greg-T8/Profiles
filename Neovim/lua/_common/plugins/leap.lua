return {
    'ggandor/leap.nvim',
    config = function()
        local leap = require("leap")
        leap.opts.case_sensitive = false
        vim.keymap.set('n', 's', '<Plug>(leap-anywhere)')
        vim.keymap.set('x', 's', '<Plug>(leap)')
        vim.keymap.set('o', 's', '<Plug>(leap-forward)')
        vim.keymap.set('o', 'S', '<Plug>(leap-backward)')
    end,
}
