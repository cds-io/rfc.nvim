local csv = require("rfc.source.csv")

describe("fields", function()
    it("splits plain fields on commas", function()
        assert.are.same({ "RFC791", "Internet Protocol", "1981" }, csv.fields("RFC791,Internet Protocol,1981"))
    end)
    it("keeps a comma inside quotes and drops the quotes", function()
        assert.are.same(
            { "RFC37", "Network Meeting Epilogue, etc", "1970" },
            csv.fields('RFC37,"Network Meeting Epilogue, etc",1970')
        )
    end)
    it("reads a doubled quote as one", function()
        assert.are.same(
            { "RFC175", 'Comments on "Socket Conventions Reconsidered"' },
            csv.fields('RFC175,"Comments on ""Socket Conventions Reconsidered"""')
        )
    end)
    it("keeps empty fields, trailing ones included", function()
        assert.are.same({ "RFC10053", "", "", "" }, csv.fields("RFC10053,,,"))
    end)
    it("refuses an unterminated quote", function()
        local fields, err = csv.fields('a,"b')
        assert.is_nil(fields)
        assert.are.equal("unterminated quote", err)
    end)
end)

describe("records", function()
    it("keys each line by the header", function()
        assert.are.same(
            { { rfc = "RFC791", title = "Internet Protocol" }, { rfc = "RFC37", title = "Epilogue, etc" } },
            csv.records({ "rfc,title", "RFC791,Internet Protocol", 'RFC37,"Epilogue, etc"' })
        )
    end)
    it("skips blank lines", function()
        assert.are.same({ { a = "1" } }, csv.records({ "a", "", "1", "" }))
    end)
    it("refuses a line whose field count differs from the header's", function()
        local records, err = csv.records({ "a,b", "1" })
        assert.is_nil(records)
        assert.are.equal("line 2: 1 fields, header has 2", err)
    end)
end)
