local M = {}

local function terminal_colors()
  local colors, received = {}, 0
  local response = vim.api.nvim_create_autocmd('TermResponse', {
    callback = function(event)
      local sequence = event.data.sequence
      local kind, payload = sequence:match '^\27%](%d+);(.*)'
      local key
      if kind == '4' then
        key = tonumber(payload:match '^(%d+);')
        if not key or key > 15 then
          return
        end
      elseif kind == '10' or kind == '11' then
        key = kind == '10' and 'foreground' or 'background'
      else
        return
      end
      local r, g, b = payload:match 'rgb:(%x+)/(%x+)/(%x+)'
      if not r then
        return
      end
      local function channel(hex)
        return math.floor(tonumber(hex, 16) * 255 / (16 ^ #hex - 1) + 0.5)
      end
      if not colors[key] then
        received = received + 1
      end
      colors[key] = ('#%02x%02x%02x'):format(channel(r), channel(g), channel(b))
    end,
  })
  -- OSC queries work through TUIOS and follow the current host, not TERM_PROGRAM
  -- or an inherited Kitty socket, which can belong to a previous attachment.
  local queries = { '\27]10;?\27\\', '\27]11;?\27\\' }
  for i = 0, 15 do
    queries[#queries + 1] = ('\27]4;%d;?\27\\'):format(i)
  end
  vim.api.nvim_ui_send(table.concat(queries))
  vim.wait(500, function()
    return received == 18
  end, 10)
  vim.api.nvim_del_autocmd(response)
  if received ~= 18 then
    vim.notify('Incomplete terminal palette response; scrollback is using fallback colors for missing entries.', vim.log.levels.WARN)
  end
  return colors
end

function M.open()
  local buffer = vim.api.nvim_get_current_buf()
  local colors = terminal_colors()
  -- Baleia prefers terminal_color_* over its explicit palette. Override only
  -- while constructing this colorizer, then leave the Neovim theme untouched.
  local saved = {}
  for i = 0, 15 do
    saved[i] = vim.g['terminal_color_' .. i]
    vim.g['terminal_color_' .. i] = colors[i]
  end
  local ok, colorizer = pcall(function()
    return require('baleia').setup { async = false }
  end)
  for i = 0, 15 do
    vim.g['terminal_color_' .. i] = saved[i]
  end
  if not ok then
    error(colorizer)
  end
  local namespace = vim.api.nvim_create_namespace 'scrollback-terminal'
  vim.api.nvim_set_hl(namespace, 'Normal', { fg = colors.foreground, bg = colors.background })
  vim.api.nvim_win_set_hl_ns(0, namespace)
  vim.bo.readonly = false
  colorizer.once(buffer)
  -- Like kitty-scrollback.nvim's scrollback_tempfile: rg-backed fzf-lua
  -- pickers need the rendered text on disk, with the same buffer name.
  -- Neovim's private tempdir owns cleanup on exit, not on picker BufLeave.
  local filename = vim.fn.tempname()
  assert(vim.fn.writefile(vim.api.nvim_buf_get_lines(buffer, 0, -1, false), filename) == 0, 'Could not write scrollback snapshot')
  assert(vim.fn.setfperm(filename, 'rw-------') == 1, 'Could not protect scrollback snapshot')
  vim.api.nvim_buf_set_name(buffer, filename)
  vim.bo.buftype = 'nofile'
  vim.bo.swapfile = false
  vim.bo.modified = false
  vim.bo.readonly = true
  vim.bo.modifiable = false
  vim.keymap.set('n', 'q', '<cmd>qa!<CR>', { buffer = buffer, silent = true })
  vim.cmd.stopinsert()
  vim.cmd 'normal! G'
end

return M
