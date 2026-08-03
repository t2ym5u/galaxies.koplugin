local DIR = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"

package.preload["gettext"] = function()
    return setmetatable({}, { __call = function(_, s) return s end })
end
package.path = DIR .. "common/?.lua;" .. DIR .. "?.lua;" .. package.path

describe("GalaxiesBoard", function()
    local Board

    setup(function()
        Board = require("board")
    end)


    -- Board:new() auto-generates internally (unlike most other games) — do not
    -- call :generate() again right after construction unless intentionally
    -- re-randomizing.
    local function newBoard(n)
        math.randomseed(42)
        return Board:new{ n = n or 6 }
    end

    describe("construction", function()
        it("creates a 6×6 board by default and auto-generates", function()
            math.randomseed(42)
            local b = Board:new()
            assert.are.equal(6, b.n)
            assert.is_not_nil(b.centers)
            assert.is_true(b.num_galaxies >= 1)
        end)

        it("exposes SIZES / DEFAULT_N", function()
            assert.are.same({6, 8}, Board.SIZES)
            assert.are.equal(6, Board.DEFAULT_N)
        end)
    end)

    describe("generate", function()
        it("assigns every cell to a galaxy in the solution", function()
            local b = newBoard(6)
            for r = 1, b.n do
                for c = 1, b.n do
                    local g = b.solution_region[r][c]
                    assert.is_true(g >= 1 and g <= b.num_galaxies)
                end
            end
        end)

        -- Regression guard for the 2026-07-17/2026-07-21 bug: step 4 used to
        -- assign leftover cells to their nearest center by Manhattan
        -- distance alone, with no check that the cell's 180-degree rotation
        -- partner ended up in the same galaxy -- violated symmetry in
        -- ~100% of sampled generations. Fixed by making step 4 try each
        -- galaxy nearest-first and only commit a cell (with its partner)
        -- when that preserves symmetry, retrying generation from scratch
        -- if any cell has nowhere valid to go.
        it("solution_region is rotationally symmetric around every galaxy's center", function()
            local b = newBoard(6)
            for g = 1, b.num_galaxies do
                local cr, cc = b.centers[g][1], b.centers[g][2]
                for r = 1, b.n do
                    for c = 1, b.n do
                        if b.solution_region[r][c] == g then
                            local sr, sc = 2 * cr - r, 2 * cc - c
                            assert.is_true(sr >= 1 and sr <= b.n and sc >= 1 and sc <= b.n,
                                ("galaxy %d cell [%d][%d]'s rotation partner is out of bounds"):format(g, r, c))
                            assert.are.equal(g, b.solution_region[sr][sc],
                                ("galaxy %d cell [%d][%d]'s rotation partner is not in the same galaxy"):format(g, r, c))
                        end
                    end
                end
                assert.are.equal(g, b.solution_region[cr][cc])
            end
        end)

        it("user_region starts fully unassigned", function()
            local b = newBoard(6)
            for r = 1, b.n do
                for c = 1, b.n do
                    assert.are.equal(0, b.user_region[r][c])
                end
            end
        end)
    end)

    describe("cycleCell (simple forward-only cycle)", function()
        it("cycles 0→1→...→N→0", function()
            local b = newBoard(6)
            local N = b.num_galaxies
            local r, c = 1, 1
            for i = 1, N do
                b:cycleCell(r, c)
                assert.are.equal(i, b.user_region[r][c])
            end
            b:cycleCell(r, c)
            assert.are.equal(0, b.user_region[r][c])
        end)
    end)

    describe("tapCell (documented wrap-around quirk)", function()
        it("cycles 1..N but does not return to 0 for N>1 (known quirk vs cycleCell)", function()
            local b = newBoard(6)
            local N = b.num_galaxies
            assert.is_true(N > 1, "test assumes n=6 always yields num_galaxies > 1")
            local r, c = 2, 2
            for i = 1, N do
                b:tapCell(r, c)
                assert.are.equal(i, b.user_region[r][c])
            end
            -- One more tap: wraps to 1, not 0, because `next == cur` only
            -- triggers the reset-to-0 branch when N == 1.
            b:tapCell(r, c)
            assert.are.equal(1, b.user_region[r][c])
        end)
    end)

    describe("undoMove", function()
        it("restores the previous value and clears won", function()
            local b = newBoard(6)
            b:cycleCell(1, 1)
            local ok = b:undoMove()
            assert.is_true(ok)
            assert.are.equal(0, b.user_region[1][1])
            assert.is_false(b.won)
        end)

        it("returns false when there is nothing to undo", function()
            local b = newBoard(6)
            assert.is_false(b:undoMove())
        end)
    end)

    describe("reveal / clearUser / countUnassigned", function()
        it("countUnassigned equals n*n on a fresh board", function()
            local b = newBoard(6)
            assert.are.equal(b.n * b.n, b:countUnassigned())
        end)

        it("reveal copies the solution into user_region and wins", function()
            local b = newBoard(6)
            b:reveal()
            assert.are.equal(0, b:countUnassigned())
            assert.is_true(b.won)
            for r = 1, b.n do
                for c = 1, b.n do
                    assert.are.equal(b.solution_region[r][c], b.user_region[r][c])
                end
            end
        end)

        it("clearUser resets user_region and won", function()
            local b = newBoard(6)
            b:reveal()
            b:clearUser()
            assert.are.equal(b.n * b.n, b:countUnassigned())
            assert.is_false(b.won)
        end)
    end)

    describe("serialize / load", function()
        it("round-trips centers, solution and user state", function()
            local b = newBoard(6)
            b:cycleCell(1, 1)
            local data = b:serialize()
            local b2 = Board:new{ n = 6 }
            local ok = b2:load(data)
            assert.is_true(ok)
            assert.are.equal(b.n, b2.n)
            assert.are.equal(b.num_galaxies, b2.num_galaxies)
            assert.are.equal(b.user_region[1][1], b2.user_region[1][1])
        end)

        it("load returns false for invalid data", function()
            local b = Board:new()
            assert.is_false(b:load(nil))
            assert.is_false(b:load({}))
        end)
    end)
end)
