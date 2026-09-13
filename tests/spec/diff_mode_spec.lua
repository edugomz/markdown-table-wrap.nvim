local h = require("tests.helpers")

local function delete_buffer(bufnr)
  if vim.api.nvim_buf_is_valid(bufnr) then
    vim.api.nvim_buf_delete(bufnr, { force = true })
  end
end

local function make_buffer(lines)
  local buf = vim.api.nvim_create_buf(true, false)
  vim.bo[buf].swapfile = false
  vim.bo[buf].filetype = "markdown"
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  return buf
end

local left_lines = {
  "| Name  | Value |",
  "| ----- | ----- |",
  "| Alpha | 1     |",
}
local right_lines = {
  "| Name  | Value |",
  "| ----- | ----- |",
  "| Alpha | 2     |",
}

h.test("Reader does not open in a window that is in diff mode", function()
  local plugin = require("markdown-table-wrap")
  local reader = require("markdown-table-wrap.reader")
  plugin.setup({ auto_preview = true, preview_mode = "reader", debounce_ms = 0 })

  local left_win = vim.api.nvim_get_current_win()
  local left = make_buffer(left_lines)
  vim.api.nvim_win_set_buf(left_win, left)

  vim.cmd("vsplit")
  local right_win = vim.api.nvim_get_current_win()
  local right = make_buffer(right_lines)
  vim.api.nvim_win_set_buf(right_win, right)

  vim.api.nvim_win_call(left_win, function()
    vim.cmd("diffthis")
  end)
  vim.api.nvim_win_call(right_win, function()
    vim.cmd("diffthis")
  end)

  vim.wait(200, function()
    return vim.wo[left_win].diff and vim.wo[right_win].diff
  end, 10)

  h.assert_true("left window keeps diff mode", vim.wo[left_win].diff)
  h.assert_true("right window keeps diff mode", vim.wo[right_win].diff)
  h.assert_false("left window is not wrapped into Reader", reader.is_reader(vim.api.nvim_win_get_buf(left_win)))
  h.assert_false("right window is not wrapped into Reader", reader.is_reader(vim.api.nvim_win_get_buf(right_win)))

  vim.cmd("diffoff!")
  vim.api.nvim_win_close(right_win, true)
  delete_buffer(left)
  delete_buffer(right)
  plugin.state.paused_buffers = {}
end)

h.test("turning on diff for an already-open Reader window falls back to source and keeps diffing", function()
  local plugin = require("markdown-table-wrap")
  local reader = require("markdown-table-wrap.reader")
  plugin.setup({ auto_preview = true, preview_mode = "reader", debounce_ms = 0 })

  local left_win = vim.api.nvim_get_current_win()
  local left = make_buffer(left_lines)
  vim.api.nvim_win_set_buf(left_win, left)
  vim.wait(200, function()
    return reader.is_reader(vim.api.nvim_win_get_buf(left_win))
  end, 10)
  h.assert_true(
    "Reader opened for the left window before diffing",
    reader.is_reader(vim.api.nvim_win_get_buf(left_win))
  )

  vim.cmd("vsplit")
  local right_win = vim.api.nvim_get_current_win()
  local right = make_buffer(right_lines)
  vim.api.nvim_win_set_buf(right_win, right)

  vim.api.nvim_win_call(left_win, function()
    vim.cmd("diffthis")
  end)
  vim.api.nvim_win_call(right_win, function()
    vim.cmd("diffthis")
  end)

  vim.wait(300, function()
    return not reader.is_reader(vim.api.nvim_win_get_buf(left_win)) and vim.wo[left_win].diff
  end, 10)

  h.assert_false(
    "left window falls back to the real source buffer",
    reader.is_reader(vim.api.nvim_win_get_buf(left_win))
  )
  h.assert_eq("left window shows its own source buffer", vim.api.nvim_win_get_buf(left_win), left)
  h.assert_true("left window is registered for diff", vim.wo[left_win].diff)
  h.assert_true("right window is registered for diff", vim.wo[right_win].diff)

  vim.cmd("diffoff!")
  vim.wait(200, function()
    return reader.is_reader(vim.api.nvim_win_get_buf(left_win))
      and reader.is_reader(vim.api.nvim_win_get_buf(right_win))
  end, 10)
  h.assert_true("Reader resumes on the left window after diffoff", reader.is_reader(vim.api.nvim_win_get_buf(left_win)))
  h.assert_true(
    "Reader resumes on the right window after diffoff",
    reader.is_reader(vim.api.nvim_win_get_buf(right_win))
  )

  vim.api.nvim_set_current_win(left_win)
  plugin.close_reader()
  vim.api.nvim_set_current_win(right_win)
  plugin.close_reader()
  vim.api.nvim_win_close(right_win, true)
  delete_buffer(left)
  delete_buffer(right)
  plugin.state.paused_buffers = {}
end)
