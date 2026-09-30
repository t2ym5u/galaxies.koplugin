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
        -- Centres live in DOUBLED coordinates: cell (r,c) sits at
        -- (2r-1, 2c-1), so an odd coordinate is a cell's middle and an even
        -- one falls between cells. The partner of (r,c) about centre (R,C) is
        -- therefore (R-r+1, C-c+1).
        --
        -- This is what fixed the plugin. Restricting centres to cell middles
        -- forces every region to be odd-sized about its centre in both axes,
        -- and an n x n grid usually cannot be tiled that way: measured on the
        -- old generator, every board at n >= 7 fell back to "one galaxy
        -- covering everything", and only 8 of 20 were valid at n = 6.
        local function partner(b, g, r, c)
            local R, C = b.centers[g][1], b.centers[g][2]
            return R - r + 1, C - c + 1
        end

        it("solution_region is rotationally symmetric around every galaxy's center", function()
            for _, n in ipairs({ 6, 7, 8 }) do
                local b = newBoard(n)
                for g = 1, b.num_galaxies do
                    for r = 1, b.n do
                        for c = 1, b.n do
                            if b.solution_region[r][c] == g then
                                local sr, sc = partner(b, g, r, c)
                                assert.is_true(sr >= 1 and sr <= b.n and sc >= 1 and sc <= b.n,
                                    ("n=%d galaxy %d cell [%d][%d]'s rotation partner is out of bounds"):format(n, g, r, c))
                                assert.are.equal(g, b.solution_region[sr][sc],
                                    ("n=%d galaxy %d cell [%d][%d]'s rotation partner is in another galaxy"):format(n, g, r, c))
                            end
                        end
                    end
                end
            end
        end)

        it("every galaxy is a single connected region", function()
            for _, n in ipairs({ 6, 7, 8 }) do
                local b = newBoard(n)
                for g = 1, b.num_galaxies do
                    local cells = {}
                    for r = 1, b.n do
                        for c = 1, b.n do
                            if b.solution_region[r][c] == g then cells[#cells + 1] = { r, c } end
                        end
                    end
                    assert.is_true(#cells > 0)
                    local seen, stack, count = {}, { cells[1] }, 0
                    seen[cells[1][1] * 100 + cells[1][2]] = true
                    while #stack > 0 do
                        local cur = table.remove(stack)
                        count = count + 1
                        for _, d in ipairs({ {1,0}, {-1,0}, {0,1}, {0,-1} }) do
                            local nr, nc = cur[1] + d[1], cur[2] + d[2]
                            local k = nr * 100 + nc
                            if nr >= 1 and nr <= b.n and nc >= 1 and nc <= b.n
                               and b.solution_region[nr][nc] == g and not seen[k] then
                                seen[k] = true
                                stack[#stack + 1] = { nr, nc }
                            end
                        end
                    end
                    assert.are.equal(#cells, count,
                        ("n=%d galaxy %d is split into disconnected pieces"):format(n, g))
                end
            end
        end)

        it("never falls back to one galaxy covering the whole grid", function()
            -- The old generator retried 3000 times and then did exactly that,
            -- every single time at n >= 7. A board with one galaxy is not a
            -- puzzle: the answer is "all of it".
            for _, n in ipairs({ 6, 7, 8 }) do
                for _ = 1, 10 do
                    local b = newBoard(n)
                    assert.is_true(b.num_galaxies > 1,
                        ("n=%d produced a single-galaxy board"):format(n))
                end
            end
        end)

        it("covers every cell", function()
            for _, n in ipairs({ 6, 7, 8 }) do
                local b = newBoard(n)
                for r = 1, b.n do
                    for c = 1, b.n do
                        assert.is_true(b.solution_region[r][c] > 0,
                            ("n=%d cell [%d][%d] belongs to no galaxy"):format(n, r, c))
                    end
                end
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
