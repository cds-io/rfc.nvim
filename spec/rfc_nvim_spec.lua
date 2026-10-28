-- Opening and navigating RFCs as help. Runs inside Neovim (make test-nvim).
local editor = require("spec.editor")
local fixtures = require("spec.fixtures")
local store = require("rfc.store")
local config = require("rfc.config")
local help = require("rfc.help")
local fp = require("cds.fp")

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

        it("soft-wraps the document's window at word boundaries", function()
            vim.cmd("Rfc 9110")
            assert.is_true(editor.wait_help("9110"))
            assert.is_true(vim.wo.wrap)
            assert.is_true(vim.wo.linebreak)
            assert.is_true(vim.wo.breakindent)
            assert.are.equal("list:-1", vim.wo.breakindentopt)
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
                count = 8 + 1,
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
            index = { count = 133 + 1, label = "simd1  Simd Process", fetched = { "simd-index" } },
            door = "simd-subjects  SIMDs by subject",
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

        it("asks the ERCs repository for an ERC the EIPs repository never held", function()
            vim.cmd("Eip 1123")
            assert.is_true(editor.wait_help("eip1123"))
            assert.are.same({ "eip1123", "erc1123" }, case.fetched)
            assert.is_truthy(
                vim.api
                    .nvim_get_current_line()
                    :match("^%*eip1123%.txt%*  Revised Ethereum Smart Contract Packaging Standard.*%*erc1123%*$")
            )
        end)

        it("names the EIP when neither repository holds the number", function()
            vim.cmd("Eip 2718")
            assert.is_true(vim.wait(2000, function()
                return #case.notices == 2
            end))
            assert.are.same({ "eip2718", "erc2718" }, case.fetched)
            assert.are.equal("EIP 2718 does not exist", case.notices[2].msg)
        end)
    end)

    describe(":Eip status", function()
        --- Every picker that opens, in order: its items, labels and prompt.
        local function pickers()
            local seen = {}
            vim.ui.select = function(items, opts, on_choice)
                table.insert(seen, {
                    items = items,
                    labels = vim.tbl_map(opts.format_item, items),
                    prompt = opts.prompt,
                    choose = on_choice,
                })
            end
            return seen
        end
        local function wait_for(seen, n)
            return vim.wait(1000, function()
                return #seen == n
            end)
        end
        local function title()
            return vim.api.nvim_buf_get_lines(0, 0, 1, false)[1]
        end
        --- The headings of the document shown, "Core  (2)" and the like, their tags stripped.
        local function headings()
            return fp.filter_map(vim.api.nvim_buf_get_lines(0, 0, -1, false), function(line)
                return line:match("^(%S.-  %(%d+%))%s+%*")
            end)
        end

        it("offers All and the statuses in lifecycle order, each with its count", function()
            local seen = pickers()
            vim.cmd("Eip status")
            assert.is_true(wait_for(seen, 1))
            assert.are.equal("EIP status", seen[1].prompt)
            assert.are.same({ "All  (8)", "Final  (5)", "Living  (3)" }, seen[1].labels)
        end)

        it(
            "renders the subjects document on the chosen status: its entries only, counts following, the title saying so",
            function()
                local seen = pickers()
                vim.cmd("Eip status")
                assert.is_true(wait_for(seen, 1))
                seen[1].choose(seen[1].items[2])
                assert.is_true(editor.wait_help("eip-subjects"))
                assert.is_truthy(title():match("^%*eip%-subjects%.txt%*  EIPs by subject  %[Status: Final%]"))
                assert.is_true(vim.fn.search("|eip1|  EIP Purpose and Guidelines (Living)", "nw") == 0)
                assert.is_true(vim.fn.search("|eip1559|  Fee market change for ETH 1.0 chain (Final)", "nw") > 0)
                local lines = headings()
                assert.is_true(vim.tbl_contains(lines, "Final  (5)"))
                assert.is_false(vim.tbl_contains(lines, "Living  (3)"))
                assert.is_true(vim.tbl_contains(lines, "Core  (2)"))
            end
        )

        it("takes the status as the argument, case aside, and All puts every entry back", function()
            vim.cmd("Eip status living")
            assert.is_true(editor.wait_help("eip-subjects"))
            assert.is_truthy(title():match("%[Status: Living%]"))
            assert.is_true(vim.tbl_contains(headings(), "Living  (3)"))
            assert.is_false(vim.tbl_contains(headings(), "Core  (2)"))
            vim.cmd("Eip status all")
            assert.is_true(vim.wait(1000, function()
                return title():match("%[Status") == nil
            end))
            assert.is_true(vim.tbl_contains(headings(), "Core  (2)"))
            assert.is_true(vim.tbl_contains(headings(), "Living  (3)"))
        end)

        it("warns of a status the index does not hold, two words included", function()
            vim.cmd("Eip status last call")
            vim.wait(500, function()
                return #case.notices == 1
            end)
            assert.are.equal("EIP has no status last call", case.notices[1].msg)
        end)

        it("opens :Eip subjects on the configured status until a choice is made", function()
            case.setup({ eip = true }, { status = { eip = "final" } })
            vim.cmd("Eip subjects")
            assert.is_true(editor.wait_help("eip-subjects"))
            assert.is_truthy(title():match("%[Status: Final%]"))
            assert.is_true(vim.tbl_contains(headings(), "Final  (5)"))
        end)

        it("keeps the reader's section and window across the re-render, and cycles the status on gs", function()
            vim.cmd("Eip subjects")
            assert.is_true(editor.wait_help("eip-subjects"))
            vim.cmd("help eip-subjects-core")
            local win, windows = vim.api.nvim_get_current_win(), #vim.api.nvim_list_wins()
            feed("gs")
            assert.is_true(vim.wait(1000, function()
                return title():match("%[Status: Final%]") ~= nil
            end))
            assert.are.equal(win, vim.api.nvim_get_current_win())
            assert.are.equal(windows, #vim.api.nvim_list_wins())
            assert.is_truthy(vim.api.nvim_get_current_line():match("^Core  %(2%)"), vim.api.nvim_get_current_line())
            feed("gs")
            assert.is_true(vim.wait(1000, function()
                return title():match("%[Status: Living%]") ~= nil
            end))
            -- no Core entry is Living, so the section is gone: the top of the document
            assert.are.equal(1, vim.fn.line("."))
            feed("gs")
            assert.is_true(vim.wait(1000, function()
                return title():match("%[Status") == nil
            end))
        end)

        it("keeps every window showing the document in its own section", function()
            vim.cmd("Eip subjects")
            assert.is_true(editor.wait_help("eip-subjects"))
            vim.cmd("help eip-subjects-erc")
            local erc_win = vim.api.nvim_get_current_win()
            vim.cmd("split")
            vim.cmd("help eip-subjects-core")
            local core_win = vim.api.nvim_get_current_win()
            assert.are_not.equal(erc_win, core_win)
            vim.cmd("Eip status final")
            assert.is_true(vim.wait(1000, function()
                return title():match("%[Status: Final%]") ~= nil
            end))
            assert.are.equal(core_win, vim.api.nvim_get_current_win())
            assert.is_truthy(vim.api.nvim_get_current_line():match("^Core  %(2%)"))
            local erc_line = vim.api.nvim_buf_get_lines(
                0,
                vim.api.nvim_win_get_cursor(erc_win)[1] - 1,
                vim.api.nvim_win_get_cursor(erc_win)[1],
                false
            )[1]
            assert.is_truthy(erc_line:match("^ERC  %(2%)"), erc_line)
        end)

        it("takes the reader to the document's window when the status is chosen from elsewhere", function()
            vim.cmd("Eip subjects")
            assert.is_true(editor.wait_help("eip-subjects"))
            local doc_win = vim.api.nvim_get_current_win()
            vim.cmd("help eip-subjects-core")
            vim.cmd("split")
            vim.cmd("enew")
            local windows = #vim.api.nvim_list_wins()
            vim.cmd("Eip status final")
            assert.is_true(vim.wait(1000, function()
                return vim.api.nvim_get_current_win() == doc_win
            end))
            assert.are.equal(windows, #vim.api.nvim_list_wins())
            assert.is_truthy(vim.api.nvim_get_current_line():match("^Core  %(2%)"))
        end)

        it("completes the statuses after the word, All first, once the index is cached", function()
            local seen = pickers()
            vim.cmd("Eip")
            assert.is_true(wait_for(seen, 1))
            assert.are.same({ "All", "Final", "Living" }, vim.fn.getcompletion("Eip status ", "cmdline"))
            assert.are.same({ "Final" }, vim.fn.getcompletion("Eip status fin", "cmdline"))
        end)

        it(
            "reads an RFC's status from the index, in the standards track's order, and filters the CSV's subjects by it",
            function()
                local seen = pickers()
                vim.cmd("Rfc status")
                assert.is_true(wait_for(seen, 1))
                assert.are.same({ "All  (4)", "DRAFT STANDARD  (1)", "UNKNOWN  (3)" }, seen[1].labels)
                vim.cmd("Rfc status draft standard")
                assert.is_true(editor.wait_help("rfc-subjects"))
                assert.is_truthy(title():match("%[Status: DRAFT STANDARD%]"))
                assert.is_true(vim.fn.search("|rfc2616|", "nw") > 0)
                assert.is_true(vim.fn.search("|rfc9110|", "nw") == 0)
            end
        )

        it("orders a BIP's four statuses as the README's lifecycle runs", function()
            local seen = pickers()
            vim.cmd("Bip status")
            assert.is_true(wait_for(seen, 1))
            assert.are.same(
                { "All  (213)", "Draft  (56)", "Complete  (22)", "Deployed  (78)", "Closed  (57)" },
                seen[1].labels
            )
        end)

        it("takes a W3C report's maturity as its status; a report without one counts under All alone", function()
            local seen = pickers()
            vim.cmd("W3c status")
            assert.is_true(wait_for(seen, 1))
            assert.are.same({
                "All  (12)",
                "Draft Standard  (2)",
                "Candidate Standard  (2)",
                "Standard  (3)",
                "Draft Note  (1)",
                "Note  (1)",
                "Draft Registry  (1)",
                "Statement  (1)",
            }, seen[1].labels)
        end)

        it("knows a SIMD's status once its text is cached, and says where the statuses are before", function()
            -- a listing of the three fixture proposals, so the subjects fetch only those
            vim.fn.writefile({
                '[{"name":"0001-simd-process.md"},{"name":"0064-transaction-receipt.md"},{"name":"0268-raise-cpi-nesting-limit.md"}]',
            }, store.index_path(config.get(), "simd-index.json"))
            local seen = pickers()
            vim.cmd("Simd status")
            assert.is_true(wait_for(seen, 1))
            assert.are.same({ "All  (3)" }, seen[1].labels)
            assert.are.equal(
                "SIMD statuses are in the proposals' texts; :Simd subjects fetches every one",
                case.notices[#case.notices].msg
            )
            vim.cmd("Simd subjects")
            assert.is_true(editor.wait_help("simd-subjects"))
            vim.cmd("Simd status")
            assert.is_true(wait_for(seen, 2))
            assert.are.same({ "All  (3)", "Accepted  (1)", "Living  (1)", "Stagnant  (1)" }, seen[2].labels)
            seen[2].choose(seen[2].items[4])
            assert.is_true(vim.wait(1000, function()
                return title():match("%[Status: Stagnant%]") ~= nil
            end))
            assert.is_true(vim.fn.search("|simd64|  Transaction Receipt", "nw") > 0)
            assert.is_true(vim.fn.search("|simd1|", "nw") == 0)
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
            assert.are.same({ "status", "subjects" }, vim.fn.getcompletion("Rfc ", "cmdline"))
            assert.are.same({ "status", "subjects" }, vim.fn.getcompletion("Eip ", "cmdline"))
            assert.are.same({ "status", "subjects" }, vim.fn.getcompletion("Simd ", "cmdline"))
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
            assert.are.equal(4 + 2, #vim.fn.getcompletion("Rfc ", "cmdline"))
            assert.are.equal(8 + 2, #vim.fn.getcompletion("Eip ", "cmdline"))
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
            assert.are.equal(help.FOOTER, fresh[#fresh])
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
            assert.is_truthy(vim.api.nvim_get_current_line():match("^HTTP  %(3%)"))
            vim.cmd("Rfc subjects uri")
            assert.is_true(vim.wait(500, function()
                return vim.api.nvim_get_current_line():match("^URI  %(1%)") ~= nil
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

        it(":Eip subjects files the hardfork meta EIPs under Meta, and every EIP under its status", function()
            vim.cmd("Eip subjects hardforks")
            assert.is_true(editor.wait_help("eip-subjects"))
            assert.is_truthy(vim.api.nvim_get_current_line():match("^Hardforks  %(1%)"))
            assert.is_true(vim.fn.search("|eip7600|  Hardfork Meta - Pectra (Final)", "nw") > 0)
            vim.cmd("help eip-subjects-meta")
            assert.is_truthy(vim.api.nvim_get_current_line():match("^Meta  %(3%)"))
            vim.cmd("help eip-subjects-status-final")
            assert.is_truthy(vim.api.nvim_get_current_line():match("^Final  %(5%)"))
            assert.is_true(vim.fn.search("|eip1559|  Fee market change for ETH 1.0 chain (Final)", "nw") > 0)
            vim.cmd("help eip-subjects-status-living")
            assert.is_truthy(vim.api.nvim_get_current_line():match("^Living  %(3%)"))
        end)

        it(":Simd subjects files each proposal under its status, fetching every proposal once", function()
            local cfg = config.get()
            -- a fresh listing of the three fixture proposals, so the directory is not asked for
            vim.fn.writefile({
                '[{"name":"0001-simd-process.md"},{"name":"0064-transaction-receipt.md"},{"name":"0268-raise-cpi-nesting-limit.md"}]',
            }, store.index_path(cfg, "simd-index.json"))
            vim.cmd("Simd subjects")
            assert.is_true(editor.wait_help("simd-subjects"))
            table.sort(case.fetched)
            assert.are.same({ "simd1", "simd268", "simd64" }, case.fetched)
            assert.is_truthy(vim.api.nvim_get_current_line():match("^%*simd%-subjects%.txt%*  SIMDs by subject"))
            assert.are.equal("fetching the SIMD subjects", case.notices[1].msg)
            vim.cmd("help simd-subjects-status-accepted")
            assert.is_truthy(vim.api.nvim_get_current_line():match("^Accepted  %(1%)"))
            assert.is_true(vim.fn.search("|simd268|  Raise CPI Nesting Limit (Accepted)", "nw") > 0)
            vim.cmd("help simd-subjects-status")
            assert.is_truthy(vim.api.nvim_get_current_line():match("^Status  %(3%)"))
            -- the texts fetched for the document are the documents' own: opening one asks for nothing
            vim.cmd("Simd 64")
            assert.is_true(editor.wait_help("simd64"))
            table.sort(case.fetched)
            assert.are.same({ "simd1", "simd268", "simd64" }, case.fetched)
            -- the nodes complete, read from the document
            assert.is_true(vim.tbl_contains(vim.fn.getcompletion("Simd subjects ", "cmdline"), "status-living"))
        end)

        it(":Bip subjects has Layer and Type as roots", function()
            vim.cmd("Bip subjects layer-applications")
            assert.is_true(editor.wait_help("bip-subjects"))
            assert.is_truthy(vim.api.nvim_get_current_line():match("^Applications  %("))
            assert.is_true(vim.fn.search("|bip32|  Hierarchical Deterministic Wallets (Deployed)", "nw") > 0)
            vim.cmd("help bip-subjects-type-informational")
            assert.is_truthy(vim.api.nvim_get_current_line():match("^Informational  %("))
        end)

        it("shows the tree in the sidebar", function()
            vim.cmd("Rfc subjects")
            assert.is_true(editor.wait_help("rfc-subjects"))
            feed("gO")
            -- the sidebar is whichever window of the tab holds the tree rows
            local function sidebar_rows()
                for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
                    local rows = vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(win), 0, -1, false)
                    if vim.tbl_contains(rows, "web  (4)") then
                        return rows
                    end
                end
            end
            assert.is_true(vim.wait(500, function()
                return sidebar_rows() ~= nil
            end))
            assert.is_true(vim.tbl_contains(sidebar_rows(), "  HTTP  (3)"))
        end)

        it("stands first in the picker and opens when chosen", function()
            local seen = picker()
            vim.cmd("Eip")
            assert.is_true(vim.wait(500, function()
                return seen.items ~= nil
            end))
            assert.are.equal("eip-subjects  EIPs by subject", seen.labels[1])
            assert.are.equal(9, #seen.items)
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
            assert.is_truthy(vim.api.nvim_get_current_line():match("^URI  %(1%)"))
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
            assert.is_true(vim.tbl_contains(vim.fn.getcompletion("Simd sub", "cmdline"), "subjects"))
        end)
    end)

    describe("the render version", function()
        it("is the fingerprint of the plugin's lua tree, which setup gives the render", function()
            local root = vim.fn.fnamemodify(debug.getinfo(require("rfc").setup, "S").source:sub(2), ":h:h:h")
            local version = store.render_version(root)
            assert.is_truthy(version:match("^%x%x%x%x%x%x%x%x%x%x%x%x$"))
            assert.are.equal(version, help.RENDER)
            assert.are.equal(" rfc.nvim render " .. version, help.FOOTER)
        end)
        it("changes with any lua file's content or name, and with nothing else", function()
            local root = vim.fn.tempname()
            vim.fn.mkdir(root .. "/lua/x", "p")
            vim.fn.writefile({ "return 1" }, root .. "/lua/a.lua")
            vim.fn.writefile({ "return 2" }, root .. "/lua/x/b.lua")
            local v1 = store.render_version(root)
            assert.are.equal(v1, store.render_version(root))
            vim.fn.writefile({ "a note" }, root .. "/README.md")
            assert.are.equal(v1, store.render_version(root))
            vim.fn.writefile({ "return 3" }, root .. "/lua/x/b.lua")
            local v2 = store.render_version(root)
            assert.are_not.equal(v1, v2)
            vim.fn.rename(root .. "/lua/x/b.lua", root .. "/lua/x/c.lua")
            assert.are_not.equal(v2, store.render_version(root))
        end)
    end)

    describe(":Crs", function()
        local sources = require("rfc.sources")
        local function fetched(pattern)
            return fp.filter(case.fetched, function(f)
                return f:match(pattern) ~= nil
            end)
        end

        it("knows a crs tag's source, with a dashed legacy id", function()
            assert.are.equal(sources.crs, sources.of("crs-r43397"))
            assert.are.equal(sources.crs, sources.of("crs-98-446rsh#summary"))
            assert.are.equal("98-446rsh", require("rfc.app.names").id_of(sources.crs, "crs-98-446rsh#summary"))
        end)

        it("opens a report by its number after the topic index, in two requests", function()
            vim.cmd("Crs R43397")
            assert.is_true(editor.wait_help("crs-r43397"))
            assert.are.equal(32, #fetched("^crs%-topic%-"))
            assert.are.same({ "crs-R43397.json", "crs-R43397.html" }, fetched("^crs%-R"))
            assert.are.equal(
                "CRS Report R43397 · Updated October 27, 2026 · 17 versions since March 9, 2016",
                vim.fn.getline(2)
            )
        end)

        it("does not ask again for a cached report whose index date has not moved", function()
            vim.cmd("Crs R43397")
            assert.is_true(editor.wait_help("crs-r43397"))
            local before = #case.fetched
            vim.cmd("helpclose")
            vim.cmd("Crs r43397")
            assert.is_true(editor.wait_help("crs-r43397"))
            assert.are.equal(before, #case.fetched)
        end)

        it("follows a citation to another report with CTRL-]", function()
            vim.cmd("Crs R43397")
            assert.is_true(editor.wait_help("crs-r43397"))
            assert.is_true(vim.fn.search("|crs-97-1011|", "W") > 0)
            feed("<C-]>")
            assert.is_true(vim.wait(2000, function()
                return vim.tbl_contains(case.fetched, "crs-97-1011.json")
            end))
            assert.is_true(vim.wait(2000, function()
                local last = case.notices[#case.notices]
                return last ~= nil and last.msg:match("CRS 97%-1011 does not exist") ~= nil
            end))
        end)

        it("refuses a report with no HTML rendering, naming the PDF", function()
            case.crs_no_html = true
            vim.cmd("Crs IF12345")
            assert.is_true(vim.wait(2000, function()
                local last = case.notices[#case.notices]
                return last ~= nil and last.msg:match("no HTML rendering") ~= nil
            end))
            assert.are.equal(
                "CRS IF12345 has no HTML rendering; the PDF is https://crsreports.congress.gov/product/pdf/IF/IF12345/1",
                case.notices[#case.notices].msg
            )
            assert.are.same({}, fetched("%.html$"))
        end)

        it("files the reports by topic and type", function()
            vim.cmd("Crs subjects")
            assert.is_true(editor.wait_help("crs-subjects"))
            assert.is_true(vim.fn.search("|crs-subjects-topics-economic-policy|", "nw") > 0)
            assert.is_true(vim.fn.search("|crs-subjects-topics-national-defense|", "nw") > 0)
            assert.is_true(vim.fn.search("|crs-subjects-type-legal-sidebar|", "nw") > 0)
            assert.is_true(
                vim.fn.search("|crs-ib10051|  Research and Development Funding: Fiscal Year 2001 (2001)", "nw") > 0
            )
            -- listed under both topics and under Type / Legacy: three rows
            local _, rows = table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n"):gsub("|crs%-ib10051|  ", "")
            assert.are.equal(3, rows)
        end)

        it("lands on a topic named by a word", function()
            vim.cmd("Crs subjects economic")
            assert.is_true(editor.wait_help("crs-subjects"))
            assert.is_true(vim.wait(2000, function()
                return vim.api.nvim_get_current_line():match("Economic Policy") ~= nil
            end))
        end)

        it("completes a report by its title", function()
            vim.cmd("Crs R43397")
            assert.is_true(editor.wait_help("crs-r43397"))
            assert.are.equal("crs-r42853", vim.fn.getcompletion("Crs nuclear", "cmdline")[1]:match("^(%S+)"))
        end)
    end)

    describe(":W3c", function()
        local sources = require("rfc.sources")
        it("knows a w3c tag's source, and still the others'", function()
            assert.are.equal(sources.w3c, sources.of("w3c-css-grid-2#5.3"))
            assert.are.equal(sources.w3c, sources.of("w3c-wcag22"))
            assert.are.equal(sources.rfc, sources.of("rfc-subjects"))
            assert.are.equal(sources.bip, sources.of("bip32-conventions"))
            assert.are.equal(sources.eip, sources.of("erc20"))
        end)

        it("follows the tag of a versioned shortname, the dot kept", function()
            require("rfc").jump("w3c-dx-prof-0.9")
            assert.is_true(editor.wait_help("w3c-dx-prof-0.9"))
            assert.are.same({ "w3c-index", "w3c-dx-prof-0.9" }, case.fetched)
        end)

        it("opens a report by shortname, writing text and document, tags at the sections", function()
            vim.cmd("W3c wot-thing-description11")
            assert.is_true(editor.wait_help("w3c-wot-thing-description11"))
            assert.are.same({ "w3c-index", "w3c-wot-thing-description11" }, case.fetched)
            assert.are.equal("fetching W3C wot-thing-description11", case.notices[1].msg)
            local tags = vim.fn.readfile(store.doc_dir(config.get()) .. "/tags")
            assert.is_truthy(
                vim.tbl_contains(
                    tags,
                    "w3c-wot-thing-description11#1.1\tw3c-wot-thing-description11.txt\t/*w3c-wot-thing-description11#1.1*"
                )
            )
        end)

        it("opens a mixed-case shortname by its lowercased tag, fetching the index's spelling", function()
            vim.cmd("W3c wcag22")
            assert.is_true(vim.wait(2000, function()
                return #case.urls > 0
            end))
            assert.are.equal("https://www.w3.org/TR/WCAG22/", case.urls[1])
        end)

        it("searches the titles and opens a lone match", function()
            vim.cmd("W3c web content accessibility guidelines")
            assert.is_true(editor.wait_help("w3c-wcag22"))
        end)

        it("follows a section link, a report link and a reference with CTRL-]", function()
            vim.cmd("W3c wot-thing-description11")
            assert.is_true(editor.wait_help("w3c-wot-thing-description11"))
            assert.is_true(vim.fn.search("|w3c-wot-thing-description11#ref-", "W") > 0)
            feed("<C-]>")
            assert.is_true(vim.wait(500, function()
                return vim.api.nvim_get_current_line():match("%*w3c%-wot%-thing%-description11#ref%-") ~= nil
            end))
            vim.cmd("1")
            assert.is_true(vim.fn.search("|w3c-wot-architecture11|", "W") > 0)
            feed("<C-]>")
            assert.is_true(vim.wait(2000, function()
                return #case.notices >= 3
            end))
            assert.are.equal("fetching W3C wot-architecture11", case.notices[2].msg)
            assert.are.equal("W3C wot-architecture11 does not exist", case.notices[3].msg)
        end)

        it("lands on a section by its tag with # and completes it", function()
            vim.cmd("W3c wot-thing-description11")
            assert.is_true(editor.wait_help("w3c-wot-thing-description11"))
            vim.cmd("help w3c-wot-thing-description11#1.1")
            assert.is_truthy(vim.api.nvim_get_current_line():match("^1%.1 "))
            assert.are.equal(
                "w3c-wot-thing-description11#1.1",
                vim.fn.getcompletion("W3c w3c-wot-thing-description11#1.1", "cmdline")[1]
            )
        end)

        it("stays put on CTRL-] over the title line's file tag", function()
            vim.cmd("W3c wot-thing-description11")
            assert.is_true(editor.wait_help("w3c-wot-thing-description11"))
            vim.cmd("1")
            vim.fn.search("w3c-wot-thing-description11.txt", "c")
            feed("<C-]>")
            assert.is_false(vim.wait(300, function()
                return #case.notices > 1
            end))
            assert.is_true(editor.wait_help("w3c-wot-thing-description11"))
        end)

        it("parses the index once for an open by shortname", function()
            local w3c = require("rfc.source.w3c")
            local index, parses = w3c.index, 0
            w3c.index = function(...)
                parses = parses + 1
                return index(...)
            end
            finally(function()
                w3c.index = index
            end)
            vim.cmd("W3c wot-thing-description11")
            assert.is_true(editor.wait_help("w3c-wot-thing-description11"))
            assert.are.equal(1, parses)
        end)

        it("asks for a report again when the index dates it later, and keeps the copy on 304", function()
            vim.cmd("W3c wot-thing-description11")
            assert.is_true(editor.wait_help("w3c-wot-thing-description11"))
            vim.cmd("helpclose")
            local cfg = config.get()
            local raw = store.raw_path(cfg, "w3c-wot-thing-description11", "html")
            -- a copy from before the index's date: the report is asked for again
            local old = require("rfc.source.w3c").date_time("2023-01-01")
            vim.uv.fs_utime(raw, old, old)
            case.w3c_modified = false
            vim.cmd("W3c wot-thing-description11")
            assert.is_true(editor.wait_help("w3c-wot-thing-description11"))
            assert.are.same({ "w3c-index", "w3c-wot-thing-description11", "w3c-wot-thing-description11" }, case.fetched)
            -- unchanged: the copy carries the index's date now
            assert.are.equal(require("rfc.source.w3c").date_time("2023-12-05"), vim.uv.fs_stat(raw).mtime.sec)
        end)

        it("says when a word names no report", function()
            vim.cmd("W3c zzzz")
            assert.is_true(vim.wait(500, function()
                return #case.notices == 1
            end))
            assert.are.equal("nothing matches zzzz", case.notices[1].msg)
        end)

        it(":W3c subjects files reports by maturity, tag and working group", function()
            vim.cmd("W3c subjects wot")
            assert.is_true(editor.wait_help("w3c-subjects"))
            assert.is_truthy(vim.api.nvim_get_current_line():match("^WoT  %("))
            vim.cmd("help w3c-subjects-maturity-standard")
            assert.is_truthy(vim.api.nvim_get_current_line():match("^Standard  %("))
            assert.are.same(
                { "|w3c-subjects-maturity|", "|w3c-subjects-tags|", "|w3c-subjects-deliverers|" },
                vim.tbl_filter(
                    function(l)
                        return l:match("^|w3c%-subjects%-%l+|$") ~= nil
                    end,
                    vim.tbl_map(function(l)
                        return l:match("^(|[^|]+|)")
                    end, vim.api.nvim_buf_get_lines(0, 3, 300, false))
                )
            )
            vim.cmd("help w3c-subjects-deliverers-web-of-things-wg")
            assert.is_truthy(vim.api.nvim_get_current_line():match("^Web of Things WG  %("))
            assert.is_true(vim.fn.search("|w3c-wot-thing-description11|", "nw") > 0)
        end)

        it("says which source to enable when it is off", function()
            case.setup({ rfc = true })
            vim.cmd("W3c wot-thing-description11")
            assert.are.equal("w3c-wot-thing-description11 is W3C; enable sources.w3c in setup()", case.notices[1].msg)
        end)
    end)

    describe("a report's rich view", function()
        local images = require("cds.images")
        after_each(function()
            images._use(nil)
        end)

        it("draws a report's figures through the images adapter, and ,tv clears them", function()
            local placed, cleared = {}, 0
            images._use({
                name = "stub",
                available = function()
                    return true
                end,
                place = function(spec)
                    table.insert(placed, spec)
                    return { id = #placed }
                end,
                clear = function()
                    cleared = cleared + 1
                end,
            })
            vim.cmd("W3c wot-thing-description11")
            assert.is_true(editor.wait_help("w3c-wot-thing-description11"))
            assert.is_true(vim.wait(500, function()
                return #placed >= 1
            end))
            assert.is_truthy(placed[1].url:match("^https://www%.w3%.org/TR/wot%-thing%-description11/.*%.png$"))
            assert.are.equal(vim.api.nvim_get_current_buf(), placed[1].buf)
            feed(",tv")
            assert.is_true(vim.wait(500, function()
                return cleared == #placed
            end))
        end)

        it("shows figures as text alone without an image backend, and raises no error", function()
            images._use(false)
            vim.cmd("W3c wot-thing-description11")
            assert.is_true(editor.wait_help("w3c-wot-thing-description11"))
            assert.are.same(
                {},
                vim.tbl_filter(function(n)
                    return n.level == vim.log.levels.ERROR
                end, case.notices)
            )
        end)

        it("folds a wide table under its caption with the entry form as virtual lines, and ,tv unfolds", function()
            local cfg = config.get()
            local wide = string.rep("x", 80)
            store.write_doc(cfg, "w3c-wide", {
                lines = {
                    help.with_tag("*w3c-wide.txt*  Wide", "w3c-wide"),
                    "",
                    "Table 1: Wide ~",
                    "  Name  Description",
                    "  ----  -----------",
                    "  id    " .. wide,
                    "  name  " .. wide,
                    "",
                    help.MODELINE,
                    help.FOOTER,
                },
                tags = { { name = "w3c-wide", line = 1 } },
            })
            vim.cmd("help w3c-wide")
            assert.is_true(editor.wait_help("w3c-wide"))
            assert.is_true(vim.wait(500, function()
                return vim.fn.foldclosed(4) == 4
            end))
            assert.are.equal(7, vim.fn.foldclosedend(4))
            local marks = vim.api.nvim_buf_get_extmarks(0, require("rfc.view").ns, 0, -1, { details = true })
            local below = vim.tbl_filter(function(m)
                return m[2] == 2 and m[4].virt_lines ~= nil
            end, marks)
            assert.are.equal(1, #below)
            -- the label line, then the 80-character cell on the line below it
            assert.is_truthy(vim.inspect(below[1][4].virt_lines):match("Description:"))
            assert.is_truthy(vim.inspect(below[1][4].virt_lines):match("    " .. wide))
            feed(",tv")
            assert.is_true(vim.wait(500, function()
                return vim.fn.foldclosed(4) == -1
            end))
        end)
    end)

    describe("activity", function()
        it("is an empty segment while nothing is out", function()
            assert.are.equal("", require("rfc").activity())
        end)
    end)
end)
