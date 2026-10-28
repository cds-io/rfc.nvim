-- Index search and source document selection.
local fp = require("cds.fp")
local Task = require("cds.task")
local sources = require("rfc.sources")
local session = require("rfc.app.session")
local ensure_setup, enabled, run = session.ensure_setup, session.enabled, session.run
local names = require("rfc.app.names")
local label, tag_of = names.label, names.tag_of
local entries = require("rfc.app.entries")
local entry_of = entries.entry_of
return function(open, jump, subjects)
    local M =
        { open = open, jump = jump, subjects = subjects, notify = session.notify, index_lines = entries.index_lines }
    --- Opens the document a shortname names in the source's index, fetching
    --- the index first; a word the index does not name is a search.
    ---@param source rfc.Source
    ---@param word string
    function M.open_named(source, word)
        ensure_setup()
        if not enabled(source) then
            M.jump(tag_of(source, word:lower()))
            return
        end
        run(M.index_lines(source), source.label .. " index", function(_, err)
            if err then
                M.notify(err, vim.log.levels.ERROR)
                return
            end
            local hit = entry_of(source, word:lower())
            if hit then
                M.jump(tag_of(source, hit.id))
            else
                M.pick(word, { source })
            end
        end)
    end

    --- Picks a document from the given sources' indices (the enabled ones,
    --- by default) with vim.ui.select and opens it. With a query, only the
    --- entries that fuzzily match it are offered, and a single match opens at
    --- once.
    ---@param query? string
    ---@param from? rfc.Source[]
    function M.pick(query, from)
        ensure_setup()
        local on = fp.filter(from or sources.all, enabled)
        -- the door into a source's subjects: first in the list, as `tag  title`
        -- like every other item
        local doors = fp.map(
            fp.filter(on, function(source)
                return source.subjects ~= nil
            end),
            function(source)
                return { source = source, door = true, text = source.prefix .. "-subjects  " .. source.subjects.title }
            end
        )
        local tasks = fp.map(on, function(source)
            return M.index_lines(source):map(function(lines)
                return fp.map(source.entries(lines), function(entry)
                    return { source = source, entry = entry, text = label(source, entry) }
                end)
            end)
        end)
        run(Task.all(tasks), "index", function(lists, err)
            if err then
                M.notify(err, vim.log.levels.ERROR)
                return
            end
            local items = fp.reduce(lists, {}, function(all, list)
                return vim.list_extend(all, list)
            end)
            if query and query ~= "" then
                items = vim.fn.matchfuzzy(items, query, { key = "text" })
                if #items == 0 then
                    M.notify("nothing matches " .. query, vim.log.levels.WARN)
                    return
                end
            end
            local function choose(item)
                if not item then
                    return
                end
                if item.door then
                    M.subjects(item.source, "")
                    return
                end
                if not item.entry.text then
                    M.notify(
                        ("%s %s has no text version"):format(item.source.label, item.entry.id),
                        vim.log.levels.WARN
                    )
                    return
                end
                M.open(item.source, item.entry.id)
            end
            if query and #items == 1 then
                choose(items[1])
                return
            end
            items = vim.list_extend(vim.deepcopy(doors), items)
            vim.ui.select(items, {
                kind = "rfc",
                prompt = query and ("documents matching " .. query) or "search/select a document",
                format_item = function(item)
                    return item.text
                end,
            }, choose)
        end)
    end

    return M
end
