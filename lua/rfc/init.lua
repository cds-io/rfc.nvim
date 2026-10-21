-- The dispatch rim: :Rfc, the keys in a document's help buffer, and the
-- pipeline that fetches a document from its source, renders it and hands
-- it to :help.
local config = require("rfc.config")
local store = require("rfc.store")
local help = require("rfc.help")
local sources = require("rfc.sources")
local outline = require("rfc.outline")
local view = require("rfc.view")
local toc = require("rfc.toc")
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

--- The text from the source: straight by number, or, for a source whose
--- files the index names, through the index the rim keeps.
---@param source rfc.Source
---@param id string
---@return cds.Task  -- of the text as one string
local function fetch_text(source, id)
    if not source.locate then
        return source.fetch(id)
    end
    return M.index_lines(source):bind(function(index)
        local file = source.locate(id, index)
        if not file then
            return Task.fail(("%s %s does not exist"):format(source.label, id))
        end
        return source.fetch(id, file)
    end)
end

--- The document in the store: fetched, rendered and written when absent,
--- rendered again from the stored text when an older render wrote it.
---@param source rfc.Source
---@param id string
---@return cds.Task  -- of the document's name
function M.ensure(source, id)
    local cfg = config.get()
    local name = source.prefix .. id
    if store.has(cfg, name) then
        return Task.of(name)
    end
    local raw = store.raw(cfg, name, source.raw_ext)
    if raw and source.placeholder and source.placeholder(raw) then
        raw = nil
    end
    local text = raw and Task.of(raw) or fetch_text(source, id):map(help.clean)
    return text:map(function(lines)
        return { raw = lines, doc = source.render(id, lines) }
    end)
        :on_main()
        :bind_result(function(r)
            local ok, err = store.write(cfg, name, source.raw_ext, r.raw, r.doc)
            return ok and name or nil, err
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

--- `:help tag`. A tag of a document that is not in the store, or that an
--- older render wrote, goes through open first (erc20 is eip20's alias, so
--- the document is eip20's); a tag of a source the reader has not enabled
--- says so; any other refusal is shown as :help would show it.
---@param tag string
function M.jump(tag)
    ensure_setup()
    local source = sources.of(tag)
    local id = source and tag:match("^%l+0*(%d+)")
    if source and id and enabled(source) and not store.has(config.get(), source.prefix .. id) then
        M.open(source, id, tag)
        return
    end
    local ok, err = pcall(vim.cmd.help, tag)
    if ok then
        return
    end
    err = vim_error(tostring(err))
    if err:match("^E149") and source and not enabled(source) then
        M.notify(
            ("%s is %s; enable sources.%s in setup()"):format(tag, source.label, source.prefix),
            vim.log.levels.WARN
        )
        return
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
    local raw = store.raw(config.get(), source.prefix .. id, source.raw_ext)
    if not raw or (source.placeholder and source.placeholder(raw)) then
        M.notify("fetching " .. source.label .. " " .. id)
    end
    run(M.ensure(source, id), source.label .. " " .. id, function(name, err)
        if err then
            M.notify(err, vim.log.levels.ERROR)
            return
        end
        -- a buffer still holding the document's earlier render goes, so :help
        -- reads the file written just now rather than showing what it loaded
        local stale = vim.fn.bufnr(store.doc_path(config.get(), name))
        if stale ~= -1 then
            vim.api.nvim_buf_delete(stale, { force = true })
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
        :bind_result(function(lines)
            local ok, err = store.write_index(cfg, source.index_file, lines)
            return ok and lines or nil, err
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

--- Picks a document from the given sources' indices (the enabled ones,
--- by default) with vim.ui.select and opens it. With a query, only the
--- entries that fuzzily match it are offered, and a single match opens at
--- once.
---@param query? string
---@param from? rfc.Source[]
function M.pick(query, from)
    ensure_setup()
    local tasks = {}
    for _, source in ipairs(from or sources.all) do
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

--- What a command can complete to, from what is on disk: every entry of
--- each given source's cached index (fresh or stale; completion cannot wait
--- on the network), and every tag of those sources' cached documents.
---@param from rfc.Source[]
---@return string[]
function M.candidates(from)
    ensure_setup()
    local cfg = config.get()
    local out = {}
    for _, source in ipairs(from) do
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
            if name and not name:match("%.txt$") and vim.tbl_contains(from, sources.of(name)) then
                table.insert(out, name)
            end
        end
    end
    return out
end

--- The completion of a command's argument: every candidate when nothing
--- is typed, the fuzzy matches otherwise.
---@param from rfc.Source[]
---@param arglead string
---@return string[]
function M.complete(from, arglead)
    local candidates = M.candidates(from)
    if arglead == "" then
        return candidates
    end
    return vim.fn.matchfuzzy(candidates, arglead)
end

--- The command for a source: a number, a tag (the source's own or an
--- alias), words to search its index, or nothing for its picker. A
--- completed item carries its title after the tag, so only the first word
--- is the tag.
---@param source rfc.Source
---@return fun(cmd: table), fun(arglead: string): string[]
function M.command(source)
    local from = { source }
    local function run_command(cmd)
        local arg = vim.trim(cmd.args)
        local first = arg:match("^(%S+)") or ""
        if arg == "" then
            M.pick(nil, from)
        elseif first:match("^%d+$") then
            -- the BIPs are filed as bip-0032; the tag is bip32
            M.jump(source.prefix .. (first:gsub("^0+(%d)", "%1")))
        elseif sources.of(first) == source then
            M.jump(first)
        else
            M.pick(arg, from)
        end
    end
    return run_command, function(arglead)
        return M.complete(from, arglead)
    end
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

--- The cursor to the heading `count` headings away (back for a negative
--- count), on the jumplist; nothing when none lies that way.
---@param count integer
function M.step(count)
    local buf = vim.api.nvim_get_current_buf()
    local headings = view.headings(buf)
    local i = outline.step(headings, vim.api.nvim_win_get_cursor(0)[1], count)
    if not i then
        return
    end
    vim.cmd("normal! m'")
    vim.api.nvim_win_set_cursor(0, { headings[i].line, 0 })
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
    vim.keymap.set("n", "]]", function()
        M.step(vim.v.count1)
    end, { buffer = buf, desc = "rfc: next section" })
    vim.keymap.set("n", "[[", function()
        M.step(-vim.v.count1)
    end, { buffer = buf, desc = "rfc: previous section" })
    vim.keymap.set("n", "gO", function()
        toc.toggle(vim.api.nvim_get_current_win())
    end, { buffer = buf, desc = "rfc: the contents beside the document" })
    vim.keymap.set("n", "<leader>tv", function()
        view.toggle(buf)
    end, { buffer = buf, desc = "rfc: [T]oggle the rich [v]iew" })
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
