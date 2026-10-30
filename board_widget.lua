local Blitbuffer = require("ffi/blitbuffer")
local Font       = require("ui/font")
local Geom       = require("ui/geometry")
local RenderText = require("ui/rendertext")

local gwb            = require("grid_widget_base")
local GridWidgetBase = gwb.GridWidgetBase
local drawLine       = gwb.drawLine

-- ---------------------------------------------------------------------------
-- Colors: one shade per galaxy (cycles through a set)
-- ---------------------------------------------------------------------------

local GALAXY_COLORS = {
    Blitbuffer.COLOR_WHITE,
    Blitbuffer.COLOR_GRAY_E,
    Blitbuffer.COLOR_GRAY_D,
    Blitbuffer.COLOR_LIGHT_GRAY,
    Blitbuffer.COLOR_GRAY_B,
    Blitbuffer.COLOR_GRAY_9,
}
local NUM_GALAXY_COLORS = #GALAXY_COLORS

local C_BG      = Blitbuffer.COLOR_WHITE
local C_LINE    = Blitbuffer.COLOR_BLACK
local C_GRID    = Blitbuffer.COLOR_GRAY_9
local C_CENTER  = Blitbuffer.COLOR_BLACK   -- ring of the galaxy center dot
local C_DOT_BG  = Blitbuffer.COLOR_WHITE   -- dot fill, readable on any shade
local C_LABEL   = Blitbuffer.COLOR_BLACK   -- galaxy number inside dot

-- ---------------------------------------------------------------------------
-- GalaxiesBoardWidget
-- ---------------------------------------------------------------------------

local GalaxiesBoardWidget = GridWidgetBase:extend{
    board = nil,
}

function GalaxiesBoardWidget:init()
    local n   = self.board and self.board.n or 6
    self.cols = n
    self.rows = n
    GridWidgetBase.init(self)

    -- Centre dots carry the galaxy number: tapping a cell cycles it through
    -- galaxies 1..num_galaxies, and shades repeat every NUM_GALAXY_COLORS,
    -- so the number is what tells the player which galaxy is next. Size the
    -- font so the widest label fits inside the dot.
    local cell  = self.dimen.w / n
    self.dot_r  = math.max(3, math.floor(cell * 0.22))
    local sample = tostring(self.board and self.board.num_galaxies or 9):gsub("%d", "8")
    local lo, hi, best = 4, math.max(4, self.dot_r * 2), nil
    while lo <= hi do
        local mid  = math.floor((lo + hi) / 2)
        local face = Font:getFace("cfont", mid)
        local m    = RenderText:sizeUtf8Text(0, self.dot_r * 4, face, sample, true, false)
        if m.x <= self.dot_r * 1.25 and (m.y_top + m.y_bottom) <= self.dot_r then
            best, lo = mid, mid + 1
        else
            hi = mid - 1
        end
    end
    self.label_face = best and Font:getFace("cfont", best)
end

function GalaxiesBoardWidget:onCellTap(row, col)
    if self.onCellTap_cb then self.onCellTap_cb(row, col) end
end

-- ---------------------------------------------------------------------------
-- paintTo
-- ---------------------------------------------------------------------------

function GalaxiesBoardWidget:paintTo(bb, x, y)
    if not self.board then return end
    self.paint_rect = Geom:new{ x = x, y = y, w = self.dimen.w, h = self.dimen.h }

    local board = self.board
    local n     = board.n
    local cell  = self.dimen.w / n

    -- Background
    bb:paintRect(x, y, self.dimen.w, self.dimen.h, C_BG)

    -- Cell backgrounds by user-assigned galaxy
    for r = 1, n do
        for c = 1, n do
            local g = board.user_region[r][c]
            if g and g > 0 then
                local ci = ((g - 1) % NUM_GALAXY_COLORS) + 1
                local bg = GALAXY_COLORS[ci]
                if bg ~= C_BG then
                    local cx = x + math.floor((c - 1) * cell)
                    local cy = y + math.floor((r - 1) * cell)
                    bb:paintRect(cx, cy, math.ceil(cell), math.ceil(cell), bg)
                end
            end
        end
    end

    -- Grid lines
    local thin  = 1
    local thick = math.max(2, math.floor(cell * 0.08))
    for i = 0, n do
        local lw = (i == 0 or i == n) and thick or thin
        -- The closing line sits inside the board so it doesn't spill past
        -- the widget's bounds.
        local p  = math.floor(i * cell) - ((i == n) and lw or 0)
        drawLine(bb, x + p, y, lw, self.dimen.h, C_LINE)
        drawLine(bb, x, y + p, self.dimen.w, lw, C_LINE)
    end

    -- Galaxy center dots: white disc with a black ring, so they read on
    -- both unshaded and shaded cells, with the galaxy number centred inside.
    local dot_r = self.dot_r
    local ring  = math.max(1, math.floor(dot_r / 6))
    local face  = self.label_face
    for g = 1, board.num_galaxies do
        local center = board.centers[g]
        if center then
            -- Centres are in doubled coordinates: cell (r,c) is at (2r-1,
            -- 2c-1), so an odd value lands on a cell's middle and an even one
            -- between cells. Pixel position is therefore half a cell per unit.
            local R, C = center[1], center[2]
            local cx = x + math.floor(C * cell / 2)
            local cy = y + math.floor(R * cell / 2)
            bb:paintCircle(cx, cy, dot_r, C_DOT_BG)
            bb:paintCircle(cx, cy, dot_r, C_CENTER, ring)
            if face then
                local txt = tostring(g)
                local m   = RenderText:sizeUtf8Text(0, dot_r * 4, face, txt, true, false)
                local tx  = cx - math.floor(m.x / 2)
                local ty  = cy + math.floor((m.y_top - m.y_bottom) / 2)
                RenderText:renderUtf8Text(bb, tx, ty, face, txt, true, false, C_LABEL)
            end
        end
    end
end

return GalaxiesBoardWidget
