require("config.keymaps")
require("config.lazy")
require("_common.options")
require("_common.keymaps")
if vim.g.vscode then
    require("_vscode.options")
else
    require("_nvim.options")
    require("_nvim.keymaps")
end
