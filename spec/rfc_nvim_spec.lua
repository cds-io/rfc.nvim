-- Opening and navigating RFCs as help. Runs inside Neovim (make test-nvim).
local editor = require("spec.editor")
local fixtures = require("spec.fixtures")
local store = require("rfc.store")
local config = require("rfc.config")

local function feed(keys)
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(keys, true, false, true), "x", false)
end

describe("rfc", function()
    local case, restore

    setup(function()
        editor.load_plugin()
    end)

    before_each(function()
        case, restore = editor.start()
    end)

    after_each(function()
        restore()
    end)

    describe(":Rfc <number>", function()
        it("fetches the RFC, writes its text, document and tags, and opens it as help", function()
            vim.cmd("Rfc 9110")
            assert.is_true(editor.wait_help("9110"))
            assert.are.same({ "9110" }, case.fetched)
            assert.are.equal("help", vim.bo.filetype)
            assert.are.equal(1, vim.fn.line("."))
            assert.is_true(vim.api.nvim_get_current_line():match("^%*rfc9110%.txt%*  HTTP Semantics") ~= nil)
            local cfg = config.get()
            assert.are.equal(1, vim.fn.filereadable(store.raw_path(cfg, "rfc9110", "txt")))
            assert.are.equal(1, vim.fn.filereadable(store.doc_path(cfg, "rfc9110")))
            local tags = vim.fn.readfile(store.doc_dir(cfg) .. "/tags")
            assert.is_truthy(vim.tbl_contains(tags, "rfc9110-3.1\trfc9110.txt\t/*rfc9110-3.1*"))
            assert.are.same({ { msg = "fetching RFC 9110", level = vim.log.levels.INFO, title = "rfc" } }, case.notices)
        end)

        it("opens an RFC already in the store without fetching", function()
            vim.cmd("Rfc 9110")
            assert.is_true(editor.wait_help("9110"))
            vim.cmd("helpclose")
            vim.cmd("Rfc 9110")
            assert.is_true(editor.wait_help("9110"))
            assert.are.same({ "9110" }, case.fetched)
        end)

        it("reports an RFC that does not exist and opens nothing", function()
            vim.cmd("Rfc 99999")
            vim.wait(500, function()
                return #case.notices == 2
            end)
            assert.are.equal("RFC 99999 does not exist", case.notices[2].msg)
            assert.are.equal(vim.log.levels.ERROR, case.notices[2].level)
            assert.are_not.equal("help", vim.bo.filetype)
        end)
    end)

    describe(":help", function()
        it("lands on a section by its tag once the RFC is in the store", function()
            vim.cmd("Rfc 9110")
            assert.is_true(editor.wait_help("9110"))
            vim.cmd("help rfc9110-3.1")
            assert.are.equal(698, vim.fn.line("."))
            assert.is_truthy(vim.api.nvim_get_current_line():match("^3%.1%.  Resources"))
        end)

        it("merges the tags of every RFC in the store into one sorted file", function()
            vim.cmd("Rfc 9110")
            assert.is_true(editor.wait_help("9110"))
            vim.cmd("Rfc 2616")
            assert.is_true(editor.wait_help("2616"))
            local tags = vim.fn.readfile(store.doc_dir(config.get()) .. "/tags")
            local sorted = vim.deepcopy(tags)
            table.sort(sorted)
            assert.are.same(sorted, tags)
            assert.is_truthy(vim.tbl_contains(tags, "rfc2616-1.4\trfc2616.txt\t/*rfc2616-1.4*"))
            assert.is_truthy(vim.tbl_contains(tags, "rfc9110\trfc9110.txt\t/*rfc9110*"))
        end)
    end)

    describe("the section keys in a document's help buffer", function()
        it("]] moves to the next heading, count-aware, and leaves a jumplist entry", function()
            vim.cmd("Rfc 9110")
            assert.is_true(editor.wait_help("9110"))
            local jumps = #vim.fn.getjumplist()[1]
            feed("]]")
            assert.are.equal(381, vim.fn.line("."))
            assert.is_truthy(vim.api.nvim_get_current_line():match("^1%.  Introduction"))
            feed("3]]")
            assert.are.equal(456, vim.fn.line("."))
            assert.are.equal(jumps + 2, #vim.fn.getjumplist()[1])
        end)

        it("[[ moves to the previous heading and stays on the first", function()
            vim.cmd("Rfc 9110")
            assert.is_true(editor.wait_help("9110"))
            vim.api.nvim_win_set_cursor(0, { 456, 0 })
            feed("[[")
            assert.are.equal(415, vim.fn.line("."))
            feed("2[[")
            assert.are.equal(381, vim.fn.line("."))
            feed("[[")
            assert.are.equal(381, vim.fn.line("."))
        end)

        it("]] past the last heading stays put", function()
            vim.cmd("Rfc 9110")
            assert.is_true(editor.wait_help("9110"))
            vim.api.nvim_win_set_cursor(0, { 10761, 0 })
            feed("]]")
            assert.are.equal(10761, vim.fn.line("."))
        end)
    end)

    describe("the rich view", function()
        local view = require("rfc.view")
        local function marks()
            return #vim.api.nvim_buf_get_extmarks(0, view.ns, 0, -1, {})
        end

        it("draws a rule above every heading and highlights its text", function()
            vim.cmd("Rfc 9110")
            assert.is_true(editor.wait_help("9110"))
            assert.are.equal(305, marks())
            local mark = vim.api.nvim_buf_get_extmarks(0, view.ns, { 380, 0 }, { 380, -1 }, { details = true })[1]
            assert.are.equal(string.rep("=", 78), mark[4].virt_lines[1][1][1])
            assert.is_true(mark[4].virt_lines_above)
            assert.are.equal("rfcHeading", mark[4].hl_group)
            assert.are.equal(#"1.  Introduction", mark[4].end_col)
            mark = vim.api.nvim_buf_get_extmarks(0, view.ns, { 382, 0 }, { 382, -1 }, { details = true })[1]
            assert.are.equal(string.rep("-", 78), mark[4].virt_lines[1][1][1])
        end)

        it("is toggled off and on with ,tv", function()
            vim.cmd("Rfc 9110")
            assert.is_true(editor.wait_help("9110"))
            feed(",tv")
            assert.are.equal(0, marks())
            feed(",tv")
            assert.are.equal(305, marks())
        end)

        it("shows the rule above a heading that lands on the top line", function()
            vim.cmd("Rfc 9110")
            assert.is_true(editor.wait_help("9110"))
            -- the reader's loop fires CursorMoved after a move, which a
            -- headless command does not
            vim.cmd("help rfc9110-3.1")
            vim.api.nvim_exec_autocmds("CursorMoved", { buffer = 0 })
            assert.are.equal(698, vim.fn.winsaveview().topline)
            assert.are.equal(1, vim.fn.winsaveview().topfill)
            -- [[ scrolling a heading onto the top line
            vim.api.nvim_win_set_cursor(0, { 383, 0 })
            vim.cmd("normal! zt")
            feed("[[")
            vim.api.nvim_exec_autocmds("CursorMoved", { buffer = 0 })
            assert.are.equal(381, vim.fn.winsaveview().topline)
            assert.are.equal(1, vim.fn.winsaveview().topfill)
            -- zt on a heading, which the loop reports as a scroll
            vim.api.nvim_win_set_cursor(0, { 383, 0 })
            vim.cmd("normal! zt")
            assert.are.equal(0, vim.fn.winsaveview().topfill)
            vim.api.nvim_exec_autocmds("WinScrolled", { buffer = 0 })
            assert.are.equal(1, vim.fn.winsaveview().topfill)
        end)

        it("survives helpclose and the next open", function()
            vim.cmd("Rfc 9110")
            assert.is_true(editor.wait_help("9110"))
            vim.cmd("helpclose")
            vim.cmd("Rfc 9110")
            assert.is_true(editor.wait_help("9110"))
            assert.are.equal(305, marks())
        end)

        it("stays off when setup says plain", function()
            case.setup({ rfc = true, eip = true }, { view = "plain" })
            vim.cmd("Rfc 9110")
            assert.is_true(editor.wait_help("9110"))
            assert.are.equal(0, marks())
            feed(",tv")
            assert.are.equal(305, marks())
        end)
    end)

    describe("the keys in an RFC's help buffer", function()
        it("fetch the RFC behind a link on CTRL-] and land on its section", function()
            vim.cmd("Rfc 9110")
            assert.is_true(editor.wait_help("9110"))
            vim.api.nvim_win_set_cursor(0, { 5648, 48 }) -- Section |rfc2616-14.4| of |rfc2616|
            feed("<C-]>")
            assert.is_true(editor.wait_help("2616"))
            assert.are.same({ "9110", "2616" }, case.fetched)
            assert.are.equal(5785, vim.fn.line("."))
            assert.is_truthy(vim.api.nvim_get_current_line():match("^14%.4 Accept%-Language"))
        end)

        it("follow a ToC row's link on Enter", function()
            vim.cmd("Rfc 9110")
            assert.is_true(editor.wait_help("9110"))
            vim.api.nvim_win_set_cursor(0, { 75, 0 }) -- |rfc9110-1.1|  Purpose
            feed("<CR>")
            assert.are.equal(383, vim.fn.line("."))
            assert.is_truthy(vim.api.nvim_get_current_line():match("^1%.1%.  Purpose"))
        end)

        it("come back with CTRL-T through the tag stack", function()
            vim.cmd("Rfc 9110")
            assert.is_true(editor.wait_help("9110"))
            vim.api.nvim_win_set_cursor(0, { 75, 0 })
            feed("<CR>")
            assert.are.equal(383, vim.fn.line("."))
            feed("<C-t>")
            assert.are.equal(75, vim.fn.line("."))
        end)

        it("report a line with no link on Enter", function()
            vim.cmd("Rfc 9110")
            assert.is_true(editor.wait_help("9110"))
            vim.api.nvim_win_set_cursor(0, { 3, 0 })
            feed("<CR>")
            assert.are.equal("no link on this line", case.notices[#case.notices].msg)
        end)

        it("highlight the requirement keywords", function()
            vim.cmd("Rfc 9110")
            assert.is_true(editor.wait_help("9110"))
            vim.cmd("help rfc9110-2.1")
            local row = vim.fn.search("MUST", "W")
            local col = vim.fn.col(".")
            assert.is_true(row > 0)
            assert.are.equal("rfcRequirement", vim.fn.synIDattr(vim.fn.synID(row, col, true), "name"))
        end)

        it("leave other help buffers alone", function()
            vim.cmd("help help")
            assert.are.equal("help", vim.bo.filetype)
            assert.are.equal("", vim.fn.mapcheck("<CR>", "n"))
            assert.are.equal("", vim.fn.mapcheck("<C-]>", "n"))
        end)
    end)

    describe(":Rfc", function()
        it("fetches the index, offers it through vim.ui.select and opens the choice", function()
            local offered, opts
            vim.ui.select = function(items, o, on_choice)
                offered, opts = items, o
                on_choice(items[#items])
            end
            vim.cmd("Rfc")
            assert.is_true(editor.wait_help("2616"))
            assert.are.equal(5, #offered)
            assert.are.equal("rfc", opts.kind)
            assert.are.equal(
                "rfc2616  Hypertext Transfer Protocol -- HTTP/1.1. R. Fielding, J. Gettys, J. Mogul, H. Frystyk, L. Masinter, P. Leach, T. Berners-Lee. June 1999.",
                opts.format_item(offered[5])
            )
            assert.are.same({ "index", "2616" }, case.fetched)
            assert.are.equal(1, vim.fn.filereadable(store.index_path(config.get(), "rfc-index.txt")))
        end)

        it("lists the RFC index alone, whatever else is enabled", function()
            local offered
            vim.ui.select = function(items, _, on_choice)
                offered = items
                on_choice(nil)
            end
            vim.cmd("Rfc")
            vim.wait(500, function()
                return offered ~= nil
            end)
            assert.are.equal(5, #offered)
            assert.are.same({ "index" }, case.fetched)
        end)

        it("reads the index from the store while it is fresh", function()
            local offered = 0
            vim.ui.select = function(_, _, on_choice)
                offered = offered + 1
                on_choice(nil)
            end
            vim.cmd("Rfc")
            vim.wait(500, function()
                return offered == 1
            end)
            vim.cmd("Rfc")
            vim.wait(500, function()
                return offered == 2
            end)
            assert.are.equal(2, offered)
            assert.are.same({ "index" }, case.fetched)
        end)

        it("declines an RFC the index lists without a text version", function()
            vim.ui.select = function(items, _, on_choice)
                local chosen = vim.deepcopy(items[2])
                chosen.entry.text = false
                on_choice(chosen)
            end
            vim.cmd("Rfc")
            vim.wait(500, function()
                return #case.notices == 1
            end)
            assert.are.equal("RFC 31 has no text version", case.notices[1].msg)
            assert.are.equal(vim.log.levels.WARN, case.notices[1].level)
            assert.are.same({ "index" }, case.fetched)
        end)
    end)

    --- What every proposal source is asked, and what each answers: a number
    --- to open, a section tag, a link to a proposal outside the fixtures, the
    --- picker, a search and a completion.
    local PROPOSALS = {
        {
            command = "Eip",
            label = "EIP",
            id = "1559",
            title = "^%*eip1559%.txt%*  Fee market change for ETH 1%.0 chain",
            fetched = { "eip1559" },
            section = { "eip1559-specification", "^SPECIFICATION" },
            missing = { id = "1559", tag = "|eip2718|", number = "2718" },
            index = {
                count = 7 + 1,
                label = "eip20  Token Standard (Final)",
                fetched = {
                    "eips-core",
                    "eips-networking",
                    "eips-interface",
                    "eips-erc",
                    "eips-meta",
                    "eips-informational",
                },
            },
            search = { "token", "eip20  Token Standard (Final)" },
            door = "eip-subjects  EIPs by subject",
            complete = { "1559", "eip1559  " },
        },
        {
            command = "Bip",
            label = "BIP",
            id = "32",
            title = "^%*bip32%.txt%*  Hierarchical Deterministic Wallets",
            fetched = { "bip32" },
            section = { "bip32-conventions", "^CONVENTIONS" },
            missing = { id = "341", tag = "|bip340|", number = "340" },
            index = { count = 213 + 1, label = "bip1  BIP Purpose and Guidelines (Closed)", fetched = { "bip-index" } },
            search = { "hierarchical", "bip32  Hierarchical Deterministic Wallets (Deployed)" },
            door = "bip-subjects  BIPs by subject",
            complete = { "hierarch", "bip32  Hierarchical Deterministic Wallets" },
        },
        {
            command = "Simd",
            label = "SIMD",
            id = "64",
            title = "^%*simd64%.txt%*  Transaction Receipts",
            fetched = { "simd-index", "simd64" },
            section = { "simd64-summary", "^SUMMARY" },
            missing = { id = "268", tag = "|simd219|", number = "219" },
            index = { count = 133, label = "simd1  Simd Process", fetched = { "simd-index" } },
            search = { "receipt", "simd64  Transaction Receipt" },
            complete = { "transaction rec", "simd64  Transaction Receipt" },
        },
    }

    --- The picker captured: the items offered, and their labels.
    local function picker()
        local seen = {}
        vim.ui.select = function(items, opts, on_choice)
            seen.items = items
            seen.labels = vim.tbl_map(opts.format_item, items)
            seen.prompt = opts.prompt
            on_choice(nil)
        end
        return seen
    end

    for _, p in ipairs(PROPOSALS) do
        local prefix = p.command:lower()
        describe(":" .. p.command, function()
            it("fetches a proposal by number and opens it as help", function()
                vim.cmd(p.command .. " " .. p.id)
                assert.is_true(editor.wait_help(prefix .. p.id))
                assert.are.same(p.fetched, case.fetched)
                assert.is_truthy(vim.api.nvim_get_current_line():match(p.title))
                assert.are.equal("fetching " .. p.label .. " " .. p.id, case.notices[1].msg)
            end)

            it("lands on a section by its tag", function()
                vim.cmd(p.command .. " " .. p.id)
                assert.is_true(editor.wait_help(prefix .. p.id))
                vim.cmd("help " .. p.section[1])
                assert.is_truthy(vim.api.nvim_get_current_line():match(p.section[2]))
            end)

            it("opens a number written with leading zeros as the same proposal", function()
                vim.cmd(p.command .. " 00" .. p.id)
                assert.is_true(editor.wait_help(prefix .. p.id))
                assert.are.same(p.fetched, case.fetched)
            end)

            it("reports a link to a proposal that does not exist", function()
                vim.cmd(p.command .. " " .. p.missing.id)
                assert.is_true(editor.wait_help(prefix .. p.missing.id))
                vim.cmd("1")
                assert.is_true(vim.fn.search(p.missing.tag, "W") > 0)
                feed("<C-]>")
                vim.wait(500, function()
                    return #case.notices == 3
                end)
                assert.are.equal("fetching " .. p.label .. " " .. p.missing.number, case.notices[2].msg)
                assert.are.equal(p.label .. " " .. p.missing.number .. " does not exist", case.notices[3].msg)
            end)

            it("lists its index in the picker", function()
                local seen = picker()
                vim.cmd(p.command)
                assert.is_true(vim.wait(500, function()
                    return seen.items ~= nil
                end))
                assert.are.equal(p.index.count, #seen.items)
                assert.is_true(vim.tbl_contains(seen.labels, p.index.label))
                if p.door then
                    assert.are.equal(p.door, seen.labels[1])
                end
                table.sort(case.fetched)
                local expected = vim.deepcopy(p.index.fetched)
                table.sort(expected)
                assert.are.same(expected, case.fetched)
            end)

            it("offers the proposals whose title matches a search", function()
                local seen = picker()
                vim.cmd(p.command .. " " .. p.search[1])
                assert.is_true(vim.wait(500, function()
                    return seen.items ~= nil
                end))
                assert.are.equal("documents matching " .. p.search[1], seen.prompt)
                assert.is_true(vim.tbl_contains(seen.labels, p.search[2]))
                if p.door then
                    assert.are.equal(p.door, seen.labels[1])
                end
            end)

            it("completes a number or a title from the cached index", function()
                local seen = picker()
                vim.cmd(p.command)
                -- the picker's turn comes on the loop; the case waits for it so
                -- the stub, and the fixture that restores the real picker, meet it
                assert.is_true(vim.wait(500, function()
                    return seen.items ~= nil
                end))
                local found = false
                for _, item in ipairs(vim.fn.getcompletion(p.command .. " " .. p.complete[1], "cmdline")) do
                    found = found or vim.startswith(item, p.complete[2])
                end
                assert.is_true(found)
            end)

            it("says which source to enable when it is off", function()
                case.setup({ rfc = true })
                vim.cmd(p.command .. " " .. p.id)
                assert.are.equal(
                    ("%s%s is %s; enable sources.%s in setup()"):format(prefix, p.id, p.label, prefix),
                    case.notices[1].msg
                )
                assert.are.equal(vim.log.levels.WARN, case.notices[1].level)
                assert.are.same({}, case.fetched)
            end)
        end)
    end

    describe(":Eip, its own", function()
        it("follows a ToC row on Enter", function()
            vim.cmd("Eip eip1559")
            assert.is_true(editor.wait_help("eip1559"))
            vim.cmd("1")
            vim.fn.search("|eip1559-block-hash-changing|")
            feed("<CR>")
            assert.is_truthy(
                vim.api.nvim_get_current_line():match("^Block Hash Changing%s+%*eip1559%-block%-hash%-changing%*$")
            )
        end)

        it("follows a moved stub into the ERCs repository and tags the result by both names", function()
            vim.cmd("Eip 20")
            assert.is_true(editor.wait_help("eip20"))
            assert.are.same({ "eip20", "erc20" }, case.fetched)
            assert.is_truthy(
                vim.api.nvim_get_current_line():match("^%*eip20%.txt%*  Token Standard.*%*eip20%* %*erc20%*$")
            )
            vim.cmd("helpclose")
            vim.cmd("help erc20")
            assert.is_true(editor.wait_help("eip20"))
        end)

        it("fetches eip20 when the erc20 alias is asked for", function()
            vim.cmd("Eip erc20")
            assert.is_true(editor.wait_help("eip20"))
            assert.are.same({ "eip20", "erc20" }, case.fetched)
            assert.is_truthy(vim.api.nvim_get_current_line():match("%*eip20%* %*erc20%*$"))
        end)
    end)

    describe(":Bip, its own", function()
        it("renders a proposal written in markdown", function()
            vim.cmd("Bip 3")
            assert.is_true(editor.wait_help("bip3"))
            assert.are.equal("BIP-3  Status: Deployed  Type: Process  Assigned: 2025-01-09", vim.fn.getline(2))
        end)
    end)

    describe(":Simd, its own", function()
        it("reads the directory once: a second proposal, or the picker, asks for no listing again", function()
            vim.cmd("Simd 64")
            assert.is_true(editor.wait_help("simd64"))
            vim.cmd("Simd 1")
            assert.is_true(editor.wait_help("simd1"))
            assert.are.same({ "simd-index", "simd64", "simd1" }, case.fetched)
            local seen = picker()
            vim.cmd("Simd")
            assert.is_true(vim.wait(500, function()
                return seen.items ~= nil
            end))
            assert.are.same({ "simd-index", "simd64", "simd1" }, case.fetched)
        end)

        it("reports a proposal the directory does not list", function()
            vim.cmd("Simd 999")
            vim.wait(500, function()
                return #case.notices == 2
            end)
            assert.are.equal("SIMD 999 does not exist", case.notices[2].msg)
            assert.are.same({ "simd-index" }, case.fetched)
        end)
    end)

    describe("search", function()
        it("opens the one document whose number or title matches", function()
            vim.ui.select = function()
                error("the picker should not open for a single match")
            end
            vim.cmd("Eip fee market change")
            assert.is_true(editor.wait_help("eip1559"))
        end)

        it("offers the matches when there are several", function()
            local offered, opts
            vim.ui.select = function(items, o, on_choice)
                offered, opts = items, o
                on_choice(nil)
            end
            vim.cmd("Eip token")
            vim.wait(500, function()
                return offered ~= nil
            end)
            assert.are.equal("documents matching token", opts.prompt)
            assert.are.equal(2 + 1, #offered)
            local texts = vim.tbl_map(opts.format_item, offered)
            assert.is_truthy(vim.tbl_contains(texts, "eip20  Token Standard (Final)"))
            assert.are.equal("eip-subjects  EIPs by subject", texts[1])
        end)

        it("searches only the command's own index", function()
            vim.cmd("Rfc fee market change")
            vim.wait(500, function()
                return #case.notices == 1
            end)
            assert.are.equal("nothing matches fee market change", case.notices[1].msg)
            assert.are.same({ "index" }, case.fetched)
        end)
    end)

    describe("completion", function()
        it("offers the subjects word alone before any index or document is cached", function()
            assert.are.same({ "subjects" }, vim.fn.getcompletion("Rfc ", "cmdline"))
            assert.are.same({ "subjects" }, vim.fn.getcompletion("Eip ", "cmdline"))
            assert.are.same({}, vim.fn.getcompletion("Simd ", "cmdline"))
        end)

        it("completes a number or a title from the command's cached index", function()
            local offered = 0
            vim.ui.select = function(_, _, on_choice)
                offered = offered + 1
                on_choice(nil)
            end
            vim.cmd("Rfc")
            vim.cmd("Eip")
            vim.wait(500, function()
                return offered == 2
            end)
            assert.are.equal(4 + 1, #vim.fn.getcompletion("Rfc ", "cmdline"))
            assert.are.equal(7 + 1, #vim.fn.getcompletion("Eip ", "cmdline"))
            assert.are.equal(
                "eip1559  Fee market change for ETH 1.0 chain (Final)",
                vim.fn.getcompletion("Eip 1559", "cmdline")[1]
            )
            assert.are.equal("eip20  Token Standard (Final)", vim.fn.getcompletion("Eip tokenstand", "cmdline")[1])
            assert.are.same({}, vim.fn.getcompletion("Rfc 1559", "cmdline"))
        end)

        it("completes the tags of the command's cached documents, sections included", function()
            vim.cmd("Rfc 9110")
            assert.is_true(editor.wait_help("9110"))
            assert.are.equal("rfc9110-3.1", vim.fn.getcompletion("Rfc rfc9110-3.1", "cmdline")[1])
            assert.is_false(vim.tbl_contains(vim.fn.getcompletion("Rfc rfc9110", "cmdline"), "rfc9110.txt"))
            assert.are.same({}, vim.fn.getcompletion("Eip rfc9110", "cmdline"))
        end)

        it("opens the first word of a completed item", function()
            vim.cmd("Eip eip1559  Fee market change for ETH 1.0 chain (Final)")
            assert.is_true(editor.wait_help("eip1559"))
        end)
    end)

    describe("the store", function()
        it("renders a document again from the stored text when an older render wrote it", function()
            vim.cmd("Eip 1559")
            assert.is_true(editor.wait_help("eip1559"))
            vim.cmd("helpclose")
            local cfg = config.get()
            local path = store.doc_path(cfg, "eip1559")
            local old = vim.fn.readfile(path)
            old[#old] = " rfc.nvim render 1"
            old[7] = "stale"
            vim.fn.writefile(old, path)
            case.notices = {}
            vim.cmd("Eip 1559")
            assert.is_true(editor.wait_help("eip1559"))
            assert.are.same({ "eip1559" }, case.fetched)
            assert.are.same({}, case.notices)
            local fresh = vim.fn.readfile(path)
            assert.are.equal("  |eip1559-simple-summary|  Simple Summary", fresh[7])
            assert.are.equal(" rfc.nvim render 5", fresh[#fresh])
        end)

        it("fetches again when the stored text is a moved stub, whatever render wrote the document", function()
            local cfg = config.get()
            vim.fn.writefile(fixtures.read(fixtures.eip20_moved), store.raw_path(cfg, "eip20", "md"))
            vim.fn.writefile(
                { "*eip20.txt*  ERC 20", " vim:ft=help:", " rfc.nvim render 1" },
                store.doc_path(cfg, "eip20")
            )
            vim.cmd("Eip 20")
            assert.is_true(editor.wait_help("eip20"))
            assert.are.same({ "eip20", "erc20" }, case.fetched)
            assert.is_truthy(vim.api.nvim_get_current_line():match("^%*eip20%.txt%*  Token Standard"))
            assert.are.equal("fetching EIP 20", case.notices[1].msg)
        end)

        it("shows the new render in a buffer that held the old one", function()
            vim.cmd("Eip 1559")
            assert.is_true(editor.wait_help("eip1559"))
            local cfg = config.get()
            local path = store.doc_path(cfg, "eip1559")
            local old = vim.fn.readfile(path)
            old[#old] = " rfc.nvim render 1"
            old[7] = "stale"
            vim.fn.writefile(old, path)
            vim.cmd("edit!")
            assert.are.equal("stale", vim.api.nvim_buf_get_lines(0, 6, 7, false)[1])
            vim.cmd("Eip 1559")
            assert.is_true(vim.wait(2000, function()
                return editor.wait_help("eip1559") and vim.api.nvim_buf_get_lines(0, 6, 7, false)[1] ~= "stale"
            end))
            assert.are.equal(
                "  |eip1559-simple-summary|  Simple Summary",
                vim.api.nvim_buf_get_lines(0, 6, 7, false)[1]
            )
        end)

        it("retires the documents of the old erc source when it registers", function()
            local cfg = config.get()
            vim.fn.writefile({ "*erc55.txt*  Old  *erc55* *eip55*" }, store.doc_path(cfg, "erc55"))
            vim.fn.writefile({ "old" }, store.raw_path(cfg, "erc55", "md"))
            vim.fn.writefile({ "*eip55.txt*  New  *eip55* *erc55*" }, store.doc_path(cfg, "eip55"))
            case.setup({ rfc = true, eip = true })
            assert.are.equal(0, vim.fn.filereadable(store.doc_path(cfg, "erc55")))
            assert.are.equal(0, vim.fn.filereadable(store.raw_path(cfg, "erc55", "md")))
            local tags = vim.fn.readfile(store.doc_dir(cfg) .. "/tags")
            assert.is_truthy(vim.tbl_contains(tags, "erc55\teip55.txt\t/*erc55*"))
            assert.is_false(vim.tbl_contains(tags, "erc55\terc55.txt\t/*erc55*"))
        end)

        it("retires the eip index of the two all pages when it registers, so the categories are fetched", function()
            local cfg = config.get()
            vim.fn.writefile({ '<h1 class="post-title">All</h1>' }, store.index_path(cfg, "eip-index.html"))
            case.setup({ rfc = true, eip = true })
            assert.are.equal(0, vim.fn.filereadable(store.index_path(cfg, "eip-index.html")))
            vim.cmd("Eip subjects")
            assert.is_true(editor.wait_help("eip-subjects"))
            assert.are.equal(6, #case.fetched)
            assert.is_true(vim.fn.search("|eip-subjects-core|  Core (2)", "nw") > 0)
            assert.are.equal(0, vim.fn.search("All (", "nw"))
        end)

        it("says when what an earlier layout left will not go", function()
            local cfg = config.get()
            -- a directory where the retirement expects a file
            vim.fn.mkdir(store.raw_path(cfg, "erc55", "md"), "p")
            case.setup({ rfc = true, eip = true })
            assert.are.equal("could not retire " .. store.raw_path(cfg, "erc55", "md"), case.notices[1].msg)
            assert.are.equal(vim.log.levels.ERROR, case.notices[1].level)
        end)
    end)

    describe("subjects", function()
        it(":Rfc subjects fetches the tags, writes the document and its tags, and opens it", function()
            vim.cmd("Rfc subjects")
            assert.is_true(editor.wait_help("rfc-subjects"))
            assert.are.same({ "subjects" }, case.fetched)
            assert.is_truthy(vim.api.nvim_get_current_line():match("^%*rfc%-subjects%.txt%*  RFCs by subject"))
            local cfg = config.get()
            assert.are.equal(1, vim.fn.filereadable(store.index_path(cfg, "rfc-subjects.csv")))
            local tags = vim.fn.readfile(store.doc_dir(cfg) .. "/tags")
            assert.is_truthy(
                vim.tbl_contains(tags, "rfc-subjects-web-http\trfc-subjects.txt\t/*rfc-subjects-web-http*")
            )
            assert.are.same(
                { { msg = "fetching the RFC subjects", level = vim.log.levels.INFO, title = "rfc" } },
                case.notices
            )
        end)

        it("opens at a node named by its slug or its last level", function()
            vim.cmd("Rfc subjects web-http")
            assert.is_true(editor.wait_help("rfc-subjects"))
            assert.is_truthy(vim.api.nvim_get_current_line():match("^web / HTTP  %(3%)"))
            vim.cmd("Rfc subjects uri")
            assert.is_true(vim.wait(500, function()
                return vim.api.nvim_get_current_line():match("^web / URI  %(1%)") ~= nil
            end))
        end)

        it("offers the nodes a search matches, with their counts", function()
            local seen
            vim.ui.select = function(items, opts, on_choice)
                seen = { labels = vim.tbl_map(opts.format_item, items), prompt = opts.prompt }
                on_choice(nil)
            end
            vim.cmd("Rfc subjects mail")
            assert.is_true(vim.wait(500, function()
                return seen ~= nil
            end))
            assert.are.equal("subjects matching mail", seen.prompt)
            assert.is_true(vim.tbl_contains(seen.labels, "messaging / email / mailing lists  (1)"))
        end)

        it("says when nothing matches", function()
            vim.cmd("Rfc subjects zzzz")
            assert.is_true(vim.wait(500, function()
                return #case.notices == 2
            end))
            assert.are.equal("nothing matches zzzz", case.notices[2].msg)
            assert.are.equal(vim.log.levels.WARN, case.notices[2].level)
        end)

        it("follows a listed document with CTRL-] and fetches it", function()
            vim.cmd("Rfc subjects web-http")
            assert.is_true(editor.wait_help("rfc-subjects"))
            assert.is_true(vim.fn.search("|rfc1945|", "W") > 0)
            feed("<C-]>")
            assert.is_true(editor.wait_help("1945"))
            assert.are.same({ "subjects", "1945" }, case.fetched)
        end)

        it("serves the cached document again without fetching", function()
            vim.cmd("Rfc subjects")
            assert.is_true(editor.wait_help("rfc-subjects"))
            vim.cmd("helpclose")
            case.notices = {}
            vim.cmd("Rfc subjects")
            assert.is_true(editor.wait_help("rfc-subjects"))
            assert.are.same({ "subjects" }, case.fetched)
            assert.are.same({}, case.notices)
        end)

        it("renders again when the index is newer than the document, in the buffer that showed it", function()
            vim.cmd("Rfc subjects")
            assert.is_true(editor.wait_help("rfc-subjects"))
            local cfg = config.get()
            local index = store.index_path(cfg, "rfc-subjects.csv")
            local lines = vim.fn.readfile(index)
            table.insert(lines, "RFC9999,Nine,2026,HTTP,web | web / HTTP,HTTP,web")
            vim.fn.writefile(lines, index)
            local later = os.time() + 10
            vim.uv.fs_utime(index, later, later)
            vim.cmd("Rfc subjects web-http")
            assert.is_true(vim.wait(2000, function()
                return vim.fn.search("|rfc9999|  Nine (2026)", "nw") > 0
            end))
            assert.are.same({ "subjects" }, case.fetched)
        end)

        it("fetches the subjects again when the index is a day old, though the document is newer", function()
            vim.cmd("Rfc subjects")
            assert.is_true(editor.wait_help("rfc-subjects"))
            vim.cmd("helpclose")
            local cfg = config.get()
            local old = os.time() - 2 * 24 * 60 * 60
            vim.uv.fs_utime(store.index_path(cfg, "rfc-subjects.csv"), old, old)
            vim.cmd("Rfc subjects")
            assert.is_true(editor.wait_help("rfc-subjects"))
            assert.are.same({ "subjects", "subjects" }, case.fetched)
        end)

        it("warns and renders from the stale copy when the fetch fails", function()
            local cfg = config.get()
            local index = store.index_path(cfg, "rfc-subjects.csv")
            vim.fn.writefile(fixtures.read(fixtures.rfc_tags), store.index_path(cfg, "rfc-subjects.csv"))
            local old = os.time() - 2 * 24 * 60 * 60
            vim.uv.fs_utime(index, old, old)
            require("rfc.fetch").subjects = function()
                return require("cds.task").fail("boom")
            end
            vim.cmd("Rfc subjects")
            assert.is_true(editor.wait_help("rfc-subjects"))
            assert.are.equal("fetching the RFC subjects", case.notices[1].msg)
            assert.are.equal(
                "the RFC subjects index could not be refreshed (boom); using the stale copy",
                case.notices[2].msg
            )
            assert.are.equal(vim.log.levels.WARN, case.notices[2].level)
        end)

        it("reports a failed fetch with no copy and opens nothing", function()
            require("rfc.fetch").subjects = function()
                return require("cds.task").fail("boom")
            end
            vim.cmd("Rfc subjects")
            assert.is_true(vim.wait(500, function()
                return #case.notices == 2
            end))
            assert.are.equal("boom", case.notices[2].msg)
            assert.are.equal(vim.log.levels.ERROR, case.notices[2].level)
            assert.are_not.equal("help", vim.bo.filetype)
        end)

        it(":Eip subjects lists the categories as roots", function()
            vim.cmd("Eip subjects core")
            assert.is_true(editor.wait_help("eip-subjects"))
            assert.is_truthy(vim.api.nvim_get_current_line():match("^Core  %(2%)"))
            assert.is_true(vim.fn.search("|eip1559|  Fee market change for ETH 1.0 chain (Final)", "nw") > 0)
            table.sort(case.fetched)
            assert.are.same(
                { "eips-core", "eips-erc", "eips-informational", "eips-interface", "eips-meta", "eips-networking" },
                case.fetched
            )
        end)

        it(":Bip subjects has Layer and Type as roots", function()
            vim.cmd("Bip subjects layer-applications")
            assert.is_true(editor.wait_help("bip-subjects"))
            assert.is_truthy(vim.api.nvim_get_current_line():match("^Layer / Applications  %("))
            assert.is_true(vim.fn.search("|bip32|  Hierarchical Deterministic Wallets (Deployed)", "nw") > 0)
            vim.cmd("help bip-subjects-type-informational")
            assert.is_truthy(vim.api.nvim_get_current_line():match("^Type / Informational  %("))
        end)

        it("shows the tree in the sidebar", function()
            vim.cmd("Rfc subjects")
            assert.is_true(editor.wait_help("rfc-subjects"))
            feed("gO")
            -- the sidebar is whichever window of the tab holds the tree rows
            local function sidebar_rows()
                for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
                    local rows = vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(win), 0, -1, false)
                    if vim.tbl_contains(rows, "web  (0)") then
                        return rows
                    end
                end
            end
            assert.is_true(vim.wait(500, function()
                return sidebar_rows() ~= nil
            end))
            assert.is_true(vim.tbl_contains(sidebar_rows(), "  web / HTTP  (3)"))
        end)

        it("stands first in the picker and opens when chosen", function()
            local seen = picker()
            vim.cmd("Eip")
            assert.is_true(vim.wait(500, function()
                return seen.items ~= nil
            end))
            assert.are.equal("eip-subjects  EIPs by subject", seen.labels[1])
            assert.are.equal(8, #seen.items)
            vim.ui.select = function(items, _, on_choice)
                on_choice(items[1])
            end
            vim.cmd("Eip")
            assert.is_true(editor.wait_help("eip-subjects"))
            assert.are.equal(6, #case.fetched)
        end)

        it("stands above a search's matches, and a lone match still opens at once", function()
            local seen = picker()
            vim.cmd("Eip token")
            assert.is_true(vim.wait(500, function()
                return seen.items ~= nil
            end))
            assert.are.equal("eip-subjects  EIPs by subject", seen.labels[1])
            assert.are.equal(3, #seen.items)
            vim.cmd("Eip fee market")
            assert.is_true(editor.wait_help("eip1559"))
        end)

        it("offers no picker for a search with no match", function()
            vim.ui.select = function()
                error("no picker expected")
            end
            vim.cmd("Eip zzzz")
            assert.is_true(vim.wait(500, function()
                return #case.notices == 1
            end))
            assert.are.equal("nothing matches zzzz", case.notices[1].msg)
        end)

        it("takes a subjects tag as the command's argument and completes the nodes once written", function()
            vim.cmd("Rfc rfc-subjects-web-uri")
            assert.is_true(editor.wait_help("rfc-subjects"))
            assert.is_truthy(vim.api.nvim_get_current_line():match("^web / URI  %(1%)"))
            assert.are.equal("rfc-subjects-web-http", vim.fn.getcompletion("Rfc rfc-subjects-web-h", "cmdline")[1])
            assert.are.same({}, vim.fn.getcompletion("Eip rfc-subjects", "cmdline"))
        end)

        it("completes a node whose name ends in .txt, and still not the file tags", function()
            local cfg = config.get()
            local lines = fixtures.read(fixtures.rfc_tags)
            table.insert(
                lines,
                "RFC9309,Robots Exclusion Protocol,2022,robots.txt,web | web / robots.txt,robots.txt,web"
            )
            vim.fn.writefile(lines, store.index_path(cfg, "rfc-subjects.csv"))
            vim.cmd("Rfc subjects")
            assert.is_true(editor.wait_help("rfc-subjects"))
            local offered = vim.fn.getcompletion("Rfc rfc-subjects", "cmdline")
            assert.is_true(vim.tbl_contains(offered, "rfc-subjects-web-robots.txt"))
            assert.is_false(vim.tbl_contains(offered, "rfc-subjects.txt"))
            assert.is_false(vim.tbl_contains(vim.fn.getcompletion("Rfc rfc9110", "cmdline"), "rfc9110.txt"))
        end)

        it("says which source to enable when it is off", function()
            case.setup({ rfc = true })
            vim.cmd("Eip subjects")
            assert.are.equal("eip-subjects is EIP; enable sources.eip in setup()", case.notices[1].msg)
            assert.are.equal(vim.log.levels.WARN, case.notices[1].level)
            assert.are.same({}, case.fetched)
        end)

        it("completes the word, and the nodes after it from the cached index", function()
            assert.is_true(vim.tbl_contains(vim.fn.getcompletion("Rfc sub", "cmdline"), "subjects"))
            assert.are.same({}, vim.fn.getcompletion("Rfc subjects ", "cmdline"))
            vim.cmd("Rfc subjects")
            assert.is_true(editor.wait_help("rfc-subjects"))
            assert.is_true(vim.tbl_contains(vim.fn.getcompletion("Rfc subjects ", "cmdline"), "web-http"))
            assert.are.equal("web-http", vim.fn.getcompletion("Rfc subjects webht", "cmdline")[1])
            assert.are.same({}, vim.fn.getcompletion("Simd sub", "cmdline"))
        end)
    end)

    describe("activity", function()
        it("is an empty segment while nothing is out", function()
            assert.are.equal("", require("rfc").activity())
        end)
    end)
end)
