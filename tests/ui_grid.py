"""Actual grid-cell/Visual checks: uv run --with pynvim python tests/ui_grid.py."""
import argparse
import pathlib
import time

import pynvim

cli = argparse.ArgumentParser()
cli.add_argument("--nvim", default="nvim")
args = cli.parse_args()
root = str(pathlib.Path(__file__).resolve().parent.parent)
n = pynvim.attach("child", argv=[args.nvim, "--embed", "-u", "NONE", "--cmd",
    "set shadafile=NONE noswapfile", "--cmd", "set rtp^=" + root])
grids, attrs = {}, {}


def drain():
    n.command("redraw")
    n.exec_lua("vim.rpcnotify(...,'mtw_grid_done')", n.channel_id)
    while True:
        message = n.next_message()
        if message.type == "notification" and message.name == "mtw_grid_done":
            return
        if message.type != "notification" or message.name != "redraw":
            continue
        for event in message.args:
            for item in event[1:]:
                if event[0] == "grid_resize":
                    grids[item[0]] = [[[' ', 0] for _ in range(item[1])] for _ in range(item[2])]
                elif event[0] == "grid_clear":
                    for row in grids.get(item[0], []):
                        for cell in row:
                            cell[:] = [' ', 0]
                elif event[0] == "hl_attr_define":
                    attrs[item[0]] = item[1]
                elif event[0] == "grid_line":
                    grid, row, column, cells = item[:4]
                    hl = 0
                    for cell in cells:
                        if len(cell) > 1:
                            hl = cell[1]
                        for _ in range(cell[2] if len(cell) > 2 else 1):
                            grids[grid][row][column] = [cell[0], hl]
                            column += 1


def selection(text, keys, expected, scroll=0):
    n.input("<Esc>")
    time.sleep(.02)
    n.exec_lua("""
      local text,scroll=...
      for row,line in ipairs(vim.api.nvim_buf_get_lines(0,0,-1,false)) do
        local col=line:find(text,1,true)
        if col then
          vim.api.nvim_win_set_cursor(0,{row,col-1})
          vim.fn.winrestview({leftcol=scroll})
          return
        end
      end
      error('missing rendered test text')
    """, text, scroll)
    drain()
    before = [[cell[0] for cell in row] for row in grids[1]]
    n.input(keys)
    time.sleep(.03)
    drain()
    # Ignore the status/command area, which intentionally shows Visual mode.
    height = n.current.window.height
    after = [[cell[0] for cell in row] for row in grids[1]]
    assert before[:height] == after[:height], "Visual moved rendered table text"
    selected = "".join(cell[0] for row in grids[1][:height] for cell in row
                       if attrs.get(cell[1], {}).get("background") == 0xff00aa)
    assert selected == expected, (text, keys, selected, expected)


try:
    n.ui_attach(80, 25, rgb=True, ext_linegrid=True)
    n.exec_lua("""
      local p=require('markdown-table-wrap')
      p.setup({auto_preview=false,fit_to_window=false,min_col_width=24,max_col_width=24,reader={wrap=false}})
      vim.bo.ft='markdown'
      vim.api.nvim_buf_set_lines(0,0,-1,false,{'| Wide | ASCII |','| - | - |',
        '| 界界 | beta |','| éZ | after |','| a\tb | tabs |'})
      p.reader_preview();vim.api.nvim_set_hl(0,'Visual',{bg=0xff00aa,fg=0x00ff00})
    """)
    drain()
    selection("界", "v", "界")
    selection("界", "<C-v>", "界")
    selection("beta", "vll", "bet")
    selection("éZ", "v", "é")
    selection("éZ", "<C-v>", "é")
    selection("a b", "vll", "a b")
    selection("tabs", "vll", "tab")
    selection("beta", "vll", "bet", scroll=5)
    print("PASS 8 UI-grid selections: CJK, composing marks, tabs, block/char Visual, horizontal scroll")
finally:
    try:
        n.command("qa!")
    except EOFError:
        pass
