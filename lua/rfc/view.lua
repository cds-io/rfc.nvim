-- The rich view of a document: a rule drawn above every heading and the
-- heading's text highlighted, as extmarks over the help buffer, so the
-- document on disk stays the text as written and the view goes on and off
-- without a reload. The model is per buffer (the outline is text-derived)
-- and revalidated by the buffer's changedtick, since :help sets the
-- filetype before it reads the file.
local outline = require("rfc.outline")

local M = {}

M.ns = vim.api.nvim_create_namespace("rfc.view")

local WIDTH = 78

---@type table<integer, { tick: integer, headings: rfc.Heading[] }>
local cache = {}
---@type table<integer, boolean>  -- the buffers the view is drawn in
local rich = {}

vim.api.nvim_set_hl(0, "rfcHeading", { link = "Title", default = true })
vim.api.nvim_set_hl(0, "rfcRule", { link = "@markup.heading.1.delimiter.vimdoc", default = true })

local function group(buf)
    return "rfc.view." .. buf
end

local function forget(buf)
    cache[buf] = nil
    rich[buf] = nil
    pcall(vim.api.nvim_del_augroup_by_name, group(buf))
end

--- The buffer's headings, parsed once per text.
---@param buf integer
---@return rfc.Heading[]
function M.headings(buf)
    local tick = vim.api.nvim_buf_get_changedtick(buf)
    if not cache[buf] then
        vim.api.nvim_create_autocmd("BufWipeout", {
            buffer = buf,
            once = true,
            callback = function()
                forget(buf)
            end,
        })
    end
    if not cache[buf] or cache[buf].tick ~= tick then
        cache[buf] = { tick = tick, headings = outline.of(vim.api.nvim_buf_get_lines(buf, 0, -1, false)) }
    end
    return cache[buf].headings
end

--- Draws the view: a rule of = above a level-one heading, of - above any
--- deeper one, and the heading's text in rfcHeading. Drawing again replaces
--- what was drawn. Whatever puts a heading on the top line (a :help, a
--- jump, a zt) is followed by the editor's move or scroll event, and that is
--- the one place the rule above it is revealed.
---@param buf integer
function M.show(buf)
    vim.api.nvim_buf_clear_namespace(buf, M.ns, 0, -1)
    vim.api.nvim_create_autocmd({ "CursorMoved", "WinScrolled" }, {
        group = vim.api.nvim_create_augroup(group(buf), { clear = true }),
        buffer = buf,
        callback = function()
            M.reveal(0)
        end,
    })
    for _, h in ipairs(M.headings(buf)) do
        local rule = string.rep(h.level == 1 and "=" or "-", WIDTH)
        vim.api.nvim_buf_set_extmark(buf, M.ns, h.line - 1, 0, {
            end_col = #h.text,
            hl_group = "rfcHeading",
            virt_lines_above = true,
            virt_lines = { { { rule, "rfcRule" } } },
        })
    end
    rich[buf] = true
end

---@param buf integer
function M.hide(buf)
    vim.api.nvim_buf_clear_namespace(buf, M.ns, 0, -1)
    rich[buf] = nil
    pcall(vim.api.nvim_del_augroup_by_name, group(buf))
end

---@param buf integer
---@return boolean
function M.is_rich(buf)
    return rich[buf] == true
end

---@param buf integer
function M.toggle(buf)
    if rich[buf] then
        M.hide(buf)
    else
        M.show(buf)
    end
end

--- A heading put on the window's top line hides the rule above it (the
--- window fills no virtual lines above its topline on its own); this scrolls
--- one virtual line so the rule shows.
---@param win integer
function M.reveal(win)
    win = win == 0 and vim.api.nvim_get_current_win() or win
    local buf = vim.api.nvim_win_get_buf(win)
    if not rich[buf] then
        return
    end
    local headings = M.headings(buf)
    local line = vim.api.nvim_win_get_cursor(win)[1]
    local i = outline.at(headings, line)
    if not i or headings[i].line ~= line then
        return
    end
    vim.api.nvim_win_call(win, function()
        local v = vim.fn.winsaveview()
        if v.topline == line and v.topfill == 0 then
            vim.fn.winrestview({ topline = line, topfill = 1 })
        end
    end)
end

return M
