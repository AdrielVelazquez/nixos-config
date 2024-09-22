return {
  "zbirenbaum/copilot.lua",
  lazy = false,
  opts = {
    -- These are disabled in the default configuration.
    suggestion = {
      enabled = true,
      auto_trigger = false,
      auto_refresh = false,
      keymap = {
        accept = "<M-a>",
        accept_line = "<M-l>",
        accept_word = "<M-k>",
        next = "<M-]>",
        prev = "<M-[>",
        dismiss = "<M-c>",
      },
    },
    filetypes = {
      yaml = true,
      ["*"] = false,
    },
    panel = { enabled = false },
  },
}
