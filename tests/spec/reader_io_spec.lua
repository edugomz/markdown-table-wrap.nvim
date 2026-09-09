local h = require("tests.helpers")
local source_lines = { "# Notes", "", "| A | B |", "| - | - |", "| one | two |" }

local function with_reader(fn, unnamed)
  local plugin = require("markdown-table-wrap")
  plugin.setup({ auto_preview = false })
  local path = vim.fn.tempname() .. ".md"
  local source
  if not unnamed then
    vim.fn.writefile({ "old disk contents" }, path)
    source = vim.fn.bufadd(path)
    vim.fn.bufload(source)
    vim.bo[source].buflisted = true
  else
    source = vim.api.nvim_create_buf(true, false)
  end
  vim.api.nvim_buf_set_lines(source, 0, -1, false, source_lines)
  vim.bo[source].filetype = "markdown"
  vim.api.nvim_set_current_buf(source)
  local view = plugin.reader_preview()
  local ok, err = pcall(fn, source, view, path)
  if require("markdown-table-wrap.reader").is_reader(vim.api.nvim_get_current_buf()) then
    plugin.close_reader()
  end
  if vim.api.nvim_buf_is_valid(source) then
    vim.api.nvim_buf_delete(source, { force = true })
  end
  vim.fn.delete(path)
  if not ok then
    error(err, 0)
  end
end

h.test("Reader real typed save-and-quit commands write Source then exit", function()
  for _, keys in ipairs({ ":wq<CR>", ":x<CR>", "ZZ" }) do
    local exit_status
    local path = vim.fn.tempname() .. ".md"
    vim.fn.writefile({ "old disk contents" }, path)
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
    }, {
      rpc = true,
      on_exit = function(_, code)
        exit_status = code
      end,
    })
    local ok, err = pcall(function()
      vim.rpcrequest(
        chan,
        "nvim_exec_lua",
        [[
        local path, lines = ...
        local p=require('markdown-table-wrap');p.setup({auto_preview=false})
        vim.cmd('edit '..vim.fn.fnameescape(path));vim.bo.ft='markdown'
        vim.api.nvim_buf_set_lines(0,0,-1,false,lines);p.reader_preview()
      ]],
        { path, source_lines }
      )
      vim.rpcrequest(chan, "nvim_input", keys)
      h.assert_true(
        keys .. " exits normally",
        vim.wait(1000, function()
          return exit_status ~= nil
        end, 10)
      )
      h.assert_eq(keys .. " exit status", exit_status, 0)
      h.assert_deep_eq(keys .. " saves only Source bytes", vim.fn.readfile(path), source_lines)
    end)
    pcall(vim.fn.jobstop, chan)
    vim.fn.delete(path)
    if not ok then
      error(err)
    end
  end
end)

h.test("late setup protects a modified phantom without discarding its text", function()
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_current_buf(buf)
  vim.api.nvim_buf_set_name(buf, "markdown-table-wrap://reader/777/unsaved.md")
  vim.bo[buf].buftype = ""
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "recover this text" })
  require("markdown-table-wrap").setup({ auto_preview = false })
  vim.wait(30)
  h.assert_true("modified phantom retained", vim.api.nvim_buf_is_valid(buf))
  h.assert_true("modified state retained", vim.bo[buf].modified)
  h.assert_deep_eq("phantom text retained", vim.api.nvim_buf_get_lines(buf, 0, -1, false), { "recover this text" })
  h.assert_false("phantom cannot own a file write", pcall(vim.cmd, "write"))
  vim.api.nvim_buf_delete(buf, { force = true })
end)

h.test("Reader writes an alternate path and preserves the original Source identity", function()
  local target = vim.fn.tempname() .. " space.md"
  with_reader(function(source, view, path)
    vim.cmd("write " .. vim.fn.fnameescape(target))
    h.assert_deep_eq("alternate file contains Markdown", vim.fn.readfile(target), source_lines)
    h.assert_deep_eq("original file unchanged", vim.fn.readfile(path), { "old disk contents" })
    h.assert_eq("Source path unchanged", vim.api.nvim_buf_get_name(source), vim.fn.resolve(path))
    h.assert_true("Reader stays active", require("markdown-table-wrap.reader").is_reader(view))
  end)
  vim.fn.delete(target)
end)

h.test("Reader saves an unnamed Source with an explicit path", function()
  with_reader(function(source, _, path)
    vim.cmd("write " .. vim.fn.fnameescape(path))
    h.assert_deep_eq("unnamed Source writes Markdown", vim.fn.readfile(path), source_lines)
    h.assert_eq("write names the Source", vim.api.nvim_buf_get_name(source), vim.fn.resolve(path))
    h.assert_false("Source is saved", vim.bo[source].modified)
  end, true)
end)

h.test("Reader forwards bang and saveas to Source without renaming the projection into a document", function()
  local target = vim.fn.tempname() .. "-saveas.md"
  with_reader(function(source, view, path)
    vim.bo[source].readonly = true
    h.assert_false("plain write respects Source readonly", pcall(vim.cmd, "write"))
    vim.cmd("write!")
    h.assert_deep_eq("bang writes original Source", vim.fn.readfile(path), source_lines)
    vim.bo[source].readonly = false
    vim.cmd("saveas " .. vim.fn.fnameescape(target))
    h.assert_eq("saveas renames canonical Source", vim.api.nvim_buf_get_name(source), vim.fn.resolve(target))
    h.assert_true(
      "projection retains a synthetic name",
      vim.api.nvim_buf_get_name(view):match("^markdown%-table%-wrap://") ~= nil
    )
    h.assert_deep_eq("saveas writes Markdown", vim.fn.readfile(target), source_lines)
  end)
  vim.fn.delete(target)
end)

h.test("Reader range writes and append use corresponding physical Source lines", function()
  local target = vim.fn.tempname() .. "-range.md"
  with_reader(function(_, view)
    local state = require("markdown-table-wrap.reader").get_state(view)
    local first = state.source_to_reader[5]
    vim.cmd(first .. "," .. first .. "write " .. vim.fn.fnameescape(target))
    h.assert_deep_eq("wrapped row write uses Source", vim.fn.readfile(target), { source_lines[5] })
    vim.cmd("1,2write >> " .. vim.fn.fnameescape(target))
    h.assert_deep_eq("append uses Source prose", vim.fn.readfile(target), { source_lines[5], "# Notes", "" })
  end)
  vim.fn.delete(target)
end)

h.test("Reader forwards fileformat and Source write hooks, and clears all saved views' modified flags", function()
  with_reader(function(source, view, path)
    local pre, post = 0, 0
    local group = vim.api.nvim_create_augroup("MtwWriteHooksTest", { clear = true })
    vim.api.nvim_create_autocmd("BufWritePre", {
      group = group,
      buffer = source,
      callback = function()
        pre = pre + 1
      end,
    })
    vim.api.nvim_create_autocmd("BufWritePost", {
      group = group,
      buffer = source,
      callback = function()
        post = post + 1
      end,
    })
    local ok, err = pcall(vim.cmd, "write ++ff=dos")
    vim.api.nvim_del_augroup_by_id(group)
    h.assert_true("write with ++ff succeeds: " .. tostring(err), ok)
    h.assert_eq("one Source pre hook", pre, 1)
    h.assert_eq("one Source post hook", post, 1)
    local bytes = table.concat(vim.fn.readfile(path, "b"), "\n")
    h.assert_true("DOS fileformat forwarded", bytes:find("\r\n", 1, true) ~= nil)
    h.assert_false("Source saved", vim.bo[source].modified)
    h.assert_false("Reader saved", vim.bo[view].modified)
  end)
end)

h.test("Reader refuses stale ranges and existing alternate paths without bang", function()
  local target = vim.fn.tempname() .. "-exists.md"
  vim.fn.writefile({ "do not replace" }, target)
  with_reader(function(source, view)
    h.assert_false("existing target requires bang", pcall(vim.cmd, "write " .. vim.fn.fnameescape(target)))
    h.assert_deep_eq("refusal preserves target", vim.fn.readfile(target), { "do not replace" })
    vim.cmd("write! " .. vim.fn.fnameescape(target))
    h.assert_deep_eq("bang replaces with Source", vim.fn.readfile(target), source_lines)
    vim.api.nvim_buf_set_lines(source, 0, 0, false, { "new earlier line" })
    h.assert_false(
      "stale range refused",
      require("markdown-table-wrap.reader").write(view, {
        file = target,
        bang = true,
        partial = true,
        first = 1,
        last = 1,
      })
    )
    h.assert_deep_eq("stale range leaves target intact", vim.fn.readfile(target), source_lines)
  end)
  vim.fn.delete(target)
end)

h.test("renaming Source updates every dependent session URI without losing ownership", function()
  local next_path = vim.fn.tempname() .. "-renamed.md"
  with_reader(function(source, view)
    vim.api.nvim_buf_set_name(source, next_path)
    vim.wait(30)
    h.assert_true("Reader still owned after rename", require("markdown-table-wrap.reader").is_reader(view))
    h.assert_eq(
      "Reader URI follows path",
      vim.api.nvim_buf_get_name(view),
      require("markdown-table-wrap.reader_io").name(view, source)
    )
    vim.cmd("write")
    h.assert_deep_eq("write follows renamed Source", vim.fn.readfile(next_path), source_lines)
  end)
  vim.fn.delete(next_path)
end)

h.test("mksession roundtrip in a fresh Neovim resolves Reader to real Source", function()
  local session = vim.fn.tempname() .. "-session.vim"
  with_reader(function(source, _, path)
    vim.cmd("write")
    local old = vim.o.sessionoptions
    vim.o.sessionoptions = "blank,buffers,curdir,tabpages,winsize"
    local ok, err = pcall(vim.cmd, "mksession! " .. vim.fn.fnameescape(session))
    vim.o.sessionoptions = old
    if not ok then
      error(err)
    end
    h.assert_true(
      "session records Reader URI",
      table.concat(vim.fn.readfile(session), "\n"):find("markdown-table-wrap://reader/v1/", 1, true) ~= nil
    )
    local check = string.format(
      [[
      require('markdown-table-wrap').setup({auto_preview=false})
      vim.cmd('silent source ' .. vim.fn.fnameescape(%q))
      vim.wait(200, function() return vim.api.nvim_buf_get_name(0) == %q end, 5)
      assert(vim.api.nvim_buf_get_name(0) == %q, 'session did not restore Source')
      assert(vim.bo.buftype == '' and vim.bo.modifiable, 'Source is not a normal document')
      assert(vim.api.nvim_buf_get_lines(0,0,1,false)[1] == '# Notes', 'restored rendered data instead of Source')
      print('SESSION_OK')
    ]],
      session,
      vim.api.nvim_buf_get_name(source),
      vim.api.nvim_buf_get_name(source)
    )
    local output = vim.fn.system({
      vim.v.progpath,
      "--headless",
      "-u",
      "NONE",
      "--cmd",
      "set shadafile=NONE noswapfile",
      "--cmd",
      "set rtp^=" .. vim.fn.fnameescape(vim.fn.getcwd()),
      "-c",
      "lua " .. check,
      "-c",
      "qa!",
    })
    h.assert_eq("fresh session exits successfully", vim.v.shell_error, 0)
    h.assert_true("fresh session validates Source: " .. output, output:find("SESSION_OK", 1, true) ~= nil)
    h.assert_deep_eq("session roundtrip never changes file", vim.fn.readfile(path), source_lines)
  end)
  vim.fn.delete(session)
end)

h.test("restored Reader session URIs resolve to Source and reject unresolvable legacy URIs", function()
  local reader = require("markdown-table-wrap.reader")
  with_reader(function(source, view, path)
    vim.fn.writefile(source_lines, path)
    vim.bo[source].modified = false
    local uri = vim.api.nvim_buf_get_name(view)
    require("markdown-table-wrap").close_reader()
    vim.api.nvim_buf_delete(source, { force = true })
    vim.cmd("edit " .. vim.fn.fnameescape(uri))
    vim.wait(150, function()
      return vim.api.nvim_buf_get_name(0) == vim.fn.resolve(path)
    end, 5)
    h.assert_eq("session lands on Source path", vim.api.nvim_buf_get_name(0), vim.fn.resolve(path))
    h.assert_eq("session Source is a normal buffer", vim.bo.buftype, "")
    h.assert_false("session is not a phantom Reader", reader.is_reader(0))
    h.assert_deep_eq("session restores Source bytes", vim.api.nvim_buf_get_lines(0, 0, -1, false), source_lines)
    local restored_source = vim.api.nvim_get_current_buf()
    vim.cmd("edit markdown-table-wrap://reader/999/lost.md")
    vim.wait(30)
    h.assert_false("legacy Reader cannot be written", pcall(vim.cmd, "write"))
    h.assert_false("legacy Reader is not editable", vim.bo.modifiable)
    vim.api.nvim_buf_delete(0, { force = true })
    if vim.api.nvim_buf_is_valid(restored_source) then
      vim.api.nvim_buf_delete(restored_source, { force = true })
    end
  end)
end)
