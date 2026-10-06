local config_path = vim.fn.getcwd() .. '/dotfiles/nvim/plugin/96-tools-opencode.lua'
local which_key_path = vim.fn.getcwd() .. '/dotfiles/nvim/plugin/80-ui-which-key.lua'
local added_specs = {}
local render_markdown_opts
local opencode_opts
local which_key_opts

local function assert_eq(expected, actual, message)
  if expected ~= actual then
    error(('%s\nexpected: %s\nactual: %s'):format(message or 'assertion failed', vim.inspect(expected), vim.inspect(actual)), 2)
  end
end

local function assert_truthy(value, message)
  if not value then
    error(message or 'expected value to be truthy', 2)
  end
end

local function assert_falsey(value, message)
  if value then
    error(message or 'expected value to be falsey', 2)
  end
end

package.preload['config.pack'] = function()
  return {
    add = function(specs)
      vim.list_extend(added_specs, specs)
    end,
    repo = function(repo, spec)
      return vim.tbl_extend('force', { src = 'https://github.com/' .. repo }, spec or {})
    end,
    range = function(range)
      return range
    end,
  }
end

package.preload['render-markdown'] = function()
  return {
    setup = function(opts)
      render_markdown_opts = opts
    end,
  }
end

package.preload['which-key'] = function()
  return {
    setup = function(opts)
      which_key_opts = opts
    end,
  }
end

package.preload.opencode = function()
  return {
    setup = function(opts)
      opencode_opts = opts
    end,
  }
end

dofile(config_path)

assert_truthy(opencode_opts, 'opencode setup was not called')
assert_truthy(render_markdown_opts, 'render-markdown setup was not called')

local sources = vim.tbl_map(function(spec)
  return spec.src
end, added_specs)
assert_truthy(vim.tbl_contains(sources, 'https://github.com/sudo-tee/opencode.nvim'), 'opencode.nvim is installed')
assert_truthy(vim.tbl_contains(sources, 'https://github.com/MeanderingProgrammer/render-markdown.nvim'), 'render-markdown.nvim is installed')

assert_eq(false, render_markdown_opts.anti_conceal.enabled, 'anti-conceal stays off for the opencode output')
assert_eq(vim.inspect { 'opencode_output' }, vim.inspect(render_markdown_opts.file_types), 'render-markdown only takes over the opencode output buffer')

assert_eq('fzf', opencode_opts.preferred_picker, 'picker')
assert_eq('blink', opencode_opts.preferred_completion, 'completion')

local server = opencode_opts.server
assert_truthy(server, 'server options were not configured')
assert_eq('http://127.0.0.1', server.url, 'server is only reachable over loopback')
assert_eq('auto', server.port, 'server port is picked per project')
assert_eq(true, server.auto_kill, 'spawned server is stopped with the last nvim instance')

local spawned
vim.system = function(cmd, opts)
  spawned = { cmd = cmd, opts = opts }
  return { pid = 4242 }
end

local pid = server.spawn_command(43210, 'http://127.0.0.1', { OPENCODE_SERVER_PASSWORD = 'secret' })

assert_eq(4242, pid, 'spawn_command returns the pid of the launcher')
assert_eq(
  vim.inspect { 'headroom', 'wrap', 'opencode', '--', 'serve', '--hostname', '127.0.0.1', '--port', '43210' },
  vim.inspect(spawned.cmd),
  'the server is launched through headroom, like the oc alias'
)
assert_eq('secret', spawned.opts.env.OPENCODE_SERVER_PASSWORD, 'server credentials are passed through the environment')
assert_falsey(table.concat(spawned.cmd, ' '):find('secret', 1, true), 'server credentials must not appear on the command line')
assert_eq(true, spawned.opts.detach, 'server is detached so it can outlive the nvim that started it')
assert_eq(false, spawned.opts.stdout, 'server does not keep a stdout pipe to nvim')
assert_eq(false, spawned.opts.stderr, 'server does not keep a stderr pipe to nvim')

local signals = {}
local real_kill = vim.uv.kill
vim.uv.kill = function(target, signal)
  table.insert(signals, { target, signal })
  return 0
end

server.kill_command(43210, 'http://127.0.0.1')
assert_eq(vim.inspect { { -4242, 'sigterm' } }, vim.inspect(signals), 'stopping the server asks the whole headroom process group to exit')

signals = {}
server.kill_command(55555, 'http://127.0.0.1')
assert_eq(0, #signals, 'a port this nvim did not spawn is left alone')

vim.uv.kill = real_kill

dofile(which_key_path)

assert_truthy(which_key_opts, 'which-key setup was not called')

local opencode_group
for _, entry in ipairs(which_key_opts.spec) do
  if entry[1] == '<leader>o' then
    opencode_group = entry
  end
end
assert_truthy(opencode_group, 'which-key has no group for the <leader>o prefix')
assert_eq('[O]pencode', opencode_group.group, 'which-key group for the opencode keymaps')

local prefix_owners = {}
for _, dir in ipairs { 'plugin', 'lua/config' } do
  for _, path in ipairs(vim.fn.glob(vim.fn.getcwd() .. '/dotfiles/nvim/' .. dir .. '/*.lua', false, true)) do
    local name = vim.fn.fnamemodify(path, ':t')
    local is_opencode_config = name == '96-tools-opencode.lua' or name == '80-ui-which-key.lua'
    if not is_opencode_config and table.concat(vim.fn.readfile(path), '\n'):find('<leader>o', 1, true) then
      table.insert(prefix_owners, name)
    end
  end
end
assert_eq(vim.inspect {}, vim.inspect(prefix_owners), 'no other config claims the <leader>o prefix that opencode.nvim uses')
