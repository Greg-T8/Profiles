return {
    'matze/vim-move',
    -- cond = not vim.g.vscode,     -- Only load in native Neovim, not VSCode
    config = function()
        -- Use Alt+j/k and Alt+h/l for moving lines/selections
        vim.g.move_key_modifier = 'A'
        vim.g.move_key_modifier_visualmode = 'A'
    end
}
