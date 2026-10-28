-- Tag navigation, cursor links and document history.
local document = require("cds.document")
local navigator = require("cds.navigator")
return function(model_of, fresh, show, resolve, notify)
    local M = {}
    local nav = navigator.new()
    local follow
    local function anchor(model, tag)
        if document.anchor(model.document, tag) then
            return tag
        end
        local owner, fragment = tag:match("^([^#]+)#(.*)$")
        return owner == model.name and fragment and document.anchor(model.document, fragment) and fragment or nil
    end

    local function jump(win, tag, remember)
        local model = model_of(vim.api.nvim_win_get_buf(win))
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
    function M.jump(tag)
        local win = vim.api.nvim_get_current_win()
        if jump(win, tag, true) then
            return
        end
        nav.follow(win, tag, resolve, function(destination, err, done)
            if not destination then
                notify(err, vim.log.levels.ERROR)
                return
            end
            local target_model = { name = destination.name, document = destination.document }
            if not anchor(target_model, tag) then
                notify("no anchor: " .. tag, vim.log.levels.WARN)
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
                notify("no anchor: " .. tag, vim.log.levels.WARN)
            end
            done()
        end)
    end

    function M.back()
        local win = vim.api.nvim_get_current_win()
        local entry = nav.pop(win)
        if not entry then
            notify("no document to go back to")
            return
        end
        local buf = entry.buf and vim.api.nvim_buf_is_valid(entry.buf) and entry.buf or vim.fn.bufnr(entry.name)
        if buf ~= -1 and vim.api.nvim_buf_is_loaded(buf) then
            vim.cmd.buffer(buf)
        else
            vim.cmd.edit(vim.fn.fnameescape(entry.name))
        end
        local model = model_of(vim.api.nvim_get_current_buf())
        if model and not model.doc then
            model.restore_views = model.restore_views or {}
            model.restore_views[win] = entry.view
        else
            vim.fn.winrestview(entry.view)
        end
    end

    local function link_under_cursor(first)
        local model = model_of(vim.api.nvim_get_current_buf())
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
    function M.follow(first)
        local target = link_under_cursor(first)
        if target then
            follow(target)
        else
            notify("no link under the cursor")
        end
    end

    function M.headings(buf)
        local model = model_of(buf)
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

    follow = require("rfc.reader.links")(model_of, M.jump, jump, notify, nav.cancel)
    M.target, M.cancel, M.forget = link_under_cursor, nav.cancel, nav.forget
    return M
end
