-- The network, as Tasks: the RFC Editor's text, index and subject tags,
-- the Ethereum proposals' repositories and listing pages, the Bitcoin
-- proposals' repository, and the Solana proposals' directory and files. A
-- spec replaces the eight functions below with Tasks of fixture text.
local Task = require("cds.task")
local http = require("cds.http")
local w3c = require("cds.w3c")

local M = {}

M.rfc_editor = "https://www.rfc-editor.org/"
M.github_raw = "https://raw.githubusercontent.com/"

--- A GET, run now: the body, or nil and a transport failure's message or
--- a status but 200 as `{ status }`.
---@param url string
---@return string|nil body
---@return any err
local function get(url)
    local res, err = http.request({ method = "GET", url = url, timeout = 30 })
    if not res then
        return nil, err.message
    end
    if res.status ~= 200 then
        return nil, { status = res.status }
    end
    return res.body
end

--- A GET as a Task of the body.
---@param url string
---@return cds.Task
function M.get(url)
    return Task.new(function()
        return get(url)
    end)
end

--- The refusal as a sentence: a 404 is the thing not existing.
---@param err any
---@param what string
---@return string
local function describe(err, what)
    if type(err) == "table" and err.status == 404 then
        return what .. " does not exist"
    elseif type(err) == "table" then
        return ("HTTP %d fetching %s"):format(err.status, what)
    end
    return ("%s: %s"):format(what, tostring(err))
end

---@param url string
---@param what string
---@return cds.Task
local function text(url, what)
    return M.get(url):map_err(function(err)
        return describe(err, what)
    end)
end

---@param rfc_num string
---@return cds.Task  -- of the text as one string
function M.rfc(rfc_num)
    return text(M.rfc_editor .. "rfc/rfc" .. rfc_num .. ".txt", "RFC " .. rfc_num)
end

---@return cds.Task  -- of the index text as one string
function M.index()
    return text(M.rfc_editor .. "rfc-index.txt", "the RFC index")
end

M.subject_tags = "https://rfc-editor.github.io/rfc-subject-tags/rfc-tags.csv"

--- The RFC Editor's subject tags, the CSV their pipeline publishes daily.
---@return cds.Task  -- of the CSV as one string
function M.subjects()
    return text(M.subject_tags, "the RFC subjects")
end

--- A proposal's markdown from its repository: ethereum/EIPs keeps
--- EIPS/eip-N.md and ethereum/ERCs keeps ERCS/erc-N.md.
---@param repo string   -- "ethereum/EIPs"
---@param dir string    -- "EIPS"
---@param prefix string -- "eip"
---@param id string
---@return cds.Task
function M.proposal(repo, dir, prefix, id)
    local url = ("%s%s/master/%s/%s-%s.md"):format(M.github_raw, repo, dir, prefix, id)
    return text(url, prefix:upper() .. " " .. id)
end

--- A Bitcoin proposal's text from bitcoin/bips, filed as bip-0032.mediawiki
--- or, for the few written in markdown, bip-0032.md; the second is asked
--- for when the first is not there.
---@param id string
---@return cds.Task
function M.bip(id)
    local base = ("%sbitcoin/bips/master/bip-%04d."):format(M.github_raw, tonumber(id))
    return Task.new(function()
        local body, err = get(base .. "mediawiki")
        if not body and type(err) == "table" and err.status == 404 then
            body, err = get(base .. "md")
        end
        if not body then
            return nil, describe(err, "BIP " .. id)
        end
        return body
    end)
end

local SIMD_REPO = "solana-foundation/solana-improvement-documents"

--- The Solana proposals directory as the GitHub contents API lists it,
--- which is the index: the file names carry the slugs the numbers alone
--- do not give.
---@return cds.Task
function M.simd_listing()
    return text("https://api.github.com/repos/" .. SIMD_REPO .. "/contents/proposals", "the SIMD index")
end

--- A Solana proposal's markdown by its file name in the directory.
---@param file string  -- 0064-transaction-receipt.md
---@param id string    -- the number, for the message
---@return cds.Task
function M.simd(file, id)
    return text(M.github_raw .. SIMD_REPO .. "/main/proposals/" .. file, "SIMD " .. id)
end

--- A W3C technical report by its URL, asked conditionally when the copy's
--- time is given: a 304 answers false (unchanged); a 200 answers the body
--- with the server's Last-Modified as the time to stamp the copy with (now,
--- when the server sends none); a 404 is the report not existing.
---@param url string         -- https://www.w3.org/TR/WCAG22/, the index's spelling
---@param shortname string   -- for the message
---@param since integer|nil  -- the copy's time
---@return cds.Task
function M.w3c(url, shortname, since)
    return Task.new(function()
        local headers = since and { ["If-Modified-Since"] = w3c.http_time(since) } or nil
        local res, err = http.request({ method = "GET", url = url, headers = headers, timeout = 30 })
        if not res then
            return nil, ("W3C %s: %s"):format(shortname, err.message)
        end
        if res.status == 304 then
            return false
        end
        if res.status ~= 200 then
            return nil, describe({ status = res.status }, "W3C " .. shortname)
        end
        local modified = res.headers["last-modified"] and w3c.parse_http_time(res.headers["last-modified"])
        return { body = res.body, modified = modified or os.time() }
    end)
end

--- A listing page, every proposal under its status.
---@param url string
---@param what string
---@return cds.Task
function M.listing(url, what)
    return text(url, what)
end

return M
