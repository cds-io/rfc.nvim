-- Source command dispatch and contextual completion.
local sources = require("rfc.sources")
local fp = require("cds.fp")
local statuses_of = require("rfc.app.entries").statuses_of
local notify = require("rfc.app.session").notify
return function(pick, jump, subjects, status, open_named, nodes, complete, clear, times)
    local M = {
        pick = pick,
        jump = jump,
        subjects = subjects,
        status = status,
        open_named = open_named,
        nodes = nodes,
        complete = complete,
        clear = clear,
        times = times,
    }
    --- The command for a source: a number, a tag (the source's own or an
    --- alias), `subjects` with a node after it or not, `status` with a status
    --- after it or not, `cc` with the bang to clear the source's cache (and
    --- without it, a line saying so), `times` for the last open's timeline,
    --- words to search its index, or nothing
    --- for its picker (on the configured status, when one is set). A
    --- completed item carries its title after the tag, so only the first
    --- word is the tag. After `subjects`, completion is over the nodes of
    --- the cached subjects index.
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
            elseif first == "times" then
                M.times(source)
            elseif first == "cc" then
                if not cmd.bang then
                    notify(("add ! to clear the %s cache: :%s! cc"):format(source.label, cmd.name), vim.log.levels.WARN)
                    return
                end
                local gone, err = M.clear(source)
                if not gone then
                    notify(err, vim.log.levels.ERROR)
                    return
                end
                notify(("%s cache cleared: %d files"):format(source.label, gone))
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

    return M.command
end
