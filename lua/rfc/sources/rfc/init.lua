local net = require("rfc.sources.rfc.fetch")
local help_rfc = require("rfc.sources.rfc.render")
local rfc = require("rfc.sources.rfc.reader")
local subjects = require("rfc.source.subjects")
local fp = require("cds.fp")

local M = {}

---@type rfc.SourceRecord
M.rfc = {
    raw_ext = "txt",
    index_file = "rfc-index.txt",
    fetch = function(id)
        return net.rfc(id)
    end,
    index = function()
        return net.index()
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
    render = help_rfc.render,
    render_model = help_rfc.render_model,
    document = help_rfc.document,
    -- the RFC Editor's subject tags: a tree of 19 roots, four levels at
    -- most, published daily as a CSV by rfc-editor/rfc-subject-tags
    subjects = {
        index_file = "rfc-subjects.csv",
        index = function()
            return net.subjects()
        end,
        entries = subjects.rfc,
        title = "RFCs by subject",
        about = "From rfc-editor.github.io/rfc-subject-tags, the RFC Editor's subject tags (beta).",
    },
}

M.rfc.prepare = help_rfc.model
return M.rfc
