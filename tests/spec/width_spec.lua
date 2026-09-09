local h = require("tests.helpers")

h.test("width handles mixed CJK and ASCII display width", function()
  local width = require("markdown-table-wrap.width")

  h.assert_eq("cjk ascii width", width.strwidth("中文ab"), 6)
  h.assert_eq("cell object width", width.strwidth({ text = "日本語" }), 6)
end)

h.test("width padding respects display width", function()
  local width = require("markdown-table-wrap.width")

  h.assert_eq("right padding", vim.api.nvim_strwidth(width.pad("中文", 6, "left")), 6)
  h.assert_eq("left padding", vim.api.nvim_strwidth(width.pad("中文", 6, "right")), 6)
  h.assert_eq("center padding", vim.api.nvim_strwidth(width.pad("中文", 7, "center")), 7)
end)

h.test("width finds the atomic display-width floor for wide glyphs", function()
  local width = require("markdown-table-wrap.width")

  h.assert_eq("CJK requires two cells", width.glyph_width_floor("中"), 2)
  h.assert_eq("emoji requires two cells", width.glyph_width_floor("😀"), 2)
  h.assert_eq("ASCII still needs one cell", width.glyph_width_floor("A"), 1)
end)
