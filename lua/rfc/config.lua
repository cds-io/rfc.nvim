-- The reader's settings. setup() merges a table over these defaults; the
-- rims read the result, and the core takes what it needs as arguments.
local M = {}

--- How a document opens: with rules above its headings, or as written.
---@alias rfc.View "rich"|"plain"

---@tag rfc.Config
---@text The settings `setup` takes; every field is optional.
---@class rfc.Config
---@field cache_dir string|nil   -- where documents live; stdpath("cache")/rfc by default
---@field notify fun(msg: string, level: integer, opts: { title: string })|nil  -- where messages go;
---   vim.notify with an "rfc: " prefix by default
---@field sources table<string, boolean>  -- which commands are defined, by prefix: rfc (the RFC
---   Editor, :Rfc), eip (Ethereum's EIPs and ERCs, :Eip), bip (Bitcoin's BIPs, :Bip), simd
---   (Solana's SIMDs, :Simd), w3c (the W3C's technical reports, :W3c)
---@field view rfc.View   -- how a document opens: "rich", with rules above its headings, or
---   "plain", as written
---@field toc { width: integer }   -- the contents sidebar
---@field status table<string, string>  -- the status a source's subjects document opens filtered to,
---   by prefix: { eip = "Final" }; every entry when unset
---@text The defaults, which `setup` merges its argument over:
---@eval return MiniDoc.afterlines_to_code(MiniDoc.current.eval_section)
M.defaults = {
    cache_dir = nil,
    notify = nil,
    sources = { rfc = true, eip = false, bip = false, simd = false, w3c = false },
    view = "rich",
    toc = { width = 44 },
    status = {},
}
--minidoc_afterlines_end

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
    vim.validate("status", current.status, "table")
    return current
end

---@return rfc.Config
function M.get()
    return current
end

return M
