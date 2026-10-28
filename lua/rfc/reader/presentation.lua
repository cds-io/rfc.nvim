-- Shared document presentation and buffer lifetimes.
local document = require("cds.document")
local vellum = require("cds.vellum")
local document_view = require("cds.document_view")
return function(deps)
    local M, models, wiped = {}, {}, {}
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
        -- a rendered document pads its banner and spacer lines, which a
        -- reader's trailing-space marker would dot
        vim.wo[win].list = false
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
            deps.bindings(buf)
        end,
        attach_window = attach_window,
        image_wait = function()
            return deps.image_wait()
        end,
        group = "rfc_document",
        filetype = "rfc-document",
    })

    function M.model(buf)
        return models[buf]
    end
    local function show(model, destination)
        model.name, model.document = destination.name, destination.document
        model.markdown = destination.document.markdown
        presenter.show(model)
        deps.bindings(model.buf)
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
    function M.reload(name)
        for buf, old in pairs(models) do
            if old.name == name and current(old) then
                local saved = {}
                for _, win in ipairs(vim.fn.win_findbuf(buf)) do
                    local view = vim.api.nvim_win_call(win, vim.fn.winsaveview)
                    local headings = deps.headings(buf) or {}
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
                            deps.reload_toc(win)
                        end
                    end
                end)
            end
        end
    end

    M.attach_window = attach_window

    M.fresh, M.show = fresh, show

    return M
end
