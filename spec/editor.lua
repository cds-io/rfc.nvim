-- The editor fixture for the *_nvim_spec.lua tier: loads the plugin from this
-- checkout, points its store at a temporary directory, replaces the network
-- with fixture text, and records what the plugin says.
local fixtures = require("spec.fixtures")
local Task = require("cds.task")

local M = {}

local root = vim.fn.getcwd()

--- Loads the plugin once per Neovim.
function M.load_plugin()
    vim.opt.runtimepath:append(root)
    vim.cmd("runtime plugin/rfc.lua")
end

--- A fresh store in a temporary directory, every source enabled, the
--- network replaced by the fixtures (a document outside them does not
--- exist), vim.notify and vim.ui.select captured. Returns the case's record
--- and its restore; `case.setup(sources)` reconfigures the sources.
function M.start()
    local fetch = require("rfc.fetch")
    local saved = {
        rfc = fetch.rfc,
        index = fetch.index,
        proposal = fetch.proposal,
        listing = fetch.listing,
        select = vim.ui.select,
        rtp = vim.o.runtimepath,
    }
    local case = { dir = vim.fn.tempname(), notices = {}, fetched = {} }
    function case.setup(sources)
        require("rfc").setup({
            cache_dir = case.dir,
            sources = sources,
            notify = function(msg, level, opts)
                table.insert(case.notices, { msg = msg, level = level, title = opts.title })
            end,
        })
    end
    case.setup({ rfc = true, eip = true })
    local bodies = {
        ["9110"] = fixtures.rfc9110,
        ["2616"] = fixtures.rfc2616,
        ["1945"] = fixtures.rfc1945,
        ["3986"] = fixtures.rfc3986,
        ["791"] = fixtures.rfc791,
    }
    fetch.rfc = function(rfc_num)
        table.insert(case.fetched, rfc_num)
        if not bodies[rfc_num] then
            return Task.fail("RFC " .. rfc_num .. " does not exist")
        end
        return Task.of(table.concat(fixtures.read(bodies[rfc_num]), "\n") .. "\n")
    end
    fetch.index = function()
        table.insert(case.fetched, "index")
        return Task.of(table.concat(fixtures.read(fixtures.rfc_index), "\n") .. "\n")
    end
    local proposals = {
        eip1 = fixtures.eip1,
        eip1559 = fixtures.eip1559,
        eip20 = fixtures.eip20_moved,
        erc20 = fixtures.erc20,
    }
    fetch.proposal = function(_, _, prefix, id)
        table.insert(case.fetched, prefix .. id)
        if not proposals[prefix .. id] then
            return Task.fail(prefix:upper() .. " " .. id .. " does not exist")
        end
        return Task.of(table.concat(fixtures.read(proposals[prefix .. id]), "\n") .. "\n")
    end
    fetch.listing = function(url)
        local which = url:match("eips") and "eips" or "ercs"
        table.insert(case.fetched, which .. "-index")
        return Task.of(table.concat(fixtures.read(fixtures[which .. "_all"]), "\n") .. "\n")
    end
    local function restore()
        fetch.rfc = saved.rfc
        fetch.index = saved.index
        fetch.proposal = saved.proposal
        fetch.listing = saved.listing
        vim.ui.select = saved.select
        -- every help window and document buffer goes, then the store's root
        -- leaves the runtimepath so the next case's root is the only one
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
        return vim.bo.filetype == "help" and vim.api.nvim_buf_get_name(0):match("/" .. name .. "%.txt$") ~= nil
    end)
end

return M
