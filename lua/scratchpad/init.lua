local arg_parser = require("scratchpad.arg_parser")
local utils = require("scratchpad.utils")

local api = vim.api
local fn = vim.fn

---@class Scratchpad
---@field winid integer
---@field buffer integer
---@field config table
---@field state WinState

---@class Node
---@field type "leaf"|"row"|"col"
---@field parent Node
---@field index integer
---@field winid integer|nil
---@field children Node[]

---@class VimOption
---@field allows_duplicates boolean
---@field commalist boolean
---@field default boolean
---@field flaglist boolean
---@field global_local boolean
---@field last_set_chan integer
---@field last_set_linenr integer
---@field last_set_sid integer
---@field name string
---@field shortname string
---@field scope "global"|"win"|"buf"
---@field type string
---@field was_set boolean

local M = {
  ---@type Scratchpad[]
  pads = {},
  cur_pad = 1,
}

-- TODO: Remove
_G.Scratchpad = M

M.default_float_config = {
  relative = "editor",
  row = 0,
  col = 0,
  zindex = 50,
  border = "single",
}

---@type table<string, VimOption>
M.win_option_info = {}

do
  -- Find all window options
  for name, spec in pairs(api.nvim_get_all_options_info()) do
    if spec.scope == "win" then
      M.win_option_info[name] = spec
    end
  end
end

local comp_float = arg_parser.FlagValueMap() --[[@as FlagValueMap ]]
comp_float:put({ "w", "width" }, {})
comp_float:put({ "h", "height" }, {})
comp_float:put({ "c", "col" }, {})
comp_float:put({ "r", "row" }, {})
comp_float:put({ "z", "zindex" }, {})
comp_float:put({ "toggle" })

---@param winid integer
---@param config table
function M.win_update_config(winid, config)
  local save_eventignore = vim.o.eventignore
  ---@diagnostic disable-next-line: undefined-field
  vim.opt.eventignore:append({ "WinLeave", "WinEnter", "WinClosed", "WinScrolled" })
  api.nvim_win_set_config(winid, vim.tbl_extend("force", api.nvim_win_get_config(winid), config))
  vim.opt.eventignore = save_eventignore
end

---@param winid integer
---@return boolean
function M.is_float(winid)
  return api.nvim_win_get_config(winid).relative ~= ""
end

---@class WinInfo
---@field winid integer
---@field x integer
---@field y integer
---@field width integer
---@field height integer
---@field anchor "NW"|"NE"|"SW"|"SE"
---@field external boolean
---@field focusable boolean
---@field floating boolean
---@field relative "editor"|"win"|"cursor"
---@field zindex integer

---@param winid integer
---@return WinInfo?
function M.win_info(winid)
  local c = api.nvim_win_get_config(winid)

  return {
    winid = winid == 0 and api.nvim_get_current_win() or winid,
    x = c.col and c.col[false] --[[@as integer ]],
    y = c.row and c.row[false] --[[@as integer ]],
    width = c.width,
    height = c.height,
    anchor = c.anchor,
    external = c.external,
    focusable = c.focusable,
    floating = c.relative ~= "",
    relative = c.relative,
    zindex = c.zindex,
  }
end

---@class WinState
---@field view table
---@field win_opts table<string, any>

---@param winid integer
---@return WinState
function M.save_win(winid)
  local ret

  api.nvim_win_call(winid, function()
    ret = {
      view = vim.fn.winsaveview(),
      win_opts = {},
    }

    for name, _ in pairs(M.win_option_info) do
      ret.win_opts[name] = api.nvim_get_option_value(name, {
        scope = "local",
        win = winid,
      })
    end
  end)

  return ret
end

---@param winid integer
---@param state WinState
function M.restore_win(winid, state)
  for name, value in pairs(state.win_opts) do
    vim.wo[winid][name] = value
  end

  api.nvim_win_call(winid, function()
    vim.fn.winrestview(state.view)
  end)
end

---@param winid integer
---@param x integer
---@param y integer
function M.float_set_pos(winid, x, y)
  M.win_update_config(winid, { col = x, row = y })
end

---@param winid integer
---@param x integer
---@param y integer
function M.float_mod_pos(winid, x, y)
  local info = M.win_info(winid)

  if info then
    M.float_set_pos(winid, info.x + x, info.y + y)
  end
end

---@return integer[]
local function tab_list_normal_wins(tabid)
  return vim.tbl_filter(function(v)
    return fn.win_gettype(v) == ""
  end, api.nvim_tabpage_list_wins(tabid))
end

local function win_safe_close(winid)
  local wins = tab_list_normal_wins(api.nvim_win_get_tabpage(winid))

  if #wins > 1 then
    api.nvim_win_close(winid, false)
  else
    local listed_bufs = vim.tbl_filter(function(v)
      return vim.bo[v].buflisted
    end, api.nvim_list_bufs())

    api.nvim_win_call(winid, function()
        local alt_bufid = fn.bufnr("#")
        if alt_bufid ~= -1 then
          api.nvim_set_current_buf(alt_bufid)
        else
          if #listed_bufs > (vim.bo[0].buflisted and 1 or 0) then
            vim.cmd("silent! bp")
          else
            vim.cmd("enew")
          end
        end
    end)
  end
end

---@param layout? table[] # A layout structured like the output of |winlayout()|. (default: layout in the current tab page)
---@return Node
function M.get_layout_tree(layout)
  layout = layout or vim.fn.winlayout()

  local function recurse(parent)
    ---@type Node
    local node = { type = parent[1], children = {} }

    if node.type == "leaf" then
      node.winid = parent[2]
    else
      for i, child in ipairs(parent[2]) do
        local child_node = recurse(child)
        child_node.index = i
        child_node.parent = node
        node.children[#node.children + 1] = child_node
      end
    end

    return node
  end

  return recurse(layout)
end

---@param node Node
---@return Node
function M.get_first_leaf(node)
  local cur = node
  while cur.type ~= "leaf" do
    cur = cur.children[1]
  end
  return cur
end

---@param node Node
---@return Node
function M.get_last_leaf(node)
  local cur = node
  while cur.type ~= "leaf" do
    cur = cur.children[#cur.children]
  end
  return cur
end

---@param tree Node
---@param winid integer
---@return Node?
function M.find_leaf(tree, winid)
  ---@param node Node
  ---@return Node?
  local function recurse(node)
    if node.type == "leaf" and node.winid == winid then
      return node
    else
      for _, child in ipairs(node) do
        local target = recurse(child)
        if target then
          return target
        end
      end
    end
  end

  return recurse(tree)
end

function M.indexof_pad(winid)
  for i, pad in ipairs(M.pads) do
    if pad.winid == winid then return i end
  end

  return -1
end

function M.add_pad(winid)
  table.insert(M.pads, math.min(M.cur_pad, #M.pads) + 1, {
    winid = winid,
    buffer = api.nvim_win_get_buf(winid),
    config = api.nvim_win_get_config(winid),
  })
end

function M.remove_pad(winid)
  local i = M.indexof_pad(winid)
  if i > -1 then table.remove(M.pads, i) end
end

---@param pad Scratchpad
function M.show_pad(pad)
  local is_open = utils.vec_indexof(api.nvim_list_wins(), pad.winid) > -1
  local is_open_in_tab = is_open and utils.vec_indexof(api.nvim_tabpage_list_wins(0), pad.winid) > -1
  local buf_valid = api.nvim_buf_is_valid(pad.buffer)

  if is_open then
    if is_open_in_tab then
      api.nvim_set_current_win(pad.winid)
      return
    end
    -- Close the pad open in another tab
    api.nvim_win_close(pad.winid, false)
  end

  local winid = api.nvim_open_win(buf_valid and pad.buffer or 0, true, pad.config)

  if winid > 0 then
    pad.winid = winid
  end

  if pad.state then
    M.restore_win(pad.winid, pad.state)
  end
end

function M.next_pad()
  if #M.pads <= 1 then return 1 end
  return M.cur_pad % #M.pads + 1
end

function M.prev_pad()
  if #M.pads <= 1 then return 1 end
  return (M.cur_pad - 2) % #M.pads + 1
end

M.subcmds = {
  Scratchpad = {
    {
      --- Move a window into / out of the scratchpad.
      name = "move",
      ---@diagnostic disable-next-line: unused-local
      command = function(ctx)
        local winid = api.nvim_get_current_win()

        if not M.is_float(winid) then
          vim.cmd("Float")
          M.cur_pad = M.cur_pad + 1
          local pad_winid = api.nvim_get_current_win()
          M.add_pad(pad_winid)
          win_safe_close(winid)
          api.nvim_win_close(pad_winid, false)
        else
          local i = M.indexof_pad(winid)

          if i > -1 then
            -- Remove the float from the scratchpad
            M.remove_pad(winid)
            vim.notify("Float removed from the scratchpad.", vim.log.levels.INFO, {})
          else
            -- Add the float to the scratchpad and hide it.
            M.add_pad(winid)
            M.cur_pad = M.cur_pad + 1
            api.nvim_win_close(winid, false)
          end
        end
      end,
    },
    {
      name = "show",
      ---@diagnostic disable-next-line: unused-local
      command = function(ctx)
        local winid = api.nvim_get_current_win()
        local i = M.indexof_pad(winid)

        if i > -1 then
          api.nvim_win_close(winid, false)
        elseif #M.pads > 0 then
          M.show_pad(M.pads[M.cur_pad])
        end
      end,
    },
  },
}

for _, subcmds in pairs(M.subcmds) do
  for _, subcmd in ipairs(subcmds) do
    subcmds[subcmd.name] = subcmd.command
  end
end

M.completers = {
  ---@param ctx CmdLineContext
  Float = function(ctx)
    return vim.list_extend(
      fn.getcompletion(ctx.arg_lead, "file", 0),
      comp_float:get_completion(ctx.arg_lead) or comp_float:get_all_names()
    )
  end,
  ---@param ctx CmdLineContext
  Scratchpad = function(ctx)
    if ctx.argidx <= 2 then
      return vim.tbl_filter(function(v)
        return type(v) ~= "number"
      end, vim.tbl_keys(M.subcmds.Scratchpad))
    end
  end,
}

return M
