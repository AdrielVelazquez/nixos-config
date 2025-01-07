return {

  'folke/snacks.nvim',
  opts = {
    dashboard = {
      sections = {
        { section = 'header' },
        { icon = ' ', title = 'Keymaps', section = 'keys', indent = 2, padding = 1 },
        { icon = ' ', title = 'Recent Files', section = 'recent_files', indent = 2, padding = 1 },
        { icon = ' ', title = 'Projects', section = 'projects', indent = 2, padding = 1 },
        { section = 'startup' },
      },
      preset = {
        header = [[
	
	  ██████   █████                   █████   █████  ███
         	 ░░██████ ░░███                   ░░███   ░░███  ░░░
	       ░███░███ ░███   ██████   ██████  ░███    ░███  ████  █████████████
	       ░███░░███░███  ███░░███ ███░░███ ░███    ░███ ░░███ ░░███░░███░░███
         	  ░███ ░░██████ ░███████ ░███ ░███ ░░███   ███   ░███  ░███ ░███ ░███
        ░███  ░░█████ ░███░░░  ░███ ░███  ░░░█████░    ░███  ░███ ░███ ░███
	  █████  ░░█████░░██████ ░░██████     ░░███      █████ █████░███ █████
	 ░░░░░    ░░░░░  ░░░░░░   ░░░░░░       ░░░      ░░░░░ ░░░░░ ░░░ ░░░░░
	
   ]],
        -- stylua: ignore
        ---@type snacks.dashboard.Item[]
        keys = {
          { icon = " ", key = "s", desc = "Search Files", action = ":lua Snacks.dashboard.pick('files')" },
          { icon = " ", key = "n", desc = "New File", action = ":ene | startinsert" },
          { icon = " ", key = "g", desc = "Find Text", action = ":lua Snacks.dashboard.pick('live_grep')" },
          { icon = " ", key = "c", desc = "Config", action = ":lua Snacks.dashboard.pick('files', {cwd = vim.fn.stdpath('config')})" },
          { icon = " ", key = "r", desc = "Restore Session", section = "session" },
          { icon = "󰒲 ", key = "l", desc = "Lazy", action = ":Lazy" },
          { icon = " ", key = "q", desc = "Quit", action = ":qa" },
        },
      },
    },
  },
}
