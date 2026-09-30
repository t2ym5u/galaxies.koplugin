local grid_utils = require("grid_utils")
local UndoStack  = require("undo_stack")

local emptyGrid = grid_utils.emptyGrid
local shuffle   = grid_utils.shuffle

-- ---------------------------------------------------------------------------
-- Constants
-- ---------------------------------------------------------------------------

local SIZES     = { 6, 8 }
local DEFAULT_N = 6

local DIR4 = { {-1,0},{1,0},{0,-1},{0,1} }

local function inBounds(r, c, n)
    return r >= 1 and r <= n and c >= 1 and c <= n
end

-- ---------------------------------------------------------------------------
-- Rotational symmetry helpers
--
-- A galaxy's centre is NOT always the middle of a cell. In this puzzle it can
-- equally sit on the edge between two cells or on the corner between four,
-- which is what lets regions of even width or height exist at all. Centres are
-- therefore held in *doubled* coordinates: cell (r, c) occupies doubled
-- position (2r-1, 2c-1), so odd doubled coordinates land on cell middles and
-- even ones land between cells.
--
-- Restricting centres to cell middles -- what this did before -- forces every
-- region to be odd-sized about its centre in both axes, and an n x n grid
-- usually cannot be tiled that way. Measured on the old generator: at n >= 7,
-- 100% of boards fell back to the degenerate "one galaxy covering everything",
-- which is not a puzzle; at n = 6 only 8 of 20 were valid.
-- ---------------------------------------------------------------------------

local function inBoundsD(R, C, n)
    return R >= 1 and R <= 2 * n - 1 and C >= 1 and C <= 2 * n - 1
end

-- 180-degree rotation of cell (r, c) about the doubled centre (R, C).
local function rotCell(r, c, R, C)
    return R - r + 1, C - c + 1
end

-- The cells the centre itself covers: one for an odd/odd centre, two for an
-- edge centre, four for a corner centre.
local function centreCells(R, C)
    local rs = (R % 2 == 1) and { (R + 1) / 2 } or { R / 2, R / 2 + 1 }
    local cs = (C % 2 == 1) and { (C + 1) / 2 } or { C / 2, C / 2 + 1 }
    local out = {}
    for _, r in ipairs(rs) do
        for _, c in ipairs(cs) do out[#out + 1] = { r, c } end
    end
    return out
end

-- ---------------------------------------------------------------------------
-- Galaxy region generation
--
-- Grows a symmetric tiling that ALWAYS succeeds, so there is no retry loop and
-- no degenerate fallback. Cells are visited in random order; each one is first
-- offered to an adjacent galaxy (taking its rotation partner along, and only
-- if both regions stay connected), and otherwise starts a galaxy of its own --
-- a domino with a free neighbour where possible, a single cell if not. A
-- single cell is always a legal galaxy, which is what guarantees termination.
-- ---------------------------------------------------------------------------

local function generateGalaxies(n)
    local region = emptyGrid(n, n, 0)
    local centers, galaxy_cells = {}, {}

    local function connected(g)
        local cells = galaxy_cells[g]
        if #cells <= 1 then return true end
        local seen, stack, count = {}, { cells[1] }, 0
        seen[cells[1][1] * (n + 1) + cells[1][2]] = true
        while #stack > 0 do
            local cur = table.remove(stack)
            count = count + 1
            for _, d in ipairs({ {1,0}, {-1,0}, {0,1}, {0,-1} }) do
                local nr, nc = cur[1] + d[1], cur[2] + d[2]
                local key = nr * (n + 1) + nc
                if inBounds(nr, nc, n) and region[nr][nc] == g and not seen[key] then
                    seen[key] = true
                    stack[#stack + 1] = { nr, nc }
                end
            end
        end
        return count == #cells
    end

    local function tryAttach(r, c, g)
        local R, C = centers[g][1], centers[g][2]
        local pr, pc = rotCell(r, c, R, C)
        if not inBounds(pr, pc, n) then return false end
        local same = (pr == r and pc == c)
        if not same and region[pr][pc] ~= 0 then return false end

        region[r][c] = g
        galaxy_cells[g][#galaxy_cells[g] + 1] = { r, c }
        if not same then
            region[pr][pc] = g
            galaxy_cells[g][#galaxy_cells[g] + 1] = { pr, pc }
        end
        if connected(g) then return true end

        -- Roll back: the pair would have split the region in two.
        region[r][c] = 0
        table.remove(galaxy_cells[g])
        if not same then
            region[pr][pc] = 0
            table.remove(galaxy_cells[g])
        end
        return false
    end

    local cells = {}
    for r = 1, n do
        for c = 1, n do cells[#cells + 1] = { r, c } end
    end
    shuffle(cells)

    for _, cell in ipairs(cells) do
        local r, c = cell[1], cell[2]
        if region[r][c] == 0 then
            -- Offer it to the galaxies already touching it.
            local neighbours, seen_g = {}, {}
            local dirs = { {1,0}, {-1,0}, {0,1}, {0,-1} }
            shuffle(dirs)
            for _, d in ipairs(dirs) do
                local nr, nc = r + d[1], c + d[2]
                if inBounds(nr, nc, n) then
                    local g = region[nr][nc]
                    if g ~= 0 and not seen_g[g] then
                        seen_g[g] = true
                        neighbours[#neighbours + 1] = g
                    end
                end
            end

            local attached = false
            for _, g in ipairs(neighbours) do
                if tryAttach(r, c, g) then attached = true break end
            end

            if not attached then
                -- A new galaxy. Prefer a domino -- its centre lands on the
                -- shared edge -- so the board does not fill with single cells.
                local partner
                for _, d in ipairs(dirs) do
                    local nr, nc = r + d[1], c + d[2]
                    if inBounds(nr, nc, n) and region[nr][nc] == 0 then
                        partner = { nr, nc }
                        break
                    end
                end
                local g = #centers + 1
                if partner then
                    centers[g] = { r + partner[1] - 1, c + partner[2] - 1 }
                    galaxy_cells[g] = { { r, c }, { partner[1], partner[2] } }
                    region[r][c] = g
                    region[partner[1]][partner[2]] = g
                else
                    centers[g] = { 2 * r - 1, 2 * c - 1 }
                    galaxy_cells[g] = { { r, c } }
                    region[r][c] = g
                end
            end
        end
    end

    return centers, region, galaxy_cells
end

-- ---------------------------------------------------------------------------
-- Win check: each region must be rotationally symmetric around its center
-- ---------------------------------------------------------------------------

local function regionIsSymmetric(user_region, centers, g, n)
    local R, C = centers[g][1], centers[g][2]
    for r = 1, n do
        for c = 1, n do
            if user_region[r][c] == g then
                local sr, sc = rotCell(r, c, R, C)
                if not inBounds(sr, sc, n) then return false end
                if user_region[sr][sc] ~= g then return false end
            end
        end
    end
    -- Every cell the centre sits on must belong to the galaxy: one cell for a
    -- centre in the middle of a cell, two on an edge, four on a corner.
    for _, cc in ipairs(centreCells(R, C)) do
        if not inBounds(cc[1], cc[2], n) then return false end
        if user_region[cc[1]][cc[2]] ~= g then return false end
    end
    return true
end

-- ---------------------------------------------------------------------------
-- GalaxiesBoard
-- ---------------------------------------------------------------------------

local GalaxiesBoard = {}
GalaxiesBoard.__index = GalaxiesBoard

function GalaxiesBoard:new(opts)
    opts = opts or {}
    local obj = setmetatable({
        n               = opts.n or DEFAULT_N,
        centers         = nil,
        solution_region = nil,
        galaxy_cells    = nil,
        num_galaxies    = 0,
        user_region     = nil,
        won             = false,
        undo            = UndoStack:new{ max_size = 500 },
    }, self)
    obj:generate()
    return obj
end

function GalaxiesBoard:generate()
    -- No retry loop and no fallback: the tiling above always succeeds, because
    -- a single cell is always a legal galaxy. The old code retried 3000 times
    -- and then dropped to one galaxy covering the whole grid -- which at n >= 7
    -- is what it did every single time.
    local centers, region, gcells = generateGalaxies(self.n)

    self.centers         = centers
    self.num_galaxies    = #centers
    self.solution_region = region
    self.galaxy_cells    = gcells
    self.user_region     = emptyGrid(self.n, self.n, 0)
    self.won             = false
    self.undo:clear()
end

-- Tap a cell: cycles its assigned galaxy 0 → 1 → 2 → ... → num_galaxies → 0
-- (0 = unassigned)
function GalaxiesBoard:tapCell(r, c)
    if self.won then return false end
    local cur  = self.user_region[r][c]
    local next = (cur % self.num_galaxies) + 1
    -- If next wraps and we've gone through all: go back to 0
    if next == cur then next = 0 end
    local old = cur
    self.undo:push{ r = r, c = c, old = old }
    self.user_region[r][c] = next
    self:_checkWin()
    return true
end

-- Forward-only cycle: 0 → 1 → 2 → ... → num_g → 0
function GalaxiesBoard:cycleCell(r, c)
    if self.won then return false end
    local cur = self.user_region[r][c]
    local old = cur
    local next
    if cur >= self.num_galaxies then
        next = 0
    else
        next = cur + 1
    end
    self.undo:push{ r = r, c = c, old = old }
    self.user_region[r][c] = next
    self:_checkWin()
    return true
end

function GalaxiesBoard:undoMove()
    local entry = self.undo:pop()
    if not entry then return false end
    self.user_region[entry.r][entry.c] = entry.old
    self.won = false
    return true
end

function GalaxiesBoard:_checkWin()
    local n = self.n
    -- All cells must be assigned
    for r = 1, n do
        for c = 1, n do
            if self.user_region[r][c] == 0 then
                self.won = false
                return
            end
        end
    end
    -- Each galaxy must be rotationally symmetric
    for g = 1, self.num_galaxies do
        if not regionIsSymmetric(self.user_region, self.centers, g, n) then
            self.won = false
            return
        end
    end
    self.won = true
end

function GalaxiesBoard:countUnassigned()
    local n, count = self.n, 0
    for r = 1, n do
        for c = 1, n do
            if self.user_region[r][c] == 0 then count = count + 1 end
        end
    end
    return count
end

function GalaxiesBoard:reveal()
    local n = self.n
    for r = 1, n do
        for c = 1, n do
            self.user_region[r][c] = self.solution_region[r][c]
        end
    end
    self.won = true
end

function GalaxiesBoard:clearUser()
    local n = self.n
    for r = 1, n do
        for c = 1, n do
            self.user_region[r][c] = 0
        end
    end
    self.won = false
    self.undo:clear()
end

-- ---------------------------------------------------------------------------
-- Serialization
-- ---------------------------------------------------------------------------

function GalaxiesBoard:serialize()
    local n = self.n
    local sol_flat, usr_flat = {}, {}
    for r = 1, n do
        for c = 1, n do
            sol_flat[#sol_flat + 1] = self.solution_region[r][c]
            usr_flat[#usr_flat + 1] = self.user_region[r][c]
        end
    end
    return {
        n            = n,
        num_galaxies = self.num_galaxies,
        -- Marks the coordinate space of `centers`. Saves written before
        -- centres moved to doubled coordinates carry no marker and are
        -- rejected on load: their centres would be drawn in the wrong place
        -- and the win check would never pass.
        center_space = "doubled",
        centers      = self.centers,
        solution     = sol_flat,
        user         = usr_flat,
        won          = self.won,
    }
end

function GalaxiesBoard:load(data)
    if type(data) ~= "table" or not data.centers then return false end
    if data.center_space ~= "doubled" then return false end
    local n = data.n or DEFAULT_N
    self.n           = n
    self.num_galaxies = data.num_galaxies or #data.centers
    self.centers     = data.centers
    self.solution_region = emptyGrid(n, n, 0)
    self.user_region     = emptyGrid(n, n, 0)
    if data.solution then
        local idx = 1
        for r = 1, n do
            for c = 1, n do
                self.solution_region[r][c] = data.solution[idx] or 0
                self.user_region[r][c]     = data.user and data.user[idx] or 0
                idx = idx + 1
            end
        end
    end
    -- Rebuild galaxy_cells from solution_region
    self.galaxy_cells = {}
    for g = 1, self.num_galaxies do self.galaxy_cells[g] = {} end
    for r = 1, n do
        for c = 1, n do
            local g = self.solution_region[r][c]
            if g >= 1 and g <= self.num_galaxies then
                self.galaxy_cells[g][#self.galaxy_cells[g] + 1] = {r, c}
            end
        end
    end
    self.won = data.won or false
    self.undo:clear()
    return true
end

GalaxiesBoard.SIZES     = SIZES
GalaxiesBoard.DEFAULT_N = DEFAULT_N

return GalaxiesBoard
