-- The cache's entries over a temporary root. Runs inside Neovim (make test-nvim).
local cache = require("rfc.cache")
local store = require("rfc.store")
local help = require("rfc.help")
local Task = require("cds.task")

describe("cache", function()
    local cfg, notices, produced

    --- A fetched entry over a stub produce that counts its calls and
    --- answers `body` or fails with `err`.
    local function fetched(spec)
        return cache.fetched(
            cfg,
            vim.tbl_extend("force", {
                file = "thing.txt",
                label = "the thing",
                notify = function(msg, level)
                    table.insert(notices, { msg = msg, level = level })
                end,
                produce = function()
                    produced = produced + 1
                    return spec.err and Task.fail(spec.err) or Task.of(spec.body or "a\nb\n")
                end,
            }, spec)
        )
    end

    --- Runs a Task to completion on the loop; the value and the error.
    local function wait(task)
        local done, value, err = false, nil, nil
        task:run():on_complete(function(terr, v, e)
            value, err, done = v, terr and tostring(terr) or e, true
        end)
        vim.wait(2000, function()
            return done
        end)
        return value, err
    end

    local function touch(path, mtime)
        vim.uv.fs_utime(path, mtime, mtime)
    end

    before_each(function()
        cfg = { cache_dir = vim.fn.tempname() }
        notices, produced = {}, 0
        store.register(cfg)
    end)

    after_each(function()
        vim.fn.delete(cfg.cache_dir, "rf")
    end)

    describe("a fetched entry", function()
        it("produces, cleans, writes and answers when there is no copy", function()
            local e = fetched({ body = "a\r\nb\n" })
            assert.is_false(e:fresh())
            assert.are.same({ "a", "b" }, wait(e:lines()))
            assert.are.same({ "a", "b" }, vim.fn.readfile(e:path()))
            assert.are.equal(1, produced)
            assert.is_true(e:fresh())
        end)
        it("answers a fresh copy without producing", function()
            local e = fetched({ max_age = 60 })
            wait(e:lines())
            wait(e:lines())
            assert.are.equal(1, produced)
        end)
        it("produces again when the copy is older than max_age", function()
            local e = fetched({ max_age = 60 })
            wait(e:lines())
            touch(e:path(), os.time() - 61)
            wait(e:lines())
            assert.are.equal(2, produced)
        end)
        it("never ages without a max_age", function()
            local e = fetched({})
            wait(e:lines())
            touch(e:path(), os.time() - 10 * 24 * 3600)
            wait(e:lines())
            assert.are.equal(1, produced)
        end)
        it("produces again when the copy is a placeholder, and cached() hides it", function()
            local e = fetched({
                placeholder = function(lines)
                    return lines[1] == "stub"
                end,
            })
            vim.fn.writefile({ "stub" }, e:path())
            assert.is_nil(e:cached())
            assert.are.same({ "a", "b" }, wait(e:lines()))
            assert.are.equal(1, produced)
            assert.are.same({ "a", "b" }, e:cached())
        end)
        it("warns and answers the stale copy when producing fails", function()
            local e = fetched({ max_age = 60, err = "boom" })
            vim.fn.writefile({ "old" }, e:path())
            touch(e:path(), os.time() - 61)
            assert.are.same({ "old" }, wait(e:lines()))
            assert.are.same({
                { msg = "the thing could not be refreshed (boom); using the stale copy", level = vim.log.levels.WARN },
            }, notices)
        end)
        it("fails with the produce's error when there is no copy", function()
            local value, err = wait(fetched({ err = "boom" }):lines())
            assert.is_nil(value)
            assert.are.equal("boom", err)
            assert.are.same({}, notices)
        end)
        it("fails with a thrown error and writes nothing", function()
            local e = fetched({})
            e.produce = function()
                return Task.new(function()
                    error("thrown")
                end)
            end
            local value, err = wait(e:lines())
            assert.is_nil(value)
            assert.is_truthy(err:match("thrown"))
            assert.are.equal(0, vim.fn.filereadable(e:path()))
        end)
        it("memoises a parse per mtime, by name, across entries for one file", function()
            local e = fetched({})
            assert.is_nil(e:memo("n", function() end))
            wait(e:lines())
            local parses = 0
            local function count(lines)
                parses = parses + 1
                return #lines
            end
            assert.are.equal(2, e:memo("n", count))
            assert.are.equal(2, fetched({}):memo("n", count))
            assert.are.equal(1, parses)
            assert.are.equal(2, e:memo("other", count))
            assert.are.equal(2, parses)
            vim.fn.writefile({ "a", "b", "c" }, e:path())
            touch(e:path(), os.time() + 5)
            assert.are.equal(3, e:memo("n", count))
            assert.are.equal(3, parses)
        end)
    end)

    describe("a derived entry", function()
        local function derived(input, body)
            return cache.derived(cfg, {
                name = "rfc7",
                from = { input },
                version = help.RENDER,
                produce = function(lines)
                    return {
                        lines = { "*rfc7.txt*  D  *rfc7*", body or lines[1], "", help.MODELINE, help.FOOTER },
                        tags = { { name = "rfc7", line = 1 } },
                    }
                end,
            })
        end
        it("produces when the document is missing, then is current", function()
            local d = derived(fetched({}))
            assert.is_false(d:current())
            assert.are.equal("rfc7", wait(d:ensure()))
            assert.is_true(d:current())
            assert.are.equal("a", vim.fn.readfile(d:path())[2])
            local tags = vim.fn.readfile(store.doc_dir(cfg) .. "/tags")
            assert.is_truthy(vim.tbl_contains(tags, "rfc7\trfc7.txt\t/*rfc7*"))
        end)
        it("produces again when the document carries an older render", function()
            local d = derived(fetched({}))
            wait(d:ensure())
            local lines = vim.fn.readfile(d:path())
            lines[#lines] = " rfc.nvim render 1"
            vim.fn.writefile(lines, d:path())
            assert.is_false(d:current())
            wait(d:ensure())
            assert.are.equal(help.FOOTER, vim.fn.readfile(d:path())[5])
        end)
        it("produces again when an input is newer, and is current when they are of one second", function()
            local input = fetched({})
            local d = derived(input)
            wait(d:ensure())
            touch(input:path(), os.time() + 10)
            assert.is_false(d:current())
            touch(d:path(), os.time() + 10)
            assert.is_true(d:current())
        end)
        it("is not current when an input is missing, and produces it through the input", function()
            local input = fetched({})
            local d = derived(input)
            wait(d:ensure())
            vim.fn.delete(input:path())
            assert.is_false(d:current())
            wait(d:ensure())
            assert.are.equal(2, produced)
            assert.is_true(d:current())
        end)
        it("does not produce when current", function()
            local d = derived(fetched({}))
            wait(d:ensure())
            local before = vim.uv.fs_stat(d:path()).mtime.sec
            touch(d:path(), before - 100)
            touch(fetched({}):path(), before - 100)
            wait(d:ensure())
            assert.are.equal(before - 100, vim.uv.fs_stat(d:path()).mtime.sec)
        end)
        it("passes a produce refusal through as the error", function()
            local d = cache.derived(cfg, {
                name = "rfc7",
                from = { fetched({}) },
                version = help.RENDER,
                produce = function()
                    return nil, "no good"
                end,
            })
            local value, err = wait(d:ensure())
            assert.is_nil(value)
            assert.are.equal("no good", err)
        end)
    end)
end)
