local fetch = require("rfc.fetch")
local help = require("rfc.help")
local rfc = require("rfc.source.rfc")
local subjects = require("rfc.source.subjects")
local fp = require("cds.fp")

local M = {}

---@type rfc.Source
M.rfc = {
    prefix = "rfc",
    aliases = {},
    label = "RFC",
    raw_ext = "txt",
    index_file = "rfc-index.txt",
    fetch = function(id)
        return fetch.rfc(id)
    end,
    index = function()
        return fetch.index()
    end,
    entries = function(lines)
        return fp.map(rfc.index(lines), function(e)
            local text = fp.any(e.formats, function(f)
                return f == "TXT"
            end)
            return { id = e.number, label = e.label, text = text, status = e.status }
        end)
    end,
    -- the standards track as RFC 2026 lays it out, then the other
    -- categories, as the index prints them
    status = {
        "PROPOSED STANDARD",
        "DRAFT STANDARD",
        "INTERNET STANDARD",
        "BEST CURRENT PRACTICE",
        "INFORMATIONAL",
        "EXPERIMENTAL",
        "HISTORIC",
        "UNKNOWN",
    },
    render = help.render,
    render_model = help.render_model,
    -- the RFC Editor's subject tags: a tree of 19 roots, four levels at
    -- most, published daily as a CSV by rfc-editor/rfc-subject-tags
    subjects = {
        index_file = "rfc-subjects.csv",
        index = function()
            return fetch.subjects()
        end,
        entries = subjects.rfc,
        title = "RFCs by subject",
        about = "From rfc-editor.github.io/rfc-subject-tags, the RFC Editor's subject tags (beta).",
    },
}

M.rfc.prepare = help.model
return M.rfc
