-- Report images and wide-table folds.
local tables = require("rfc.tables")
local images = require("cds.images")
local fp = require("cds.fp")
local WIDTH = 78
local M = {}
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
local function show_report(buf, lines, ns)
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
        vim.api.nvim_buf_set_extmark(buf, ns, t.caption_line - 1, 0, {
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

M.show, M.hide, M.is_report = show_report, hide_report, is_report
return M
