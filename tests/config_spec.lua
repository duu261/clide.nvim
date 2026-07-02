local config = require("clide.config")

describe("config", function()
  it("returns defaults before setup", function()
    assert.equals("auto", config.get().terminal.provider)
    assert.equals(true, config.get().review.inline)
  end)

  it("deep-merges user opts over defaults", function()
    config.setup({ terminal = { split_side = "left" } })
    assert.equals("left", config.get().terminal.split_side)
    assert.equals("auto", config.get().terminal.provider)
  end)
end)
