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
            assert.are.equal(4, #offered)
            assert.are.equal("rfc", opts.kind)
            assert.are.equal(
                "rfc2616  Hypertext Transfer Protocol -- HTTP/1.1. R. Fielding, J. Gettys, J. Mogul, H. Frystyk, L. Masinter, P. Leach, T. Berners-Lee. June 1999.",
                opts.format_item(offered[4])
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
            assert.are.equal(4, #offered)
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
                local chosen = vim.deepcopy(items[1])
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

    describe(":Eip", function()
        it("opens a proposal by number with its title, header and contents", function()
            vim.cmd("Eip 1559")
            assert.is_true(editor.wait_help("eip1559"))
            assert.are.same({ "eip1559" }, case.fetched)
            local lines = vim.api.nvim_buf_get_lines(0, 0, 8, false)
            assert.is_truthy(lines[1]:match("^%*eip1559%.txt%*  Fee market change for ETH 1%.0 chain"))
            assert.are.equal(
                "EIP-1559  Status: Final  Type: Standards Track  Category: Core  Created: 2019-04-13",
                lines[2]
            )
            assert.are.equal("Requires: |eip2718|, |eip2930|", lines[3])
            assert.are.equal("CONTENTS", lines[6])
            assert.are.equal("  |eip1559-simple-summary|  Simple Summary", lines[7])
        end)

        it("lands on a section by its tag and follows a ToC row", function()
            vim.cmd("Eip eip1559")
            assert.is_true(editor.wait_help("eip1559"))
            vim.cmd("help eip1559-specification")
            assert.is_truthy(vim.api.nvim_get_current_line():match("^SPECIFICATION%s+%*eip1559%-specification%*$"))
            vim.cmd("1")
            vim.fn.search("|eip1559-block-hash-changing|")
            feed("<CR>")
            assert.is_truthy(
                vim.api.nvim_get_current_line():match("^Block Hash Changing%s+%*eip1559%-block%-hash%-changing%*$")
            )
        end)

        it("reports a link to a proposal that does not exist", function()
            vim.cmd("Eip 1559")
            assert.is_true(editor.wait_help("eip1559"))
            vim.cmd("3")
            vim.fn.search("|eip2718|")
            vim.cmd("normal! l")
            feed("<C-]>")
            vim.wait(500, function()
                return #case.notices == 3
            end)
            assert.are.equal("fetching EIP 2718", case.notices[2].msg)
            assert.are.equal("EIP 2718 does not exist", case.notices[3].msg)
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

        it("lists both listings as one index, a number listed twice once", function()
            local offered, opts
            vim.ui.select = function(items, o, on_choice)
                offered, opts = items, o
                on_choice(nil)
            end
            vim.cmd("Eip")
            vim.wait(500, function()
                return offered ~= nil
            end)
            assert.are.equal(5 + 3 - 1, #offered)
            assert.are.equal("eip1559  Fee market change for ETH 1.0 chain (Final)", opts.format_item(offered[5]))
            assert.are.equal("eip20  Token Standard (Final)", opts.format_item(offered[6]))
            table.sort(case.fetched)
            assert.are.same({ "eips-index", "ercs-index" }, case.fetched)
        end)

        it("says which source to enable when eip is off", function()
            case.setup({ rfc = true })
            vim.cmd("Eip 1559")
            assert.are.equal("eip1559 is EIP; enable sources.eip in setup()", case.notices[1].msg)
            assert.are.equal(vim.log.levels.WARN, case.notices[1].level)
            assert.are.same({}, case.fetched)
        end)
    end)

    describe(":Bip", function()
        it("fetches the proposal and opens it as help", function()
            vim.cmd("Bip 32")
            assert.is_true(editor.wait_help("bip32"))
            assert.are.same({ "bip32" }, case.fetched)
            assert.is_truthy(
                vim.api.nvim_get_current_line():match("^%*bip32%.txt%*  Hierarchical Deterministic Wallets")
            )
            assert.are.equal("fetching BIP 32", case.notices[1].msg)
        end)

        it("lands on a section by its tag", function()
            vim.cmd("Bip 32")
            assert.is_true(editor.wait_help("bip32"))
            vim.cmd("help bip32-conventions")
            assert.is_truthy(vim.api.nvim_get_current_line():match("^CONVENTIONS"))
        end)

        it("opens a number written with leading zeros as the same proposal", function()
            vim.cmd("Bip 0032")
            assert.is_true(editor.wait_help("bip32"))
            assert.are.same({ "bip32" }, case.fetched)
        end)

        it("fetches a linked proposal on CTRL-] and reports one that does not exist", function()
            vim.cmd("Bip 341")
            assert.is_true(editor.wait_help("bip341"))
            assert.is_true(vim.fn.search("|bip340|", "W") > 0)
            feed("<C-]>")
            vim.wait(500, function()
                return #case.notices == 3
            end)
            assert.are.same({ "bip341", "bip340" }, case.fetched)
            assert.are.equal("fetching BIP 340", case.notices[2].msg)
            assert.are.equal("BIP 340 does not exist", case.notices[3].msg)
        end)

        it("renders a proposal written in markdown", function()
            vim.cmd("Bip 3")
            assert.is_true(editor.wait_help("bip3"))
            assert.are.equal("BIP-3  Status: Deployed  Type: Process  Assigned: 2025-01-09", vim.fn.getline(2))
        end)

        it("lists the repository's README as the index", function()
            local offered, opts
            vim.ui.select = function(items, o, on_choice)
                offered, opts = items, o
                on_choice(nil)
            end
            vim.cmd("Bip")
            vim.wait(500, function()
                return offered ~= nil
            end)
            assert.are.equal(213, #offered)
            assert.are.equal("bip1  BIP Purpose and Guidelines (Closed)", opts.format_item(offered[1]))
            assert.is_truthy(
                vim.tbl_contains(
                    vim.tbl_map(opts.format_item, offered),
                    "bip32  Hierarchical Deterministic Wallets (Deployed)"
                )
            )
            assert.are.same({ "bip-index" }, case.fetched)
        end)

        it("offers the proposals whose title matches a search", function()
            local offered, opts
            vim.ui.select = function(items, o, on_choice)
                offered, opts = items, o
                on_choice(nil)
            end
            vim.cmd("Bip hierarchical")
            vim.wait(500, function()
                return offered ~= nil
            end)
            assert.are.equal("documents matching hierarchical", opts.prompt)
            local texts = vim.tbl_map(opts.format_item, offered)
            assert.is_truthy(vim.tbl_contains(texts, "bip32  Hierarchical Deterministic Wallets (Deployed)"))
        end)

        it("completes a number or a title from the cached index", function()
            local offered = false
            vim.ui.select = function(_, _, on_choice)
                offered = true
                on_choice(nil)
            end
            vim.cmd("Bip")
            -- the picker's turn comes on the loop; the case waits for it so
            -- the stub, and the fixture that restores the real picker, meet it
            assert.is_true(vim.wait(500, function()
                return offered
            end))
            local function offers(arglead, prefix)
                for _, item in ipairs(vim.fn.getcompletion("Bip " .. arglead, "cmdline")) do
                    if vim.startswith(item, prefix) then
                        return true
                    end
                end
                return false
            end
            assert.is_true(offers("hierarch", "bip32  Hierarchical Deterministic Wallets"))
            assert.is_true(offers("341", "bip341  "))
        end)

        it("says which source to enable when bip is off", function()
            case.setup({ rfc = true })
            vim.cmd("Bip 32")
            assert.are.equal("bip32 is BIP; enable sources.bip in setup()", case.notices[1].msg)
            assert.are.same({}, case.fetched)
        end)
    end)

    describe(":Simd", function()
        it("finds the proposal's file through the directory, fetches it and opens it as help", function()
            vim.cmd("Simd 64")
            assert.is_true(editor.wait_help("simd64"))
            assert.are.same({ "simd-index", "simd64" }, case.fetched)
            assert.is_truthy(vim.api.nvim_get_current_line():match("^%*simd64%.txt%*  Transaction Receipts"))
            assert.are.equal("fetching SIMD 64", case.notices[1].msg)
        end)

        it("lands on a section by its tag", function()
            vim.cmd("Simd 64")
            assert.is_true(editor.wait_help("simd64"))
            vim.cmd("help simd64-summary")
            assert.is_truthy(vim.api.nvim_get_current_line():match("^SUMMARY"))
        end)

        it("opens a number written with leading zeros as the same proposal", function()
            vim.cmd("Simd 0064")
            assert.is_true(editor.wait_help("simd64"))
            assert.are.same({ "simd-index", "simd64" }, case.fetched)
        end)

        it("reports a proposal the directory does not list", function()
            vim.cmd("Simd 999")
            vim.wait(500, function()
                return #case.notices == 2
            end)
            assert.are.equal("SIMD 999 does not exist", case.notices[2].msg)
            assert.are.same({ "simd-index" }, case.fetched)
        end)

        it("follows the proposal another extends on CTRL-]", function()
            vim.cmd("Simd 268")
            assert.is_true(editor.wait_help("simd268"))
            assert.is_true(vim.fn.search("|simd219|", "W") > 0)
            feed("<C-]>")
            vim.wait(500, function()
                return #case.notices == 3
            end)
            assert.are.equal("SIMD 219 does not exist", case.notices[3].msg)
        end)

        it("lists the proposals directory as the index", function()
            local offered, opts
            vim.ui.select = function(items, o, on_choice)
                offered, opts = items, o
                on_choice(nil)
            end
            vim.cmd("Simd")
            vim.wait(500, function()
                return offered ~= nil
            end)
            assert.are.equal(133, #offered)
            assert.are.equal("simd1  Simd Process", opts.format_item(offered[1]))
            assert.are.same({ "simd-index" }, case.fetched)
        end)

        it("completes a number or a title from the cached index", function()
            local offered = false
            vim.ui.select = function(_, _, on_choice)
                offered = true
                on_choice(nil)
            end
            vim.cmd("Simd")
            assert.is_true(vim.wait(500, function()
                return offered
            end))
            local found = false
            for _, item in ipairs(vim.fn.getcompletion("Simd transaction rec", "cmdline")) do
                found = found or vim.startswith(item, "simd64  Transaction Receipt")
            end
            assert.is_true(found)
        end)

        it("says which source to enable when simd is off", function()
            case.setup({ rfc = true })
            vim.cmd("Simd 64")
            assert.are.equal("simd64 is SIMD; enable sources.simd in setup()", case.notices[1].msg)
            assert.are.same({}, case.fetched)
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
            assert.are.equal(2, #offered)
            local texts = vim.tbl_map(opts.format_item, offered)
            assert.is_truthy(vim.tbl_contains(texts, "eip20  Token Standard (Final)"))
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
        it("offers nothing before any index or document is cached", function()
            assert.are.same({}, vim.fn.getcompletion("Rfc ", "cmdline"))
            assert.are.same({}, vim.fn.getcompletion("Eip ", "cmdline"))
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
            assert.are.equal(4, #vim.fn.getcompletion("Rfc ", "cmdline"))
            assert.are.equal(7, #vim.fn.getcompletion("Eip ", "cmdline"))
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
    end)

    describe("activity", function()
        it("is an empty segment while nothing is out", function()
            assert.are.equal("", require("rfc").activity())
        end)
    end)
end)
