---@tag rfc.nvim
---@text RFCs, Ethereum's EIPs and ERCs, Bitcoin's BIPs, Solana's SIMDs and the
--- W3C's technical reports, as Neovim help.
---
--- `:Rfc 9110` fetches the RFC's text from the RFC Editor, renders it as a
--- help document and opens it with |:help|; `:Eip 1559`, `:Bip 32`,
--- `:Simd 64` and `:W3c wcag22` do the same from each proposal's source.
--- From then on the editor's own help navigation is the whole interface: >
---
---   :help rfc9110         the RFC
---   :help rfc9110-3.1     a section, completed over every cached document
---   CTRL-]                follow a link: a section, a cited RFC, a reference
---   CTRL-T                back through the tag stack, across documents
---   :helpgrep MUST NOT    search every cached document into the quickfix
--- <
--- A link to a document not cached yet (`|rfc2616|` in RFC 9110's text)
--- fetches it on CTRL-] and then jumps. Requires Neovim 0.13 (`vim.async`)
--- and `curl`; the house library cds-lua comes with the plugin as its one
--- dependency (|rfc.nvim-setup|).
---
---@toc

---@tag rfc.nvim-commands
---@toc_entry Commands
---@text One command per source, each with the same forms: a number (or a
--- shortname), a tag, words to search the index, nothing for the picker, and
--- `status` and `subjects` for a source that has them. >
---
---   :Rfc                  the RFC index in vim.ui.select
---   :Rfc http semantics   the entries whose number or title match, fuzzily;
---                         one match opens at once, several are offered
---   :Rfc 9110             an RFC by number
---   :Rfc rfc2616-14.4     a tag
---   :Rfc sem<Tab>         completion by number or title over the cached
---                         index and the tags of cached RFCs
---   :Rfc status           the statuses of the lifecycle, each with its count
---   :Rfc status internet standard   the subjects filtered to that status
---   :Rfc subjects         the RFCs by subject, as one help document
---   :Rfc subjects dns     a subject by slug or name, else a search over them
--- <
--- The five commands: >
---
---   :Rfc    the RFC Editor's RFCs
---   :Eip    Ethereum's EIPs and ERCs, one number space: `:Eip 20` is ERC-20
---   :Bip    Bitcoin's BIPs; `:Bip 0032` and `:Bip 32` are the same one
---   :Simd   Solana's SIMDs
---   :W3c    the W3C's technical reports, by shortname: `:W3c wcag22`
--- <
--- A picked or completed item reads `eip20  Token Standard (Final)`: the tag,
--- then the title; the command takes the first word. The first item a picker
--- offers is the source's subjects document, above the index and above a
--- search's matches alike. Completion cannot wait on the network, so it
--- offers what the last picker or search left in the cache; those fetch an
--- index that is missing or a day old. |rfc.nvim-sources| has each source.

---@tag rfc.nvim-keys
---@toc_entry Keys
---@text In a document's window: >
---
---   CTRL-]       follow the tag under the cursor; an uncached target fetches
---   CTRL-T       back through the tag stack, across documents
---   <CR>         follow the first link on the line: Enter on a ToC row
---   ]]  [[       the next and the previous section, with a count
---   gO           the contents beside the document
---   gs           in a subjects document, the next status of the lifecycle
---   <Leader>tv   the rich view on and off
---   zo           unfold a wide table laid out under its caption
--- <
--- `gO` opens the contents beside the document: one row per heading,
--- indented by level, the cursor on the section yours is in. There `<CR>` is
--- |:help| on that section in the document's window, so CTRL-T returns, and
--- `q` or `gO` closes it.
---
--- A document opens in the rich view: a rule above every heading and the
--- heading highlighted, drawn over the text as extmarks, so `<Leader>tv` puts
--- the text back as written in place; the file on disk is the text plus its
--- tags and links either way. The requirement words of RFC 2119 (MUST,
--- SHOULD NOT, MAY) are bold. In a W3C report, a figure's image is drawn
--- below its URL line where an image plugin is loaded and the terminal can
--- draw (image.nvim under kitty or ghostty); otherwise the caption, alt text
--- and URL read as text, and |gx| on the URL opens it.

---@tag rfc.nvim-status
---@toc_entry By status
---@text Every source's documents move through a lifecycle, and its index says
--- where each stands: an RFC's category (PROPOSED STANDARD, INTERNET
--- STANDARD, INFORMATIONAL), an EIP's status (Draft, Review, Last Call,
--- Final, Living, Stagnant, Withdrawn), a BIP's (Draft, Complete, Deployed,
--- Closed), a W3C report's maturity (Draft Standard, Candidate Standard,
--- Standard, Note). The status cuts across the subjects: a Core EIP and an
--- ERC are each Draft or Final, so the filter is the subjects document's
--- (|rfc.nvim-subjects|).
---
--- `:Eip status` offers the statuses in the lifecycle's order, each with its
--- count and `All` first. Choosing one renders the subjects document again
--- with only the proposals standing there: every category keeps its heading
--- with the count of what remains, the `Status` root has that one child, and
--- the title line reads `[Status: Final]`. The document opens at the section
--- you were in, or at its top when that section has nothing left.
--- `:Eip status final` goes straight there, case aside, `:Eip status all`
--- puts everything back, and `:Eip status <Tab>` completes the names. In the
--- document `gs` cycles the status: All, each in order, All again; every
--- window showing the document keeps its section, and the contents sidebar
--- follows.
---
--- The choice holds for the session and starts from `All`, or from the
--- status `setup` names for the source: `status = { eip = "Final" }`. The
--- SIMDs keep their status in each proposal's text, so theirs are known once
--- `:Simd subjects` has fetched the texts; `:Simd status` says so until then.

---@tag rfc.nvim-subjects
---@toc_entry By subject
---@text `:Rfc subjects` opens the RFCs by subject as one help document: a
--- contents block of every subject, indented by level, then one section per
--- subject listing the RFCs filed there as links. Everything a document has,
--- this one has too: `gO` is the tree as a sidebar, `<CR>` or CTRL-] on a
--- listed RFC fetches and opens it, `]]` walks the subjects, |:helpgrep|
--- searches them, and `:help rfc-subjects-naming-dns` lands on a subject by
--- its tag (the path slugged, level by level). `:Rfc subjects dns` lands
--- there too, and a word that names no subject is a search over them.
---
--- Where each source's subjects come from:
---
---   `:Rfc subjects`    the RFC Editor's subject tags (the rfc-subject-tags
---                    repository, in beta): a curated tree of 19 roots, four
---                    levels at most, that their pipeline assigns to every
---                    RFC and publishes daily as a CSV. An RFC sits under its
---                    deepest tags; the count beside a subject is every RFC
---                    under it, each counted once.
---   `:Eip subjects`    two roots: the site's six categories (Core, Networking,
---                    Interface, ERC, Meta, Informational), with the hardfork
---                    meta EIPs under `Meta / Hardforks` since their titles
---                    say so, and Status, so `Status / Last Call` is what is
---                    about to be final across the categories.
---   `:Bip subjects`    the README's two columns, Layer and Type, each a root.
---   `:Simd subjects`   each proposal's status, read from its frontmatter: the
---                    first open fetches every proposal once, eight at a
---                    time, and keeps the texts.
---   `:W3c subjects`    Maturity, Tags and Deliverers (the working groups), so
---                    `:W3c subjects wot` lands on the Web of Things reports.

---@tag rfc.nvim-sources
---@toc_entry Sources
---@text Five sources, chosen in |rfc.nvim-setup|; only the RFC Editor is on by
--- default.
---
---   `rfc`    tags `rfc9110`, `rfc9110-3.1`; the text from rfc-editor.org, the
---          index from rfc-index.txt.
---   `eip`    tags `eip1559`, `eip1559-specification`, `eip20` with `erc20` as
---          its alias; the text from github.com/ethereum/EIPs, then from
---          ethereum/ERCs when the EIPs repository says the proposal moved
---          or never had it; the index is the site's six category pages read
---          as one, each number once, which is also where a proposal's
---          category comes from.
---   `bip`    tags `bip32`, `bip32-conventions`; the text from
---          github.com/bitcoin/bips, MediaWiki or markdown, the index the
---          repository's README.
---   `simd`   tags `simd64`, `simd64-summary`; the text from the proposals
---          directory of solana-foundation/solana-improvement-documents,
---          which, listed through the GitHub API, is also the index.
---   `w3c`    tags `w3c-wcag22`, `w3c-css-grid-2#5.3` (the `#` splits the
---          shortname from the section, since shortnames carry dashes); the
---          HTML from www.w3.org/TR/<shortname>/ as ReSpec or Bikeshed writes
---          it, read by `cds.html`; the index is www.w3.org/TR. A report is
---          asked for again with `If-Modified-Since` when the index dates it
---          after the copy, so a republished draft follows its publication.
---
--- Every index is kept a day. A text is rendered once and kept: the
--- frontmatter or preamble becomes a header block, headings get tags and a
--- table of contents of links, fenced code becomes a help code block, tables
--- are aligned, and every cited RFC, EIP, section or reference becomes a
--- link.

---@tag rfc.nvim-cache
---@toc_entry The cache
---@text Everything lives under `stdpath("cache")/rfc/`, or `cache_dir`: each
--- text as fetched (`rfc9110.txt`, `eip1559.md`), its document
--- (`doc/rfc9110.txt`), the tags file, each source's index and its subjects
--- document. That `doc/` directory is appended to the runtimepath, which is
--- how |:help| finds a document; the tags file is the plugin's own, since
--- |:helptags| would read the `*/*` media ranges in an RFC's text as tags.
--- An index is fetched again when more than a day old, and a stale copy
--- stands in with a warning when the fetch fails; a document is rendered
--- again when the render that wrote it is older than the plugin's or its
--- text is newer. Delete the directory to start over.
---
--- `require("rfc").activity()` is a statusline segment naming the fetches
--- out, with their seconds; `User RfcActivity` fires when one starts or ends.

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
local w3c = require("cds.w3c")
local cache = require("rfc.cache")
local redraw = require("cds.redraw")
local lifecycle = require("rfc.status")
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

--- The checkout this module was loaded from.
---@return string
local function plugin_root()
    return vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":h:h:h")
end

---@tag rfc.nvim-setup rfc.setup()
---@toc_entry Setup
---@signature rfc.setup(opts)
---@text The reader's settings (|rfc.Config|) merged over the defaults, and the
--- cache's `doc/` directory put on the runtimepath. Optional: the first
--- command runs it with the defaults. >lua
---
---   require("rfc").setup({ sources = { eip = true }, status = { eip = "Final" } })
--- <
---@param opts? rfc.Config   -- the settings; what is left out keeps its default
function M.setup(opts)
    help.set_render(store.render_version(plugin_root()))
    local ok, err = store.register(config.set(opts))
    -- a session's status choices start over with its settings
    lifecycle.chosen = {}
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

--- A document's tag: the prefix and the id, joined with a dash for a
--- source that goes by shortname (w3c-wcag22) and directly otherwise
--- (rfc9110).
---@param source rfc.Source
---@param id string
---@return string
local function tag_of(source, id)
    return source.key == "shortname" and (source.prefix .. "-" .. id) or (source.prefix .. id)
end

--- The id a tag of the source carries, or nil for a subjects tag: the
--- number after the prefix, or the shortname before the section's #.
---@param source rfc.Source
---@param tag string
---@return string|nil
local function id_of(source, tag)
    if tag:match("^%l[%l%d]-%l%-subjects") then
        return nil
    end
    if source.key == "shortname" then
        return tag:match("^" .. source.prefix .. "%-([^#%.]+)")
    end
    return tag:match("^%l+0*(%d+)")
end

local entry_of

--- The text from the source: straight by number, or, for a source whose
--- index names each document's file, with the file its entry carries, the
--- index fetched first; `since` is the copy's time, for a source that asks
--- conditionally.
---@param source rfc.Source
---@param id string
---@param since integer|nil
---@return cds.Task  -- of the text as one string, or as the cache's produce answers
local function fetch_text(source, id, since)
    if not source.located then
        return source.fetch(id)
    end
    return M.index_lines(source):bind(function()
        local entry = entry_of(source, id)
        if not (entry and entry.file) then
            return Task.fail(("%s %s does not exist"):format(source.label, id))
        end
        return source.fetch(id, entry.file, since)
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
--- The index's entry for a document, from the cached index, parsed once
--- per copy; nil without.
---@param source rfc.Source
---@param id string
---@return rfc.Entry|nil
entry_of = function(source, id)
    local entries = index_of(source):memo("entries", source.entries) or {}
    return fp.find(entries, function(e)
        return e.id == id
    end)
end

local function raw_of(source, id)
    local entry = source.key == "shortname" and entry_of(source, id) or nil
    return cache.fetched(config.get(), {
        file = tag_of(source, id) .. "." .. source.raw_ext,
        produce = function(since)
            return fetch_text(source, id, since)
        end,
        label = source.label .. " " .. id,
        placeholder = source.placeholder,
        -- a report republished after the copy was taken is asked for again
        modified = entry and entry.date and w3c.date_time(entry.date) or nil,
    })
end

--- A document as a cache entry over its text: rendered when missing, when
--- an older render wrote it, or when the text is newer.
---@param source rfc.Source
---@param id string
---@return rfc.Derived
local function document_of(source, id)
    return cache.derived(config.get(), {
        name = tag_of(source, id),
        from = { raw_of(source, id) },
        version = help.RENDER,
        produce = function(lines)
            -- a render that needs the document's file (a report's URL, for
            -- its figures) gets it as a third argument; the others ignore it
            local entry = source.located and entry_of(source, id) or nil
            return source.render(id, lines, entry and entry.file or nil)
        end,
    })
end

--- The entries with their statuses: as the index gives them, or, for a
--- source whose index carries none, read from each cached text (an entry
--- whose text is not on disk has none yet).
---@param source rfc.Source
---@param entries rfc.Entry[]
---@return rfc.Entry[]
local function with_status(source, entries)
    if not source.status_of then
        return entries
    end
    return fp.map(entries, function(e)
        local copy = vim.deepcopy(e)
        copy.status = raw_of(source, e.id):memo("status", source.status_of)
        return copy
    end)
end

--- The statuses a source's cached index places its entries in, with
--- counts, in lifecycle order; none before the index is on disk.
---@param source rfc.Source
---@return { name: string, count: integer }[]
local function statuses_of(source)
    local entries = index_of(source):memo("entries", source.entries)
    return entries and lifecycle.counts(source.status, with_status(source, entries)) or {}
end

--- A source's subjects document as a cache entry: over its subjects
--- index, or, for a source whose subjects are in its documents' texts,
--- over the text of every document the cached index names (none cached:
--- no inputs, and the document is not current until the index is).
--- Filtered to the status chosen for the source (the reader's default
--- before any choice): only the entries standing there are filed, the
--- title line says so, and the render version carries the status, so a
--- document rendered under another is rendered again. The source's index
--- says where each entry stands, so it joins the inputs when a status
--- filters.
---@param source rfc.Source
---@return rfc.Derived
local function subjects_of(source)
    local s = source.subjects
    local status =
        lifecycle.named(source.status or {}, lifecycle.get(source.prefix, config.get().status[source.prefix]))
    local doc = { prefix = source.prefix, title = s.title, about = s.about, key = source.key, status = status }
    local name = source.prefix .. "-subjects"
    local version = help.RENDER .. subjects.suffix(status)
    if s.texts then
        local listed = index_of(source):memo("entries", source.entries) or {}
        return cache.derived(config.get(), {
            name = name,
            from = fp.map(listed, function(e)
                return raw_of(source, e.id)
            end),
            version = version,
            limit = 8,
            produce = function(...)
                local texts = { ... }
                local entries = fp.filter_map(listed, function(e, i)
                    if not status or source.status_of(texts[i]) == status then
                        return s.entry(e.id, texts[i])
                    end
                end)
                return subjects.render(doc, cds_subjects.tree(entries, s.roots))
            end,
        })
    end
    local from = { subjects_index_of(source) }
    if status then
        table.insert(from, index_of(source))
    end
    return cache.derived(config.get(), {
        name = name,
        from = from,
        version = version,
        produce = function(lines, index_lines)
            local entries, err = s.entries(lines)
            if not entries then
                return nil, err
            end
            if status then
                local standing = fp.set(
                    fp.filter(with_status(source, source.entries(index_lines)), function(e)
                        return e.status == status
                    end),
                    function(e)
                        return e.id
                    end
                )
                entries = fp.filter(entries, function(e)
                    return standing[e.id] == true
                end)
            end
            return subjects.render(doc, cds_subjects.tree(entries, s.roots))
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
        refresh(store.doc_path(cfg, name))
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
    local id = source and id_of(source, tag)
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
    tag = tag or tag_of(source, id)
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
        -- a buffer still holding the document's earlier render is refreshed,
        -- so :help reads the file written just now rather than showing what
        -- it loaded; then straight to :help, since asking jump again would
        -- ask the store again
        refresh(store.doc_path(config.get(), name))
        help_tag(tag, source)
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
    return tag_of(source, entry.id) .. "  " .. entry.label
end

--- A source's index as a Task of its lines: the cached copy while it is a
--- day old, fetched otherwise, and the stale copy when the fetch fails.
---@param source rfc.Source
---@return cds.Task
function M.index_lines(source)
    return index_of(source):lines()
end

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
    if fp.any(from, function(source)
        return enabled(source) and source.status ~= nil
    end) then
        table.insert(out, "status")
    end
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
--- alias), `subjects` with a node after it or not, `status` with a status
--- after it or not, words to search its index, or nothing for its picker
--- (on the configured status, when one is set). A completed item carries its title
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
        elseif first == "status" and source.status then
            M.status(source, vim.trim(arg:sub(#first + 1)))
        elseif sources.of(first) == source then
            M.jump(first)
        elseif source.key == "shortname" and arg == first then
            -- one word: the report of that shortname when the index names
            -- it, a search otherwise
            M.open_named(source, first)
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
            if source.status and cmdline:match("^%S+%s+status%s") then
                local names = fp.map(statuses_of(source), function(c)
                    return c.name
                end)
                table.insert(names, 1, "All")
                return arglead == "" and names or vim.fn.matchfuzzy(names, arglead)
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
    local subjects_source = sources.of(vim.fn.fnamemodify(vim.api.nvim_buf_get_name(buf), ":t:r"))
    if subjects_source and vim.api.nvim_buf_get_name(buf):match("%-subjects%.txt$") then
        vim.keymap.set("n", "gs", function()
            local order = fp.map(statuses_of(subjects_source), function(c)
                return c.name
            end)
            local current = lifecycle.get(subjects_source.prefix, config.get().status[subjects_source.prefix])
            M.status(subjects_source, lifecycle.next(order, current) or "all")
        end, { buffer = buf, desc = "rfc: the subjects on the next status of the lifecycle" })
    end
    vim.keymap.set("n", "<leader>tv", function()
        view.toggle(buf)
    end, { buffer = buf, desc = "rfc: [T]oggle the rich [v]iew" })
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
