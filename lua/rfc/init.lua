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
local subjects = require("rfc.subjects")
local cds_subjects = require("cds.subjects")
local cache = require("rfc.cache")
local fp = require("cds.fp")
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
    local ok, err = store.register(config.set(opts))
    configured = true
    if not ok then
        M.notify(err, vim.log.levels.ERROR)
    end
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

local DAY = 24 * 60 * 60

--- A source's index as a cache entry: kept a day, the stale copy with a
--- warning when the fetch fails.
---@param source rfc.Source
---@return rfc.Fetched
local function index_of(source)
    return cache.fetched(config.get(), {
        file = source.index_file,
        produce = source.index,
        max_age = DAY,
        label = "the " .. source.label .. " index",
        notify = M.notify,
    })
end

--- A source's subjects index as a cache entry, kept like its index.
---@param source rfc.Source
---@return rfc.Fetched
local function subjects_index_of(source)
    local s = source.subjects
    return cache.fetched(config.get(), {
        file = s.index_file,
        produce = s.index,
        max_age = DAY,
        label = "the " .. source.label .. " subjects index",
        notify = M.notify,
    })
end

--- A document's text as a cache entry: it never ages, and a placeholder
--- (the stub a moved proposal leaves) is fetched again.
---@param source rfc.Source
---@param id string
---@return rfc.Fetched
local function raw_of(source, id)
    return cache.fetched(config.get(), {
        file = source.prefix .. id .. "." .. source.raw_ext,
        produce = function()
            return fetch_text(source, id)
        end,
        label = source.label .. " " .. id,
        placeholder = source.placeholder,
    })
end

--- A document as a cache entry over its text: rendered when missing, when
--- an older render wrote it, or when the text is newer.
---@param source rfc.Source
---@param id string
---@return rfc.Derived
local function document_of(source, id)
    return cache.derived(config.get(), {
        name = source.prefix .. id,
        from = { raw_of(source, id) },
        version = help.RENDER,
        produce = function(lines)
            return source.render(id, lines)
        end,
    })
end

--- A source's subjects document as a cache entry: over its subjects
--- index, or, for a source whose subjects are in its documents' texts,
--- over the text of every document the cached index names (none cached:
--- no inputs, and the document is not current until the index is).
---@param source rfc.Source
---@return rfc.Derived
local function subjects_of(source)
    local s = source.subjects
    local doc = { prefix = source.prefix, title = s.title, about = s.about }
    local name = source.prefix .. "-subjects"
    if s.texts then
        local listed = index_of(source):memo("entries", source.entries) or {}
        return cache.derived(config.get(), {
            name = name,
            from = fp.map(listed, function(e)
                return raw_of(source, e.id)
            end),
            version = help.RENDER,
            limit = 8,
            produce = function(...)
                local texts = { ... }
                local entries = fp.map(listed, function(e, i)
                    return s.entry(e.id, texts[i])
                end)
                return subjects.render(doc, cds_subjects.tree(entries))
            end,
        })
    end
    return cache.derived(config.get(), {
        name = name,
        from = { subjects_index_of(source) },
        version = help.RENDER,
        produce = function(lines)
            local entries, err = s.entries(lines)
            if not entries then
                return nil, err
            end
            return subjects.render(doc, cds_subjects.tree(entries))
        end,
    })
end

--- Whether a source's subjects need no fetch: its subjects index is
--- fresh, or, for subjects in the texts, its index is fresh and every
--- text it names is on disk.
---@param source rfc.Source
---@return boolean
local function subjects_fresh(source)
    if not source.subjects.texts then
        return subjects_index_of(source):fresh()
    end
    return index_of(source):fresh()
        and fp.all(subjects_of(source).from, function(input)
            return input:mtime() ~= nil
        end)
end

--- The document in the store: fetched, rendered and written when absent,
--- rendered again when an older render wrote it or its text is newer.
---@param source rfc.Source
---@param id string
---@return cds.Task  -- of the document's name
function M.ensure(source, id)
    return document_of(source, id):ensure()
end

--- Runs a Task on the main loop, tracked in the activity segment, and hands
--- `done(value, err)` its outcome; a thrown error arrives as the err.
---@param task cds.Task
---@param label string
---@param done fun(value: any, err: any)
local with_subjects

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

--- The subjects document in the store: rendered from the subjects index
--- (the cached copy while it is a day old) unless it is already there by
--- the current render and no older than the index.
---@param source rfc.Source
---@return cds.Task  -- of the document's name
function M.ensure_subjects(source)
    if source.subjects.texts then
        -- the index first, since the document's inputs are what it names
        return index_of(source):lines():bind(function()
            return subjects_of(source):ensure()
        end)
    end
    return subjects_of(source):ensure()
end

--- Runs `done` once the source's subjects document is in the store: a
--- source the reader has not enabled is refused in words, a fetch is
--- announced, a failure is notified, and a buffer still holding the old
--- document goes first so :help reads the file written just now.
---@param source rfc.Source
---@param done fun()
with_subjects = function(source, done)
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
        local stale = vim.fn.bufnr(store.doc_path(cfg, name))
        if stale ~= -1 then
            vim.api.nvim_buf_delete(stale, { force = true })
        end
        done()
    end)
end

--- `:help tag`, with a refusal in words: a tag of a source the reader has
--- not enabled says so; any other refusal is shown as :help would show it.
---@param tag string
---@param source rfc.Source|nil
local function help_tag(tag, source)
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

--- `:help tag`. A tag of a document that is not in the store, or that an
--- older render wrote, goes through open first (erc20 is eip20's alias, so
--- the document is eip20's); a subjects tag whose document is missing or
--- older than its index goes through the subjects pipeline first; a tag
--- of a source the reader has not enabled says so; any other refusal is
--- shown as :help would show it.
---@param tag string
function M.jump(tag)
    ensure_setup()
    local source = sources.of(tag)
    local id = source and tag:match("^%l+0*(%d+)")
    if source and id and enabled(source) and not document_of(source, id):current() then
        M.open(source, id, tag)
        return
    end
    if source and not id and source.subjects and enabled(source) then
        if not subjects_of(source):current() then
            -- straight to :help afterwards: the document was just written,
            -- and asking jump again would ask the store again
            with_subjects(source, function()
                help_tag(tag, source)
            end)
            return
        end
    end
    help_tag(tag, source)
end

--- Opens the document at `tag` (its own tag by default), fetching it from
--- its source when needed.
---@param source rfc.Source
---@param id string
---@param tag? string
function M.open(source, id, tag)
    ensure_setup()
    tag = tag or (source.prefix .. id)
    if document_of(source, id):current() then
        M.jump(tag)
        return
    end
    if not raw_of(source, id):cached() then
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
    return index_of(source):lines()
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
                M.notify(("%s %s has no text version"):format(item.source.label, item.entry.id), vim.log.levels.WARN)
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

--- What a command can complete to, from what is on disk: every entry of
--- each given source's cached index (fresh or stale; completion cannot wait
--- on the network), parsed once per version of the file, the word
--- `subjects` for a source that has them, and every tag of those sources'
--- cached documents.
---@param from rfc.Source[]
---@return string[]
function M.candidates(from)
    ensure_setup()
    local cfg = config.get()
    local out = fp.reduce(fp.filter(from, enabled), {}, function(all, source)
        local labels = index_of(source):memo("labels", function(lines)
            return fp.map(source.entries(lines), function(entry)
                return label(source, entry)
            end)
        end)
        return vim.list_extend(all, labels or {})
    end)
    local any_subjects = fp.any(from, function(source)
        return enabled(source) and source.subjects ~= nil
    end)
    if any_subjects then
        table.insert(out, "subjects")
    end
    local tags = store.doc_dir(cfg) .. "/tags"
    if vim.fn.filereadable(tags) == 1 then
        local entries = fp.map(vim.fn.readfile(tags), function(line)
            local name, file = line:match("^([^\t]+)\t([^\t]+)")
            return { name = name, file = file }
        end)
        -- a document's file tag is its file's name; a node named robots.txt
        -- ends the same way and is a tag to offer
        local offered = fp.filter(entries, function(t)
            return t.name ~= nil and t.name ~= t.file and vim.tbl_contains(from, sources.of(t.name))
        end)
        vim.list_extend(
            out,
            fp.map(offered, function(t)
                return t.name
            end)
        )
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
--- alias), `subjects` with a node after it or not, words to search its
--- index, or nothing for its picker. A completed item carries its title
--- after the tag, so only the first word is the tag. After `subjects`,
--- completion is over the nodes of the cached subjects index.
---@param source rfc.Source
---@return fun(cmd: table), fun(arglead: string, cmdline: string): string[]
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
        elseif first == "subjects" and source.subjects then
            M.subjects(source, vim.trim(arg:sub(#first + 1)))
        elseif sources.of(first) == source then
            M.jump(first)
        else
            M.pick(arg, from)
        end
    end
    return run_command,
        function(arglead, cmdline)
            if source.subjects and cmdline:match("^%S+%s+subjects%s") then
                local slugs = fp.map(M.nodes(source), function(n)
                    return n.slug
                end)
                return arglead == "" and slugs or vim.fn.matchfuzzy(slugs, arglead)
            end
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
