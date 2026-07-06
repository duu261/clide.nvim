describe("config", function()
  local config

  before_each(function()
    package.loaded["clide.config"] = nil
    config = require("clide.config")
  end)

  it("returns defaults before setup", function()
    assert.equals("auto", config.get().terminal.provider)
    assert.equals(true, config.get().review.inline)
    assert.equals("off", config.get().follow)
  end)

  it("deep-merges user opts over defaults", function()
    config.setup({ follow = "both", terminal = { split_side = "left" } })
    assert.equals("both", config.get().follow)
    assert.equals("left", config.get().terminal.split_side)
    assert.equals("auto", config.get().terminal.provider)
  end)

  it("rejects invalid follow mode", function()
    assert.has_error(function()
      config.setup({ follow = "notifiy" })
    end, "invalid follow mode: notifiy")
  end)
end)
