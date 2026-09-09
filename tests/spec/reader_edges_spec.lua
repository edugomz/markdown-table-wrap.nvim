local h = require("tests.helpers")

local function open_reader(opts, lines)
  local plugin = require("markdown-table-wrap")
  plugin.setup(vim.tbl_deep_extend("force", {
    auto_preview = true,
    preview_mode = "reader",
    debounce_ms = 0,
    max_width_ratio = 1,
    min_col_width = 4,
    max_col_width = 16,
  }, opts or {}))

  local source_bufnr = vim.api.nvim_create_buf(false, true)
  vim.bo[source_bufnr].buftype = "nofile"
  vim.bo[source_bufnr].swapfile = false
  vim.bo[source_bufnr].filetype = "markdown"
  vim.api.nvim_buf_set_lines(source_bufnr, 0, -1, false, lines or {
    "| Name | Value |",
    "| --- | --- |",
    "| one | two |",
  })
  vim.api.nvim_set_current_buf(source_bufnr)
  return plugin, source_bufnr, plugin.reader_preview()
end

local function leave_insert()
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", true, false, true), "xt", false)
  vim.wait(80)
end

local function close_source(plugin, source_bufnr)
  if vim.api.nvim_get_current_buf() ~= source_bufnr then
    plugin.close_reader()
  end
  plugin.state.paused_buffers[source_bufnr] = nil
  if vim.api.nvim_buf_is_valid(source_bufnr) then
    vim.api.nvim_buf_delete(source_bufnr, { force = true })
  end
end

h.test("Reader insert handoff resumes only its own automatic pause", function()
  -- A separate event loop is necessary: feedkeys(..., 'x') inside a test
  -- command implicitly exits Insert when typeahead empties.
  local chan = vim.fn.jobstart({
    vim.v.progpath,
    "--embed",
    "--headless",
    "-u",
    "NONE",
    "--cmd",
    "set shadafile=NONE noswapfile",
    "--cmd",
    "set rtp^=" .. vim.fn.fnameescape(vim.fn.getcwd()),
  }, { rpc = true })
  local function lua(code, args)
    return vim.rpcrequest(chan, "nvim_exec_lua", code, args or {})
  end
  local ok, err = pcall(function()
    for _, policy in ipairs({ "auto", "paused", "manual", "cancel", "setup", "disable" }) do
      lua(
        [[
        local policy = ...
        local p = require('markdown-table-wrap')
        p.setup({auto_preview=policy~='manual', debounce_ms=0, reset_state=true})
        vim.cmd('enew!'); vim.bo.ft='markdown'
        vim.api.nvim_buf_set_lines(0,0,-1,false,{'| A | B |','| - | - |','| one | two |'})
        _G.edge_source=vim.api.nvim_get_current_buf()
        p.reader_preview()
        if policy=='paused' then p.state.paused_buffers[edge_source]=true end
      ]],
        { policy }
      )
      vim.rpcrequest(chan, "nvim_input", "i")
      h.assert_true(
        policy .. " reaches real Source Insert",
        vim.wait(500, function()
          return lua(
            "return vim.api.nvim_get_current_buf()==edge_source and vim.api.nvim_get_mode().mode:sub(1,1)=='i'"
          )
        end, 10)
      )
      if policy == "cancel" then
        lua("require('markdown-table-wrap').pause_buffer(edge_source)")
      elseif policy == "setup" then
        lua("require('markdown-table-wrap').setup({auto_preview=false,debounce_ms=0})")
      elseif policy == "disable" then
        lua("require('markdown-table-wrap').disable_auto_preview()")
      end
      vim.rpcrequest(chan, "nvim_input", "<Esc>")
      vim.wait(80)
      h.assert_eq(
        policy .. " resume policy",
        lua("return require('markdown-table-wrap.reader').is_reader(0)"),
        policy == "auto"
      )
      if policy == "paused" or policy == "cancel" or policy == "disable" then
        h.assert_true(
          policy .. " retains explicit pause",
          lua("return require('markdown-table-wrap').state.paused_buffers[edge_source]==true")
        )
      end
      lua("require('markdown-table-wrap').close_reader(); vim.api.nvim_buf_delete(edge_source,{force=true})")
    end
    for _, key in ipairs({ "i", "a", "I", "A", "o", "O" }) do
      lua([[
        local p=require('markdown-table-wrap');p.setup({auto_preview=false,reset_state=true})
        vim.cmd('enew!');vim.bo.ft='markdown';edge_source=vim.api.nvim_get_current_buf()
        _G.edge_original={'| A | B |','| - | - |','| one | two |'}
        vim.api.nvim_buf_set_lines(0,0,-1,false,edge_original)
        vim.bo.undolevels=-1;vim.bo.undolevels=1000
        vim.api.nvim_win_set_cursor(0,{3,2});p.reader_preview()
      ]])
      vim.rpcrequest(chan, "nvim_input", key .. "SAFE<Esc>")
      vim.wait(80)
      h.assert_true(
        key .. " inserts fast typeahead before Escape",
        lua("return table.concat(vim.api.nvim_buf_get_lines(edge_source,0,-1,false),'\\n'):find('SAFE',1,true)~=nil")
      )
      lua([[
        _G.edge_undo_calls=0
        vim.keymap.set('n','u',function() edge_undo_calls=edge_undo_calls+1;vim.cmd('undo') end,{buffer=edge_source})
        require('markdown-table-wrap').reader_preview()
      ]])
      vim.rpcrequest(chan, "nvim_input", "u")
      vim.wait(80)
      h.assert_eq("Reader undo honors Source mapping", lua("return edge_undo_calls"), 1)
      h.assert_true(
        key .. " is one Source undo unit",
        lua("return vim.deep_equal(vim.api.nvim_buf_get_lines(edge_source,0,-1,false),edge_original)")
      )
      lua("vim.api.nvim_buf_delete(edge_source,{force=true})")
    end
  end)
  vim.fn.jobstop(chan)
  if not ok then
    error(err)
  end
end)

h.test("Reader Visual redraws whole concealed lines with display-column block ranges", function()
  local plugin, source_bufnr, reader_bufnr = open_reader({ auto_preview = false }, {
    "| Wide | ASCII |",
    "| --- | --- |",
    "| 界界 | beta |",
  })
  local reader = require("markdown-table-wrap.reader")
  local state = reader.get_state(reader_bufnr)
  local target
  for row, object in ipairs(state.line_objects) do
    for _, cell in ipairs(type(object) == "table" and object.cells or {}) do
      if cell.row_index == 1 and cell.column_index == 1 and cell.text:find("界", 1, true) then
        target = { row = row, start_col = cell.start_col, end_col = cell.end_col }
        break
      end
    end
    if target then
      break
    end
  end
  h.assert_true("wide Reader cell is available", target ~= nil)
  local target_line = vim.api.nvim_buf_get_lines(reader_bufnr, target.row - 1, target.row, false)[1]
  local glyph_col = assert(target_line:find("界", 1, true)) - 1
  vim.api.nvim_win_set_cursor(0, { target.row, glyph_col })

  -- Native block Visual records virtual columns, not byte columns. Selecting
  -- a single display column at a two-column glyph must highlight that glyph,
  -- never the following padding/border byte.
  vim.cmd("normal! \22")
  reader.update_visual_selection(reader_bufnr)
  local marks = vim.api.nvim_buf_get_extmarks(reader_bufnr, reader.visual_namespace(), 0, -1, { details = true })
  h.assert_eq("one-line native block selection has one full-line overlay", #marks, 1)
  local mark = marks[1]
  local line = vim.api.nvim_buf_get_lines(reader_bufnr, mark[2], mark[2] + 1, false)[1] or ""
  h.assert_eq("selection overlay starts at the base conceal column", mark[3], 0)
  local rendered = {}
  local selected = {}
  for _, chunk in ipairs(mark[4].virt_text or {}) do
    table.insert(rendered, chunk[1])
    if chunk[2] == "Visual" then
      table.insert(selected, chunk[1])
    end
  end
  h.assert_eq("full-line Visual redraw preserves bytes", table.concat(rendered), line)
  h.assert_eq("one display column on wide glyph selects its full UTF-8 glyph", table.concat(selected), "界")

  -- Actual UI-grid highlighting is verified separately; screenpos() reports
  -- the concealed underlying bytes, not the virtual-text overlay's cells.

  leave_insert()
  close_source(plugin, source_bufnr)
end)

h.test("Reader Visual keeps combining marks with their glyph and honors exclusive selection", function()
  local plugin, source, view = open_reader({ auto_preview = false }, {
    "| A | B |",
    "| - | - |",
    "| éZ | text |",
  })
  local reader = require("markdown-table-wrap.reader")
  local row, col
  for index, line in ipairs(vim.api.nvim_buf_get_lines(view, 0, -1, false)) do
    local first = line:find("éZ", 1, true)
    if first then
      row, col = index, first - 1
      break
    end
  end
  local function selected()
    reader.update_visual_selection(view)
    local values = {}
    for _, mark in ipairs(vim.api.nvim_buf_get_extmarks(view, reader.visual_namespace(), 0, -1, { details = true })) do
      for _, chunk in ipairs(mark[4].virt_text or {}) do
        if chunk[2] == "Visual" then
          values[#values + 1] = chunk[1]
        end
      end
    end
    return table.concat(values)
  end
  vim.api.nvim_win_set_cursor(0, { row, col })
  vim.cmd("normal! v")
  h.assert_eq("composing mark shares selected base", selected(), "é")
  leave_insert()
  local previous = vim.o.selection
  vim.o.selection = "exclusive"
  vim.api.nvim_win_set_cursor(0, { row, col })
  vim.cmd("normal! vl")
  h.assert_eq("exclusive endpoint excludes following Z", selected(), "é")
  leave_insert()
  vim.o.selection = previous
  close_source(plugin, source)
end)
