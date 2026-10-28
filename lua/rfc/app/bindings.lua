-- Buffer bindings, lifecycle cycling and help highlighting.
local config = require("rfc.config")
local sources = require("rfc.sources")
local outline = require("rfc.outline")
local view = require("rfc.view")
local toc = require("rfc.toc")
local lifecycle = require("rfc.status")
local fp = require("cds.fp")
local ensure_setup = require("rfc.app.session").ensure_setup
local statuses_of = require("rfc.app.entries").statuses_of
local owns = require("rfc.app.ownership").owns
-- The requirement keywords of RFC 2119, highlighted in a document's help
-- buffer. A keyword may wrap, so a space in it matches across a line break.
-- stylua: ignore
local REQUIREMENTS = {
    "MUST NOT", "MUST", "NOT REQUIRED", "REQUIRED", "SHALL NOT", "SHALL", "SHOULD NOT", "SHOULD",
    "NOT RECOMMENDED", "RECOMMENDED", "MAY NOT", "MAY", "NOT OPTIONAL", "OPTIONAL",
}

return function(reader, follow, follow_line, status)
    local M = { follow = follow, follow_line = follow_line, status = status, owns = owns }
    --- The cursor to the heading `count` headings away (back for a negative
    --- count), on the jumplist; nothing when none lies that way.
    ---@param count integer
    function M.step(count)
        if reader.model(vim.api.nvim_get_current_buf()) then
            reader.step(count)
            return
        end
        local buf = vim.api.nvim_get_current_buf()
        local headings = view.headings(buf)
        local i = outline.step(headings, vim.api.nvim_win_get_cursor(0)[1], count)
        if not i then
            return
        end
        vim.cmd("normal! m'")
        vim.api.nvim_win_set_cursor(0, { headings[i].line, 0 })
    end

    local function subject_keys(buf, source)
        if not source then
            return
        end
        vim.keymap.set("n", "gs", function()
            local order = fp.map(statuses_of(source), function(c)
                return c.name
            end)
            local selected = lifecycle.get(source.prefix, config.get().status[source.prefix])
            M.status(source, lifecycle.next(order, selected) or "all")
        end, { buffer = buf, desc = "rfc: the subjects on the next status of the lifecycle" })
    end

    --- The keys and highlights of a document's help buffer; a no-op for any other.
    ---@param buf integer
    function M.attach(buf)
        ensure_setup()
        if reader.model(buf) then
            reader.attach(buf)
            local name = reader.model(buf).name
            if name and name:match("%-subjects$") then
                subject_keys(buf, sources.of(name))
            end
            return
        end
        if not M.owns(buf) then
            return
        end
        local bindings = {
            { "<C-]>", follow, "follow the tag under the cursor" },
            { "<CR>", follow_line, "follow the first link on the line" },
            {
                "]]",
                function()
                    M.step(vim.v.count1)
                end,
                "next section",
            },
            {
                "[[",
                function()
                    M.step(-vim.v.count1)
                end,
                "previous section",
            },
            {
                "gO",
                function()
                    toc.toggle(vim.api.nvim_get_current_win())
                end,
                "the contents beside the document",
            },
            {
                "<leader>tv",
                function()
                    view.toggle(buf)
                end,
                "[T]oggle the rich [v]iew",
            },
        }
        fp.each(bindings, function(binding)
            vim.keymap.set("n", binding[1], binding[2], { buffer = buf, desc = "rfc: " .. binding[3] })
        end)
        local subjects_source = sources.of(vim.fn.fnamemodify(vim.api.nvim_buf_get_name(buf), ":t:r"))
        if subjects_source and vim.api.nvim_buf_get_name(buf):match("%-subjects%.txt$") then
            subject_keys(buf, subjects_source)
        end
        -- a rendered document keeps its source's line breaks, so a paragraph
        -- can run far past the help width; the window wraps it at word
        -- boundaries, continuations indented and list items hanging
        fp.each(vim.fn.win_findbuf(buf), function(win)
            vim.wo[win].wrap = true
            vim.wo[win].linebreak = true
            vim.wo[win].breakindent = true
            vim.wo[win].breakindentopt = "list:-1"
        end)
        if config.get().view == "rich" then
            -- :help sets the filetype before it reads the file, so the view is
            -- drawn now for a buffer that has its text and after the read otherwise
            if vim.api.nvim_buf_line_count(buf) > 1 then
                view.show(buf)
            else
                vim.api.nvim_create_autocmd("BufReadPost", {
                    buffer = buf,
                    once = true,
                    callback = function()
                        view.show(buf)
                    end,
                })
            end
        end
        local alternates = table.concat(REQUIREMENTS, "\\|"):gsub(" ", "\\\\_s\\\\+")
        vim.api.nvim_buf_call(buf, function()
            vim.cmd("syntax match rfcRequirement /\\<\\(" .. alternates .. "\\)\\>/")
        end)
        local type_hl = vim.api.nvim_get_hl(0, { name = "Type", link = false })
        vim.api.nvim_set_hl(0, "rfcRequirement", { fg = type_hl.fg, bold = true, default = true })
    end

    return M
end
