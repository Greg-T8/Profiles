return {
    {
        'nvim-lualine/lualine.nvim',
        dependencies = { 'nvim-tree/nvim-web-devicons' },
        config = function()
            require('lualine').setup({
                options = {
                    icons_enabled = false,
                    theme = 'auto',
                    component_separators = { left = '|', right = '|'},
                    section_separators = { left = '', right = ''},
                    disabled_filetypes = {
                        statusline = {},
                        winbar = {},
                    },
                    ignore_focus = {},
                    always_divide_middle = true,
                    globalstatus = true,
                    refresh = {
                        statusline = 1000,
                        tabline = 1000,
                        winbar = 1000,
                    }
                },
                sections = {
                    lualine_a = {'mode'},
                    lualine_b = {
                        'branch',
                        'diff',
                        {
                            'diagnostics',
                            sources = {'nvim_diagnostic'},
                            sections = {'error', 'warn', 'info', 'hint'},
                            symbols = {error = 'E:', warn = 'W:', info = 'I:', hint = 'H:'},
                        }
                    },
                    lualine_c = {
                        {
                            'filename',
                            path = 1,
                            symbols = {
                                modified = '[+]',
                                readonly = '[-]',
                                unnamed = '[No Name]',
                            }
                        }
                    },
                    lualine_x = {
                        {
                            'encoding',
                            fmt = function(str) return str:upper() end
                        },
                        {
                            'fileformat',
                            fmt = function(str) return str:upper() end
                        },
                        {
                            'filetype',
                            fmt = function(str) return str:upper() end
                        }
                    },
                    lualine_y = {'progress'},
                    lualine_z = {'location'}
                },
                inactive_sections = {
                    lualine_a = {},
                    lualine_b = {},
                    lualine_c = {'filename'},
                    lualine_x = {'location'},
                    lualine_y = {},
                    lualine_z = {}
                },
                tabline = {},
                winbar = {},
                inactive_winbar = {},
                extensions = {'neo-tree'}
            })

            vim.opt.number = true
            vim.opt.relativenumber = true
        end
    }
}
