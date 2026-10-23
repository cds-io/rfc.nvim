-- The one module that names an image plugin, as cds.async is the one that
-- names vim.async: a view asks for a picture below a buffer row and gets a
-- placement back, and which plugin draws it is this file's business. The
-- first backend is image.nvim; another is another table below, chosen by
-- which plugin loads. With no backend, available() is false and every
-- other call is a no-op, so a document reads as rendered.
local M = {}

---@class cds.images.Spec
---@field buf integer
---@field win integer
---@field row integer       -- 1-based; the image goes below this line
---@field url string        -- an http(s) URL or a file path
---@field max_height integer -- rows

---@class cds.images.Placement
---@field buf integer
---@field backend table
---@field image any|nil     -- the backend's object once it exists
---@field cleared boolean|nil

---@class cds.images.Backend
---@field name string
---@field available fun(): boolean
---@field place fun(spec: cds.images.Spec, placement: cds.images.Placement): cds.images.Placement|nil, string|nil
---@field clear fun(placement: cds.images.Placement)

--- image.nvim: from_url and from_file bind an image to a buffer and a
--- window, inline below a row, padding the buffer with virtual lines;
--- from_url is asynchronous, so the placement is filled in when the
--- image arrives, and a placement cleared before then clears the image
--- on arrival.
local image_nvim = {
  name = "image.nvim",
  available = function()
    local ok, image = pcall(require, "image")
    return ok and type(image.is_enabled) == "function" and image.is_enabled() == true
  end,
  place = function(spec, placement)
    local image = require("image")
    local opts = {
      window = spec.win,
      buffer = spec.buf,
      inline = true,
      with_virtual_padding = true,
      x = 0,
      y = spec.row - 1, -- the extmark row, 0-based
      -- `height` would be the exact height, scaling a small diagram up;
      -- the per-image percentage of the window is the cap it offers
      max_height_window_percentage = spec.max_height / vim.api.nvim_win_get_height(spec.win) * 100,
    }
    local function show(img)
      if not img then
        return
      end
      if placement.cleared then
        img:clear()
        return
      end
      placement.image = img
      img:render()
    end
    if spec.url:match("^https?://") then
      image.from_url(spec.url, opts, show)
    else
      show(image.from_file(spec.url, opts))
    end
    return placement
  end,
  clear = function(placement)
    if placement.image then
      placement.image:clear()
      placement.image = nil
    end
    placement.cleared = true
  end,
}

-- The backends, first available wins.
M._backends = { image_nvim }

-- A backend forced by a spec: a table to use it, false for none, nil for
-- the usual choice.
local forced = nil

-- The placements made, by buffer.
---@type table<integer, cds.images.Placement[]>
local placements = {}

--- For specs: use this backend (a table), none (false), or the usual (nil),
--- forgetting the placements made so far, since they were another
--- backend's.
---@param backend table|false|nil
function M._use(backend)
  forced = backend
  placements = {}
end

---@return cds.images.Backend|nil
local function backend()
  if forced == false then
    return nil
  elseif forced then
    return forced
  end
  for _, b in ipairs(M._backends) do
    if b.available() then
      return b
    end
  end
  return nil
end

--- Whether a backend is loaded and can draw here.
---@return boolean
function M.available()
  return backend() ~= nil
end

--- Draws the image at `spec.url` inline below `spec.row`; the placement,
--- or nil and the reason when the backend refuses; nil without a backend.
---@param spec cds.images.Spec
---@return cds.images.Placement|nil
---@return string|nil err
function M.place(spec)
  local b = backend()
  if not b then
    return nil
  end
  local placement = { buf = spec.buf, backend = b }
  local made, err = b.place(spec, placement)
  if not made then
    return nil, err
  end
  -- whatever table the backend answers is the placement the adapter clears
  made.backend = b
  made.buf = made.buf or spec.buf
  placements[spec.buf] = placements[spec.buf] or {}
  table.insert(placements[spec.buf], made)
  return made
end

--- Removes one placement, once.
---@param placement cds.images.Placement|nil
function M.clear(placement)
  if placement and placement.backend and not placement.cleared then
    placement.backend.clear(placement)
    placement.cleared = true
  end
end

--- Removes every placement made in the buffer.
---@param buf integer
function M.clear_all(buf)
  for _, p in ipairs(placements[buf] or {}) do
    M.clear(p)
  end
  placements[buf] = nil
end

return M
