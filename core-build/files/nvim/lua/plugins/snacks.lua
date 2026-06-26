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
    -- Dev-mode auto-launch: when started with ADT_DEV=1 (see connect.sh --dev /
    -- connect.ps1 -Dev), open a floating terminal running Copilot on VimEnter so the
    -- operator lands straight in the Copilot CLI inside nvim.
    init = function()
      if vim.env.ADT_DEV ~= "1" then
        return
      end
      vim.api.nvim_create_autocmd("VimEnter", {
        once = true,
        callback = function()
          vim.defer_fn(function()
            if _G.Snacks and Snacks.terminal then
              Snacks.terminal("copilot")
            end
          end, 200)
        end,
      })
    end,
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
