local pack = require 'config.pack'

pack.add {
  pack.repo('L3MON4D3/LuaSnip', { version = pack.range '2.x' }),
  pack.repo('saghen/blink.cmp', {
    version = pack.range '*',
    data = {
      build = { 'nix', 'run', '.#build-plugin' },
    },
  }),
}

require('blink.cmp').setup {
  keymap = { preset = 'super-tab' },
  completion = {
    menu = {
      draw = {
        treesitter = { 'lsp' },
        columns = {
          { 'label', 'label_description', gap = 1 },
          { 'kind_icon', 'kind' },
        },
      },
    },
    documentation = { auto_show = true, auto_show_delay_ms = 500 },
    accept = {
      auto_brackets = {
        enabled = true,
      },
    },
  },
  appearance = {
    use_nvim_cmp_as_default = false,
    nerd_font_variant = 'mono',
  },
  snippets = {
    expand = function(snippet)
      require('luasnip').lsp_expand(snippet)
    end,
    active = function(filter)
      if filter and filter.direction then
        return require('luasnip').jumpable(filter.direction)
      end

      return require('luasnip').in_snippet()
    end,
    jump = function(direction)
      require('luasnip').jump(direction)
    end,
  },
  sources = {
    default = { 'lsp', 'path', 'snippets', 'buffer' },
  },
  signature = { enabled = true },
}
