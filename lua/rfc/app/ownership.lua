-- Recognize documents owned by this plugin.
local config = require("rfc.config")
local store = require("rfc.store")
local M = {}

--- Whether the buffer is one of the store's documents. Both paths are
--- resolved: Neovim names a buffer by its real path, and a cache under a
--- symlinked directory (/var on macOS) would otherwise never match.
---@param buf integer
---@return boolean
function M.owns(buf)
    if vim.api.nvim_buf_get_name(buf):match("^rfc://document/") then
        return true
    end
    local name = vim.fn.resolve(vim.api.nvim_buf_get_name(buf))
    local dir = vim.fn.fnamemodify(vim.fn.resolve(store.doc_dir(config.get())), ":p")
    return name:match("^rfc://document/") ~= nil or vim.startswith(name, dir)
end

return M
