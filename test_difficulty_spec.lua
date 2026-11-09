-- Difficulty guarantees for Galaxies (see docs/dev/TESTING.md, "Difficulty
-- specs"). Galaxies has no difficulty levels, only two sizes (6x6, 8x8).
-- What holds at both: every puzzle is unique and solved by the board's
-- human-style solver (Board._logicSolve, tier 1 = mirror/reach, tier 2 =
-- cut cells) without trial; 8x8 is the bigger puzzle on averages; same
-- seed, same puzzle; generation is bounded by counts, never the clock.
local DIR = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"

package.preload["gettext"] = function()
    return setmetatable({}, { __call = function(_, s) return s end })
end
package.path = DIR .. "common/?.lua;" .. DIR .. "?.lua;" .. package.path

describe("Galaxies difficulty", function()
    local Board

    setup(function()
        Board = require("board")
    end)

    describe("generator (1.6.0)", function()
        it("every puzzle: one solution (connected galaxies), no trial and error", function()
            for _, n in ipairs(Board.SIZES) do
                for seed = 1, 30 do
                    math.randomseed(seed)
                    local b = Board:new{ n = n }
                    local solved, _, owner = Board._logicSolve(n, b.centers, 2)
                    assert.is_true(solved, ("n=%d seed=%d needs trial"):format(n, seed))
                    for r = 1, n do
                        for c = 1, n do
                            assert.are.equal(b.solution_region[r][c], owner[(r - 1) * n + c])
                        end
                    end
                    local count, exhausted = Board._countSolutions(n, b.centers, 2, 2e6)
                    assert.is_false(exhausted)
                    assert.are.equal(1, count)
                    b:reveal()
                    b.won = false
                    b:_checkWin()
                    assert.is_true(b.won)
                end
            end
        end)

        it("adds centres when tilings keep failing, and still ends solvable", function()
            local saved = Board.ATTEMPTS
            Board.ATTEMPTS = 1
            local ok, err = pcall(function()
                for seed = 1, 60 do
                    math.randomseed(seed)
                    local b = Board:new{ n = 8 }
                    assert.is_true((Board._logicSolve(8, b.centers, 2)))
                    local count = Board._countSolutions(8, b.centers, 2, 2e6)
                    assert.are.equal(1, count)
                end
            end)
            Board.ATTEMPTS = saved
            assert(ok, err)
        end)

        it("the same seed gives the same puzzle", function()
            for _, n in ipairs(Board.SIZES) do
                math.randomseed(77)
                local a = Board:new{ n = n }:serialize()
                math.randomseed(77)
                local b = Board:new{ n = n }:serialize()
                assert.are.same(a, b)
            end
        end)

        it("stays quick (8x8)", function()
            local t = os.clock()
            for seed = 1, 30 do
                math.randomseed(seed)
                Board:new{ n = 8 }
            end
            assert.is_true(os.clock() - t < 3, "30 puzzles took " .. (os.clock() - t) .. " s")
        end)

        it("8x8 is the bigger puzzle: more galaxies and no fewer tier-2 steps on average", function()
            local SEEDS = 10
            local avg = {}
            for _, n in ipairs(Board.SIZES) do
                local g, t2s = 0, 0
                for seed = 1, SEEDS do
                    math.randomseed(seed * 37)
                    local b = Board:new{ n = n }
                    local _, t2 = Board._logicSolve(n, b.centers, 2)
                    g, t2s = g + b.num_galaxies, t2s + t2
                end
                avg[n] = { g = g / SEEDS, t2 = t2s / SEEDS }
            end
            assert.is_true(avg[6].g < avg[8].g)
            assert.is_true(avg[6].t2 <= avg[8].t2,
                ("t2 avg 6x6 %.1f vs 8x8 %.1f"):format(avg[6].t2, avg[8].t2))
        end)

        -- Generation is bounded by ATTEMPTS and the centre split, never by
        -- time: with a clock that jumps 1000 s at every read, a seed still
        -- gives the same puzzle.
        it("generation never reads the clock", function()
            local oc, ot = os.clock, os.time
            for _, n in ipairs(Board.SIZES) do
                math.randomseed(91)
                local a = Board:new{ n = n }:serialize()
                local t = 0
                os.clock = function() t = t + 1000; return t end
                os.time = function(x) if x then return ot(x) end; t = t + 1000; return t end
                local ok, b = pcall(function() math.randomseed(91); return Board:new{ n = n }:serialize() end)
                os.clock, os.time = oc, ot
                assert.is_true(ok, tostring(b))
                assert.are.same(a, b)
            end
            local src = assert(io.open(DIR .. "board.lua")):read("*a")
            assert.is_nil(src:find("os%.clock"))
            assert.is_nil(src:find("os%.time"))
        end)
    end)
end)
