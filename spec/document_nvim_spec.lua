local editor = require("spec.editor")
local config = require("rfc.config")
local store = require("rfc.store")
local Task = require("cds.task")

local function model()
    return require("rfc").document_model(vim.api.nvim_get_current_buf())
end
local function wait_document(name)
    return vim.wait(3000, function()
        return vim.api.nvim_buf_get_name(0) == "rfc://document/" .. name and model() and model().doc ~= nil
    end)
end
--- The document shown and its styled draw in: the view draws the Markdown
--- first and styles a tick later.
local function wait_styled(name)
    return wait_document(name)
        and vim.wait(3000, function()
            return model() and model().doc and model().doc.styled == true
        end)
end
local function feed(keys)
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(keys, true, false, true), "x", false)
end
local function cursor_on(target)
    for _, link in ipairs(model().document.links) do
        if link.target == target then
            vim.api.nvim_win_set_cursor(0, { link.lnum, link.col })
            return
        end
    end
    error("missing link: " .. target)
end

describe("the shared RFC document reader", function()
    local case, restore
    setup(function()
        editor.load_plugin()
    end)
    before_each(function()
        case, restore = editor.start()
        case.setup({ rfc = true, eip = true, bip = true, simd = true, w3c = true, crs = true }, { view = "document" })
    end)
    after_each(function()
        restore()
    end)

    it("uses the shared document view by default with a Markdown fallback and help export", function()
        assert.equals("document", config.defaults.view)
        vim.cmd("Rfc 9110")
        assert.is_true(wait_document("rfc9110"))
        assert.equals("markdown", vim.bo.filetype)
        assert.matches("^# HTTP Semantics", vim.api.nvim_get_current_line())
        assert.is_false(model().doc.styled)
        assert.equals(1, vim.fn.filereadable(store.doc_path(config.get(), "rfc9110")))
        vim.cmd("help rfc9110-3.1")
        assert.equals("help", vim.bo.filetype)
        assert.matches("Resources", vim.api.nvim_get_current_line())
    end)

    it("follows a cross-document tag and returns to the originating view", function()
        vim.cmd("Rfc 9110")
        assert.is_true(wait_document("rfc9110"))
        cursor_on("rfc-tag:rfc2616-14.4")
        local position = vim.api.nvim_win_get_cursor(0)
        feed("<C-]>")
        assert.is_true(wait_document("rfc2616"))
        assert.matches("Accept%-Language", vim.api.nvim_get_current_line())
        feed("<C-T>")
        assert.equals("rfc://document/rfc9110", vim.api.nvim_buf_get_name(0))
        assert.same(position, vim.api.nvim_win_get_cursor(0))
        assert.same({ "9110", "2616" }, case.fetched)
    end)

    it("returns to an unnamed originating buffer without losing its contents", function()
        vim.cmd.enew()
        local original = vim.api.nvim_get_current_buf()
        vim.api.nvim_buf_set_lines(original, 0, -1, false, { "unsaved notes", "keep this" })
        vim.api.nvim_win_set_cursor(0, { 2, 3 })
        vim.cmd("Rfc 9110")
        assert.is_true(wait_document("rfc9110"))
        feed("<C-T>")
        assert.equals(original, vim.api.nvim_get_current_buf())
        assert.same({ "unsaved notes", "keep this" }, vim.api.nvim_buf_get_lines(0, 0, -1, false))
        assert.same({ 2, 3 }, vim.api.nvim_win_get_cursor(0))
        vim.bo.modified = false
    end)

    it("uses shared history for same-document tags and keeps proposal aliases", function()
        vim.cmd("Eip 20")
        assert.is_true(wait_document("eip20"))
        require("rfc").jump("erc20")
        require("rfc").jump("eip20-abstract")
        assert.matches("ABSTRACT", vim.api.nvim_get_current_line())
        feed("<C-T>")
        assert.equals(1, vim.api.nvim_win_get_cursor(0)[1])
    end)

    it("shows a CRS report's head, resolves its section tag and follows a citation", function()
        vim.cmd("Crs R43397")
        assert.is_true(wait_document("crs-r43397"), vim.inspect(case.notices))
        local text = table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n")
        assert.is_not_nil(text:find("Legislative Branch Appropriations: Frequently Asked Questions", 1, true))
        assert.is_not_nil(text:find("17 versions since March 9, 2016", 1, true))
        assert.is_not_nil(
            text:find("https://www.congress.gov/crs_external_products/R/PDF/R43397/R43397.37.pdf", 1, true)
        )
        require("rfc").jump("crs-r43397#summary")
        assert.matches("Summary", vim.api.nvim_get_current_line())
        cursor_on("rfc-tag:crs-97-1011")
        feed("<C-]>")
        assert.is_true(vim.wait(2000, function()
            return vim.tbl_contains(case.fetched, "crs-97-1011.json")
        end))
    end)

    it("keeps native HTML anchors and numeric tags equivalent in W3C documents", function()
        vim.cmd("W3c wcag22")
        assert.is_true(wait_document("w3c-wcag22"), vim.inspect(case.notices))
        require("rfc").jump("w3c-wcag22#1")
        local numbered = vim.api.nvim_win_get_cursor(0)[1]
        require("rfc").jump("w3c-wcag22#intro")
        assert.equals(numbered, vim.api.nvim_win_get_cursor(0)[1])
        assert.matches("Introduction", vim.api.nvim_get_current_line())
    end)

    it("connects section movement and the contents sidebar to shared anchor positions", function()
        vim.cmd("Rfc 9110")
        assert.is_true(wait_document("rfc9110"))
        local owner = vim.api.nvim_get_current_win()
        feed("]]")
        assert.matches("Introduction", vim.api.nvim_get_current_line())
        require("rfc.toc").open(owner)
        local sidebar = assert(
            require("rfc.toc").window(owner),
            "owns=" .. tostring(require("rfc").owns(0)) .. " model=" .. tostring(model() ~= nil)
        )
        vim.api.nvim_set_current_win(sidebar)
        vim.api.nvim_win_set_cursor(0, { 2, 0 })
        feed("<CR>")
        assert.equals(owner, vim.api.nvim_get_current_win())
        assert.matches("Purpose", vim.api.nvim_get_current_line())
    end)

    it("only lands the latest pending tag follow in a window", function()
        local fetch = require("rfc.fetch")
        local callbacks = {}
        fetch.rfc = function(id)
            return Task.new(function()
                require("cds.async").await(1, function(done)
                    callbacks[id] = done
                end)
                return table.concat(require("spec.fixtures").read("rfc" .. id .. ".txt"), "\n")
            end)
        end
        vim.cmd("Rfc 9110")
        vim.cmd("Rfc 2616")
        assert.is_true(vim.wait(1000, function()
            return callbacks["9110"] and callbacks["2616"]
        end))
        callbacks["2616"]()
        assert.is_true(wait_document("rfc2616"))
        callbacks["9110"]()
        assert.is_true(vim.wait(1000, function()
            return require("rfc").activity() == ""
        end))
        assert.equals("rfc://document/rfc2616", vim.api.nvim_buf_get_name(0))
    end)
    it("keeps another report's numeric tag separate from the current report", function()
        vim.cmd("W3c wcag22")
        assert.is_true(wait_document("w3c-wcag22"))
        require("rfc").jump("w3c-wot-thing-description11#1")
        assert.is_true(wait_document("w3c-wot-thing-description11"))
        assert.matches("Introduction", vim.api.nvim_get_current_line())
    end)

    it("refuses missing tags without moving the current document", function()
        vim.cmd("Rfc 9110")
        assert.is_true(wait_document("rfc9110"))
        require("rfc").jump("rfc2616-not-a-section")
        assert.is_true(vim.wait(2000, function()
            return require("rfc").activity() == ""
        end))
        assert.equals("rfc://document/rfc9110", vim.api.nvim_buf_get_name(0))
        assert.matches("no anchor", case.notices[#case.notices].msg)
    end)

    it("shows a progress dashboard above a document being prepared and closes it once the page is final", function()
        case.setup(
            { rfc = true, eip = true, bip = true, simd = true, w3c = true, crs = true },
            { view = "document", progress = { show_after = 0, linger = 50 } }
        )
        local owner = vim.api.nvim_get_current_win()
        vim.cmd("Crs subjects")
        assert.is_true(vim.wait(3000, function()
            return require("rfc").dashboard_window(owner) ~= nil
        end))
        local report = require("rfc").progress_report(owner)
        assert.is_not_nil(report)
        assert.is_true(wait_document("crs-subjects"))
        assert.is_true(vim.wait(3000, function()
            return report:finished()
        end))
        local fp = require("cds.fp")
        assert.same(
            { "reading source", "parsing metadata", "filing", "writing the page", "building the page", "styling" },
            fp.map(report.phases, function(phase)
                return phase.name
            end)
        )
        assert.equals(32, report.phases[1].of)
        assert.equals(32, report.phases[1].count)
        for _, phase in ipairs(report.phases) do
            assert.equals("done", phase.status, phase.name)
        end
        assert.is_true(vim.wait(2000, function()
            return require("rfc").dashboard_window(owner) == nil
        end))
    end)

    it("opens the dashboard at once for a page whose inputs are large, and hops between the warm stages", function()
        case.setup(
            { rfc = true, eip = true, bip = true, simd = true, w3c = true, crs = true },
            { view = "document", progress = { show_after = 60000, linger = 500, at_once_bytes = 1 } }
        )
        local owner = vim.api.nvim_get_current_win()
        vim.cmd("Crs subjects")
        assert.is_true(vim.wait(3000, function()
            return require("rfc").dashboard_window(owner) ~= nil
        end, 1))
        local first = require("rfc").progress_report(owner)
        assert.is_true(wait_document("crs-subjects"))
        assert.is_true(vim.wait(3000, function()
            return first:finished()
        end))
        -- the page is on disk now; a new session would build its model again
        vim.api.nvim_buf_delete(vim.api.nvim_get_current_buf(), { force = true })
        require("rfc").close_dashboards()
        require("rfc.cache.models").forget_all()
        owner = vim.api.nvim_get_current_win()
        local ticks = 0
        local timer = vim.uv.new_timer()
        timer:start(
            0,
            1,
            vim.schedule_wrap(function()
                ticks = ticks + 1
            end)
        )
        vim.cmd("Crs subjects")
        assert.is_true(vim.wait(3000, function()
            return require("rfc").dashboard_window(owner) ~= nil
        end, 1))
        local report = require("rfc").progress_report(owner)
        assert.is_true(wait_document("crs-subjects"))
        assert.is_true(vim.wait(3000, function()
            return report:finished()
        end))
        timer:stop()
        assert.same(
            { "parsing metadata", "filing", "building the page", "styling" },
            require("cds.fp").map(report.phases, function(phase)
                return phase.name
            end)
        )
        -- the loop turned between the stages: the heartbeat ran more than once
        assert.is_true(ticks > 1, "ticks: " .. ticks)
    end)

    it("shows a hidden document buffer again without resolving or rendering it again", function()
        vim.cmd("Rfc 9110")
        assert.is_true(wait_document("rfc9110"))
        local buf, doc = vim.api.nvim_get_current_buf(), model().doc
        local draws = model().draws
        vim.cmd("enew")
        assert.are_not.equal(buf, vim.api.nvim_get_current_buf())
        vim.cmd("Rfc 9110")
        assert.is_true(wait_document("rfc9110"))
        assert.equals(buf, vim.api.nvim_get_current_buf())
        assert.is_true(model().doc == doc)
        assert.equals(draws, model().draws)
        assert.same({ "9110" }, case.fetched)
        require("rfc").jump("rfc9110-3.1")
        assert.equals(buf, vim.api.nvim_get_current_buf())
        assert.is_true(vim.api.nvim_win_get_cursor(0)[1] > 1)
    end)

    it("turns list markers off in a document window, since the rendering pads its lines", function()
        vim.o.list = true
        vim.cmd("Rfc 9110")
        assert.is_true(wait_document("rfc9110"))
        assert.is_false(vim.wo.list)
        vim.o.list = false
    end)

    it("opens subject documents and retains lifecycle cycling", function()
        vim.cmd("Eip subjects")
        assert.is_true(wait_document("eip-subjects"))
        assert.truthy(vim.fn.maparg("gs", "n") ~= "")
        feed("gs")
        assert.is_true(vim.wait(2000, function()
            return model() and model().document and model().document.markdown[1]:find("Status:", 1, true) ~= nil
        end))
    end)

    it("opens BIP and SIMD documents through the same shared view", function()
        vim.cmd("Bip 32")
        assert.is_true(wait_document("bip32"))
        assert.is_true(#model().document.headings > 0)
        vim.cmd("Simd 64")
        assert.is_true(wait_document("simd64"))
        assert.is_true(#model().document.headings > 0)
        feed("<C-T>")
        assert.equals("rfc://document/bip32", vim.api.nvim_buf_get_name(0))
    end)

    it("restores the saved view after back reloads a wiped document asynchronously", function()
        vim.cmd("Rfc 9110")
        assert.is_true(wait_document("rfc9110"))
        require("rfc").jump("rfc9110-3.1")
        vim.api.nvim_win_set_cursor(0, { vim.api.nvim_win_get_cursor(0)[1] + 2, 3 })
        local saved = vim.api.nvim_win_get_cursor(0)
        local origin = vim.api.nvim_get_current_buf()
        require("rfc").jump("rfc2616")
        assert.is_true(wait_document("rfc2616"))
        vim.api.nvim_buf_delete(origin, { force = true })
        feed("<C-T>")
        assert.is_true(wait_document("rfc9110"))
        -- the saved view is of the styled layout, applied once that draw is in
        assert.is_true(vim.wait(2000, function()
            return vim.deep_equal(saved, vim.api.nvim_win_get_cursor(0))
        end))
        assert.same({ "9110", "2616" }, case.fetched)
    end)

    it("keeps a later local jump when a pending document fetch completes", function()
        vim.cmd("Rfc 9110")
        assert.is_true(wait_document("rfc9110"))
        local pending
        require("rfc.fetch").rfc = function()
            return Task.new(function()
                require("cds.async").await(1, function(done)
                    pending = done
                end)
                return table.concat(require("spec.fixtures").read("rfc2616.txt"), "\n")
            end)
        end
        require("rfc").jump("rfc2616")
        assert.is_true(vim.wait(1000, function()
            return pending ~= nil
        end))
        require("rfc").jump("rfc9110-3.1")
        local local_position = vim.api.nvim_win_get_cursor(0)
        pending()
        assert.is_true(vim.wait(2000, function()
            return require("rfc").activity() == ""
        end))
        assert.equals("rfc://document/rfc9110", vim.api.nvim_buf_get_name(0))
        assert.same(local_position, vim.api.nvim_win_get_cursor(0))
        assert.equals(1, vim.fn.filereadable(store.doc_path(config.get(), "rfc2616")))
    end)

    it("follows the first source link on Enter even when a later link is shorter", function()
        vim.cmd("Rfc 9110")
        assert.is_true(wait_document("rfc9110"))
        cursor_on("rfc-tag:rfc2616-14.4")
        feed("<CR>")
        assert.is_true(wait_document("rfc2616"))
        assert.matches("Accept%-Language", vim.api.nvim_get_current_line())
    end)

    it("renders from cached source plans even when the help-import adapter is unavailable", function()
        local document = require("rfc.document")
        local old = document.from_help
        document.from_help = function()
            error("formatted help must not be reparsed")
        end
        local ok, err = pcall(function()
            vim.cmd("Rfc 9110")
            assert.is_true(wait_document("rfc9110"))
            vim.cmd("Eip subjects")
            assert.is_true(wait_document("eip-subjects"))
            assert.is_true(#model().document.headings > 0)
        end)
        document.from_help = old
        assert.is_true(ok, err)
    end)

    describe("with vellum", function()
        local fake, saved
        before_each(function()
            fake = { calls = 0, pending = 0 }
            saved = {}
            for _, name in ipairs({ "vellum.render", "vellum.theme", "vellum.media" }) do
                saved[name] = { loaded = package.loaded[name], preload = package.preload[name] }
                package.loaded[name] = nil
            end
            package.preload["vellum.theme"] = function()
                return { apply = function() end }
            end
            package.preload["vellum.media"] = function()
                return fake
            end
            package.preload["vellum.render"] = function()
                return {
                    reset = function() end,
                    render = function(buf)
                        fake.calls = fake.calls + 1
                        if fake.fail then
                            error("renderer failed")
                        end
                        local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
                        local source = require("cds.document").new(lines)
                        local rows = {}
                        for _, link in ipairs(source.links) do
                            rows[link.lnum] = rows[link.lnum] or {}
                            table.insert(rows[link.lnum], { link.col, link.end_col, "Normal", 100, link.target })
                        end
                        if fake.wait then
                            fake.pending = fake.pending + 1
                        end
                        return lines, rows, 0, { { 0, #lines, 0, #lines } }
                    end,
                }
            end
            require("cds.vellum").forget()
            require("cds.vellum").restyle()
        end)
        after_each(function()
            for name, entry in pairs(saved) do
                package.loaded[name], package.preload[name] = entry.loaded, entry.preload
            end
            require("cds.vellum").forget()
            require("cds.vellum").restyle()
        end)

        it("follows rendered tag spans and retains the source contract", function()
            vim.cmd("Rfc 9110")
            assert.is_true(wait_styled("rfc9110"))
            assert.equals("rfc-document", vim.bo.filetype)
            assert.is_true(model().doc.styled)
            assert.is_true(model().doc.source == model().document)
            cursor_on("rfc-tag:rfc2616-14.4")
            local position = vim.api.nvim_win_get_cursor(0)
            feed("<C-]>")
            assert.is_true(wait_styled("rfc2616"))
            assert.matches("Accept%-Language", vim.api.nvim_get_current_line())
            feed("<C-T>")
            assert.is_true(wait_styled("rfc9110"))
            assert.same(position, vim.api.nvim_win_get_cursor(0))
        end)

        it("follows the leftmost rendered link on Enter rather than the shortest span", function()
            vim.cmd("Rfc 9110")
            assert.is_true(wait_styled("rfc9110"))
            cursor_on("rfc-tag:rfc2616-14.4")
            feed("<CR>")
            assert.is_true(wait_styled("rfc2616"))
            assert.matches("Accept%-Language", vim.api.nvim_get_current_line())
        end)

        it("redraws on colorscheme changes and falls back if vellum fails", function()
            vim.cmd("Eip 20")
            assert.is_true(wait_styled("eip20"))
            local calls = fake.calls
            vim.api.nvim_exec_autocmds("ColorScheme", {})
            assert.is_true(fake.calls > calls)
            fake.fail = true
            vim.api.nvim_exec_autocmds("ColorScheme", {})
            assert.is_true(vim.wait(2000, function()
                return model().doc.styled == false
            end))
            assert.equals("markdown", vim.bo.filetype)
            require("rfc").jump("eip20-abstract")
            assert.matches("ABSTRACT", vim.api.nvim_get_current_line())
        end)

        it("ignores image retries for a replaced or wiped model", function()
            fake.wait = true
            vim.cmd("Eip 20")
            assert.is_true(wait_document("eip20"))
            local buf = vim.api.nvim_get_current_buf()
            local old = model()
            fake.wait = false
            vim.cmd.edit(vim.fn.fnameescape(vim.api.nvim_buf_get_name(buf)))
            assert.is_true(vim.wait(2000, function()
                return model() and model() ~= old and model().doc ~= nil and model().doc.styled
            end))
            local calls = fake.calls
            vim.wait(600)
            assert.equals(calls, fake.calls)
            vim.api.nvim_buf_delete(buf, { force = true })
        end)
    end)

    it("quits the last document window while an unrelated float is open", function()
        vim.cmd("silent! only")
        vim.cmd("Rfc 9110")
        assert.is_true(wait_document("rfc9110"))
        local win = vim.api.nvim_get_current_win()
        local floating = vim.api.nvim_open_win(vim.api.nvim_create_buf(false, true), false, {
            relative = "editor",
            row = 0,
            col = 0,
            width = 10,
            height = 2,
        })
        local ok, err = pcall(vim.fn.maparg("q", "n", false, true).callback)
        vim.api.nvim_win_close(floating, true)
        assert.is_true(ok, tostring(err))
        assert.is_true(vim.api.nvim_win_is_valid(win))
        assert.is_nil(model())
    end)

    it("prepares a cold document once for its help export and Markdown view", function()
        local source = require("rfc.sources").rfc
        local original, calls = source.prepare, 0
        source.prepare = function(...)
            calls = calls + 1
            return original(...)
        end
        local ok, err = pcall(function()
            vim.cmd("Rfc 9110")
            assert.is_true(wait_document("rfc9110"))
            assert.equals(1, calls)
            vim.cmd("Rfc 2616")
            assert.is_true(wait_document("rfc2616"))
            vim.cmd("Rfc 9110")
            assert.is_true(wait_document("rfc9110"))
            assert.equals(2, calls)
        end)
        source.prepare = original
        assert.is_true(ok, tostring(err))
    end)

    for _, item in ipairs({
        { "eip", "Eip 20", "eip20" },
        { "w3c", "W3c wcag22", "w3c-wcag22" },
    }) do
        it("reuses the prepared " .. item[1] .. " model when reopening a document", function()
            local source = require("rfc.sources")[item[1]]
            local original, calls = source.prepare, 0
            source.prepare = function(...)
                calls = calls + 1
                return original(...)
            end
            local ok, err = pcall(function()
                vim.cmd(item[2])
                assert.is_true(wait_document(item[3]), vim.inspect(case.notices))
                assert.equals(1, calls)
                vim.cmd.enew()
                vim.cmd(item[2])
                assert.is_true(wait_document(item[3]), vim.inspect(case.notices))
                assert.equals(1, calls)
            end)
            source.prepare = original
            assert.is_true(ok, tostring(err))
        end)
    end

    it("prepares subjects once for export and view, and invalidates on a status change", function()
        local subjects = require("rfc.subjects")
        local original, calls = subjects.model, 0
        subjects.model = function(...)
            calls = calls + 1
            return original(...)
        end
        local ok, err = pcall(function()
            vim.cmd("Eip subjects")
            assert.is_true(wait_document("eip-subjects"), vim.inspect(case.notices))
            assert.equals(1, calls)
            vim.cmd("Eip status final")
            assert.is_true(
                vim.wait(3000, function()
                    return calls == 2
                end),
                vim.inspect(case.notices)
            )
            assert.equals(2, calls)
        end)
        subjects.model = original
        assert.is_true(ok, tostring(err))
    end)
end)
