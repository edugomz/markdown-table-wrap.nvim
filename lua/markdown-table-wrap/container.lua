local M = {}

function M.line(line)
  line = line or ""
  local cursor = 1
  local depth = 0

  while cursor <= #line do
    local marker_start = cursor
    local spaces = 0
    while spaces < 3 and line:sub(cursor, cursor) == " " do
      cursor = cursor + 1
      spaces = spaces + 1
    end
    if line:sub(cursor, cursor) ~= ">" then
      cursor = marker_start
      break
    end
    cursor = cursor + 1
    if line:sub(cursor, cursor):match("[ \t]") then
      cursor = cursor + 1
    end
    depth = depth + 1
  end

  if depth == 0 then
    return {
      kind = "source",
      depth = 0,
      content = line,
      content_start_col = 0,
      source_prefix = "",
      render_prefix = "",
      signature = "source:0",
    }
  end

  return {
    kind = "blockquote",
    depth = depth,
    content = line:sub(cursor),
    content_start_col = cursor - 1,
    source_prefix = line:sub(1, cursor - 1),
    render_prefix = string.rep("> ", depth),
    signature = "blockquote:" .. depth,
  }
end

-- Strip exactly `depth` quote markers, leaving any deeper container marker in
-- the returned content.  Fenced-code tracking uses this instead of stripping
-- every marker: a deeper quote is content of an outer quoted fence, not a
-- change that ends that fence.
function M.strip_quote_prefix(line, depth)
  line = line or ""
  depth = math.max(0, math.floor(tonumber(depth) or 0))
  local cursor = 1

  for _ = 1, depth do
    local spaces = 0
    while spaces < 3 and line:sub(cursor, cursor) == " " do
      cursor = cursor + 1
      spaces = spaces + 1
    end
    if line:sub(cursor, cursor) ~= ">" then
      return nil
    end
    cursor = cursor + 1
    if line:sub(cursor, cursor):match("[ \t]") then
      cursor = cursor + 1
    end
  end

  return line:sub(cursor), cursor - 1
end

function M.same(left, right)
  return left and right and left.signature == right.signature
end

return M
