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
        "<C-t>",
        function() Snacks.terminal() end,
        desc = "Toggle Terminal (fallback)",
        mode = { "n", "t" },
      },
      {
        "<leader>tt",
        function() Snacks.terminal() end,
        desc = "Toggle Terminal",
        mode = { "n" },
      },
    },
  },
}
