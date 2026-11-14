-- The reader's settings. setup() merges a table over these defaults; the
-- rims read the result, and the core takes what it needs as arguments.
local M = {}

--- Commands open a Markdown page by default; "help" opens the help export.
---@alias rfc.View "document"|"help"

---@tag rfc.Config
---@text The settings `setup` takes; every field is optional.
---@class rfc.Config
---@field cache_dir string|nil   -- where documents live; stdpath("cache")/rfc by default
---@field notify fun(msg: string, level: integer, opts: { title: string })|nil  -- where messages go;
---   vim.notify with an "rfc: " prefix by default
---@field sources table<string, boolean>  -- which sources are on, by prefix; a source left out is on as
---   its spec says (rfc on, the rest off). The shipped sources: rfc (the RFC Editor, :Rfc), eip
---   (Ethereum's EIPs and ERCs, :Eip), bip (Bitcoin's BIPs, :Bip), simd (Solana's SIMDs, :Simd), w3c
---   (the W3C's technical reports, :W3c), crs (the US Congressional Research Service's reports, :Crs);
---   every registered source has its command, and an off source's command says how to turn it on
---@field view rfc.View   -- how a document opens: "document" through Markdown/vellum, or "help" as the help
---   export (which the rich view decorates unless vim.g.rfc_rich is false)
---@field toc { width: integer }   -- the contents sidebar
---@field status table<string, string>  -- the status a source's subjects document opens filtered to,
---   by prefix: { eip = "Final" }; every entry when unset
---@field styled_max_lines integer  -- a document with more Markdown lines than this stays plain: treesitter and
---   vellum over tens of thousands of lines cost seconds the reader would wait frozen for
---@field progress { show_after: integer, linger: integer, at_once_bytes: integer }  -- the dashboard above a
---   document being prepared: shown once the preparation has run show_after milliseconds, or at once when it
---   fetches or its inputs on disk exceed at_once_bytes; kept linger milliseconds after it ends
---@text The defaults, which `setup` merges its argument over:
---@eval return MiniDoc.afterlines_to_code(MiniDoc.current.eval_section)
M.defaults = {
    cache_dir = nil,
    notify = nil,
    sources = {},
    view = "document",
    toc = { width = 44 },
    status = {},
    progress = { show_after = 500, linger = 1500, at_once_bytes = 2 * 1024 * 1024 },
    styled_max_lines = 20000,
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
    local registered = vim.tbl_map(function(spec)
        return spec.prefix
    end, require("rfc.sources").specs())
    for prefix, on in pairs(current.sources) do
        vim.validate("sources." .. prefix, prefix, function(p)
            return vim.tbl_contains(registered, p)
        end, "a registered source: " .. table.concat(registered, ", "))
        vim.validate("sources." .. prefix, on, "boolean")
    end
    vim.validate("view", current.view, function(v)
        return v == "document" or v == "help"
    end, "document or help")
    vim.validate("toc", current.toc, "table")
    vim.validate("toc.width", current.toc.width, "number")
    vim.validate("status", current.status, "table")
    vim.validate("progress", current.progress, "table")
    vim.validate("progress.show_after", current.progress.show_after, "number")
    vim.validate("progress.linger", current.progress.linger, "number")
    vim.validate("progress.at_once_bytes", current.progress.at_once_bytes, "number")
    vim.validate("styled_max_lines", current.styled_max_lines, "number")
    return current
end

---@return rfc.Config
function M.get()
    return current
end

return M
