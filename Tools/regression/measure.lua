-- Times fn and counts the garbage it makes, over 200 runs after warming up (after the
-- collection, so what the collector shrinks has grown back), and checks both
-- against a budget: under budget ms and under 0.01 KB a run. Runs go on in batches of 200
-- until 50 ms have passed: os.clock ticks every millisecond on Windows, which decided a
-- fast call's time over 200 runs alone. Not a test itself (run-all.sh runs only test*.lua).
-- Run from the repo root.
--
--   local Measure = dofile("Tools/regression/measure.lua")(check)
--   Measure("the list redrawn", 2, function() view:Redraw() end)
local RUNS, WARM, MIN_SECONDS = 200, 10, 0.05

return function(check)
    return function(label, budget, fn)
        collectgarbage("collect")
        collectgarbage("stop")
        for _ = 1, WARM do fn() end
        local before, start, runs = collectgarbage("count"), os.clock(), 0
        repeat
            for _ = 1, RUNS do fn() end
            runs = runs + RUNS
        until os.clock() - start >= MIN_SECONDS
        local ms = (os.clock() - start) * 1000 / runs
        local kb = (collectgarbage("count") - before) / runs
        collectgarbage("restart")
        print(("  %s: %.3f ms, %.3f KB"):format(label, ms, kb))
        check(label .. " takes under " .. budget .. " ms", ms < budget)
        check(label .. " makes no garbage", kb < 0.01)
    end
end
