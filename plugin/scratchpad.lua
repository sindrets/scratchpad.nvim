local lazy = require("scratchpad.lazy")

local arg_parser = lazy.require("scratchpad.arg_parser") ---@module "scratchpad.arg_parser"
local sp = lazy.require("scratchpad") ---@module "scratchpad"
local utils = lazy.require("scratchpad.utils") ---@module "scratchpad.utils"

local api = vim.api
local fn = vim.fn

local function completion(_, cmd_line, cur_pos)
  local ctx = arg_parser.scan(cmd_line, { cur_pos = cur_pos, allow_ex_range = true })
  local cmd = ctx.args[1]

  if cmd and sp.completers[cmd] then
    return arg_parser.process_candidates(sp.completers[cmd](ctx) or {}, ctx)
  end
end

api.nvim_create_user_command("Float", function(ctx)
  local cmdline = arg_parser.scan(ctx.args)
  local argo = arg_parser.parse(cmdline.args) --[[@as ArgObject ]]
  local cur_info = sp.win_info(0) or {}
  local do_toggle = argo:get_flag("toggle") --[[@as boolean ]]

  -- Toggle from float to split
  if do_toggle and cur_info.floating then
    sp.remove_pad(cur_info.winid)
    local layout = sp.get_layout_tree()
    local leaf = sp.get_last_leaf(layout)

    api.nvim_win_call(leaf.winid, function()
      vim.cmd(string.format(
        "rightbelow %s sp",
        (not leaf.parent or leaf.parent.type == "row") and "vertical" or ""
      ))
      api.nvim_win_set_buf(0, api.nvim_win_get_buf(cur_info.winid))
      api.nvim_win_close(cur_info.winid, false)
    end)

    return
  end

  local viewport_width = vim.o.columns
  local viewport_height = vim.o.lines
  local c = vim.deepcopy(sp.default_float_config)

  local cw = tonumber(argo:get_flag({ "w", "width" })) or 100
  local ch = tonumber(argo:get_flag({ "h", "height" })) or 24

  if cw % 1 ~= 0 then cw = cw * viewport_width end
  if ch % 1 ~= 0 then ch = ch * viewport_height end

  c.width = utils.clamp(cw, 1, viewport_width)
  c.height = utils.clamp(ch, 1, viewport_height)

  local cc = tonumber(argo:get_flag({ "c", "col" })) or math.floor(viewport_width * 0.5 - c.width * 0.5)
  local cr = tonumber(argo:get_flag({ "r", "row" })) or math.floor(viewport_height * 0.5 - c.height * 0.5)

  if cc % 1 ~= 0 then cc = math.floor(cc * viewport_width + 0.5) end
  if cr % 1 ~= 0 then cr = math.floor(cr * viewport_height + 0.5) end

  c.col = utils.clamp(cc, 1, viewport_width - c.width)
  c.row = utils.clamp(cr, 1, viewport_height - c.height)

  c.zindex = tonumber(argo:get_flag({ "z", "zindex" })) or c.zindex

  local winid = api.nvim_open_win(0, true, c)

  if do_toggle then
    -- Toggle from split to float. We already created the float: just close the
    -- remaining split.
    api.nvim_win_close(cur_info.winid, false)
  elseif winid > 0 and argo.args[1] then
    api.nvim_win_call(winid, function ()
      vim.cmd("edit " .. fn.fnameescape(argo.args[1]))
    end)
  end
end, {
  nargs = "*",
  complete = completion,
})

api.nvim_create_user_command("FloatMove", function(ctx)
  local cmdline = arg_parser.scan(ctx.args)
  local info = sp.win_info(0)

  if not info or not info.floating then return end

  local arg_x = cmdline.args[1] or "+0"
  local arg_y = cmdline.args[2] or "+0"
  local value_x = tonumber(arg_x) or 0
  local value_y = tonumber(arg_y) or 0
  local new_x, new_y

  if value_x % 1 ~= 0 then
    value_x = math.floor(
      vim.o.columns * value_x
      - (info.relative == "editor" and info.width / 2 or 0)
    )
  end
  if value_y % 1 ~= 0 then
    value_y = math.floor(
      vim.o.lines * value_y
      - (info.relative == "editor" and info.height / 2 or 0)
    )
  end

  if arg_x:match("^[+-]") then
    new_x = info.x + value_x
  else
    new_x = value_x
  end

  if arg_y:match("^[+-]") then
    new_y = info.y + value_y
  else
    new_y = value_y
  end

  sp.float_set_pos(info.winid, new_x, new_y)
end, { nargs = "+", bar = true })

api.nvim_create_user_command("Scratchpad", function(ctx)
  local cmdline = arg_parser.scan(ctx.args)
  local argo = arg_parser.parse(cmdline.args) --[[@as ArgObject ]]
  local subcmd = argo.args[1]

  if subcmd and sp.subcmds.Scratchpad[subcmd] then
    sp.subcmds.Scratchpad[subcmd](cmdline, argo)
  end
end, { nargs = "*", complete = completion })

-- AUTO COMMANDS

sp.augroup = api.nvim_create_augroup("scratchpad.nvim", {})

api.nvim_create_autocmd("WinLeave", {
  group = sp.augroup,
  ---@diagnostic disable-next-line: unused-local
  callback = function(ctx)
    local winid = api.nvim_get_current_win()
    local i = sp.indexof_pad(winid)

    if i > -1 then
      -- Update the pad config
      sp.pads[i] = vim.tbl_extend("force", sp.pads[i], {
        buffer = api.nvim_win_get_buf(winid),
        config = api.nvim_win_get_config(winid),
      })
    end
  end,
})

api.nvim_create_autocmd("WinClosed", {
  group = sp.augroup,
  callback = function(ctx)
    local winid = tonumber(ctx.match)
    local i = sp.indexof_pad(winid)
    if i > -1 then sp.cur_pad = sp.next_pad() end
  end,
})

