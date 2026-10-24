-- Loading the normal key groups must not load a coding-agent client/server.
local which_key
package.preload['config.pack'] = function()
  return {
    add = function() end,
    repo = function(repo)
      return repo
    end,
  }
end
package.preload['which-key'] = function()
  return {
    setup = function(opts)
      which_key = opts
    end,
  }
end
assert(vim.fn.filereadable 'dotfiles/nvim/plugin/96-tools-opencode.lua' == 0, 'retired agent server plugin is still installed')
dofile 'dotfiles/nvim/plugin/80-ui-which-key.lua'
assert(which_key, 'normal which-key setup was removed')
for _, entry in ipairs(which_key.spec) do
  assert(entry[1] ~= '<leader>o', 'retired OpenCode prefix remains registered')
end
assert(vim.fn.filereadable 'dotfiles/nvim/lua/config/scrollback.lua' == 1, 'general scrollback support was removed')
assert(package.loaded.opencode == nil, 'Neovim loaded a retired agent client')
