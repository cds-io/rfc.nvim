-- The entry's capability check. Runs inside Neovim (make test-nvim).
vim.opt.rtp:append(vim.fn.getcwd())

describe("the entry's capability check", function()
    local needs = require("cds.needs")
    local real_check = needs.check
    local real_notify = vim.notify
    local seen

    before_each(function()
        seen = {}
        vim.notify = function(msg, level)
            table.insert(seen, { msg = msg, level = level })
        end
        pcall(vim.api.nvim_del_user_command, "Rfc")
    end)

    after_each(function()
        needs.check = real_check
        package.loaded["cds.needs"] = needs
        package.preload["cds.needs"] = nil
        vim.notify = real_notify
    end)

    it("defines nothing, in words, when the libraries present lack a capability", function()
        needs.check = function(plugin, capabilities)
            assert.are.equal("rfc.nvim", plugin)
            assert.are.same({ "windows" }, capabilities.redraw)
            return "rfc.nvim needs cds-lua with redraw.places: the check's own words"
        end
        vim.cmd("runtime plugin/rfc.lua")
        assert.are.equal(0, vim.fn.exists(":Rfc"))
        assert.are.same({
            {
                msg = "rfc.nvim needs cds-lua with redraw.places: the check's own words",
                level = vim.log.levels.ERROR,
            },
        }, seen)
    end)

    it("defines nothing when the cds-lua-fp present is too old to carry cds.needs", function()
        package.loaded["cds.needs"] = nil
        package.preload["cds.needs"] = function()
            error("module 'cds.needs' not found")
        end
        vim.cmd("runtime plugin/rfc.lua")
        assert.are.equal(0, vim.fn.exists(":Rfc"))
        assert.are.equal("rfc.nvim needs cds-lua-fp with cds.needs: install or update cds-io/cds-lua-fp", seen[1].msg)
    end)

    it("defines the commands when everything declared is there", function()
        vim.cmd("runtime plugin/rfc.lua")
        assert.are.equal(2, vim.fn.exists(":Rfc"))
        assert.are.same({}, seen)
    end)
end)
