local a = vim.api

local M = {}

local modes = {
  ALL = 1,
  OURS = 2,
  THEIRS = 3,
  BASE = 4,
}

local markers = {
  ours = "^<<<<<<< ",
  theirs = "^>>>>>>> ",
  base = "^||||||| ",
  delimiter = "^=======$",
}

local missing_markers = function()
  for name, marker in pairs(markers) do
    if vim.fn.search(marker, "nw") == 0 then
      return name
    end
  end
end

M.start = function()
  local missing = missing_markers()
  if missing then
    -- TODO: Not sure many people will make the connection from a missing marker (most
    -- likely the "base" marker) to the need to adjust `merge.conflictstyle`. Might be
    -- better to just say "make sure you are using the right merge.conflictstyle"
    vim.notify(string.format("Missing marker: %s", missing), "error")
  end

  local contents = M.get_contents(a.nvim_buf_get_lines(0, 0, -1, false))
  local filename = vim.fn.bufname()
  local filetype = vim.bo.filetype

  vim.cmd [[tabnew git-therapy://ours]]
  local left = {
    win = a.nvim_get_current_win(),
    bufnr = a.nvim_get_current_buf(),
  }
  vim.cmd [[diffthis]]

  vim.cmd("belowright vnew " .. filename)
  local middle = {
    win = a.nvim_get_current_win(),
    bufnr = a.nvim_get_current_buf(),
  }
  vim.cmd [[diffthis]]

  vim.cmd [[belowright vnew git-therapy://theirs]]
  local right = {
    win = a.nvim_get_current_win(),
    bufnr = a.nvim_get_current_buf(),
  }
  vim.cmd [[diffthis]]

  vim.cmd [[wincmd =]]

  a.nvim_buf_set_lines(left.bufnr, 0, -1, false, contents.ours.lines)
  a.nvim_buf_set_lines(right.bufnr, 0, -1, false, contents.theirs.lines)

  local base_ns = a.nvim_create_namespace "diff-therapy"
  for idx, hunk in ipairs(contents.base.hunks) do
    local start = -1
    if idx == 1 then
      start = 0
    end

    if hunk.mode == modes.BASE then
      for _, line in ipairs(hunk.lines) do
        local buffer_line = a.nvim_buf_line_count(middle.bufnr) - 1

        a.nvim_buf_set_extmark(middle.bufnr, base_ns, buffer_line, 0, {
          virt_lines = { { { line } } },
        })

        a.nvim_buf_set_extmark(left.bufnr, base_ns, buffer_line, 0, {
          virt_lines = { { { "" } } },
        })
        a.nvim_buf_set_extmark(right.bufnr, base_ns, buffer_line, 0, {
          virt_lines = { { { "" } } },
        })
      end
    else
      a.nvim_buf_set_lines(middle.bufnr, start, -1, false, hunk.lines)
    end
  end

  for _, conf in ipairs { left, middle, right } do
    vim.bo[conf.bufnr].filetype = filetype
    vim.wo[conf.win].wrap = false

    -- 'scrollbind' on
    -- 'cursorbind' on
    -- 'scrollopt'  includes "hor"
  end

  for _, conf in ipairs { left, right } do
    -- Make these "scratch buffers"
    vim.bo[conf.bufnr].buftype = "nofile"
    vim.bo[conf.bufnr].bufhidden = "hide"
    vim.bo[conf.bufnr].swapfile = false
  end

  -- Fix redraw bugs
  vim.cmd [[mode]]

  a.nvim_set_current_win(middle.win)
end

local Contents = {}
Contents.__index = Contents

function Contents:new(mode)
  return setmetatable({ lines = {}, hunks = {}, mode = mode }, self)
end

function Contents:insert(mode, hunk, line)
  if not self.hunks[hunk] then
    self.hunks[hunk] = {
      lines = {},
      mode = mode,
    }
  end

  table.insert(self.hunks[hunk].lines, line)
  table.insert(self.lines, line)
end

M.get_contents = function(lines)
  local hunk = 1
  local mode = modes.ALL

  local contents = {
    ours = Contents:new(modes.OURS),
    theirs = Contents:new(modes.THEIRS),
    base = Contents:new(modes.BASE),
  }

  for _, line in ipairs(lines) do
    if string.find(line, markers.ours) then
      -- Starting new diff
      hunk = hunk + 1
      mode = modes.OURS
    elseif string.find(line, markers.base) then
      mode = modes.BASE
    elseif string.find(line, markers.delimiter) then
      mode = modes.THEIRS
    elseif string.find(line, markers.theirs) then
      -- Ending the diff, so next line is good
      hunk = hunk + 1
      mode = modes.ALL
    else
      if mode == modes.ALL then
        contents.ours:insert(mode, hunk, line)
        contents.theirs:insert(mode, hunk, line)
        contents.base:insert(mode, hunk, line)
      elseif mode == modes.OURS then
        contents.ours:insert(mode, hunk, line)
      elseif mode == modes.THEIRS then
        contents.theirs:insert(mode, hunk, line)
      elseif mode == modes.BASE then
        contents.base:insert(mode, hunk, line)
      else
        error "Unknown mode?"
      end
    end
  end

  return contents
end

return M
