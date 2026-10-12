-- source.luau
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")

local ModMenu = {}
ModMenu.__index = ModMenu

local DEFAULT_THEME = {
    Background = Color3.fromRGB(16, 18, 17),
    Panel = Color3.fromRGB(25, 28, 26),
    PanelAlt = Color3.fromRGB(33, 37, 34),
    Row = Color3.fromRGB(29, 32, 30),
    RowSelected = Color3.fromRGB(42, 54, 43),
    Accent = Color3.fromRGB(115, 220, 105),
    AccentDark = Color3.fromRGB(56, 135, 55),
    Text = Color3.fromRGB(238, 241, 237),
    Muted = Color3.fromRGB(155, 163, 154),
    Border = Color3.fromRGB(65, 73, 65),
    Disabled = Color3.fromRGB(95, 100, 94),
    Danger = Color3.fromRGB(225, 85, 75),
}

local function create(className, properties, parent)
    local object = Instance.new(className)
    for key, value in pairs(properties or {}) do
        object[key] = value
    end
    object.Parent = parent
    return object
end

local function corner(parent, radius)
    return create("UICorner", { CornerRadius = UDim.new(0, radius or 3) }, parent)
end

local function stroke(parent, color, thickness, transparency)
    return create("UIStroke", {
        Color = color,
        Thickness = thickness or 1,
        Transparency = transparency or 0,
    }, parent)
end

local function label(parent, text, size, color, font)
    return create("TextLabel", {
        BackgroundTransparency = 1,
        Text = text or "",
        TextColor3 = color,
        Font = font or Enum.Font.Gotham,
        TextSize = size or 14,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextYAlignment = Enum.TextYAlignment.Center,
        TextTruncate = Enum.TextTruncate.AtEnd,
    }, parent)
end

function ModMenu.new(config)
    config = config or {}
    local self = setmetatable({}, ModMenu)

    self.Theme = {}
    for key, value in pairs(DEFAULT_THEME) do
        self.Theme[key] = (config.Theme and config.Theme[key]) or value
    end

    self.Title = config.Title or "MOD MENU"
    self.Subtitle = config.Subtitle or "INTERACTION MENU"
    self.ToggleKey = config.ToggleKey or Enum.KeyCode.RightShift
    self.Visible = false
    self.Tabs = {}
    self.ActiveTabIndex = 1
    self.ActiveOptionIndex = 1
    self._connections = {}
    self._destroyed = false
    self._lbDown = false
    self._r3Down = false
    self._lastToggle = 0
    self._toggleDebounce = config.ToggleDebounce or 0.25
    self._rowButtons = {}
    self._tabButtons = {}

    local player = Players.LocalPlayer
    assert(player, "ModMenu.new() must be called from a LocalScript")

    local playerGui = player:WaitForChild("PlayerGui")
    self.Gui = create("ScreenGui", {
        Name = config.GuiName or "GTAStyleModMenu",
        ResetOnSpawn = false,
        IgnoreGuiInset = true,
        DisplayOrder = config.DisplayOrder or 50,
        ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
        Enabled = true,
    }, playerGui)

    self.Overlay = create("Frame", {
        Name = "Overlay",
        BackgroundColor3 = Color3.new(0, 0, 0),
        BackgroundTransparency = 0.38,
        Size = UDim2.fromScale(1, 1),
        Visible = false,
    }, self.Gui)

    self.Main = create("Frame", {
        Name = "Main",
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0.5, 0.5),
        Size = config.Size or UDim2.fromOffset(760, 440),
        BackgroundColor3 = self.Theme.Background,
        BorderSizePixel = 0,
        Visible = false,
    }, self.Overlay)
    corner(self.Main, 4)
    stroke(self.Main, self.Theme.Border, 1, 0.1)

    self.TopBar = create("Frame", {
        Name = "TopBar",
        Size = UDim2.new(1, 0, 0, 66),
        BackgroundColor3 = self.Theme.Panel,
        BorderSizePixel = 0,
    }, self.Main)
    corner(self.TopBar, 4)

    create("Frame", {
        Name = "AccentLine",
        Position = UDim2.new(0, 0, 1, -3),
        Size = UDim2.new(1, 0, 0, 3),
        BackgroundColor3 = self.Theme.Accent,
        BorderSizePixel = 0,
    }, self.TopBar)

    local logo = create("Frame", {
        Name = "LogoBlock",
        Position = UDim2.fromOffset(18, 15),
        Size = UDim2.fromOffset(35, 35),
        BackgroundColor3 = self.Theme.Accent,
        BorderSizePixel = 0,
    }, self.TopBar)
    corner(logo, 3)
    local logoText = label(logo, "R", 23, self.Theme.Background, Enum.Font.GothamBlack)
    logoText.Size = UDim2.fromScale(1, 1)
    logoText.TextXAlignment = Enum.TextXAlignment.Center

    local title = label(self.TopBar, self.Title, 18, self.Theme.Text, Enum.Font.GothamBold)
    title.Name = "Title"
    title.Position = UDim2.fromOffset(65, 12)
    title.Size = UDim2.new(0.6, -65, 0, 25)

    local subtitle = label(self.TopBar, self.Subtitle, 10, self.Theme.Muted, Enum.Font.GothamMedium)
    subtitle.Name = "Subtitle"
    subtitle.Position = UDim2.fromOffset(66, 37)
    subtitle.Size = UDim2.new(0.7, -66, 0, 14)

    self.Status = label(self.TopBar, "●  READY", 11, self.Theme.Accent, Enum.Font.GothamBold)
    self.Status.Name = "Status"
    self.Status.AnchorPoint = Vector2.new(1, 0.5)
    self.Status.Position = UDim2.new(1, -20, 0.5, 0)
    self.Status.Size = UDim2.fromOffset(110, 20)
    self.Status.TextXAlignment = Enum.TextXAlignment.Right

    self.Sidebar = create("Frame", {
        Name = "Sidebar",
        Position = UDim2.fromOffset(0, 66),
        Size = UDim2.new(0, 190, 1, -108),
        BackgroundColor3 = self.Theme.Panel,
        BorderSizePixel = 0,
    }, self.Main)

    self.TabList = create("Frame", {
        Name = "TabList",
        Position = UDim2.fromOffset(10, 14),
        Size = UDim2.new(1, -20, 1, -28),
        BackgroundTransparency = 1,
    }, self.Sidebar)
    create("UIListLayout", {
        Padding = UDim.new(0, 5),
        SortOrder = Enum.SortOrder.LayoutOrder,
    }, self.TabList)

    self.Content = create("Frame", {
        Name = "Content",
        Position = UDim2.fromOffset(190, 66),
        Size = UDim2.new(1, -190, 1, -108),
        BackgroundColor3 = self.Theme.Background,
        BorderSizePixel = 0,
    }, self.Main)

    self.SectionLabel = label(self.Content, "OPTIONS", 11, self.Theme.Accent, Enum.Font.GothamBold)
    self.SectionLabel.Position = UDim2.fromOffset(20, 14)
    self.SectionLabel.Size = UDim2.new(1, -40, 0, 18)

    self.OptionList = create("ScrollingFrame", {
        Name = "OptionList",
        Position = UDim2.fromOffset(14, 40),
        Size = UDim2.new(1, -28, 1, -52),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ScrollBarThickness = 3,
        ScrollBarImageColor3 = self.Theme.Accent,
        CanvasSize = UDim2.fromOffset(0, 0),
        AutomaticCanvasSize = Enum.AutomaticSize.Y,
    }, self.Content)
    create("UIListLayout", {
        Padding = UDim.new(0, 5),
        SortOrder = Enum.SortOrder.LayoutOrder,
    }, self.OptionList)

    self.DescriptionBar = create("Frame", {
        Name = "DescriptionBar",
        Position = UDim2.new(0, 0, 1, -42),
        Size = UDim2.new(1, 0, 0, 42),
        BackgroundColor3 = self.Theme.Panel,
        BorderSizePixel = 0,
    }, self.Main)

    self.Description = label(self.DescriptionBar, "Select an option to view its description.", 12,
        self.Theme.Muted, Enum.Font.Gotham)
    self.Description.Position = UDim2.fromOffset(18, 0)
    self.Description.Size = UDim2.new(1, -250, 1, 0)

    self.ControlsHint = label(self.DescriptionBar, "LB + R3  MENU     A  SELECT     B  BACK", 10,
        self.Theme.Text, Enum.Font.GothamBold)
    self.ControlsHint.AnchorPoint = Vector2.new(1, 0)
    self.ControlsHint.Position = UDim2.new(1, -16, 0, 0)
    self.ControlsHint.Size = UDim2.fromOffset(235, 42)
    self.ControlsHint.TextXAlignment = Enum.TextXAlignment.Right

    self:_connectInput()
    self:SetVisible(false)
    return self
end

function ModMenu:_activeTab()
    return self.Tabs[self.ActiveTabIndex]
end

function ModMenu:_activeOption()
    local tab = self:_activeTab()
    return tab and tab.Options[self.ActiveOptionIndex]
end

function ModMenu:_connectInput()
    table.insert(self._connections, UserInputService.InputBegan:Connect(function(input, processed)
        if self._destroyed then return end

        if input.KeyCode == Enum.KeyCode.ButtonL1 then
            self._lbDown = true
        elseif input.KeyCode == Enum.KeyCode.ButtonR3 then
            self._r3Down = true
        end

        if self._lbDown and self._r3Down then
            self:_toggleWithDebounce()
            return
        end

        if input.KeyCode == self.ToggleKey and not processed then
            self:_toggleWithDebounce()
            return
        end

        if not self.Visible then return end

        local key = input.KeyCode
        if key == Enum.KeyCode.DPadDown or key == Enum.KeyCode.Down then
            self:MoveSelection(1)
        elseif key == Enum.KeyCode.DPadUp or key == Enum.KeyCode.Up then
            self:MoveSelection(-1)
        elseif key == Enum.KeyCode.DPadLeft or key == Enum.KeyCode.Left then
            self:AdjustSelection(-1)
        elseif key == Enum.KeyCode.DPadRight or key == Enum.KeyCode.Right then
            self:AdjustSelection(1)
        elseif key == Enum.KeyCode.ButtonA or key == Enum.KeyCode.Return or key == Enum.KeyCode.KeypadEnter then
            self:ActivateSelection()
        elseif key == Enum.KeyCode.ButtonB or key == Enum.KeyCode.Backspace or key == Enum.KeyCode.Escape then
            self:Back()
        elseif key == Enum.KeyCode.ButtonL2 then
            self:ChangeTab(-1)
        elseif key == Enum.KeyCode.ButtonR2 then
            self:ChangeTab(1)
        end
    end))

    table.insert(self._connections, UserInputService.InputEnded:Connect(function(input)
        if input.KeyCode == Enum.KeyCode.ButtonL1 then self._lbDown = false end
        if input.KeyCode == Enum.KeyCode.ButtonR3 then self._r3Down = false end
    end))
end

function ModMenu:_toggleWithDebounce()
    local now = os.clock()
    if now - self._lastToggle < self._toggleDebounce then return end
    self._lastToggle = now
    self:SetVisible(not self.Visible)
end

function ModMenu:SetVisible(visible)
    self.Visible = visible == true
    self.Overlay.Visible = self.Visible
    self.Main.Visible = self.Visible

    if self.Visible then
        self:_renderTabs()
        self:_renderOptions()
        self:_updateDescription()
        self.Status.Text = "●  MENU ACTIVE"
    else
        self.Status.Text = "●  READY"
    end
end

function ModMenu:Toggle()
    self:SetVisible(not self.Visible)
end

function ModMenu:AddTab(name, icon)
    assert(type(name) == "string", "Tab name must be a string")
    local tab = {
        Name = name,
        Icon = icon or "›",
        Options = {},
    }
    table.insert(self.Tabs, tab)
    if #self.Tabs == 1 then
        self.ActiveTabIndex = 1
        self.ActiveOptionIndex = 1
    end
    self:_renderTabs()
    self:_renderOptions()
    return tab
end

function ModMenu:_addOption(tab, option)
    tab = tab or self:_activeTab()
    assert(tab, "Create a tab with AddTab() before adding options")
    option.Name = option.Name or "Option"
    option.Description = option.Description or ""
    option.Enabled = option.Enabled ~= false
    table.insert(tab.Options, option)
    self:_renderOptions()
    return option
end

function ModMenu:AddToggle(name, defaultValue, callback, description, tab)
    return self:_addOption(tab, {
        Type = "Toggle", Name = name, Value = defaultValue == true,
        Callback = callback, Description = description,
    })
end

function ModMenu:AddButton(name, callback, description, tab)
    return self:_addOption(tab, {
        Type = "Button", Name = name, Callback = callback, Description = description,
    })
end

function ModMenu:AddList(name, values, defaultValue, callback, description, tab)
    values = values or {}
    local selected = defaultValue
    if selected == nil and #values > 0 then selected = values[1] end
    return self:_addOption(tab, {
        Type = "List", Name = name, Values = values, Value = selected,
        Callback = callback, Description = description,
    })
end

function ModMenu:AddSlider(name, minValue, maxValue, defaultValue, step, callback, description, tab)
    minValue = tonumber(minValue) or 0
    maxValue = tonumber(maxValue) or 100
    step = tonumber(step) or 1
    local value = math.clamp(tonumber(defaultValue) or minValue, minValue, maxValue)
    return self:_addOption(tab, {
        Type = "Slider", Name = name, Min = minValue, Max = maxValue,
        Step = math.max(step, 0.0001), Value = value,
        Callback = callback, Description = description,
    })
end

function ModMenu:AddSeparator(name, tab)
    return self:_addOption(tab, {
        Type = "Separator", Name = name or "────────",
        Description = "",
    })
end

function ModMenu:_renderTabs()
    for _, child in ipairs(self.TabList:GetChildren()) do
        if child:IsA("GuiObject") then child:Destroy() end
    end
    self._tabButtons = {}

    for index, tab in ipairs(self.Tabs) do
        local selected = index == self.ActiveTabIndex
        local button = create("TextButton", {
            Name = "Tab_" .. index,
            LayoutOrder = index,
            Size = UDim2.new(1, 0, 0, 38),
            BackgroundColor3 = selected and self.Theme.RowSelected or self.Theme.Panel,
            BorderSizePixel = 0,
            AutoButtonColor = false,
            Text = "",
        }, self.TabList)
        corner(button, 3)

        if selected then
            create("Frame", {
                Name = "SelectionStripe",
                Size = UDim2.new(0, 3, 1, -10),
                Position = UDim2.fromOffset(0, 5),
                BackgroundColor3 = self.Theme.Accent,
                BorderSizePixel = 0,
            }, button)
        end

        local tabText = label(button, tab.Icon .. "   " .. tab.Name, 13,
            selected and self.Theme.Accent or self.Theme.Text,
            selected and Enum.Font.GothamBold or Enum.Font.GothamMedium)
        tabText.Position = UDim2.fromOffset(13, 0)
        tabText.Size = UDim2.new(1, -20, 1, 0)

        button.Activated:Connect(function()
            self.ActiveTabIndex = index
            self.ActiveOptionIndex = 1
            self:_renderTabs()
            self:_renderOptions()
            self:_updateDescription()
        end)
        self._tabButtons[index] = button
    end
end

function ModMenu:_clearOptionRows()
    for _, child in ipairs(self.OptionList:GetChildren()) do
        if child:IsA("GuiObject") then child:Destroy() end
    end
    self._rowButtons = {}
end

function ModMenu:_renderOptions()
    self:_clearOptionRows()
    local tab = self:_activeTab()
    self.SectionLabel.Text = tab and string.upper(tab.Name) .. "  /  OPTIONS" or "OPTIONS"
    if not tab then return end

    if #tab.Options == 0 then
        local empty = label(self.OptionList, "No options have been added to this category.", 13, self.Theme.Muted)
        empty.Size = UDim2.new(1, -8, 0, 42)
        return
    end

    self.ActiveOptionIndex = math.clamp(self.ActiveOptionIndex, 1, #tab.Options)
    for index, option in ipairs(tab.Options) do
        local selected = index == self.ActiveOptionIndex
        if option.Type == "Separator" then
            local separator = label(self.OptionList, string.upper(option.Name), 10, self.Theme.Accent, Enum.Font.GothamBold)
            separator.Name = "Separator_" .. index
            separator.LayoutOrder = index
            separator.Size = UDim2.new(1, -8, 0, 23)
        else
            local row = create("TextButton", {
                Name = "Option_" .. index,
                LayoutOrder = index,
                Size = UDim2.new(1, -8, 0, 39),
                BackgroundColor3 = selected and self.Theme.RowSelected or self.Theme.Row,
                BorderSizePixel = 0,
                AutoButtonColor = false,
                Text = "",
            }, self.OptionList)
            corner(row, 3)

            if selected then
                create("Frame", {
                    Name = "SelectionStripe",
                    Size = UDim2.new(0, 3, 1, -8),
                    Position = UDim2.fromOffset(0, 4),
                    BackgroundColor3 = self.Theme.Accent,
                    BorderSizePixel = 0,
                }, row)
            end

            local optionLabel = label(row, option.Name, 13,
                selected and self.Theme.Text or self.Theme.Muted,
                selected and Enum.Font.GothamBold or Enum.Font.Gotham)
            optionLabel.Position = UDim2.fromOffset(13, 0)
            optionLabel.Size = UDim2.new(0.68, -13, 1, 0)

            local valueText = ""
            local valueColor = self.Theme.Accent
            if option.Type == "Toggle" then
                valueText = option.Value and "ON" or "OFF"
                valueColor = option.Value and self.Theme.Accent or self.Theme.Muted
            elseif option.Type == "List" then
                valueText = tostring(option.Value or "—") .. "   ‹ ›"
            elseif option.Type == "Slider" then
                valueText = tostring(option.Value)
            elseif option.Type == "Button" then
                valueText = "›"
            end

            local valueLabel = label(row, valueText, 12, valueColor, Enum.Font.GothamBold)
            valueLabel.Name = "Value"
            valueLabel.AnchorPoint = Vector2.new(1, 0)
            valueLabel.Position = UDim2.new(1, -14, 0, 0)
            valueLabel.Size = UDim2.new(0.32, 0, 1, 0)
            valueLabel.TextXAlignment = Enum.TextXAlignment.Right

            row.Activated:Connect(function()
                self.ActiveOptionIndex = index
                self:_renderOptions()
                self:_updateDescription()
                self:ActivateSelection()
            end)
            self._rowButtons[index] = row
        end
    end

    local selectedRow = self._rowButtons[self.ActiveOptionIndex]
    if selectedRow then
        local relativeY = selectedRow.Position.Y.Offset
        local viewTop = self.OptionList.CanvasPosition.Y
        local viewBottom = viewTop + self.OptionList.AbsoluteWindowSize.Y
        if relativeY < viewTop then
            self.OptionList.CanvasPosition = Vector2.new(0, relativeY)
        elseif relativeY + selectedRow.AbsoluteSize.Y > viewBottom then
            self.OptionList.CanvasPosition = Vector2.new(0, relativeY + selectedRow.AbsoluteSize.Y - self.OptionList.AbsoluteWindowSize.Y)
        end
    end
end

function ModMenu:_updateDescription()
    local option = self:_activeOption()
    self.Description.Text = option and (option.Description ~= "" and option.Description or option.Name)
        or "Choose a category to begin."
end

function ModMenu:MoveSelection(direction)
    local tab = self:_activeTab()
    if not tab or #tab.Options == 0 then return end
    local index = self.ActiveOptionIndex
    for _ = 1, #tab.Options do
        index = ((index - 1 + direction) % #tab.Options) + 1
        if tab.Options[index].Type ~= "Separator" then
            self.ActiveOptionIndex = index
            break
        end
    end
    self:_renderOptions()
    self:_updateDescription()
end

function ModMenu:ChangeTab(direction)
    if #self.Tabs == 0 then return end
    self.ActiveTabIndex = ((self.ActiveTabIndex - 1 + direction) % #self.Tabs) + 1
    self.ActiveOptionIndex = 1
    self:_renderTabs()
    self:_renderOptions()
    self:_updateDescription()
end

function ModMenu:_setOptionValue(option, value)
    option.Value = value
    if type(option.Callback) == "function" then
        task.spawn(function()
            local ok, err = pcall(option.Callback, value, option)
            if not ok then warn("[ModMenu] Option callback failed:", err) end
        end)
    end
    self:_renderOptions()
    self:_updateDescription()
end

function ModMenu:AdjustSelection(direction)
    local option = self:_activeOption()
    if not option then return end

    if option.Type == "Toggle" then
        self:_setOptionValue(option, not option.Value)
    elseif option.Type == "List" then
        if #option.Values == 0 then return end
        local current = table.find(option.Values, option.Value) or 1
        current = ((current - 1 + direction) % #option.Values) + 1
        self:_setOptionValue(option, option.Values[current])
    elseif option.Type == "Slider" then
        local nextValue = math.clamp(option.Value + direction * option.Step, option.Min, option.Max)
        local precision = 0
        local stepString = tostring(option.Step)
        local decimal = string.find(stepString, "%.")
        if decimal then precision = #stepString - decimal end
        nextValue = tonumber(string.format("%." .. math.min(precision, 6) .. "f", nextValue))
        self:_setOptionValue(option, nextValue)
    end
end

function ModMenu:ActivateSelection()
    local option = self:_activeOption()
    if not option then return end

    if option.Type == "Toggle" then
        self:_setOptionValue(option, not option.Value)
    elseif option.Type == "Button" then
        if type(option.Callback) == "function" then
            task.spawn(function()
                local ok, err = pcall(option.Callback, option)
                if not ok then warn("[ModMenu] Button callback failed:", err) end
            end)
        end
    elseif option.Type == "List" then
        self:AdjustSelection(1)
    elseif option.Type == "Slider" then
        self:AdjustSelection(1)
    end
end

function ModMenu:Back()
    -- Reserved for submenu support. With no submenu open, close the menu.
    self:SetVisible(false)
end

function ModMenu:SetStatus(text, color)
    self.Status.Text = "●  " .. tostring(text or "READY")
    self.Status.TextColor3 = color or self.Theme.Accent
end

function ModMenu:SetToggle(option, value, suppressCallback)
    assert(option and option.Type == "Toggle", "SetToggle expects an option returned by AddToggle")
    option.Value = value == true
    if not suppressCallback and type(option.Callback) == "function" then
        task.spawn(function()
            local ok, err = pcall(option.Callback, option.Value, option)
            if not ok then warn("[ModMenu] Toggle callback failed:", err) end
        end)
    end
    self:_renderOptions()
end

function ModMenu:Destroy()
    if self._destroyed then return end
    self._destroyed = true
    for _, connection in ipairs(self._connections) do
        connection:Disconnect()
    end
    table.clear(self._connections)
    if self.Gui then self.Gui:Destroy() end
end

return ModMenu
