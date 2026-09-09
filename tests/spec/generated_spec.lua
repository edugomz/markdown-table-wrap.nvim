local h = require("tests.helpers")

h.test("generated mixed Unicode tables retain exact Source spans and equal-width rendered rows", function()
  local parser = require("markdown-table-wrap.parser")
  local render = require("markdown-table-wrap.render")
  local config = require("markdown-table-wrap.config")
  local values = {
    "",
    "界😀",
    "éclair",
    "a\\|b",
    "`a|b`",
    "`unmatched",
    "**bold**",
    "[label](https://example.com)",
    "word  tail",
    "a\tb",
    "éZ",
  }
  local seed = 1741
  local function choose(size)
    seed = (seed * 48271) % 2147483647
    return (seed % size) + 1
  end
  for case = 1, 80 do
    -- Keep unmatched code delimiters out of pairs spanning another cell;
    -- those intentionally change separator interpretation in this plugin.
    local row = {}
    for column = 1, 3 do
      row[column] = values[choose(#values)]
    end
    if table.concat(row):find("`unmatched", 1, true) then
      row = { "`unmatched", "界😀", "éclair" }
    end
    local prefix = string.rep("> ", choose(4) - 1)
    local lines =
      { prefix .. "| A | B | C |", prefix .. "| - | :- | -: |", prefix .. "| " .. table.concat(row, " | ") .. " |" }
    local tables = parser.parse_lines(lines)
    h.assert_eq("generated table parsed " .. case, #tables, 1)
    local model = assert(tables[1])
    for _, cell in ipairs(model.rows[1]) do
      local span = cell.source_span
      h.assert_eq(
        "generated span roundtrips " .. case,
        lines[span.start_lnum]:sub(span.start_col + 1, span.end_col),
        cell.raw
      )
    end
    local opts = config.resolve({ min_col_width = 1, max_col_width = choose(12), max_width_ratio = 1 })
    local output = render.render_table(model, opts)
    local expected = vim.fn.strdisplaywidth(output.lines[1])
    for _, line in ipairs(output.lines) do
      h.assert_eq("generated row width " .. case, vim.fn.strdisplaywidth(line), expected)
    end
  end
end)
