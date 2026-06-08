local PANE_TAG = "claudecode.nvim"
local pane_id = nil
local reclaimed = false

local function is_in_tmux()
  return vim and vim.env and vim.env.TMUX ~= nil
end

local function extract_pane_id(out)
  local id = out:gsub("%s+", ""):match("%%(%d+)")
  return id and ("%" .. id) or nil
end

local function get_pane_state()
  if not pane_id then
    return nil
  end
  local result = vim.fn.system("tmux-ctrl pane state -p " .. pane_id .. " 2>/dev/null")
  if vim.v.shell_error ~= 0 then
    return nil
  end
  local state = result:gsub("%s+", "")
  return state ~= "" and state or nil
end

local function hide_pane()
  if pane_id and get_pane_state() == "visible" then
    vim.fn.system("tmux-ctrl pane hide -p " .. pane_id .. " --tag " .. PANE_TAG)
  end
end

local function show_pane(direction, size)
  local cmd = "tmux-ctrl pane show -d " .. direction .. " --tag " .. PANE_TAG
  if size then
    cmd = cmd .. " --size " .. size
  end
  vim.fn.system(cmd)
end

local function get_current_pane_id()
  local result = vim.fn.system("tmux display-message -p '#{pane_id}'")
  if vim.v.shell_error ~= 0 then
    return nil
  end
  return extract_pane_id(result)
end

local function has_claude_process(target_pane_id)
  local tty = vim.fn.system("tmux display-message -t " .. target_pane_id .. " -p '#{pane_tty}' 2>/dev/null")
  tty = tty:gsub("%s+", "")
  if vim.v.shell_error ~= 0 or tty == "" then
    return false
  end

  local tty_short = tty:gsub("^/dev/", "")
  local ps_result = vim.fn.system("ps -t " .. tty_short .. " -o command= 2>/dev/null")

  for line in ps_result:gmatch("[^\n]+") do
    if line:match("^claude") or line:match("/claude") then
      return true
    end
  end
  return false
end

local function find_existing_claude_pane_id(nvim_pane_id)
  -- Check visible panes in the current window by tmux-ctrl tag
  local visible = vim.fn.system("tmux-ctrl pane list --tag " .. PANE_TAG .. " 2>/dev/null")
  if vim.v.shell_error == 0 then
    for id in visible:gmatch("%%%d+") do
      if id ~= nvim_pane_id and has_claude_process(id) then
        return id
      end
    end
  end

  -- Check the current window's hidden panes by tmux-ctrl tag
  local hidden = vim.fn.system("tmux-ctrl pane list --hidden --tag " .. PANE_TAG .. " 2>/dev/null")
  if vim.v.shell_error == 0 then
    for id in hidden:gmatch("%%%d+") do
      if has_claude_process(id) then
        return id
      end
    end
  end

  -- Fallback: scan visible panes for a running claude process (manual panes)
  local proc_result = vim.fn.system("tmux-ctrl pane list 2>/dev/null")
  if vim.v.shell_error == 0 then
    for id in proc_result:gmatch("%%%d+") do
      if id ~= nvim_pane_id and has_claude_process(id) then
        vim.fn.system("tmux-ctrl pane tag add " .. PANE_TAG .. " -p " .. id)
        return id
      end
    end
  end

  return nil
end

local function reconnect_in_pane()
  vim.fn.system("tmux send-keys -t " .. pane_id .. " '/ide'")
  -- vim.defer_fn(function()
  --   vim.fn.system("tmux send-keys -t " .. pane_id .. " Enter")
  -- end, 100)
  reclaimed = false
end

local mod = {}

function mod.get_split_size(effective_config)
  local size = mod.config.provider_opts.split_size
  if size == nil then
    size = effective_config.split_width_percentage
  end
  if not size or size <= 0 then
    return 80
  end
  return size
end

function mod.get_split_direction(effective_config)
  local dir = mod.config.provider_opts.split_direction
  if dir == nil then
    dir = effective_config.split_side
  end
  return dir or "right"
end

function mod.setup(config)
  mod.config = config
  if mod.config.provider_opts == nil then
    mod.config.provider_opts = {}
  end
  mod.logger = require("claudecode.logger")
  mod.nvim_pane_id = get_current_pane_id()

  local existing_pane_id = find_existing_claude_pane_id(mod.nvim_pane_id)
  if existing_pane_id then
    pane_id = existing_pane_id
    reclaimed = true
    mod.logger.debug("terminal", "Reclaimed existing Claude pane: " .. pane_id)
  end
end

local function is_tracked_pane_id_valid()
  if not pane_id then
    return false
  end
  if not get_pane_state() or not has_claude_process(pane_id) then
    pane_id = nil
    reclaimed = false
    return false
  end
  return true
end

local function validate_and_discover()
  if is_tracked_pane_id_valid() then
    return
  end
  local existing_pane_id = find_existing_claude_pane_id(mod.nvim_pane_id)
  if existing_pane_id then
    pane_id = existing_pane_id
    reclaimed = true
    mod.logger.debug("terminal", "Discovered Claude pane: " .. pane_id)
  end
end

function mod.open(cmd_string, env_table, effective_config, focus)
  validate_and_discover()

  local state = get_pane_state()
  if state then
    if reclaimed then
      reconnect_in_pane()
      mod.logger.debug("terminal", "Reconnected Claude in reclaimed pane: " .. pane_id)
    end
    mod.logger.debug("terminal", "Claude tmux pane already exists, focusing existing pane")
    if focus ~= false then
      if state == "hidden" then
        show_pane(mod.get_split_direction(effective_config), mod.get_split_size(effective_config))
      else
        vim.fn.system("tmux select-pane -t " .. pane_id)
      end
    end
    return
  end

  local direction = mod.get_split_direction(effective_config)
  local split_cmd = "tmux-ctrl pane split -d " .. direction .. " --template '#{pane_id}'"
  split_cmd = split_cmd .. " --size " .. mod.get_split_size(effective_config)
  if env_table then
    for key, value in pairs(env_table) do
      if key ~= "FORCE_CODE_TERMINAL" then
        split_cmd = split_cmd .. " --env " .. vim.fn.shellescape(key .. "=" .. value)
      end
    end
  end
  if focus == false then
    split_cmd = split_cmd .. " --no-focus"
  end
  split_cmd = split_cmd .. " -- " .. cmd_string

  mod.logger.debug("terminal", "Opening tmux pane with command: " .. split_cmd)

  local new_pane_id = extract_pane_id(vim.fn.system(split_cmd))
  if new_pane_id then
    pane_id = new_pane_id
    mod.logger.debug("terminal", "Created tmux pane with ID: " .. pane_id)
    vim.fn.system("tmux-ctrl pane tag add " .. PANE_TAG .. " -p " .. pane_id)
  else
    mod.logger.error("terminal", "Failed to create tmux pane")
  end
end

function mod.close()
  if not pane_id then
    mod.logger.debug("terminal", "No Claude tmux pane found to close")
    return
  end

  vim.fn.system("tmux kill-pane -t " .. pane_id)
  mod.logger.debug("terminal", "Closed tmux pane: " .. pane_id)
  pane_id = nil
  reclaimed = false
end

function mod.simple_toggle(cmd_string, env_table, effective_config)
  validate_and_discover()

  local state = get_pane_state()
  if state then
    if reclaimed then
      reconnect_in_pane()
      mod.logger.debug("terminal", "Reconnected Claude in reclaimed pane: " .. pane_id)
      if state == "hidden" then
        show_pane(mod.get_split_direction(effective_config), mod.get_split_size(effective_config))
      end
      vim.fn.system("tmux select-pane -t " .. pane_id)
      return
    end
    if state == "hidden" then
      show_pane(mod.get_split_direction(effective_config), mod.get_split_size(effective_config))
    else
      hide_pane()
    end
  else
    mod.open(cmd_string, env_table, effective_config, true)
  end
end

function mod.focus_toggle(cmd_string, env_table, effective_config)
  validate_and_discover()

  local state = get_pane_state()
  if state then
    if reclaimed then
      reconnect_in_pane()
      mod.logger.debug("terminal", "Reconnected Claude in reclaimed pane: " .. pane_id)
      if state == "hidden" then
        show_pane(mod.get_split_direction(effective_config), mod.get_split_size(effective_config))
      end
      vim.fn.system("tmux select-pane -t " .. pane_id)
      return
    end
    if state == "hidden" then
      show_pane(mod.get_split_direction(effective_config), mod.get_split_size(effective_config))
    end
  else
    mod.open(cmd_string, env_table, effective_config, false)
    return
  end

  local current_pane_id = get_current_pane_id()

  if current_pane_id == mod.nvim_pane_id then
    vim.fn.system("tmux select-pane -t " .. pane_id)
  else
    vim.fn.system("tmux select-pane -t " .. mod.nvim_pane_id)
  end
end

function mod.get_active_bufnr()
  return nil
end

function mod.is_available()
  return is_in_tmux() and vim.fn.executable("tmux-ctrl") == 1
end

return mod
