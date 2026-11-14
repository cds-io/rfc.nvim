local dates = require("rfc.dates")

describe("times", function()
    it("turns an index date into a time and back, and reads and writes HTTP dates", function()
        assert.are.equal(
            "Mon, 04 Dec 2023 05:07:44 GMT",
            dates.http_time(dates.parse_http_time("Mon, 04 Dec 2023 05:07:44 GMT"))
        )
        assert.is_true(dates.date_time("2023-12-05") > dates.parse_http_time("Mon, 04 Dec 2023 05:07:44 GMT"))
        assert.is_nil(dates.parse_http_time("yesterday"))
    end)
end)
