local pack = require 'config.pack'

pack.add {
  pack.repo('MeanderingProgrammer/render-markdown.nvim', { version = pack.range '*' }),
  pack.repo 'sudo-tee/opencode.nvim',
}

local host = '127.0.0.1'
local launcher_pids = {}

require('render-markdown').setup {
  anti_conceal = { enabled = false },
  file_types = { 'opencode_output' },
}

require('opencode').setup {
  preferred_picker = 'fzf',
  preferred_completion = 'blink',
  server = {
    url = 'http://' .. host,
    port = 'auto',
    auto_kill = true,
    spawn_command = function(port, _, env)
      local process = vim.system({ 'headroom', 'wrap', 'opencode', '--', 'serve', '--hostname', host, '--port', tostring(port) }, {
        env = env,
        detach = true,
        stdout = false,
        stderr = false,
      })

      launcher_pids[port] = process.pid
      return process.pid
    end,
    kill_command = function(port)
      local pid = launcher_pids[port]
      if pid then
        vim.uv.kill(-pid, 'sigterm')
      end
    end,
  },
}

-- The provider plugin can finish discovery after the first catalog fetch.
-- Drop the cached promise so the next picker uses the updated server catalog.
vim.api.nvim_create_autocmd('User', {
  group = vim.api.nvim_create_augroup('opencode-model-catalog', { clear = true }),
  pattern = { 'OpencodeEvent:provider.updated', 'OpencodeEvent:model.updated' },
  callback = function()
    local config_file = package.loaded['opencode.config_file']
    if config_file then
      config_file.providers_promise = nil
    end
  end,
})
