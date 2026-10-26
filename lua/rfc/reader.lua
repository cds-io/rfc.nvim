-- Shared document rendering and tag navigation, with RFC resolution injected.
local document = require("cds.document")
local navigator = require("cds.navigator")
local vellum = require("cds.vellum")
local document_view = require("cds.document_view")

local Reader = {}

---@class rfc.ReaderDestination
---@field name string
---@field document rfc.Document

---@param deps { resolve: fun(tag: string, done: fun(destination: rfc.ReaderDestination?, err: string?)), notify: function, toc: table, attach: function? }
---@return table
function Reader.new(deps)
    local M, models, wiped = {}, {}, {}
    local nav = navigator.new()
    local ns = vim.api.nvim_create_namespace("rfc.document")
    local function current(model)
        return models[model.buf] == model
            and vim.api.nvim_buf_is_valid(model.buf)
            and vim.api.nvim_buf_is_loaded(model.buf)
    end
    local function draw(buf, rendered)
        vim.bo[buf].modifiable = true
        vim.api.nvim_buf_set_lines(buf, 0, -1, false, rendered.lines)
        vim.bo[buf].modifiable = false
        vim.bo[buf].modified = false
        vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
        for _, mark in ipairs(rendered.marks) do
            vim.api.nvim_buf_set_extmark(buf, ns, mark.lnum - 1, mark.col, {
                end_col = mark.end_col,
                hl_group = mark.hl,
                priority = mark.priority,
            })
        end
    end
    local function attach_window(win)
        local model = models[vim.api.nvim_win_get_buf(win)]
        vim.wo[win].wrap = not (model and model.doc and model.doc.styled)
        vim.wo[win].linebreak = true
        if model and model.doc and model.doc.styled then
            vim.wo[win].number, vim.wo[win].relativenumber = false, false
            vim.wo[win].signcolumn, vim.wo[win].foldcolumn, vim.wo[win].statuscolumn = "no", "0", ""
        end
    end
    local presenter = document_view.new({
        current = current,
        render = function(markdown, width)
            return vellum.render(markdown, width, { notify = deps.notify })
        end,
        draw = draw,
        attach = function(buf)
            M.attach(buf)
        end,
        attach_window = attach_window,
        image_wait = function()
            return M.image_wait
        end,
        group = "rfc_document",
        filetype = "rfc-document",
    })
    M.image_wait = 500

    function M.model(buf)
        return models[buf]
    end

    local function anchor(model, tag)
        if document.anchor(model.document, tag) then
            return tag
        end
        local owner, fragment = tag:match("^([^#]+)#(.*)$")
        return owner == model.name and fragment and document.anchor(model.document, fragment) and fragment or nil
    end

    local function jump(win, tag, remember)
        local model = models[vim.api.nvim_win_get_buf(win)]
        local found = model and model.document and anchor(model, tag)
        if not found then
            return false
        end
        local entry =
            { name = vim.api.nvim_buf_get_name(model.buf), view = vim.api.nvim_win_call(win, vim.fn.winsaveview) }
        local landed = nav.jump(win, model.document, model.doc, found)
        if landed and remember then
            nav.push(win, entry)
        end
        return landed
    end

    local function show(model, destination)
        model.name, model.document = destination.name, destination.document
        model.markdown = destination.document.markdown
        presenter.show(model)
        M.attach(model.buf)
        if deps.attach then
            deps.attach(model.buf)
        end
    end

    local function fresh(buf)
        local model = { buf = buf }
        models[buf] = model
        vim.bo[buf].buftype, vim.bo[buf].bufhidden = "nofile", "hide"
        vim.bo[buf].swapfile = false
        if not wiped[buf] then
            wiped[buf] = true
            vim.api.nvim_create_autocmd("BufWipeout", {
                buffer = buf,
                once = true,
                callback = function()
                    models[buf], wiped[buf] = nil, nil
                end,
            })
        end
        return model
    end

    function M.read(buf, name, after)
        local tag = name:match("^rfc://document/(.+)$")
        if not tag then
            return
        end
        local model = fresh(buf)
        draw(buf, { lines = { "loading " .. tag }, marks = {} })
        deps.resolve(tag, function(destination, err)
            if not current(model) then
                return
            end
            if not destination then
                draw(buf, { lines = { err or "document not available" }, marks = {} })
                deps.notify(err or "document not available", vim.log.levels.ERROR)
                return
            end
            show(model, destination)
            for win, saved in pairs(model.restore_views or {}) do
                if vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_buf(win) == buf then
                    vim.api.nvim_win_call(win, function()
                        vim.fn.winrestview(saved)
                    end)
                end
            end
            model.restore_views = nil
            if after then
                after(model)
            end
        end)
    end

    function M.jump(tag)
        local win = vim.api.nvim_get_current_win()
        if jump(win, tag, true) then
            return
        end
        nav.follow(win, tag, deps.resolve, function(destination, err, done)
            if not destination then
                deps.notify(err, vim.log.levels.ERROR)
                return
            end
            local target_model = { name = destination.name, document = destination.document }
            if not anchor(target_model, tag) then
                deps.notify("no anchor: " .. tag, vim.log.levels.WARN)
                return
            end
            local name = "rfc://document/" .. destination.name
            local buf = vim.fn.bufnr(name)
            if buf == -1 then
                buf = vim.api.nvim_create_buf(false, true)
                vim.api.nvim_buf_set_name(buf, name)
            end
            local model = fresh(buf)
            vim.api.nvim_win_set_buf(win, buf)
            show(model, destination)
            if not jump(win, tag, false) then
                vim.api.nvim_win_set_cursor(win, { 1, 0 })
                deps.notify("no anchor: " .. tag, vim.log.levels.WARN)
            end
            done()
        end)
    end

    function M.back()
        local win = vim.api.nvim_get_current_win()
        local entry = nav.pop(win)
        if not entry then
            deps.notify("no document to go back to")
            return
        end
        local buf = entry.buf and vim.api.nvim_buf_is_valid(entry.buf) and entry.buf or vim.fn.bufnr(entry.name)
        if buf ~= -1 and vim.api.nvim_buf_is_loaded(buf) then
            vim.cmd.buffer(buf)
        else
            vim.cmd.edit(vim.fn.fnameescape(entry.name))
        end
        local model = models[vim.api.nvim_get_current_buf()]
        if model and not model.doc then
            model.restore_views = model.restore_views or {}
            model.restore_views[win] = entry.view
        else
            vim.fn.winrestview(entry.view)
        end
    end

    local function link_under_cursor(first)
        local model = models[vim.api.nvim_get_current_buf()]
        if not (model and model.doc) then
            return nil
        end
        local row, col = unpack(vim.api.nvim_win_get_cursor(0))
        return document.target(
            model.document,
            model.doc,
            row,
            col,
            { first = first, line = vim.api.nvim_get_current_line() }
        )
    end

    local function follow(target)
        local tag = target:match("^rfc%-tag:(.+)$")
        if tag then
            M.jump(tag)
            return
        end
        local model = models[vim.api.nvim_get_current_buf()]
        local base, fragment = target:match("^([^#]*)#(.*)$")
        if fragment and (base == "" or model and base == model.document.url) then
            if not jump(vim.api.nvim_get_current_win(), fragment, true) then
                deps.notify("no anchor: " .. fragment)
            end
            return
        end
        local report = target:match("^https?://www%.w3%.org/TR/([^/#?]+)/?")
        if report then
            M.jump("w3c-" .. report:lower() .. (fragment and "#" .. fragment or ""))
            return
        end
        nav.cancel(vim.api.nvim_get_current_win())
        local scheme = (target:match("^(%a[%w+.-]*):") or ""):lower()
        if scheme == "javascript" or scheme == "data" then
            deps.notify("not followed: " .. target)
            return
        end
        vim.ui.open(target)
    end

    function M.follow(first)
        local target = link_under_cursor(first)
        if target then
            follow(target)
        else
            deps.notify("no link under the cursor")
        end
    end

    function M.headings(buf)
        local model = models[buf]
        if not (model and model.document and model.doc) then
            return nil
        end
        local headings = {}
        for _, h in ipairs(model.document.headings) do
            local row = document.anchor(model.document, h.tag, model.doc)
            if row then
                headings[#headings + 1] = { tag = h.tag, text = h.text, level = h.level, line = row }
            end
        end
        return headings
    end

    function M.step(count)
        local headings = M.headings(vim.api.nvim_get_current_buf()) or {}
        local index = require("rfc.outline").step(headings, vim.api.nvim_win_get_cursor(0)[1], count)
        if index then
            M.jump(headings[index].tag)
        end
    end

    function M.attach(buf)
        local function map(key, action)
            vim.keymap.set("n", key, action, { buffer = buf, desc = "rfc: document navigation" })
        end
        map("<C-]>", function()
            M.follow(false)
        end)
        map("<CR>", function()
            M.follow(true)
        end)
        map("<C-T>", M.back)
        map("]]", function()
            M.step(vim.v.count1)
        end)
        map("[[", function()
            M.step(-vim.v.count1)
        end)
        map("gO", function()
            deps.toc.toggle(vim.api.nvim_get_current_win())
        end)
        map("q", function()
            nav.cancel(vim.api.nvim_get_current_win())
            if #vim.api.nvim_tabpage_list_wins(0) > 1 then
                vim.cmd.close()
            else
                vim.cmd.enew()
            end
        end)
        map("gx", function()
            local target = link_under_cursor(false)
            if target then
                vim.ui.open(target)
            end
        end)
    end

    function M.reload(name)
        for buf, old in pairs(models) do
            if old.name == name and current(old) then
                local saved = {}
                for _, win in ipairs(vim.fn.win_findbuf(buf)) do
                    local view = vim.api.nvim_win_call(win, vim.fn.winsaveview)
                    local headings = M.headings(buf) or {}
                    local at = require("rfc.outline").at(headings, view.lnum)
                    saved[win] = {
                        view = view,
                        tag = at and headings[at].tag,
                        offset = at and view.lnum - headings[at].line or 0,
                    }
                end
                M.read(buf, vim.api.nvim_buf_get_name(buf), function(model)
                    for win, held in pairs(saved) do
                        if vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_buf(win) == buf then
                            local row = held.tag and document.anchor(model.document, held.tag, model.doc)
                            if row then
                                held.view.lnum = row + held.offset
                            end
                            vim.api.nvim_win_call(win, function()
                                vim.fn.winrestview(held.view)
                            end)
                            deps.toc.reload(win)
                        end
                    end
                end)
            end
        end
    end

    M.attach_window = attach_window
    M.forget = nav.forget
    return M
end
return Reader
