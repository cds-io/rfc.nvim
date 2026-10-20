-- The dispatch rim: :Rfc, the keys in a document's help buffer, and the
-- pipeline that fetches a document from its source, renders it and hands
-- it to :help.
local config = require("rfc.config")
local store = require("rfc.store")
local help = require("rfc.help")
local sources = require("rfc.sources")
local Task = require("cds.task")

local M = {}

local TITLE = "rfc"

M._activity = require("cds.activity").new({ autocmd = "RfcActivity" })

--- The statusline segment: the fetches out, with their seconds.
---@return string
function M.activity()
    return M._activity:segment()
end

--- Every message goes through here: the reader's `notify` handler when set,
--- vim.notify with the title as a prefix otherwise. Safe from a fast event.
---@param msg string
---@param level? integer
function M.notify(msg, level)
    level = level or vim.log.levels.INFO
    local function deliver()
        local handler = config.get().notify
        if handler then
            handler(msg, level, { title = TITLE })
        else
            vim.notify(TITLE .. ": " .. msg, level, { title = TITLE })
        end
    end
    if vim.in_fast_event() then
        vim.schedule(deliver)
    else
        deliver()
    end
end

local configured = false

---@param opts? rfc.Config
function M.setup(opts)
    store.register(config.set(opts))
    configured = true
end

local function ensure_setup()
    if not configured then
        M.setup()
    end
end

---@param source rfc.Source
---@return boolean
local function enabled(source)
    return config.get().sources[source.prefix] == true
end

--- The document in the store: fetched, rendered and written when absent.
---@param source rfc.Source
---@param id string
---@return cds.Task  -- of the document's name
function M.ensure(source, id)
    local cfg = config.get()
    local name = source.prefix .. id
    if store.has(cfg, name) then
        return Task.of(name)
    end
    return source
        .fetch(id)
        :map(help.clean)
        :map(function(lines)
            return { raw = lines, doc = source.render(id, lines) }
        end)
        :on_main()
        :bind(function(r)
            local ok, err = store.write(cfg, name, source.raw_ext, r.raw, r.doc)
            if not ok then
                return Task.fail(err)
            end
            return Task.of(name)
        end)
end

--- Runs a Task on the main loop, tracked in the activity segment, and hands
--- `done(value, err)` its outcome; a thrown error arrives as the err.
---@param task cds.Task
---@param label string
---@param done fun(value: any, err: any)
local function run(task, label, done)
    local handle = task:on_main():run()
    M._activity:track("fetch", label, handle)
    handle:on_complete(function(terr, value, err)
        vim.schedule(function()
            done(value, terr and tostring(terr) or err)
        end)
    end)
end

---@param err string
---@return string
local function vim_error(err)
    return err:match("E%d+:.*") or err
end

--- `:help tag`. A tag of a document its source has not been asked for
--- fetches it first and tries again; a tag of a source the reader has not
--- enabled says so; any other refusal is shown as :help would show it.
---@param tag string
function M.jump(tag)
    ensure_setup()
    local ok, err = pcall(vim.cmd.help, tag)
    if ok then
        return
    end
    err = vim_error(tostring(err))
    local source = err:match("^E149") and sources.of(tag)
    if source then
        if not enabled(source) then
            M.notify(
                ("%s is %s; enable sources.%s in setup()"):format(tag, source.label, source.prefix),
                vim.log.levels.WARN
            )
            return
        end
        local id = tag:match("^%l+(%d+)")
        if not store.has(config.get(), source.prefix .. id) then
            M.open(source, id, tag)
            return
        end
    end
    M.notify(err, vim.log.levels.ERROR)
end

--- Opens the document at `tag` (its own tag by default), fetching it from
--- its source when needed.
---@param source rfc.Source
---@param id string
---@param tag? string
function M.open(source, id, tag)
    ensure_setup()
    tag = tag or (source.prefix .. id)
    if store.has(config.get(), source.prefix .. id) then
        M.jump(tag)
        return
    end
    M.notify("fetching " .. source.label .. " " .. id)
    run(M.ensure(source, id), source.label .. " " .. id, function(_, err)
        if err then
            M.notify(err, vim.log.levels.ERROR)
            return
        end
        M.jump(tag)
    end)
end

--- The tag under the cursor, through jump.
function M.follow()
    local ok, word = pcall(vim.fn.expand, "<cword>")
    if not ok or word == "" then
        M.notify("nothing under the cursor", vim.log.levels.WARN)
        return
    end
    M.jump(word)
end

--- The first link on the cursor line, through jump: Enter on a ToC row.
function M.follow_line()
    local tag = vim.api.nvim_get_current_line():match("|([^|%s]+)|")
    if not tag then
        M.notify("no link on this line", vim.log.levels.WARN)
        return
    end
    M.jump(tag)
end

--- How the picker and completion show an entry: its tag, then its title,
--- so the tag is the first word of whatever the reader picks.
---@param source rfc.Source
---@param entry rfc.Entry
---@return string
local function label(source, entry)
    return source.prefix .. entry.id .. "  " .. entry.label
end

--- A source's index as a Task of its lines: the cached copy while it is a
--- day old, fetched otherwise, and the stale copy when the fetch fails.
---@param source rfc.Source
---@return cds.Task
function M.index_lines(source)
    local cfg = config.get()
    local cached, fresh = store.read_index(cfg, source.index_file)
    if cached and fresh then
        return Task.of(cached)
    end
    return source
        .index()
        :map(help.clean)
        :on_main()
        :bind(function(lines)
            local ok, err = store.write_index(cfg, source.index_file, lines)
            if not ok then
                return Task.fail(err)
            end
            return Task.of(lines)
        end)
        :recover(function(err)
            if cached then
                M.notify(
                    ("the %s index could not be refreshed (%s); using the stale copy"):format(
                        source.label,
                        tostring(err)
                    ),
                    vim.log.levels.WARN
                )
                return Task.of(cached)
            end
            return Task.fail(err)
        end)
end

--- Picks a document from the enabled sources' indices with vim.ui.select
--- and opens it. With a query, only the entries that fuzzily match it are
--- offered, and a single match opens at once.
---@param query? string
function M.pick(query)
    ensure_setup()
    local tasks = {}
    for _, source in ipairs(sources.all) do
        if enabled(source) then
            table.insert(
                tasks,
                M.index_lines(source):map(function(lines)
                    local items = {}
                    for _, entry in ipairs(source.entries(lines)) do
                        table.insert(items, { source = source, entry = entry, text = label(source, entry) })
                    end
                    return items
                end)
            )
        end
    end
    run(Task.all(tasks), "index", function(lists, err)
        if err then
            M.notify(err, vim.log.levels.ERROR)
            return
        end
        local items = {}
        for _, list in ipairs(lists) do
            vim.list_extend(items, list)
        end
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
            if not item.entry.text then
                M.notify(("%s %s has no text version"):format(item.source.label, item.entry.id), vim.log.levels.WARN)
                return
            end
            M.open(item.source, item.entry.id)
        end
        if query and #items == 1 then
            choose(items[1])
            return
        end
        vim.ui.select(items, {
            kind = "rfc",
            prompt = query and ("documents matching " .. query) or "search/select a document",
            format_item = function(item)
                return item.text
            end,
        }, choose)
    end)
end

-- The entries of each cached index, parsed once per version of the file.
local parsed = {}

--- What :Rfc can complete to, from what is on disk: every entry of each
--- enabled source's cached index (fresh or stale; completion cannot wait
--- on the network), and every tag of every cached document.
---@return string[]
function M.candidates()
    ensure_setup()
    local cfg = config.get()
    local out = {}
    for _, source in ipairs(sources.all) do
        if enabled(source) then
            local path = store.index_path(cfg, source.index_file)
            local stat = vim.uv.fs_stat(path)
            if stat then
                local memo = parsed[path]
                if not memo or memo.mtime ~= stat.mtime.sec then
                    memo = { mtime = stat.mtime.sec, labels = {} }
                    for _, entry in ipairs(source.entries(vim.fn.readfile(path))) do
                        table.insert(memo.labels, label(source, entry))
                    end
                    parsed[path] = memo
                end
                vim.list_extend(out, memo.labels)
            end
        end
    end
    local tags = store.doc_dir(cfg) .. "/tags"
    if vim.fn.filereadable(tags) == 1 then
        for _, line in ipairs(vim.fn.readfile(tags)) do
            local name = line:match("^([^\t]+)\t")
            if name and not name:match("%.txt$") then
                table.insert(out, name)
            end
        end
    end
    return out
end

--- The completion of :Rfc's argument: every candidate when nothing is
--- typed, the fuzzy matches otherwise.
---@param arglead string
---@return string[]
function M.complete(arglead)
    local candidates = M.candidates()
    if arglead == "" then
        return candidates
    end
    return vim.fn.matchfuzzy(candidates, arglead)
end

-- The requirement keywords of RFC 2119, highlighted in a document's help
-- buffer. A keyword may wrap, so a space in it matches across a line break.
-- stylua: ignore
local REQUIREMENTS = {
    "MUST NOT", "MUST", "NOT REQUIRED", "REQUIRED", "SHALL NOT", "SHALL", "SHOULD NOT", "SHOULD",
    "NOT RECOMMENDED", "RECOMMENDED", "MAY NOT", "MAY", "NOT OPTIONAL", "OPTIONAL",
}

--- Whether the buffer is one of the store's documents. Both paths are
--- resolved: Neovim names a buffer by its real path, and a cache under a
--- symlinked directory (/var on macOS) would otherwise never match.
---@param buf integer
---@return boolean
function M.owns(buf)
    local name = vim.fn.resolve(vim.api.nvim_buf_get_name(buf))
    local dir = vim.fn.fnamemodify(vim.fn.resolve(store.doc_dir(config.get())), ":p")
    return vim.startswith(name, dir)
end

--- The keys and highlights of a document's help buffer; a no-op for any other.
---@param buf integer
function M.attach(buf)
    ensure_setup()
    if not M.owns(buf) then
        return
    end
    vim.keymap.set("n", "<C-]>", M.follow, { buffer = buf, desc = "rfc: follow the tag under the cursor" })
    vim.keymap.set("n", "<CR>", M.follow_line, { buffer = buf, desc = "rfc: follow the first link on the line" })
    local alternates = table.concat(REQUIREMENTS, "\\|"):gsub(" ", "\\\\_s\\\\+")
    vim.api.nvim_buf_call(buf, function()
        vim.cmd("syntax match rfcRequirement /\\<\\(" .. alternates .. "\\)\\>/")
    end)
    local type_hl = vim.api.nvim_get_hl(0, { name = "Type", link = false })
    vim.api.nvim_set_hl(0, "rfcRequirement", { fg = type_hl.fg, bold = true, default = true })
end

return M
