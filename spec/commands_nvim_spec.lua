local editor = require("spec.editor")

describe("command orchestration", function()
    local case, restore, command
    setup(function()
        editor.load_plugin()
    end)
    before_each(function()
        case, restore = editor.start()
        command = require("rfc").command
    end)
    after_each(function()
        require("rfc").command = command
        restore()
    end)

    it("reports unexpected command exceptions through RFC's configured notifier once", function()
        require("rfc").command = function()
            return function()
                error("unexpected command failure")
            end, function()
                return {}
            end
        end
        vim.cmd("Rfc 9110")
        assert.are.equal(1, #case.notices)
        assert.is_truthy(case.notices[1].msg:find("unexpected command failure", 1, true))
        assert.are.equal(vim.log.levels.ERROR, case.notices[1].level)
    end)
end)
