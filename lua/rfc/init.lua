-- Compose the public API from narrow controllers and source adapters.
local session = require("rfc.app.session")
local entries = require("rfc.app.entries")
local cached = require("rfc.app.subjects_cache")
local view = require("rfc.view")
local toc = require("rfc.toc")
local owns = require("rfc.app.ownership").owns
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":h:h:h")
session.root = root
local M = {}

---@param opts? rfc.Config
function M.setup(opts)
    session.setup(opts, root)
end

local bindings
local reader = require("rfc.reader").new({
    attach = function(buf)
        bindings.attach(buf)
    end,
    notify = session.notify,
    toc = toc,
    resolve = require("rfc.app.resolve"),
})
local refresh = require("rfc.app.refresh")(reader.reload)
local subject_ui
local navigation = require("rfc.app.navigation")(
    { jump = reader.jump, model = reader.model, follow = reader.follow },
    function(source, done)
        subject_ui.with_subjects(source, done)
    end,
    refresh
)
subject_ui = require("rfc.app.subject_ui")(navigation.help_tag, refresh)
local picker = require("rfc.app.picker")(navigation.open, navigation.jump, subject_ui.subjects)
local completion = require("rfc.app.completion")
bindings = require("rfc.app.bindings")(
    { model = reader.model, step = reader.step, attach = reader.attach },
    navigation.follow,
    navigation.follow_line,
    subject_ui.status
)
view.configure(reader.headings)
toc.configure({ owns = owns, document_model = reader.model, jump = navigation.jump })
M.command = require("rfc.app.command")(
    picker.pick,
    navigation.jump,
    subject_ui.subjects,
    subject_ui.status,
    picker.open_named,
    subject_ui.nodes,
    completion.complete,
    require("rfc.app.clear").clear
)
M._activity, M.activity, M.notify = session._activity, session.activity, session.notify
M.ensure, M.index_lines, M.ensure_subjects = entries.ensure, entries.index_lines, cached.ensure_subjects
M.open, M.jump, M.follow, M.follow_line = navigation.open, navigation.jump, navigation.follow, navigation.follow_line
M.open_named, M.pick = picker.open_named, picker.pick
M.status, M.nodes, M.subjects = subject_ui.status, subject_ui.nodes, subject_ui.subjects
M.candidates, M.complete = completion.candidates, completion.complete
M.owns, M.step, M.attach = owns, bindings.step, bindings.attach
M.read_document, M.document_model, M.document_headings = reader.read, reader.model, reader.headings
M.document_window, M.document_forget = reader.attach_window, reader.forget
return M
