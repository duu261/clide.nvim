local follow = require("clide.follow")

describe("follow", function()
  it("does nothing when off", function()
    local calls = 0
    follow.handle("/tmp/a.lua", {
      mode = "off",
      notify_fn = function()
        calls = calls + 1
      end,
      open_fn = function()
        calls = calls + 10
      end,
    })
    assert.equals(0, calls)
  end)

  it("notifies and opens for both", function()
    local seen = {}
    follow.handle("/tmp/a.lua", {
      mode = "both",
      modified = false,
      notify_fn = function(msg)
        table.insert(seen, "n:" .. msg)
      end,
      open_fn = function(path, use_split)
        table.insert(seen, "o:" .. path .. ":" .. tostring(use_split))
      end,
    })
    assert.same({ "n:/tmp/a.lua", "o:/tmp/a.lua:false" }, seen)
  end)

  it("uses split when current buffer is modified", function()
    local seen = {}
    follow.handle("/tmp/a.lua", {
      mode = "jump",
      modified = true,
      open_fn = function(path, use_split)
        table.insert(seen, path .. ":" .. tostring(use_split))
      end,
    })
    assert.same({ "/tmp/a.lua:true" }, seen)
  end)

  it("queues last path with mode snapshot", function()
    local seen = {}
    follow.queue("/tmp/one.lua", {
      mode = "notify",
      notify_fn = function(path)
        table.insert(seen, path)
      end,
    })
    follow.queue("/tmp/two.lua", {
      mode = "notify",
      notify_fn = function(path)
        table.insert(seen, path)
      end,
    })
    vim.wait(50, function()
      return #seen == 1
    end)
    assert.same({ "/tmp/two.lua" }, seen)
  end)

  it("keeps queued follow after config changes", function()
    local seen = {}
    follow.queue("/tmp/two.lua", {
      mode = "notify",
      notify_fn = function(path)
        table.insert(seen, path)
      end,
    })
    package.loaded["clide.config"] = nil
    require("clide.config").setup({ follow = "off" })
    vim.wait(50, function()
      return #seen == 1
    end)
    assert.same({ "/tmp/two.lua" }, seen)
  end)

  it("keeps queued modified snapshot", function()
    local seen = {}
    follow.queue("/tmp/two.lua", {
      mode = "jump",
      modified = true,
      open_fn = function(path, use_split)
        table.insert(seen, path .. ":" .. tostring(use_split))
      end,
    })
    vim.bo.modified = false
    vim.wait(50, function()
      return #seen == 1
    end)
    assert.same({ "/tmp/two.lua:true" }, seen)
  end)
end)
