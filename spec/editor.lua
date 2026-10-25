-- The editor fixture for the *_nvim_spec.lua tier: loads the plugin from this
-- checkout, points its store at a temporary directory, replaces the network
-- with fixture text, and records what the plugin says.
local fixtures = require("spec.fixtures")
local Task = require("cds.task")

local M = {}

local root = vim.fn.getcwd()

--- Loads the plugin once per Neovim.
function M.load_plugin()
    -- the reader's leader, which the ,tv key is spelled against
    vim.g.mapleader = ","
    vim.opt.runtimepath:append(root)
    vim.cmd("runtime plugin/rfc.lua")
end

--- A Task of a fixture's text, as the network answers it.
---@param fixture string
---@return cds.Task
local function text_of(fixture)
    return Task.of(table.concat(fixtures.read(fixture), "\n") .. "\n")
end

--- A fresh store in a temporary directory, every source enabled, the
--- network replaced by the fixtures (a document outside them does not
--- exist), vim.notify and vim.ui.select captured. Returns the case's record
--- and its restore; `case.setup(sources, extra)` reconfigures the sources, with any
--- other settings merged over.
function M.start()
    local fetch = require("rfc.fetch")
    local saved = { select = vim.ui.select, rtp = vim.o.runtimepath, fetch = {} }
    for name, fn in pairs(fetch) do
        if type(fn) == "function" then
            saved.fetch[name] = fn
        end
    end
    local case = { dir = vim.fn.tempname(), notices = {}, fetched = {}, urls = {} }
    function case.setup(sources, extra)
        require("rfc").setup(vim.tbl_extend("force", {
            cache_dir = case.dir,
            sources = sources,
            notify = function(msg, level, opts)
                table.insert(case.notices, { msg = msg, level = level, title = opts.title })
            end,
        }, extra or {}))
    end
    case.setup({ rfc = true, eip = true, bip = true, simd = true, w3c = true })

    --- What a stub does: records what was asked, answers the fixture, or
    --- refuses as the network would for a document outside them.
    ---@param asked string
    ---@param fixture string|nil
    ---@param missing? string
    ---@return cds.Task
    local function answer(asked, fixture, missing)
        table.insert(case.fetched, asked)
        if not fixture then
            return Task.fail(missing)
        end
        return text_of(fixture)
    end
    local rfcs = {
        ["9110"] = fixtures.rfc9110,
        ["2616"] = fixtures.rfc2616,
        ["1945"] = fixtures.rfc1945,
        ["3986"] = fixtures.rfc3986,
        ["791"] = fixtures.rfc791,
    }
    fetch.rfc = function(n)
        return answer(n, rfcs[n], "RFC " .. n .. " does not exist")
    end
    fetch.index = function()
        return answer("index", fixtures.rfc_index)
    end
    local proposals = {
        eip1 = fixtures.eip1,
        eip1559 = fixtures.eip1559,
        eip20 = fixtures.eip20_moved,
        erc20 = fixtures.erc20,
        -- an ERC filed since the repositories split: ERCs holds it, EIPs has no stub
        erc1123 = fixtures.erc1123,
    }
    fetch.proposal = function(_, _, prefix, id)
        return answer(prefix .. id, proposals[prefix .. id], prefix:upper() .. " " .. id .. " does not exist")
    end
    -- the EIP site's category pages: four as fixtures, two as a page with
    -- the title alone
    local categories = {
        core = fixtures.eips_core,
        erc = fixtures.eips_erc,
        meta = fixtures.eips_meta,
        informational = fixtures.eips_informational,
    }
    fetch.listing = function(url)
        if url:match("bitcoin") then
            return answer("bip-index", fixtures.bips_readme)
        end
        if url == "https://www.w3.org/TR/" then
            return answer("w3c-index", fixtures.w3c_tr)
        end
        local category = url:match("eips%.ethereum%.org/(%a+)")
        table.insert(case.fetched, "eips-" .. category)
        if categories[category] then
            return text_of(categories[category])
        end
        local title = category:sub(1, 1):upper() .. category:sub(2)
        return Task.of('<h1 class="post-title">' .. title .. "</h1>\n")
    end
    fetch.subjects = function()
        return answer("subjects", fixtures.rfc_tags)
    end
    -- W3C reports by the URL asked for (the index's spelling), with a
    -- modification time; `case.w3c_modified = false` makes the stub answer
    -- "unchanged", as a 304 would
    local reports = {
        ["wot-thing-description11"] = fixtures.w3c_td,
        ["css-grid-2"] = fixtures.w3c_grid,
        WCAG22 = fixtures.w3c_grid,
        ["dx-prof-0.9"] = fixtures.w3c_grid,
    }
    fetch.w3c = function(url, shortname)
        table.insert(case.urls, url)
        table.insert(case.fetched, "w3c-" .. shortname)
        if case.w3c_modified == false then
            return Task.of(false)
        end
        local fixture = reports[url:match("/TR/([^/]+)")]
        if not fixture then
            return Task.fail("W3C " .. shortname .. " does not exist")
        end
        return Task.of({ body = table.concat(fixtures.read(fixture), "\n") .. "\n", modified = 1701666464 })
    end
    fetch.simd_listing = function()
        return answer("simd-index", fixtures.simd_listing)
    end
    local simds = {
        ["0064-transaction-receipt.md"] = fixtures.simd64,
        ["0001-simd-process.md"] = fixtures.simd1,
        ["0268-raise-cpi-nesting-limit.md"] = fixtures.simd_related,
    }
    fetch.simd = function(file, id)
        return answer("simd" .. id, simds[file], "SIMD " .. id .. " does not exist")
    end
    local bips = { ["32"] = fixtures.bip32, ["22"] = fixtures.bip22, ["341"] = fixtures.bip341, ["3"] = fixtures.bip3 }
    fetch.bip = function(id)
        return answer("bip" .. id, bips[id], "BIP " .. id .. " does not exist")
    end
    local function restore()
        for name, fn in pairs(saved.fetch) do
            fetch[name] = fn
        end
        vim.ui.select = saved.select
        -- every sidebar, help window and document buffer goes, then the
        -- store's root leaves the runtimepath so the next case's root is the
        -- only one
        require("rfc.toc").close_all()
        pcall(vim.cmd, "helpclose")
        for _, buf in ipairs(vim.api.nvim_list_bufs()) do
            if vim.startswith(vim.api.nvim_buf_get_name(buf), vim.fn.resolve(case.dir)) then
                vim.api.nvim_buf_delete(buf, { force = true })
            end
        end
        vim.o.runtimepath = saved.rtp
        vim.fn.delete(case.dir, "rf")
    end
    return case, restore
end

--- Waits for the current buffer to be the help document named `name`
--- (an RFC number, or a tag such as eip1559).
---@param name string
---@return boolean
function M.wait_help(name)
    if name:match("^%d") then
        name = "rfc" .. name
    end
    return vim.wait(2000, function()
        return vim.bo.filetype == "help"
            and vim.api.nvim_buf_get_name(0):match("/" .. vim.pesc(name) .. "%.txt$") ~= nil
    end)
end

return M
