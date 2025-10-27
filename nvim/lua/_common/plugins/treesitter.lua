-- ==============================================================================
-- TREESITTER CONFIGURATION (Shared)
-- ==============================================================================
-- Tree-sitter provides better syntax highlighting and incremental text selection
-- Incremental selection allows expanding selection scope with repeated keypresses

return {
    "nvim-treesitter/nvim-treesitter",
    build = ":TSUpdate",
    event = { "BufReadPost", "BufNewFile" },
    dependencies = {
        "nvim-treesitter/nvim-treesitter-textobjects",
    },
    config = function()
        require("nvim-treesitter.configs").setup({
            -- Install parsers for common languages
            ensure_installed = {
                "lua",
                "vim",
                "vimdoc",
                "python",
                "javascript",
                "typescript",
                "html",
                "css",
                "json",
                "yaml",
                "markdown",
                "markdown_inline",
                "bash",
            },

            -- Install parsers synchronously (only applied to `ensure_installed`)
            sync_install = false,

            -- Automatically install missing parsers when entering buffer
            auto_install = true,

            -- Highlighting
            highlight = {
                enable = true,
                additional_vim_regex_highlighting = false,
            },

            -- Indentation based on treesitter
            indent = {
                enable = true,
            },

            -- Incremental selection based on syntax tree
            incremental_selection = {
                enable = true,
                keymaps = {
                    init_selection = "<C-a>",      -- Start selection or expand to smallest node
                    node_incremental = "<C-a>",    -- Increment to the next larger node
                    scope_incremental = false,     -- Disabled to avoid conflicts
                    node_decremental = "<C-s>",    -- Decrement to the previous smaller node
                },
            },

            -- Text objects for easier navigation and selection
            textobjects = {
                select = {
                    enable = true,
                    lookahead = true, -- Automatically jump forward to textobj
                    keymaps = {
                        -- Function text objects
                        ["af"] = "@function.outer",
                        ["if"] = "@function.inner",

                        -- Class text objects
                        ["ac"] = "@class.outer",
                        ["ic"] = "@class.inner",

                        -- Block text objects
                        ["ab"] = "@block.outer",
                        ["ib"] = "@block.inner",

                        -- Parameter/argument text objects
                        ["aa"] = "@parameter.outer",
                        ["ia"] = "@parameter.inner",
                    },
                },
                move = {
                    enable = true,
                    set_jumps = true, -- Add jumps to jumplist
                    goto_next_start = {
                        ["]f"] = "@function.outer",
                        ["]c"] = "@class.outer",
                    },
                    goto_next_end = {
                        ["]F"] = "@function.outer",
                        ["]C"] = "@class.outer",
                    },
                    goto_previous_start = {
                        ["[f"] = "@function.outer",
                        ["[c"] = "@class.outer",
                    },
                    goto_previous_end = {
                        ["[F"] = "@function.outer",
                        ["[C"] = "@class.outer",
                    },
                },
            },
        })
    end,
}
