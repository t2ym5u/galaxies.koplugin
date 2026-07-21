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
-- ---------------------------------------------------------------------------

-- The 180-degree rotation of (r, c) around center (cr, cc) in an n×n grid.
-- Center (cr, cc) is the galaxy center cell (1-indexed).
local function rotCell(r, c, cr, cc)
    return 2 * cr - r, 2 * cc - c
end

-- ---------------------------------------------------------------------------
-- Galaxy region generation
--
-- Algorithm:
--   1. Pick K galaxy centers at distinct cells.
--   2. Flood-fill each galaxy symmetrically: whenever a cell is added to
--      galaxy G, its 180-rotation around G's center is also added.
--   3. Cells not yet assigned are distributed to the nearest galaxy.
-- ---------------------------------------------------------------------------

local function generateGalaxies(n, num_galaxies)
    -- Step 1: pick centers
    local all_cells = {}
    for r = 1, n do
        for c = 1, n do all_cells[#all_cells + 1] = {r, c} end
    end
    shuffle(all_cells)

    local centers = {}
    for i = 1, math.min(num_galaxies, #all_cells) do
        centers[i] = all_cells[i]
    end
    if #centers == 0 then return nil end

    local num_g    = #centers
    local region   = emptyGrid(n, n, 0)  -- cell → galaxy index (0 = unassigned)

    -- Step 2: seed each galaxy with its center (and symmetric center = itself)
    local galaxy_cells = {}
    for g = 1, num_g do
        galaxy_cells[g] = {}
        local cr, cc = centers[g][1], centers[g][2]
        region[cr][cc] = g
        galaxy_cells[g][#galaxy_cells[g] + 1] = {cr, cc}
    end

    -- Step 3: grow each galaxy using symmetric BFS
    local max_iters = n * n * 4
    local changed = true
    local iter = 0
    while changed and iter < max_iters do
        changed = false
        iter = iter + 1
        -- Shuffle galaxy order for fairness
        local gorder = {}
        for g = 1, num_g do gorder[g] = g end
        shuffle(gorder)

        for _, g in ipairs(gorder) do
            local cr, cc = centers[g][1], centers[g][2]
            -- Try to expand: pick a random cell in this galaxy and look for
            -- an unassigned orthogonal neighbor whose symmetric cell is also
            -- unassigned (or in the same galaxy or is the center itself).
            local gcells = galaxy_cells[g]
            local order  = {}
            for i = 1, #gcells do order[i] = i end
            shuffle(order)

            for _, ci in ipairs(order) do
                local r, c = gcells[ci][1], gcells[ci][2]
                local dirs = {{-1,0},{1,0},{0,-1},{0,1}}
                shuffle(dirs)
                for _, d in ipairs(dirs) do
                    local nr, nc = r + d[1], c + d[2]
                    if inBounds(nr, nc, n) and region[nr][nc] == 0 then
                        -- Check symmetric cell
                        local sr, sc = rotCell(nr, nc, cr, cc)
                        if inBounds(sr, sc, n) and (region[sr][sc] == 0 or region[sr][sc] == g) then
                            -- Assign both
                            region[nr][nc] = g
                            gcells[#gcells + 1] = {nr, nc}
                            if sr ~= nr or sc ~= nc then
                                if region[sr][sc] == 0 then
                                    region[sr][sc] = g
                                    gcells[#gcells + 1] = {sr, sc}
                                end
                            end
                            changed = true
                            break
                        end
                    end
                end
                if changed then break end
            end
        end
    end

    -- Step 4: assign remaining unassigned cells, preserving rotational
    -- symmetry. For each remaining cell, try galaxies nearest-first; commit
    -- the cell (and its rotation partner under that galaxy's center, if the
    -- partner is also still unassigned) to the first galaxy where that
    -- doesn't conflict with a cell already locked into a different galaxy.
    -- If no galaxy works for some cell, this whole attempt fails and the
    -- caller's retry loop tries a fresh random center placement -- unlike
    -- nearest-galaxy-regardless-of-symmetry (the old behavior), which
    -- silently produced a region that violated the puzzle's own win
    -- condition on almost every generation.
    local remaining = {}
    for r = 1, n do
        for c = 1, n do
            if region[r][c] == 0 then
                remaining[#remaining + 1] = {r, c}
            end
        end
    end
    shuffle(remaining)
    for _, cell in ipairs(remaining) do
        local r, c = cell[1], cell[2]
        if region[r][c] == 0 then  -- may already be claimed as an earlier cell's partner
            local order = {}
            for g = 1, num_g do order[g] = g end
            table.sort(order, function(a, b)
                local da = math.abs(r - centers[a][1]) + math.abs(c - centers[a][2])
                local db = math.abs(r - centers[b][1]) + math.abs(c - centers[b][2])
                return da < db
            end)
            local placed = false
            for _, g in ipairs(order) do
                local cr, cc = centers[g][1], centers[g][2]
                local sr, sc = rotCell(r, c, cr, cc)
                if inBounds(sr, sc, n) and (region[sr][sc] == 0 or region[sr][sc] == g) then
                    region[r][c] = g
                    galaxy_cells[g][#galaxy_cells[g] + 1] = { r, c }
                    if (sr ~= r or sc ~= c) and region[sr][sc] == 0 then
                        region[sr][sc] = g
                        galaxy_cells[g][#galaxy_cells[g] + 1] = { sr, sc }
                    end
                    placed = true
                    break
                end
            end
            if not placed then return nil end
        end
    end

    return centers, region, galaxy_cells
end

-- ---------------------------------------------------------------------------
-- Win check: each region must be rotationally symmetric around its center
-- ---------------------------------------------------------------------------

local function regionIsSymmetric(user_region, centers, g, n)
    local cr, cc = centers[g][1], centers[g][2]
    -- Collect all cells assigned to g by the user
    local cells_g = {}
    for r = 1, n do
        for c = 1, n do
            if user_region[r][c] == g then
                cells_g[#cells_g + 1] = {r, c}
            end
        end
    end
    -- For each cell, its rotation must also be in g
    for _, cell in ipairs(cells_g) do
        local sr, sc = rotCell(cell[1], cell[2], cr, cc)
        if not inBounds(sr, sc, n) then return false end
        if user_region[sr][sc] ~= g then return false end
    end
    -- The center must be assigned to g
    if user_region[cr][cc] ~= g then return false end
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
    local n            = self.n
    -- Number of galaxies scales with grid size
    local num_galaxies = math.max(3, math.floor(n * n / 6))

    local centers, region, gcells
    for _ = 1, 3000 do
        centers, region, gcells = generateGalaxies(n, num_galaxies)
        if centers then break end
    end

    if not centers then
        -- Fallback: single galaxy covering the whole grid
        centers = {{math.ceil(n / 2), math.ceil(n / 2)}}
        region  = emptyGrid(n, n, 1)
        gcells  = {}
        gcells[1] = {}
        for r = 1, n do
            for c = 1, n do gcells[1][#gcells[1] + 1] = {r, c} end
        end
    end

    self.centers         = centers
    self.num_galaxies    = #centers
    self.solution_region = region
    self.galaxy_cells    = gcells
    self.user_region     = emptyGrid(n, n, 0)
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
        centers      = self.centers,
        solution     = sol_flat,
        user         = usr_flat,
        won          = self.won,
    }
end

function GalaxiesBoard:load(data)
    if type(data) ~= "table" or not data.centers then return false end
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
