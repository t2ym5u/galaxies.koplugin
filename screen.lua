local _dir = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"
local function lrequire(name)
    local key = _dir .. name
    if not package.loaded[key] then
        package.loaded[key] = assert(loadfile(_dir .. name .. ".lua"))()
    end
    return package.loaded[key]
end

local Device          = require("device")
local FrameContainer  = require("ui/widget/container/framecontainer")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan  = require("ui/widget/horizontalspan")
local Size            = require("ui/size")
local UIManager       = require("ui/uimanager")
local VerticalGroup   = require("ui/widget/verticalgroup")
local VerticalSpan    = require("ui/widget/verticalspan")
local _               = require("i18n")
local T               = require("ffi/util").template

local ScreenBase            = require("screen_base")
local MenuHelper            = require("menu_helper")
local GalaxiesBoard         = lrequire("board")
local GalaxiesBoardWidget   = lrequire("board_widget")

local DeviceScreen = Device.screen

local GAME_RULES_EN = _([[
Galaxies (Tentai Show) — Rules

Divide the grid into regions, one region per galaxy symbol.

Rules:
• Each region must be rotationally symmetric by 180° around its galaxy symbol.
• Every cell belongs to exactly one region.
• Galaxy symbols may be centred on a cell, on an edge midpoint, or on a vertex (corner of four cells).

The puzzle is solved when all cells are assigned to a galaxy and each region has perfect 180° symmetry around its symbol.

Tap a cell to assign it to the next galaxy (1, 2, 3, …); keep tapping to cycle through them and back to unassigned. The number inside each symbol is its galaxy.
]])

local GAME_RULES_FR = [[
Galaxies (Tentai Show) — Règles

Divisez la grille en régions, une région par symbole de galaxie.

Règles :
• Chaque région doit être symétrique par rotation à 180° autour de son symbole de galaxie.
• Chaque case appartient à exactement une région.
• Les symboles de galaxie peuvent être centrés sur une case, sur le milieu d'un bord, ou sur un sommet (coin de quatre cases).

Le puzzle est résolu quand toutes les cases sont attribuées à une galaxie et que chaque région présente une symétrie parfaite à 180° autour de son symbole.

Appuyez sur une case pour l'attribuer à la galaxie suivante (1, 2, 3, …) ; continuez d'appuyer pour les faire défiler jusqu'à revenir à non attribuée. Le numéro dans chaque symbole est celui de sa galaxie.
]]

local GalaxiesScreen = ScreenBase:extend{}

function GalaxiesScreen:init()
    local state = self.plugin:loadState()
    local n     = self.plugin:getSetting("grid_n", GalaxiesBoard.DEFAULT_N)
    self.board  = GalaxiesBoard:new{ n = n }
    if not self.board:load(state) then
        self.board:generate()
    end
    ScreenBase.init(self)
end

function GalaxiesScreen:serializeState()
    return self.board:serialize()
end

function GalaxiesScreen:buildLayout()
    local is_landscape = self:isLandscape()

    local title_bar = self:buildTitleBar(_("Galaxies"), function()
        return {
            { text = _("New game"),            callback = function() self:onNewGame() end },
            { text = self:getSizeButtonText(), callback = function() self:openSizeMenu() end },
            { text = _("Show solution"),       callback = function() self:onReveal() end },
            self:makeRulesButtonConfig(GAME_RULES_EN, GAME_RULES_FR),
        }
    end)

    self.status_text:setMaxWidth(self:getControlsWidth())
    local controls = VerticalGroup:new{
        align = "center",
        self.status_text,
        VerticalSpan:new{ width = Size.span.vertical_large },
        self:buildActionBar({
            { text = _("Clear"), callback = function() self:onClear() end },
            { text = _("Undo"),  callback = function() self:onUndo() end },
        }),
    }

    -- The widget draws its own thick outer grid line, so the frame stays
    -- borderless: one visible edge around the board, not two.
    local frame_pad   = Size.padding.large
    local frame_extra = 2 * frame_pad
    local budget_w, budget_h = self:getBoardBudget(title_bar, controls)
    self.board_widget = GalaxiesBoardWidget:new{
        board        = self.board,
        max_size     = math.min(budget_w, budget_h) - frame_extra,
        onCellTap_cb = function(r, c) self:onCellTap(r, c) end,
    }
    local board_frame = FrameContainer:new{
        padding    = frame_pad,
        margin     = 0,
        bordersize = 0,
        self.board_widget,
    }

    if is_landscape then
        local content = HorizontalGroup:new{
            align = "center",
            board_frame,
            HorizontalSpan:new{ width = self:getGutter() },
            controls,
        }
        self:buildLandscapeLayout(title_bar, content)
    else
        self:buildPortraitLayout(title_bar, board_frame,
            VerticalGroup:new{ align = "center", controls, VerticalSpan:new{ width = self:getGutter() } })
    end
    self:updateStatus()
end

function GalaxiesScreen:onCellTap(r, c)
    self.board:cycleCell(r, c)
    self.board_widget:refresh()
    self.plugin:saveState(self.board:serialize())
    if self.board.won then
        self:updateStatus(_("Congratulations! All galaxies complete!"))
    else
        self:updateStatus()
    end
end

function GalaxiesScreen:onUndo()
    if self.board:undoMove() then
        self.board_widget:refresh()
        self.plugin:saveState(self.board:serialize())
        self:updateStatus()
    end
end

function GalaxiesScreen:onClear()
    self.board:clearUser()
    self.board_widget:refresh()
    self.plugin:saveState(self.board:serialize())
    self:updateStatus(_("Board cleared."))
end

function GalaxiesScreen:onReveal()
    self.board:reveal()
    self.board_widget:refresh()
    self.plugin:saveState(self.board:serialize())
    self:updateStatus(_("Solution revealed."))
end

function GalaxiesScreen:onNewGame()
    local n    = self.plugin:getSetting("grid_n", GalaxiesBoard.DEFAULT_N)
    self.board = GalaxiesBoard:new{ n = n }
    self.board:generate()
    self.plugin:saveState(self.board:serialize())
    self:buildLayout()
    UIManager:setDirty(self, function() return "ui", self.dimen end)
end

function GalaxiesScreen:openSizeMenu()
    local sizes = {}
    for _, sz in ipairs(GalaxiesBoard.SIZES) do
        sizes[#sizes + 1] = { id = sz, text = sz .. "\xC3\x97" .. sz }
    end
    MenuHelper.openSizeMenu{
        title     = _("Select size"),
        sizes     = sizes,
        current   = self.plugin:getSetting("grid_n", GalaxiesBoard.DEFAULT_N),
        parent    = self,
        on_select = function(sz)
            if sz ~= self.board.n then
                self.plugin:saveSetting("grid_n", sz)
                self:onNewGame()
            end
        end,
    }
end

function GalaxiesScreen:updateStatus(msg)
    local status
    if msg then
        status = msg
    elseif self.board.won then
        status = _("Congratulations! All galaxies complete!")
    else
        local unassigned = self.board:countUnassigned()
        local n          = self.board.n
        status = self:joinStatus(
            T("%1×%1", n),
            T(_("Unassigned: %1"), unassigned))
    end
    ScreenBase.updateStatus(self, status)
    -- Every move, hint, undo and reveal ends here, so the bar follows the board.
    self:refreshActionBar()
end

-- Show solution marks the board won, so it ends the round too.
function GalaxiesScreen:isRoundOver()
    return self.board.won
end

function GalaxiesScreen:getSizeButtonText()
    local n = self.board.n
    return T(_("Size: %1"), n .. "\xC3\x97" .. n)
end

return GalaxiesScreen
