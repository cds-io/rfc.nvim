-- The dispatch rim: :Rfc, the keys in an RFC's help buffer, and the
-- pipeline that fetches an RFC, renders it and hands it to :help.
local config = require("rfc.config")
local store = require("rfc.store")
local fetch = require("rfc.fetch")
local help = require("rfc.help")
local rfc = require("cds.rfc")
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

--- The RFC in the store: fetched, rendered and written when it is absent.
---@param rfc_num string
---@return cds.Task  -- of rfc_num
function M.ensure(rfc_num)
    local cfg = config.get()
    if store.has(cfg, rfc_num) then
        return Task.of(rfc_num)
    end
    return fetch
        .rfc(rfc_num)
        :map(help.clean)
        :map(function(lines)
            return { raw = lines, doc = help.render(rfc_num, lines) }
        end)
        :on_main()
        :bind(function(r)
            local ok, err = store.write(cfg, rfc_num, r.raw, r.doc)
            if not ok then
                return Task.fail(err)
            end
            return Task.of(rfc_num)
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

--- `:help tag`. A tag of an RFC not in the store fetches it first and
--- tries again; any other refusal is shown as :help would show it.
---@param tag string
function M.jump(tag)
    ensure_setup()
    local ok, err = pcall(vim.cmd.help, tag)
    if ok then
        return
    end
    err = vim_error(tostring(err))
    local rfc_num = tag:match("^rfc(%d+)")
    if rfc_num and err:match("^E149") and not store.has(config.get(), rfc_num) then
        M.open(rfc_num, tag)
        return
    end
    M.notify(err, vim.log.levels.ERROR)
end

--- Opens the RFC at `tag` (its own tag by default), fetching it when needed.
---@param rfc_num string
---@param tag? string
function M.open(rfc_num, tag)
    ensure_setup()
    tag = tag or ("rfc" .. rfc_num)
    if store.has(config.get(), rfc_num) then
        M.jump(tag)
        return
    end
    M.notify("fetching RFC " .. rfc_num)
    run(M.ensure(rfc_num), "RFC " .. rfc_num, function(_, err)
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

--- The index as a Task of its lines: the cached copy while it is a day
--- old, fetched otherwise, and the stale copy when the fetch fails.
---@return cds.Task
function M.index_lines()
    local cfg = config.get()
    local cached, fresh = store.read_index(cfg)
    if cached and fresh then
        return Task.of(cached)
    end
    return fetch
        .index()
        :map(help.clean)
        :on_main()
        :bind(function(lines)
            local ok, err = store.write_index(cfg, lines)
            if not ok then
                return Task.fail(err)
            end
            return Task.of(lines)
        end)
        :recover(function(err)
            if cached then
                M.notify(
                    "the RFC index could not be refreshed (" .. tostring(err) .. "); using the stale copy",
                    vim.log.levels.WARN
                )
                return Task.of(cached)
            end
            return Task.fail(err)
        end)
end

--- Picks an RFC from the index with vim.ui.select and opens it.
function M.pick()
    ensure_setup()
    run(M.index_lines(), "RFC index", function(lines, err)
        if err then
            M.notify(err, vim.log.levels.ERROR)
            return
        end
        vim.ui.select(rfc.index(lines), {
            kind = "rfc",
            prompt = "search/select an RFC",
            format_item = function(item)
                return item.number .. " " .. item.label
            end,
        }, function(item)
            if not item then
                return
            end
            if not vim.tbl_contains(item.formats, "TXT") then
                M.notify(
                    ("RFC %s has no text version (%s)"):format(item.number, table.concat(item.formats, ", ")),
                    vim.log.levels.WARN
                )
                return
            end
            M.open(item.number)
        end)
    end)
end

-- The requirement keywords of RFC 2119, highlighted in an RFC's help buffer.
-- A keyword may wrap, so a space in it matches across a line break.
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

--- The keys and highlights of an RFC's help buffer; a no-op for any other.
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
