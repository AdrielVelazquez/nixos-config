local builtin = require("telescope.builtin")
vim.keymap.set("n", "<leader>fg", builtin.live_grep, { desc = "Live Grep on all files and content" })
vim.keymap.set("n", "<leader>fh", builtin.help_tags, { desc = "fzf on help tags" })
