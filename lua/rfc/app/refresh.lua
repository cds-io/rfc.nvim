-- Preserve sections across document exports and reloads.
local view = require("rfc.view")
local outline = require("rfc.outline")
local redraw = require("cds.redraw")
local fp = require("cds.fp")
local toc = require("rfc.toc")
return function(reload)
    --- A document window's place across a redraw: the section its cursor is
    --- in, by tag, since the lines move; :help on that tag after, and on the
    --- document's own tag (its top) when the section is gone, both in that
    --- window, which :help reuses as it is a help window.
    ---@param file_tag string  -- eip-subjects, rfc9110
    ---@return cds.redraw.Keep
    local function section_of(file_tag)
        return {
            key = function(win)
                local headings = view.headings(vim.api.nvim_win_get_buf(win))
                local at = outline.at(headings, vim.api.nvim_win_get_cursor(win)[1])
                return at and headings[at].tag or file_tag
            end,
            seek = function(win, tag)
                return vim.api.nvim_win_call(win, function()
                    return pcall(vim.cmd.help, tag) or pcall(vim.cmd.help, file_tag)
                end)
            end,
        }
    end

    --- The buffer holding a document's earlier render, once the file is
    --- written anew: reloaded from disk in every window showing it, each
    --- window kept in its section, so a help window stays one (and :help
    --- reuses it) and the sidebar beside it reads the new rows; deleted when
    --- no window shows it, so :help reads the file rather than what the
    --- buffer loaded.
    ---@param path string
    local function refresh(path)
        if reload then
            reload(vim.fn.fnamemodify(path, ":t:r"))
        end
        local buf = vim.fn.bufnr(path)
        if buf == -1 then
            return
        end
        if #vim.fn.win_findbuf(buf) == 0 then
            vim.api.nvim_buf_delete(buf, { force = true })
            return
        end
        local wins = redraw.windows(buf, function(showing)
            -- one :edit reloads the buffer for every window
            vim.api.nvim_win_call(showing[1], function()
                vim.cmd("silent edit")
            end)
        end, section_of(vim.fn.fnamemodify(path, ":t:r")))
        fp.each(wins, toc.reload)
    end

    return refresh
end
