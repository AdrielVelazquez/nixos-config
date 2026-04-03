local session_dir = vim.fn.stdpath 'data' .. '/sessions/'
local has_sessions = false

if vim.fn.isdirectory(session_dir) == 1 then
  has_sessions = next(vim.fn.glob(session_dir .. '*', false, true)) ~= nil
end

require('mini.sessions').setup {
  autoread = has_sessions, -- Only autoread if there is a session to restore
  autowrite = true, -- Automatically write session on certain events
  directory = session_dir, -- Directory for session files
  file = '', -- Path to the last read or written session
  hooks = {
    pre = nil, -- Function to run before writing or reading a session
    post = nil, -- Function to run after writing or reading a session
  },
  verbose = { read = false, write = true }, -- Verbosity settings
}
