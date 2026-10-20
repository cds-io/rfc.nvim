-- The reader's settings. setup() merges a table over these defaults; the
-- rims read the result, and the core takes what it needs as arguments.
local M = {}

---@class rfc.Config
---@field cache_dir string|nil   -- where documents live; stdpath("cache")/rfc by default
---@field notify fun(msg: string, level: integer, opts: { title: string })|nil  -- where messages go; vim.notify by default
---@field sources table<string, boolean>  -- which sources :Rfc reads: rfc (the RFC Editor), eip and erc (the Ethereum repositories)

M.defaults = {
    cache_dir = nil,
    notify = nil,
    sources = { rfc = true, eip = false, erc = false },
}

local current = vim.deepcopy(M.defaults)

---@param opts rfc.Config|nil
---@return rfc.Config
function M.set(opts)
    current = vim.tbl_deep_extend("force", vim.deepcopy(M.defaults), opts or {})
    vim.validate("cache_dir", current.cache_dir, "string", true)
    vim.validate("notify", current.notify, "function", true)
    vim.validate("sources", current.sources, "table")
    return current
end

---@return rfc.Config
function M.get()
    return current
end

return M
