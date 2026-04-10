local pack = require 'config.pack'

pack.add {
  pack.repo('echasnovski/mini.sessions', { version = pack.range '*' }),
}

require 'config.sessions'
