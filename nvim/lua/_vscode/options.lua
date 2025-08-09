-- Loads the VS Code API module
local vscode = require('vscode')

vim.opt.columns = 400

-- Trigger move into new window
vim.api.nvim_set_keymap('n', '<leader>dw',
    "<Cmd>call VSCodeNotify('workbench.action.moveEditorToNewWindow')<CR>",
    { noremap = true, silent = true })

-- Markdown: Open preview to the side
vim.api.nvim_set_keymap('n', '<leader>de',
    "<cmd>call VSCodeNotify('markdown.showPreviewToSide')<CR>",
    { noremap = true, silent = true })

-- Trigger inline chat
vim.api.nvim_set_keymap('n', '<leader>ic',
    "<Cmd>call VSCodeNotify('workbench.action.chat.inlineVoiceChat')<CR>",
    { noremap = true, silent = true })

-- Inline chat undo
vim.api.nvim_set_keymap('n', '<leader>icu',
    "<Cmd>call VSCodeNotify('undo')<CR>",
    { noremap = true, silent = true })

-- Open in integrated terminal
vim.api.nvim_set_keymap('n', '<leader>it',
    "<Cmd>call VSCodeNotify('openInIntegratedTerminal')<CR>",
    { noremap = true, silent = true })

-- Open in integrated terminal
vim.api.nvim_set_keymap('n', '<leader>at',
    "<Cmd>call VSCodeNotify('openInIntegratedTerminal')<CR>",
    { noremap = true, silent = true })

-- Toggle inline suggestions (VSCode Neovim)
vim.api.nvim_set_keymap('n', '<leader>tis',
  "<Cmd>call VSCodeNotify('settings.cycle.inlineSuggestToggle')<CR>",
  { noremap = true, silent = true })

-- Toggle intellisense
vim.api.nvim_set_keymap('n', '<leader>tii',
    "<Cmd>call VSCodeNotify('settings.cycle.intellisenseToggle')<CR>",
    { noremap = true, silent = true })

-- Toggle Next Edit Suggestions
vim.api.nvim_set_keymap('n', '<leader>nes',
    "<Cmd>call VSCodeNotify('settings.cycle.nextEditSuggestionsToggle')<CR>",
    { noremap = true, silent = true })

-- Toggle code block when in markdown
vim.api.nvim_set_keymap('n', '<leader>ic',
    "<Cmd>call VSCodeNotify('markdown.extension.editing.toggleCodeBlock')<CR>a",
    { noremap = true, silent = true })

-- Open television file finder
vim.api.nvim_set_keymap('n', '<leader>tvf',
    "<Cmd>call VSCodeNotify('television.ToggleFileFinder')<CR>",
    { noremap = true, silent = true })

-- Open television text finder
vim.api.nvim_set_keymap('n', '<leader>tvt',
    "<Cmd>call VSCodeNotify('television.ToggleTextFinder')<CR>",
    { noremap = true, silent = true })

-- GCC Build functionality
_G.build_if_gccbuild_enabled = function()
  local enabled = vscode.get_config("workspaceKeybindings.gccbuild.enabled")
  if enabled then
    vim.cmd("call VSCodeNotify('workbench.action.tasks.runTask', 'GCC Build')")
  else
    print("GCC Build is disabled")
  end
end
vim.api.nvim_set_keymap('n', '<leader>bc',
    "<Cmd>lua build_if_gccbuild_enabled()<CR>",
    { noremap = true, silent = true })
