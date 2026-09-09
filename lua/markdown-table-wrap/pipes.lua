local utf8 = require("markdown-table-wrap.utf8")

local M = {}

local function backtick_run_at(text, index)
  local count = 0
  local cursor = index
  while cursor <= #text do
    local ch, _, end_col = utf8.next(text, cursor)
    if ch ~= "`" then
      break
    end
    count = count + 1
    cursor = end_col + 1
  end
  return count, cursor - 1
end

function M.positions(line)
  local positions = {}
  line = line or ""

  -- Record tick runs before deciding whether one opens code.  A run opens a
  -- code span only when a later run of exactly the same length exists.  This
  -- keeps unmatched backticks literal without repeatedly searching the rest of
  -- a long line for every candidate opener.
  local runs = {}
  local later = {}
  local escaped = false
  local index = 1

  while index <= #line do
    local ch, start_col, end_col = utf8.next(line, index)
    if not ch then
      break
    end
    if ch == "`" then
      local count, run_end = backtick_run_at(line, index)
      table.insert(runs, { start_col = start_col, end_col = run_end, count = count, escaped = escaped })
      later[count] = (later[count] or 0) + 1
      escaped = false
      index = run_end + 1
    elseif escaped then
      escaped = false
      index = end_col + 1
    elseif ch == "\\" then
      escaped = true
      index = end_col + 1
    else
      index = end_col + 1
    end
  end

  local run_index = 1
  local code_ticks = nil
  escaped = false
  index = 1
  while index <= #line do
    local run = runs[run_index]
    if run and run.start_col == index then
      later[run.count] = later[run.count] - 1
      if code_ticks then
        if run.count == code_ticks then
          code_ticks = nil
        end
      elseif not run.escaped and later[run.count] > 0 then
        code_ticks = run.count
      end
      escaped = false
      index = run.end_col + 1
      run_index = run_index + 1
    else
      local ch, start_col, end_col = utf8.next(line, index)
      if escaped then
        escaped = false
      elseif ch == "\\" and not code_ticks then
        escaped = true
      elseif ch == "|" and not code_ticks then
        table.insert(positions, start_col)
      end
      index = end_col + 1
    end
  end

  return positions
end

function M.has(line)
  return #M.positions(line or "") > 0
end

function M.segments(line)
  line = line or ""
  local positions = M.positions(line)
  local segments = {}
  local segment_start = 1
  for _, position in ipairs(positions) do
    table.insert(segments, { start_col = segment_start, end_col = position - 1 })
    segment_start = position + 1
  end
  table.insert(segments, { start_col = segment_start, end_col = #line })

  local first_pipe = positions[1]
  if first_pipe and line:sub(1, first_pipe - 1):match("^%s*$") then
    table.remove(segments, 1)
  end
  local last_pipe = positions[#positions]
  if last_pipe and line:sub(last_pipe + 1):match("^%s*$") and #segments > 1 then
    table.remove(segments)
  end
  return segments
end

local function trim_span(line, left, right)
  while left <= right and line:sub(left, left):match("%s") do
    left = left + 1
  end
  while right >= left and line:sub(right, right):match("%s") do
    right = right - 1
  end
  return left, right
end

function M.cell_spans(line, offset)
  if not M.has(line or "") then
    return {}
  end
  offset = tonumber(offset) or 0
  local spans = {}
  for _, segment in ipairs(M.segments(line)) do
    local left, right = trim_span(line, segment.start_col, segment.end_col)
    if left > right then
      left = segment.start_col
      right = segment.end_col
    end
    table.insert(spans, {
      start_col = offset + math.max(left - 1, 0),
      end_col = offset + math.max(right, left - 1),
    })
  end
  return spans
end

return M
