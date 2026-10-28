-- Application navigation over shared documents and legacy help exports.
local config = require("rfc.config")
local store = require("rfc.store")
local sources = require("rfc.sources")
local session = require("rfc.app.session")
local ensure_setup, enabled, run = session.ensure_setup, session.enabled, session.run
local names = require("rfc.app.names")
local tag_of, id_of = names.tag_of, names.id_of
local entries = require("rfc.app.entries")
local document_of, raw_of = entries.document_of, entries.raw_of
local subjects_of = require("rfc.app.subjects_cache").subjects_of
return function(reader, with_subjects, refresh)
    local M = { notify = session.notify, ensure = entries.ensure }
    ---@param err string
    ---@return string
    local function vim_error(err)
        return err:match("E%d+:.*") or err
    end
    --- `:help tag`, with a refusal in words: a tag of a source the reader has
    --- not enabled says so; any other refusal is shown as :help would show it.
    ---@param tag string
    ---@param source rfc.Source|nil
    function M.help_tag(tag, source)
        if config.get().view == "document" then
            reader.jump(tag)
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

    --- `:help tag`. A tag of a document that is not in the store, or that an
    --- older render wrote, goes through open first (erc20 is eip20's alias, so
    --- the document is eip20's); a subjects tag whose document is missing or
    --- older than its index goes through the subjects pipeline first; a tag
    --- of a source the reader has not enabled says so; any other refusal is
    --- shown as :help would show it.
    ---@param tag string
    function M.jump(tag)
        ensure_setup()
        if config.get().view == "document" then
            reader.jump(tag)
            return
        end
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
                    M.help_tag(tag, source)
                end)
                return
            end
        end
        M.help_tag(tag, source)
    end

    --- Opens the document at `tag` (its own tag by default), fetching it from
    --- its source when needed.
    ---@param source rfc.Source
    ---@param id string
    ---@param tag? string
    function M.open(source, id, tag)
        ensure_setup()
        tag = tag or tag_of(source, id)
        if config.get().view == "document" then
            reader.jump(tag)
            return
        end
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
            M.help_tag(tag, source)
        end)
    end

    --- The tag under the cursor, through jump.
    function M.follow()
        if reader.model(vim.api.nvim_get_current_buf()) then
            reader.follow(false)
            return
        end
        local ok, word = pcall(vim.fn.expand, "<cword>")
        if not ok or type(word) ~= "string" or word == "" then
            M.notify("nothing under the cursor", vim.log.levels.WARN)
            return
        end
        M.jump(word)
    end

    --- The first link on the cursor line, through jump: Enter on a ToC row.
    function M.follow_line()
        if reader.model(vim.api.nvim_get_current_buf()) then
            reader.follow(true)
            return
        end
        local tag = vim.api.nvim_get_current_line():match("|([^|%s]+)|")
        if not tag then
            M.notify("no link on this line", vim.log.levels.WARN)
            return
        end
        M.jump(tag)
    end

    return M
end
