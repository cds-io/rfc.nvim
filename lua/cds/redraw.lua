-- A buffer drawn again while it is on screen: the draw runs once, and every
-- window showing the buffer is put back on its place, so the layout stays
-- the reader's. The place is a key the caller names (a line, a section's
-- tag, an item's signature) taken before the draw and sought after it; with
-- no key, or when the key is gone, the window keeps its line, clamped to
-- the new length. The two halves are `places` and `restore`, for a draw
-- whose text lands later (a listing filled page by page); `windows` is both
-- around a draw that returns with its text. Dependents of the buffer's text
-- (a sidebar, folds) are the caller's to refresh, with the windows answered.
local M = {}

---@class cds.redraw.Keep
---@field key fun(win: integer): any                 -- the window's place before the draw; nil for none
---@field seek fun(win: integer, key: any): boolean  -- the window onto its place after; false when the place is gone

--- The window's cursor, its line clamped to the buffer's length.
---@param win integer
---@param cursor integer[]
local function clamp(win, cursor)
  local last = vim.api.nvim_buf_line_count(vim.api.nvim_win_get_buf(win))
  pcall(vim.api.nvim_win_set_cursor, win, { math.min(cursor[1], last), cursor[2] })
end

---@class cds.redraw.Places
---@field buf integer
---@field wins integer[]                                    -- the windows showing the buffer when taken
---@field of table<integer, { cursor: integer[], key: any }>  -- each window's cursor and place

--- The windows showing `buf` and each one's place, taken before a draw:
--- its cursor, and the key `keep` names when given.
---@param buf integer
---@param keep? cds.redraw.Keep
---@return cds.redraw.Places
function M.places(buf, keep)
  local wins = vim.fn.win_findbuf(buf)
  local of = {}
  for _, win in ipairs(wins) do
    of[win] = { cursor = vim.api.nvim_win_get_cursor(win), key = keep and keep.key(win) or nil }
  end
  return { buf = buf, wins = wins, of = of }
end

--- Each window back on its place, after the draw: where `keep` finds the
--- key it named, or on its line clamped to the new length. A window gone
--- meanwhile is passed over. Whenever after: at once, or when the text
--- the place is in has landed.
---@param places cds.redraw.Places
---@param keep? cds.redraw.Keep
function M.restore(places, keep)
  for _, win in ipairs(places.wins) do
    if vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_buf(win) == places.buf then
      local place = places.of[win]
      local found = keep ~= nil and place.key ~= nil and keep.seek(win, place.key)
      if not found then
        clamp(win, place.cursor)
      end
    end
  end
end

--- Runs `draw` with the windows showing `buf`, then puts each window back:
--- on the place `keep` names when it is still there, on its line otherwise.
--- The two halves as one call, for a draw whose text is there when it
--- returns. Answers the windows, for the caller's own dependents.
---@param buf integer
---@param draw fun(wins: integer[])
---@param keep? cds.redraw.Keep
---@return integer[] wins
function M.windows(buf, draw, keep)
  local places = M.places(buf, keep)
  draw(places.wins)
  M.restore(places, keep)
  return places.wins
end

return M
