local M = {}

local loaded = {}
local did_setup = false

local function as_command(command)
  if type(command) == 'table' then
    return command
  end

  return { vim.o.shell, vim.o.shellcmdflag, command }
end

local function build_plugin(ev)
  local data = ev.data.spec.data or {}
  local build = data.build
  if not build then
    return
  end

  local result = vim
    .system(as_command(build), {
      cwd = ev.data.path,
      text = true,
    })
    :wait()

  if result.code == 0 then
    return
  end

  local output = result.stderr
  if output == nil or output == '' then
    output = result.stdout
  end
  if output == nil or output == '' then
    output = 'unknown error'
  end

  vim.schedule(function()
    vim.notify(('Build failed for %s\n%s'):format(ev.data.spec.name, output), vim.log.levels.ERROR, { title = 'vim.pack' })
  end)
end

function M.setup()
  if did_setup then
    return
  end

  did_setup = true

  local group = vim.api.nvim_create_augroup('native-pack-hooks', { clear = true })

  vim.api.nvim_create_autocmd('PackChanged', {
    group = group,
    callback = function(ev)
      if ev.data.kind == 'install' or ev.data.kind == 'update' then
        build_plugin(ev)
      end
    end,
  })
end

function M.add(specs, opts)
  local add_opts = vim.tbl_extend('force', { confirm = false }, opts or {})
  return vim.pack.add(specs, add_opts)
end

function M.repo(repo, spec)
  return vim.tbl_extend('force', {
    src = 'https://github.com/' .. repo,
  }, spec or {})
end

function M.range(range)
  return vim.version.range(range)
end

function M.run_once(key, fn)
  if loaded[key] then
    return
  end

  local ok, result = pcall(fn)
  if not ok then
    error(result)
  end

  loaded[key] = true
  return result
end

function M.proxy_command(name, load, opts)
  vim.api.nvim_create_user_command(name, function(command)
    pcall(vim.api.nvim_del_user_command, name)
    load()

    local packed = {
      cmd = name,
      args = command.fargs,
      bang = command.bang,
    }

    if command.range > 0 then
      packed.range = { command.line1, command.line2 }
    end

    vim.api.nvim_cmd(packed, {})
  end, opts or { nargs = '*' })
end

return M
