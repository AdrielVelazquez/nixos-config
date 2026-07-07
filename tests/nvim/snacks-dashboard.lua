local config_path = vim.fn.getcwd() .. '/dotfiles/nvim/plugin/31-core-snacks.lua'
local captured_opts

local function assert_eq(expected, actual, message)
  if expected ~= actual then
    error(
      ('%s\nexpected: %s\nactual: %s'):format(message or 'assertion failed', vim.inspect(expected), vim.inspect(actual)),
      2
    )
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
    add = function() end,
    repo = function(repo, spec)
      return vim.tbl_extend('force', { src = 'https://github.com/' .. repo }, spec or {})
    end,
  }
end

_G.Snacks = {
  git = {
    roots = {},
    get_root = function(path)
      return _G.Snacks.git.roots[path]
    end,
  },
}

package.preload.snacks = function()
  return {
    setup = function(opts)
      captured_opts = opts
    end,
  }
end

dofile(config_path)

assert_truthy(captured_opts, 'snacks setup was not called')

local sections = captured_opts.dashboard and captured_opts.dashboard.sections
assert_truthy(sections, 'dashboard sections were not configured')
assert_eq(100, captured_opts.dashboard.width, 'dashboard width')

local repo_recent = sections[2]
local global_recent = sections[3]

assert_eq('Recently Opened in Current Git Directory', repo_recent.title, 'project recent files title')
assert_eq('recent_files', repo_recent.section, 'project recent files section')
assert_eq('function', type(repo_recent.filter), 'project recent files filter')

assert_eq('Recently Opened in General', global_recent.title, 'global recent files title')
assert_eq('recent_files', global_recent.section, 'global recent files section')
assert_eq(nil, global_recent.filter, 'global recent files should be unfiltered')

local cwd = vim.fn.getcwd()
local in_repo = cwd .. '/dotfiles/nvim/init.lua'
local also_in_repo = cwd .. '/dotfiles/nvim/plugin/31-core-snacks.lua'
local outside_repo = '/tmp/other-project/file.lua'

_G.Snacks.git.roots[cwd] = cwd
_G.Snacks.git.roots[in_repo] = cwd
_G.Snacks.git.roots[also_in_repo] = cwd
_G.Snacks.git.roots[outside_repo] = '/tmp/other-project'

assert_truthy(repo_recent.filter(in_repo), 'keeps oldfiles in the current git root')
assert_truthy(repo_recent.filter(also_in_repo), 'keeps all oldfiles in the current git root')
assert_falsey(repo_recent.filter(outside_repo), 'filters oldfiles from other git roots')

_G.Snacks.git.roots[cwd] = nil
assert_falsey(repo_recent.filter(in_repo), 'outside git repos, the project-local section is empty')
