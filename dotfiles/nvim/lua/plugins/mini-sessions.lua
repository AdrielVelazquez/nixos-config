return {
  'echasnovski/mini.sessions',
  version = '*', -- use latest version
  -- config = function()
  --   require('mini.sessions').setup({
  --     -- Configuration options
  --     autoread = true,                                    -- Automatically read the latest session on startup
  --     autowrite = true,                                   -- Automatically write session on certain events
  --     directory = vim.fn.stdpath('data') .. '/sessions/', -- Directory for session files
  --     file = '',                                          -- Path to the last read or written session
  --     hooks = {
  --       pre = nil,                                        -- Function to run before writing or reading a session
  --       post = nil,                                       -- Function to run after writing or reading a session
  --     },
  --     verbose = { read = false, write = true },           -- Verbosity settings
  --   })
  -- end,
}
