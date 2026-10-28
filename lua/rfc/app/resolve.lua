-- Source-tag resolution for the shared document reader.
local sources = require("rfc.sources")
local session = require("rfc.app.session")
local enabled, run = session.enabled, session.run
local id_of = require("rfc.app.names").id_of
local entries = require("rfc.app.entries")
local document_of, raw_of = entries.document_of, entries.raw_of
local subjects = require("rfc.app.subjects_cache")
local subjects_of, subjects_fresh = subjects.subjects_of, subjects.subjects_fresh
-- one Markdown document per source plan: a plan held in memory gives the
-- same document, so a wiped buffer costs a draw and nothing else
local from_model = require("cds.fp").memoize(require("rfc.document").from_model)
local M = { notify = session.notify, ensure = entries.ensure, ensure_subjects = subjects.ensure_subjects }
return function(tag, done)
    local source = sources.of(tag)
    if not source then
        done(nil, "unknown document tag: " .. tag)
        return
    end
    if not enabled(source) then
        done(nil, ("%s is %s; enable sources.%s in setup()"):format(tag, source.label, source.prefix))
        return
    end
    local id = id_of(source, tag)
    local progress = require("rfc.app.progress")
    --- The document for the page: its source plan (held in memory, or read
    --- and prepared after a hop) and the Markdown built from it after one
    --- more hop, each stage named on the source's report.
    local function destination(name)
        local derived = id and document_of(source, id) or subjects_of(source)
        run(
            derived:source_model_task():tick():map(function(model)
                progress.phase(source.prefix, "building the page")
                return from_model(model)
            end),
            source.label .. " " .. name,
            function(doc, err)
                if not doc then
                    done(nil, err)
                else
                    done({ name = name, document = doc })
                end
            end
        )
    end
    if not id then
        if not source.subjects then
            done(nil, "no subjects for " .. source.label)
            return
        end
        if subjects_of(source):current() then
            destination(source.prefix .. "-subjects")
        else
            if not subjects_fresh(source) then
                M.notify("fetching the " .. source.label .. " subjects")
            end
            run(M.ensure_subjects(source), source.label .. " subjects", function(_, err)
                if err then
                    done(nil, err)
                else
                    destination(source.prefix .. "-subjects")
                end
            end)
        end
        return
    end
    if not raw_of(source, id):cached() then
        M.notify("fetching " .. source.label .. " " .. id)
        require("rfc.app.progress").phase(source.prefix, "fetching the text")
    end
    run(M.ensure(source, id), source.label .. " " .. id, function(name, err)
        if err then
            done(nil, err)
        else
            destination(name)
        end
    end)
end
