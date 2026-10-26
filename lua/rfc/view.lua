-- The rich view of a document: a rule drawn above every heading and the
-- heading's text highlighted, as extmarks over the help buffer, so the
-- document on disk stays the text as written and the view goes on and off
-- without a reload. A W3C report gets two more: its figures drawn below
-- their URL lines through the images adapter where a backend can, and a
-- table wider than the page folded under its caption with the entry form
-- as virtual lines, so the file keeps the aligned table. The model is per
-- buffer (the outline is text-derived) and revalidated by the buffer's
-- changedtick, since :help sets the filetype before it reads the file.
local outline = require("rfc.outline")
local tables = require("rfc.tables")
local images = require("cds.images")
local fp = require("cds.fp")

local M = {}

M.ns = vim.api.nvim_create_namespace("rfc.view")

local WIDTH = 78

---@type table<integer, { tick: integer, headings: rfc.Heading[] }>
local cache = {}
---@type table<integer, boolean>  -- the buffers the view is drawn in
local rich = {}

vim.api.nvim_set_hl(0, "rfcHeading", { link = "Title", default = true })
vim.api.nvim_set_hl(0, "rfcRule", { link = "@markup.heading.1.delimiter.vimdoc", default = true })
vim.api.nvim_set_hl(0, "rfcEntry", { link = "Normal", default = true })

--- Whether the buffer holds a W3C report: its file is named by the w3c
--- prefix.
---@param buf integer
---@return boolean
local function is_report(buf)
    return vim.api.nvim_buf_get_name(buf):match("/w3c%-[^/]*%.txt$") ~= nil
end

--- The lines a figure's image sits on: a line that is only an indented
--- URL ending in an image extension; SVG is left to gx, the ImageMagick
--- here having no coder for it.
---@param lines string[]
---@return { line: integer, url: string }[]
local function figure_urls(lines)
    local out = {}
    for i, l in ipairs(lines) do
        local url = l:match("^%s+(https?://%S+)$")
        if url and url:lower():match("%.[pj][np]e?g$") or url and url:lower():match("%.gif$") then
            table.insert(out, { line = i, url = url })
        end
    end
    return out
end

--- The windows showing the buffer.
---@param buf integer
---@return integer[]
local function windows_of(buf)
    return vim.fn.win_findbuf(buf)
end

--- The fold text of a wide table's rows: the caption above and the count.
---@return string
function M.foldtext()
    local caption = vim.fn.getline(vim.v.foldstart - 1):gsub(" ~$", "")
    return ("%s (%d rows, zo for the aligned table)"):format(caption, vim.v.foldend - vim.v.foldstart + 1)
end

--- Draws a report's figures and folds its wide tables.
---@param buf integer
---@param lines string[]
local function show_report(buf, lines)
    if images.available() then
        for _, f in ipairs(figure_urls(lines)) do
            for _, win in ipairs(windows_of(buf)) do
                local height = math.max(4, math.floor(vim.api.nvim_win_get_height(win) * 0.4))
                images.place({ buf = buf, win = win, row = f.line, url = f.url, max_height = height })
                break
            end
        end
    end
    local wide = fp.filter(tables.of(lines), function(t)
        return fp.any({ unpack(lines, t.first, t.last) }, function(l)
            return #l > WIDTH
        end)
    end)
    for _, t in ipairs(wide) do
        local entries = tables.entries(t, WIDTH)
        vim.api.nvim_buf_set_extmark(buf, M.ns, t.caption_line - 1, 0, {
            virt_lines = fp.map(entries, function(l)
                return { { l, "rfcEntry" } }
            end),
        })
        for _, win in ipairs(windows_of(buf)) do
            vim.api.nvim_win_call(win, function()
                -- a help window opens with folds disabled
                vim.wo[win].foldenable = true
                vim.wo[win].foldmethod = "manual"
                vim.wo[win].foldtext = "v:lua.require'rfc.view'.foldtext()"
                vim.cmd(("%d,%dfold"):format(t.first, t.last))
                vim.cmd(("%dfoldclose"):format(t.first))
            end)
        end
    end
end

--- Removes a report's figures and folds.
---@param buf integer
local function hide_report(buf)
    images.clear_all(buf)
    for _, win in ipairs(windows_of(buf)) do
        vim.api.nvim_win_call(win, function()
            if vim.wo[win].foldmethod == "manual" then
                vim.cmd("normal! zE")
            end
        end)
    end
end

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
    local document_headings = require("rfc").document_headings(buf)
    if document_headings then
        return document_headings
    end
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
    if is_report(buf) then
        show_report(buf, vim.api.nvim_buf_get_lines(buf, 0, -1, false))
    end
    rich[buf] = true
end

---@param buf integer
function M.hide(buf)
    vim.api.nvim_buf_clear_namespace(buf, M.ns, 0, -1)
    if is_report(buf) then
        hide_report(buf)
    end
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
