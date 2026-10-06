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
