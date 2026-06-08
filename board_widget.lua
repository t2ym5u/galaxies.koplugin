local Blitbuffer = require("ffi/blitbuffer")
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
    Blitbuffer.COLOR_GRAY_C,
    Blitbuffer.COLOR_GRAY_B,
    Blitbuffer.COLOR_GRAY_9,
}
local NUM_GALAXY_COLORS = #GALAXY_COLORS

local C_BG      = Blitbuffer.COLOR_WHITE
local C_LINE    = Blitbuffer.COLOR_BLACK
local C_GRID    = Blitbuffer.COLOR_GRAY_9
local C_CENTER  = Blitbuffer.COLOR_BLACK   -- filled dot for galaxy center
local C_LABEL   = Blitbuffer.COLOR_GRAY_4  -- galaxy number inside dot

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
        drawLine(bb, x + math.floor(i * cell), y, lw, self.dimen.h, C_LINE)
        drawLine(bb, x, y + math.floor(i * cell), self.dimen.w, lw, C_LINE)
    end

    -- Galaxy center dots
    local dot_r = math.max(3, math.floor(cell * 0.18))
    for g = 1, board.num_galaxies do
        local center = board.centers[g]
        if center then
            local cr, cc = center[1], center[2]
            local cx = x + math.floor((cc - 1) * cell) + math.floor(cell / 2)
            local cy = y + math.floor((cr - 1) * cell) + math.floor(cell / 2)
            -- Draw filled circle (approximated by a square for e-ink)
            bb:paintRect(cx - dot_r, cy - dot_r, dot_r * 2, dot_r * 2, C_CENTER)
            -- Draw galaxy number inside the dot if space allows
            if dot_r >= 4 then
                local face = self.note_face
                local txt  = tostring(g)
                local m    = RenderText:sizeUtf8Text(0, dot_r * 2, face, txt, true, false)
                local tx   = cx - math.floor(m.x / 2)
                local ty   = cy - math.floor((m.y_bottom - m.y_top) / 2) - m.y_top
                RenderText:renderUtf8Text(bb, tx, ty, face, txt, true, false, C_LABEL)
            end
        end
    end
end

return GalaxiesBoardWidget
