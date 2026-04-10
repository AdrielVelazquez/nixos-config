local pack = require 'config.pack'

pack.add {
  pack.repo 'folke/todo-comments.nvim',
}

require('todo-comments').setup { signs = false }
