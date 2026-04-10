local pack = require 'config.pack'

local load_lint = function()
  pack.run_once('nvim-lint', function()
    pack.add {
      pack.repo 'mfussenegger/nvim-lint',
    }

    local lint = require 'lint'
    lint.linters_by_ft = {
      markdown = { 'markdownlint' },
    }

    local lint_augroup = vim.api.nvim_create_augroup('lint', { clear = true })
    vim.api.nvim_create_autocmd({ 'BufEnter', 'BufWritePost', 'InsertLeave' }, {
      group = lint_augroup,
      callback = function()
        if vim.opt_local.modifiable:get() then
          lint.try_lint()
        end
      end,
    })

    if vim.opt_local.modifiable:get() then
      lint.try_lint()
    end
  end)
end

vim.api.nvim_create_autocmd({ 'BufReadPre', 'BufNewFile' }, {
  once = true,
  callback = load_lint,
})
