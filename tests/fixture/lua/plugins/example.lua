return {
  {
    "example-org/example.nvim",
    keys = {
      { "<leader>xe", "<cmd>ExampleOpen<cr>", desc = "Open Example" },
      { "<leader>xv", "<cmd>ExampleVisual<cr>", mode = "v", desc = "Example Visual" },
      { "<leader>xa", "<cmd>ExampleA<cr>", mode = { "n", "v" }, desc = "Mode Table Before Desc" },
      { "<leader>xb", "<cmd>ExampleB<cr>", desc = "Mode Table After Desc", mode = { "n", "x" } },
    },
  },
}
