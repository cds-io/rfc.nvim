-- The reader's settings. setup() merges a table over these defaults; the
-- rims read the result, and the core takes what it needs as arguments.
local M = {}

---@class rfc.Config
---@field cache_dir string|nil   -- where documents live; stdpath("cache")/rfc by default
---@field notify fun(msg: string, level: integer, opts: { title: string })|nil  -- where messages go; vim.notify by default
---@field sources table<string, boolean>  -- rfc (the RFC Editor, :Rfc), eip (Ethereum's EIPs and ERCs, :Eip), bip (Bitcoin's BIPs, :Bip), simd (Solana's SIMDs, :Simd)
---@field view "rich"|"plain"   -- how a document opens: with rules above its headings, or as written
---@field toc { width: integer } -- the contents sidebar

M.defaults = {
    cache_dir = nil,
    notify = nil,
    sources = { rfc = true, eip = false, bip = false, simd = false },
    view = "rich",
    toc = { width = 44 },
}

local current = vim.deepcopy(M.defaults)

---@param opts rfc.Config|nil
---@return rfc.Config
function M.set(opts)
    current = vim.tbl_deep_extend("force", vim.deepcopy(M.defaults), opts or {})
    vim.validate("cache_dir", current.cache_dir, "string", true)
    vim.validate("notify", current.notify, "function", true)
    vim.validate("sources", current.sources, "table")
    vim.validate("view", current.view, function(v)
        return v == "rich" or v == "plain"
    end, "rich or plain")
    vim.validate("toc", current.toc, "table")
    vim.validate("toc.width", current.toc.width, "number")
    return current
end

---@return rfc.Config
function M.get()
    return current
end

return M
