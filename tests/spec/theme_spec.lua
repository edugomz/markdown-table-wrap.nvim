local h = require("tests.helpers")

h.test("theme presets and overrides", function()
  local theme = require("markdown-table-wrap.theme")
  local previous_normal = vim.api.nvim_get_hl(0, { name = "Normal", link = false })
  local previous_title = vim.api.nvim_get_hl(0, { name = "Title", link = false })
  vim.api.nvim_set_hl(0, "Normal", { fg = "#c0caf5", bg = "#1a1b26" })
  vim.api.nvim_set_hl(0, "Title", { fg = "#7aa2f7", bg = "#202030", bold = true })

  theme.apply({ highlight_preset = "default" })
  local default_inline = vim.api.nvim_get_hl(0, { name = "MarkdownTableWrapInline", link = false })
  local default_header = vim.api.nvim_get_hl(0, { name = "MarkdownTableWrapHeader", link = false })
  local default_blank = vim.api.nvim_get_hl(0, { name = "MarkdownTableWrapBlank", link = false })
  h.assert_eq("default inline does not inherit a background", default_inline.bg, nil)
  h.assert_eq("default header does not inherit a background", default_header.bg, nil)
  h.assert_eq("default padding does not inherit a background", default_blank.bg, nil)

  theme.apply({
    highlight_preset = "tokyonight",
    highlights = {
      code = { fg = "#ffffff" },
    },
  })

  local code = vim.api.nvim_get_hl(0, { name = "MarkdownTableWrapCode" })
  h.assert_eq("theme override code fg", code.fg, tonumber("ffffff", 16))

  local presets = {}
  for _, preset in ipairs(theme.presets()) do
    presets[preset] = true
  end
  h.assert_true("tokyonight preset", presets.tokyonight)
  h.assert_true("catppuccin preset", presets.catppuccin)
  h.assert_true("default preset", presets.default)
  h.assert_true("render_markdown preset", presets.render_markdown)
  h.assert_true("auto preset", presets.auto)

  theme.apply({ highlight_preset = "catppuccin" })
  local header = vim.api.nvim_get_hl(0, { name = "MarkdownTableWrapHeader" })
  h.assert_eq("catppuccin header fg", header.fg, tonumber("89b4fa", 16))

  local previous_colors_name = vim.g.colors_name
  vim.g.colors_name = "catppuccin-mocha"
  theme.apply({ highlight_preset = "auto" })
  local auto_code = vim.api.nvim_get_hl(0, { name = "MarkdownTableWrapCode" })
  h.assert_eq("auto detects catppuccin", auto_code.fg, tonumber("a6e3a1", 16))
  vim.g.colors_name = previous_colors_name

  theme.apply({
    highlight_preset = "custom_test",
    themes = {
      custom_test = {
        border = { fg = "#111111" },
        inline = { fg = "#222222" },
        source = { fg = "#333333" },
        header = { fg = "#444444" },
        code = { fg = "#555555" },
        link = { fg = "#666666" },
        bold = { fg = "#777777" },
        italic = { fg = "#888888" },
        strike = { fg = "#999999" },
        mark = { fg = "#aaaaaa" },
        wiki_link = { fg = "#bbbbbb" },
        image = { fg = "#cccccc" },
        blank = { fg = "#dddddd" },
      },
    },
  })
  local mark = vim.api.nvim_get_hl(0, { name = "MarkdownTableWrapMark" })
  h.assert_eq("custom theme table", mark.fg, tonumber("aaaaaa", 16))

  local plugin = require("markdown-table-wrap")
  plugin.setup({
    auto_preview = false,
    highlight_preset = "catppuccin2",
    themes = {
      catppuccin2 = {
        border = { fg = "#123456" },
        inline = { link = "Normal" },
        blank = { link = "Normal" },
      },
    },
  })
  theme.apply(plugin.config)
  local configured_border = vim.api.nvim_get_hl(0, { name = "MarkdownTableWrapBorder" })
  local configured_inline = vim.api.nvim_get_hl(0, { name = "MarkdownTableWrapInline", link = false })
  local configured_blank = vim.api.nvim_get_hl(0, { name = "MarkdownTableWrapBlank", link = false })
  h.assert_eq("setup preserves custom preset name", plugin.config.highlight_preset, "catppuccin2")
  h.assert_eq("setup applies custom preset", configured_border.fg, tonumber("123456", 16))
  h.assert_eq("custom linked inline stays transparent", configured_inline.bg, nil)
  h.assert_eq("custom linked padding stays transparent", configured_blank.bg, nil)

  theme.apply({
    highlight_preset = "default",
    highlights = {
      inline = { fg = "#ffffff", bg = "#101010" },
    },
  })
  local explicit_background = vim.api.nvim_get_hl(0, { name = "MarkdownTableWrapInline", link = false })
  h.assert_eq("explicit inline background remains opt-in", explicit_background.bg, tonumber("101010", 16))

  local theme_dir = vim.fn.tempname()
  vim.fn.mkdir(theme_dir, "p")
  vim.fn.writefile({
    "return {",
    "  border = { fg = '#010101' },",
    "  inline = { fg = '#020202' },",
    "  source = { fg = '#030303' },",
    "  header = { fg = '#040404' },",
    "  code = { fg = '#050505' },",
    "  link = { fg = '#060606' },",
    "  bold = { fg = '#070707' },",
    "  italic = { fg = '#080808' },",
    "  strike = { fg = '#090909' },",
    "  mark = { fg = '#0a0a0a' },",
    "  wiki_link = { fg = '#0b0b0b' },",
    "  image = { fg = '#0c0c0c' },",
    "  blank = { fg = '#0d0d0d' },",
    "}",
  }, theme_dir .. "/file_theme.lua")
  theme.apply({ highlight_preset = "file_theme", theme_dir = theme_dir })
  local image = vim.api.nvim_get_hl(0, { name = "MarkdownTableWrapImage" })
  h.assert_eq("theme loaded from directory", image.fg, tonumber("0c0c0c", 16))

  vim.api.nvim_set_hl(0, "Normal", previous_normal)
  vim.api.nvim_set_hl(0, "Title", previous_title)
end)

h.test("theme ensure skips unchanged highlight application", function()
  local theme = require("markdown-table-wrap.theme")
  local config = { highlight_preset = "default" }
  theme.apply(config)

  local original_set_hl = vim.api.nvim_set_hl
  local calls = 0
  vim.api.nvim_set_hl = function(...)
    calls = calls + 1
    return original_set_hl(...)
  end
  local ok, err = pcall(function()
    h.assert_false("unchanged theme is already applied", theme.ensure(config))
    h.assert_eq("unchanged theme defines no highlights", calls, 0)
    h.assert_true("changed theme is applied", theme.ensure({ highlight_preset = "catppuccin" }))
    h.assert_true("changed theme defines highlights", calls > 0)
  end)
  vim.api.nvim_set_hl = original_set_hl
  theme.apply(config)
  if not ok then
    error(err, 0)
  end
end)

h.test("theme files stay within theme_dir while Unicode preset names remain valid", function()
  local theme = require("markdown-table-wrap.theme")
  local theme_dir = vim.fn.tempname()
  local parent_dir = vim.fn.fnamemodify(theme_dir, ":h")
  local outside_name = "markdown_table_wrap_outside_" .. vim.fn.fnamemodify(theme_dir, ":t")
  local outside_path = parent_dir .. "/" .. outside_name .. ".lua"
  local unicode_name = "\u{30C6}\u{30FC}\u{30DE}"
  local unicode_path = theme_dir .. "/" .. unicode_name .. ".lua"
  vim.fn.mkdir(theme_dir, "p")
  vim.fn.writefile({ "return { border = { fg = '#ff0000' } }" }, outside_path)
  vim.fn.writefile({ "return { border = { fg = '#00ff00' } }" }, unicode_path)

  for _, preset in ipairs({ "../" .. outside_name, "..\\" .. outside_name, outside_path }) do
    theme.apply({ highlight_preset = preset, theme_dir = theme_dir })
    local traversal = vim.api.nvim_get_hl(0, { name = "MarkdownTableWrapBorder", link = false })
    h.assert_false("unsafe preset is not executed: " .. preset, traversal.fg == tonumber("ff0000", 16))
  end

  local candidate = theme_dir .. "/linked.lua"
  vim.fn.writefile({ "return { border = { fg = '#0000ff' } }" }, candidate)
  local original_resolve = vim.fn.resolve
  vim.fn.resolve = function(path)
    if path == candidate then
      return outside_path
    end
    return original_resolve(path)
  end
  local ok, err = pcall(theme.apply, { highlight_preset = "linked", theme_dir = theme_dir })
  vim.fn.resolve = original_resolve
  if not ok then
    error(err, 0)
  end
  local linked = vim.api.nvim_get_hl(0, { name = "MarkdownTableWrapBorder", link = false })
  h.assert_false("resolved path outside theme_dir is not executed", linked.fg == tonumber("0000ff", 16))

  theme.apply({ highlight_preset = unicode_name, theme_dir = theme_dir })
  local unicode = vim.api.nvim_get_hl(0, { name = "MarkdownTableWrapBorder", link = false })
  h.assert_eq("Unicode theme filename is allowed", unicode.fg, tonumber("00ff00", 16))

  vim.fn.delete(unicode_path)
  vim.fn.delete(outside_path)
  vim.fn.delete(theme_dir, "d")
end)
