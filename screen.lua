local _dir = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"
local function lrequire(name)
    local key = _dir .. name
    if not package.loaded[key] then
        package.loaded[key] = assert(loadfile(_dir .. name .. ".lua"))()
    end
    return package.loaded[key]
end

local ButtonTable     = require("ui/widget/buttontable")
local Device          = require("device")
local FrameContainer  = require("ui/widget/container/framecontainer")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan  = require("ui/widget/horizontalspan")
local Size            = require("ui/size")
local UIManager       = require("ui/uimanager")
local VerticalGroup   = require("ui/widget/verticalgroup")
local VerticalSpan    = require("ui/widget/verticalspan")
local _               = require("gettext")
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
]])

local GAME_RULES_FR = [[
Galaxies (Tentai Show) — Règles

Divisez la grille en régions, une région par symbole de galaxie.

Règles :
• Chaque région doit être symétrique par rotation à 180° autour de son symbole de galaxie.
• Chaque case appartient à exactement une région.
• Les symboles de galaxie peuvent être centrés sur une case, sur le milieu d'un bord, ou sur un sommet (coin de quatre cases).

Le puzzle est résolu quand toutes les cases sont attribuées à une galaxie et que chaque région présente une symétrie parfaite à 180° autour de son symbole.
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
    local sw           = DeviceScreen:getWidth()
    local is_landscape = self:isLandscape()

    self.board_widget = GalaxiesBoardWidget:new{
        board        = self.board,
        onCellTap_cb = function(r, c) self:onCellTap(r, c) end,
    }

    local board_frame = FrameContainer:new{
        padding = Size.padding.large,
        margin  = Size.margin.default,
        self.board_widget,
    }

    local board_frame_size  = self.board_widget.size + (Size.padding.large + Size.margin.default) * 2
    local right_panel_width = sw - board_frame_size - Size.span.horizontal_default
    local button_width = is_landscape
        and math.max(right_panel_width - Size.span.horizontal_default, 100)
        or  math.floor(sw * 0.9)

    local top_buttons = ButtonTable:new{
        shrink_unneeded_width = true,
        width   = button_width,
        buttons = {{
            { text = _("New"),
              callback = function() self:onNewGame() end },
            { id = "size_button", text = self:getSizeButtonText(),
              callback = function() self:openSizeMenu() end },
            { text = _("Reveal"),
              callback = function() self:onReveal() end },
            self:makeRulesButtonConfig(GAME_RULES_EN, GAME_RULES_FR),
            self:makeCloseButtonConfig(),
        }},
    }
    self.size_button = top_buttons:getButtonById("size_button")

    local bottom_buttons = ButtonTable:new{
        shrink_unneeded_width = true,
        width   = button_width,
        buttons = {{
            { text = _("Clear"),
              callback = function() self:onClear() end },
            { text = _("Undo"),
              callback = function() self:onUndo() end },
        }},
    }

    if is_landscape then
        local right_panel = VerticalGroup:new{
            align = "center",
            top_buttons,
            VerticalSpan:new{ width = Size.span.vertical_large },
            self.status_text,
            VerticalSpan:new{ width = Size.span.vertical_large },
            bottom_buttons,
        }
        self.layout = HorizontalGroup:new{
            align  = "center",
            board_frame,
            HorizontalSpan:new{ width = Size.span.horizontal_default },
            right_panel,
        }
    else
        self.layout = VerticalGroup:new{
            align = "center",
            VerticalSpan:new{ width = Size.span.vertical_large },
            top_buttons,
            VerticalSpan:new{ width = Size.span.vertical_large },
            board_frame,
            VerticalSpan:new{ width = Size.span.vertical_large },
            self.status_text,
            VerticalSpan:new{ width = Size.span.vertical_large },
            bottom_buttons,
            VerticalSpan:new{ width = Size.span.vertical_large },
        }
    end
    self[1] = self.layout
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
        title     = _("Select grid size"),
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
        local num_g      = self.board.num_galaxies
        status = T(_("%1\xC3\x97%2 \xC2\xB7 %3 galaxies \xC2\xB7 Unassigned: %4"),
                   n, n, num_g, unassigned)
    end
    ScreenBase.updateStatus(self, status)
end

function GalaxiesScreen:getSizeButtonText()
    local n = self.board.n
    return T(_("Size: %1"), n .. "\xC3\x97" .. n)
end

return GalaxiesScreen
