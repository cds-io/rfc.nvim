-- A buffer's headings, for whatever reads a document's outline (the contents
-- sidebar, ]] and [[, a refresh's section restore) in any view: a document
-- page's from its model, which the reader answers, and a help buffer's from
-- its text, parsed once per changedtick, since :help sets the filetype
-- before it reads the file.
local outline = require("rfc.outline")
local M = {}

---@type table<integer, { tick: integer, headings: rfc.Heading[] }>
local cache = {}

local document_headings = function(_)
    return nil
end

--- Sets where a document page's headings come from.
---@param headings fun(buf: integer): rfc.Heading[]|nil
function M.configure(headings)
    document_headings = headings
end

--- The buffer's headings, parsed once per text.
---@param buf integer
---@return rfc.Heading[]
function M.headings(buf)
    local found = document_headings(buf)
    if found then
        return found
    end
    local tick = vim.api.nvim_buf_get_changedtick(buf)
    if not cache[buf] then
        vim.api.nvim_create_autocmd("BufWipeout", {
            buffer = buf,
            once = true,
            callback = function()
                cache[buf] = nil
            end,
        })
    end
    if not cache[buf] or cache[buf].tick ~= tick then
        cache[buf] = { tick = tick, headings = outline.of(vim.api.nvim_buf_get_lines(buf, 0, -1, false)) }
    end
    return cache[buf].headings
end

return M
