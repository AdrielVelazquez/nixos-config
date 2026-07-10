local config_path = vim.fn.getcwd() .. '/dotfiles/nvim/plugin/40-core-conform.lua'
local captured_opts

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

package.preload['config.pack'] = function()
  return {
    add = function() end,
    repo = function(repo, spec)
      return vim.tbl_extend('force', { src = 'https://github.com/' .. repo }, spec or {})
    end,
  }
end

package.preload.conform = function()
  return {
    setup = function(opts)
      captured_opts = opts
    end,
    format = function() end,
  }
end

dofile(config_path)

assert_truthy(captured_opts, 'conform setup was not called')

local json_formatters = captured_opts.formatters_by_ft and captured_opts.formatters_by_ft.json
assert_truthy(json_formatters, 'json formatter was not configured')
assert_eq('jq', json_formatters[1], 'json formatter')
