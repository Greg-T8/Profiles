-- ---------------------------------------------------------------------------
-- Description   : Configure Telescope fuzzy search for native Neovim
-- Context       : Neovim profile — native Neovim plugin setup
-- Author        : Greg Tate & coding agent
-- Last Modified : 2026-11-10
-- Revision History:
--   2026-11-10 - Add Telescope fuzzy finder setup.
-- ---------------------------------------------------------------------------
return {
    {
        "nvim-telescope/telescope.nvim",
        version = "*",
        dependencies = {
            "nvim-lua/plenary.nvim",
        },
        config = function()
            require("telescope").setup({
                defaults = {
                    layout_strategy = "horizontal",
                    layout_config = {
                        horizontal = {
                            preview_width = 0.55,
                        },
                    },
                    sorting_strategy = "ascending",
                },
            })
        end,
    },
}
