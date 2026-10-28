-- Subjects and lifecycle selection in editor UI.
local config = require("rfc.config")
local store = require("rfc.store")
local subjects = require("rfc.subjects")
local lifecycle = require("rfc.status")
local fp = require("cds.fp")
local session = require("rfc.app.session")
local ensure_setup, enabled, run = session.ensure_setup, session.enabled, session.run
local entries = require("rfc.app.entries")
local index_of, statuses_of = entries.index_of, entries.statuses_of
local cached = require("rfc.app.subjects_cache")
local subjects_of, subjects_fresh = cached.subjects_of, cached.subjects_fresh
return function(help_tag, refresh)
    local M = { notify = session.notify, index_lines = entries.index_lines, ensure_subjects = cached.ensure_subjects }
    --- Runs `done` once the source's subjects document is in the store: a
    --- source the reader has not enabled is refused in words, a fetch is
    --- announced, a failure is notified, and a buffer still holding the old
    --- document goes first so :help reads the file written just now.
    ---@param source rfc.Source
    ---@param done fun()
    local function with_subjects(source, done)
        local cfg = config.get()
        local name = source.prefix .. "-subjects"
        if not enabled(source) then
            M.notify(
                ("%s is %s; enable sources.%s in setup()"):format(name, source.label, source.prefix),
                vim.log.levels.WARN
            )
            return
        end
        if not subjects_fresh(source) then
            M.notify("fetching the " .. source.label .. " subjects")
        end
        run(M.ensure_subjects(source), source.label .. " subjects", function(_, err)
            if err then
                M.notify(err, vim.log.levels.ERROR)
                return
            end
            refresh(store.doc_path(cfg, name))
            done()
        end)
    end
    --- Filters the source's subjects document to one status: `name` empty
    --- offers every status the index holds, with its count and All first;
    --- otherwise the status it names, case aside, or All. The document is
    --- rendered again with the entries standing there and opened, at the
    --- section the reader was in when it was the document shown.
    ---@param source rfc.Source
    ---@param name string
    function M.status(source, name)
        ensure_setup()
        run(M.index_lines(source), source.label .. " index", function(_, err)
            if err then
                M.notify(err, vim.log.levels.ERROR)
                return
            end
            local counts = statuses_of(source)
            if #counts == 0 and source.status_of then
                M.notify(
                    ("%s statuses are in the proposals' texts; :%s subjects fetches every one"):format(
                        source.label,
                        source.label:sub(1, 1) .. source.label:sub(2):lower()
                    ),
                    vim.log.levels.INFO
                )
            end
            --- The choice recorded, the document rendered again. A window
            --- showing it is kept in its section by the redraw; the reader is
            --- taken to one when elsewhere, and the document opened when none.
            local function apply(status)
                lifecycle.set(source.prefix, status)
                with_subjects(source, function()
                    local file_tag = source.prefix .. "-subjects"
                    local buf = vim.fn.bufnr(store.doc_path(config.get(), file_tag))
                    if buf == vim.api.nvim_get_current_buf() then
                        return
                    end
                    local wins = buf ~= -1 and vim.fn.win_findbuf(buf) or {}
                    if #wins > 0 then
                        vim.api.nvim_set_current_win(wins[1])
                        return
                    end
                    help_tag(file_tag, source)
                end)
            end
            if name ~= "" then
                if name:lower() == "all" then
                    apply(nil)
                    return
                end
                local hit = fp.find(counts, function(c)
                    return c.name:lower() == name:lower()
                end)
                if not hit then
                    M.notify(("%s has no status %s"):format(source.label, name), vim.log.levels.WARN)
                    return
                end
                apply(hit.name)
                return
            end
            local total = #(index_of(source):memo("entries", source.entries) or {})
            local items = fp.map(counts, function(c)
                return { name = c.name, text = ("%s  (%d)"):format(c.name, c.count) }
            end)
            table.insert(items, 1, { name = nil, text = ("All  (%d)"):format(total) })
            vim.ui.select(items, {
                kind = "rfc",
                prompt = source.label .. " status",
                format_item = function(item)
                    return item.text
                end,
            }, function(item)
                if item then
                    apply(item.name)
                end
            end)
        end)
    end

    --- The nodes of a source's subjects, read from the subjects document in
    --- the store (completion cannot wait on the network), once per version
    --- of the file; none before the document exists.
    ---@param source rfc.Source
    ---@return rfc.SubjectNode[]
    function M.nodes(source)
        ensure_setup()
        if not source.subjects then
            return {}
        end
        return subjects_of(source):memo("nodes", subjects.read_nodes) or {}
    end

    --- Opens the source's subjects document: at its top for an empty query;
    --- at the node the query names by its slug, or by its last level when
    --- that names one node; otherwise at the one node a fuzzy search over the
    --- paths finds, with several offered in vim.ui.select and none said so.
    ---@param source rfc.Source
    ---@param query string
    function M.subjects(source, query)
        ensure_setup()
        with_subjects(source, function()
            if query == "" then
                help_tag(source.prefix .. "-subjects", source)
                return
            end
            local nodes = M.nodes(source)
            local exact = fp.find(nodes, function(n)
                return n.slug == query
            end)
            local by_leaf = fp.filter(nodes, function(n)
                return n.leaf == query
            end)
            local hit = exact or (#by_leaf == 1 and by_leaf[1]) or nil
            if hit then
                help_tag(hit.tag, source)
                return
            end
            local matches = vim.fn.matchfuzzy(nodes, query, { key = "path" })
            if #matches == 0 then
                M.notify("nothing matches " .. query, vim.log.levels.WARN)
                return
            end
            if #matches == 1 then
                help_tag(matches[1].tag, source)
                return
            end
            vim.ui.select(matches, {
                kind = "rfc",
                prompt = "subjects matching " .. query,
                format_item = function(n)
                    return ("%s  (%d)"):format(n.path, n.count)
                end,
            }, function(n)
                if n then
                    help_tag(n.tag, source)
                end
            end)
        end)
    end

    M.with_subjects = with_subjects
    return M
end
