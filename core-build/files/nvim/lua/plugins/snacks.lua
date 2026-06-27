return {
  {
    "folke/snacks.nvim",
    opts = {
      terminal = {
        win = {
          style = "terminal",
          position = "float",
          width = 0.9,
          height = 0.9,
          border = "rounded",
        },
      },
    },
    keys = {
      {
        "<C-/>",
        function() Snacks.terminal() end,
        desc = "Toggle Terminal",
        mode = { "n", "t" },
      },
      {
        -- Same physical Ctrl+/ key: terminals deliver it as the legacy byte
        -- 0x1f (<C-_>) when the modern key protocol isn't negotiated (e.g.
        -- through tmux with extended-keys off). Map it so Ctrl+/ works there too.
        "<C-_>",
        function() Snacks.terminal() end,
        desc = "Toggle Terminal (Ctrl+/ legacy byte)",
        mode = { "n", "t" },
      },
      {
        "<leader>fL",
        function()
          Snacks.notify("Open terminals: " .. #Snacks.terminal.list(), { title = "Terminal" })
        end,
        desc = "List terminals (count)",
        mode = { "n" },
      },
    },
  },
}
