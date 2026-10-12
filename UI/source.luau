-- source.luau
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")

local ModMenu = {}
ModMenu.__index = ModMenu

-- GTA-inspired palette: deep charcoal, soft highlight, restrained accent
local DEFAULT_THEME = {
	Background   = Color3.fromRGB(8, 10, 12),
	Panel        = Color3.fromRGB(12, 14, 16),
	Row          = Color3.fromRGB(0, 0, 0),
	RowHover     = Color3.fromRGB(28, 32, 36),
	RowSelected  = Color3.fromRGB(255, 255, 255),
	Accent       = Color3.fromRGB(255, 255, 255),
	AccentDim    = Color3.fromRGB(180, 185, 190),
	Text         = Color3.fromRGB(230, 232, 235),
	Muted        = Color3.fromRGB(160, 165, 170),
	Value        = Color3.fromRGB(200, 205, 210),
	Border       = Color3.fromRGB(40, 45, 50),
	Disabled     = Color3.fromRGB(90, 95, 100),
	Danger       = Color3.fromRGB(220, 70, 60),
	Success      = Color3.fromRGB(90, 200, 100),
	Overlay      = Color3.fromRGB(0, 0, 0),
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
	return create("UICorner", { CornerRadius = UDim.new(0, radius or 0) }, parent)
end

local function stroke(parent, color, thickness, transparency)
	return create("UIStroke", {
		Color = color,
		Thickness = thickness or 1,
		Transparency = transparency or 0,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
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
		RichText = false,
	}, parent)
end

local function tween(instance, props, duration, style, direction)
	local info = TweenInfo.new(
		duration or 0.12,
		style or Enum.EasingStyle.Quad,
		direction or Enum.EasingDirection.Out
	)
	local t = TweenService:Create(instance, info, props)
	t:Play()
	return t
end

function ModMenu.new(config)
	config = config or {}
	local self = setmetatable({}, ModMenu)

	self.Theme = {}
	for key, value in pairs(DEFAULT_THEME) do
		self.Theme[key] = (config.Theme and config.Theme[key]) or value
	end

	self.Title = config.Title or "INTERACTION MENU"
	self.Subtitle = config.Subtitle or ""
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
	self._hoverConnections = {}

	local player = Players.LocalPlayer
	assert(player, "ModMenu.new() must be called from a LocalScript")

	local playerGui = player:WaitForChild("PlayerGui")
	self.Gui = create("ScreenGui", {
		Name = config.GuiName or "GTAInteractionMenu",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = config.DisplayOrder or 50,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Enabled = true,
	}, playerGui)

	-- Full-screen dim (very light so the world stays readable)
	self.Overlay = create("Frame", {
		Name = "Overlay",
		BackgroundColor3 = self.Theme.Overlay,
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Visible = false,
		BorderSizePixel = 0,
	}, self.Gui)

	-- Main panel – compact, left-anchored like classic GTA interaction menu
	local defaultSize = config.Size or UDim2.fromOffset(340, 380)
	self.Main = create("Frame", {
		Name = "Main",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = config.Position or UDim2.new(0, 40, 0.5, 0),
		Size = defaultSize,
		BackgroundColor3 = self.Theme.Background,
		BackgroundTransparency = 0.22,
		BorderSizePixel = 0,
		Visible = false,
		ClipsDescendants = true,
	}, self.Overlay)
	corner(self.Main, 2)

	-- Subtle outer stroke
	stroke(self.Main, Color3.fromRGB(255, 255, 255), 1, 0.88)

	-- Header
	self.TopBar = create("Frame", {
		Name = "TopBar",
		Size = UDim2.new(1, 0, 0, 48),
		BackgroundColor3 = self.Theme.Panel,
		BackgroundTransparency = 0.35,
		BorderSizePixel = 0,
	}, self.Main)

	create("Frame", {
		Name = "TopLine",
		Size = UDim2.new(1, 0, 0, 1),
		BackgroundColor3 = Color3.fromRGB(255, 255, 255),
		BackgroundTransparency = 0.75,
		BorderSizePixel = 0,
	}, self.TopBar)

	self.TitleLabel = label(self.TopBar, self.Title, 13, self.Theme.Text, Enum.Font.GothamBold)
	self.TitleLabel.Name = "Title"
	self.TitleLabel.Position = UDim2.fromOffset(14, 6)
	self.TitleLabel.Size = UDim2.new(1, -80, 0, 18)

	self.PageLabel = label(self.TopBar, "1 / 1", 11, self.Theme.Muted, Enum.Font.GothamMedium)
	self.PageLabel.Name = "Page"
	self.PageLabel.AnchorPoint = Vector2.new(1, 0)
	self.PageLabel.Position = UDim2.new(1, -14, 0, 6)
	self.PageLabel.Size = UDim2.fromOffset(60, 18)
	self.PageLabel.TextXAlignment = Enum.TextXAlignment.Right

	self.CategoryLabel = label(self.TopBar, "", 11, self.Theme.AccentDim, Enum.Font.Gotham)
	self.CategoryLabel.Name = "Category"
	self.CategoryLabel.Position = UDim2.fromOffset(14, 26)
	self.CategoryLabel.Size = UDim2.new(1, -28, 0, 16)

	-- Option list
	self.OptionList = create("ScrollingFrame", {
		Name = "OptionList",
		Position = UDim2.fromOffset(0, 48),
		Size = UDim2.new(1, 0, 1, -96),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 2,
		ScrollBarImageColor3 = Color3.fromRGB(255, 255, 255),
		ScrollBarImageTransparency = 0.6,
		CanvasSize = UDim2.fromOffset(0, 0),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
	}, self.Main)
	create("UIListLayout", {
		Padding = UDim.new(0, 0),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, self.OptionList)

	-- Description footer
	self.DescriptionBar = create("Frame", {
		Name = "DescriptionBar",
		Position = UDim2.new(0, 0, 1, -48),
		Size = UDim2.new(1, 0, 0, 48),
		BackgroundColor3 = self.Theme.Panel,
		BackgroundTransparency = 0.35,
		BorderSizePixel = 0,
	}, self.Main)

	create("Frame", {
		Name = "FooterLine",
		Size = UDim2.new(1, 0, 0, 1),
		BackgroundColor3 = Color3.fromRGB(255, 255, 255),
		BackgroundTransparency = 0.8,
		BorderSizePixel = 0,
	}, self.DescriptionBar)

	self.Description = label(self.DescriptionBar, "Select an option.", 12,
		self.Theme.Muted, Enum.Font.Gotham)
	self.Description.Position = UDim2.fromOffset(14, 4)
	self.Description.Size = UDim2.new(1, -28, 1, -8)
	self.Description.TextYAlignment = Enum.TextYAlignment.Top
	self.Description.TextWrapped = true

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
		self.Overlay.BackgroundTransparency = 1
		self.Main.BackgroundTransparency = 0.35
		tween(self.Overlay, { BackgroundTransparency = 0.55 }, 0.15)
		tween(self.Main, { BackgroundTransparency = 0.18 }, 0.14)
		self:_renderOptions()
		self:_updateHeader()
		self:_updateDescription()
	end
end

function ModMenu:Toggle()
	self:SetVisible(not self.Visible)
end

function ModMenu:AddTab(name, icon)
	assert(type(name) == "string", "Tab name must be a string")
	local tab = {
		Name = name,
		Icon = icon or "",
		Options = {},
	}
	table.insert(self.Tabs, tab)
	if #self.Tabs == 1 then
		self.ActiveTabIndex = 1
		self.ActiveOptionIndex = 1
	end
	self:_renderOptions()
	self:_updateHeader()
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

function ModMenu:_clearHoverConnections()
	for _, conn in ipairs(self._hoverConnections) do
		conn:Disconnect()
	end
	table.clear(self._hoverConnections)
end

function ModMenu:_bindHover(button, isSelected)
	if isSelected then return end
	local enter = button.MouseEnter:Connect(function()
		if not self.Visible then return end
		tween(button, { BackgroundTransparency = 0.82 }, 0.08)
	end)
	local leave = button.MouseLeave:Connect(function()
		if not self.Visible then return end
		tween(button, { BackgroundTransparency = 1 }, 0.1)
	end)
	table.insert(self._hoverConnections, enter)
	table.insert(self._hoverConnections, leave)
end

function ModMenu:_updateHeader()
	local tab = self:_activeTab()
	local totalTabs = math.max(#self.Tabs, 1)
	self.PageLabel.Text = string.format("%d / %d", self.ActiveTabIndex, totalTabs)
	self.CategoryLabel.Text = tab and string.upper(tab.Name) or ""
	self.TitleLabel.Text = self.Title
end

function ModMenu:_clearOptionRows()
	for _, child in ipairs(self.OptionList:GetChildren()) do
		if child:IsA("GuiObject") then child:Destroy() end
	end
	self._rowButtons = {}
	self:_clearHoverConnections()
end

function ModMenu:_renderOptions()
	self:_clearOptionRows()
	local tab = self:_activeTab()
	if not tab then return end

	if #tab.Options == 0 then
		local empty = label(self.OptionList, "No options.", 13, self.Theme.Muted)
		empty.Size = UDim2.new(1, -20, 0, 36)
		empty.Position = UDim2.fromOffset(14, 0)
		return
	end

	self.ActiveOptionIndex = math.clamp(self.ActiveOptionIndex, 1, #tab.Options)

	for index, option in ipairs(tab.Options) do
		local selected = index == self.ActiveOptionIndex

		if option.Type == "Separator" then
			local sep = create("Frame", {
				Name = "Separator_" .. index,
				LayoutOrder = index,
				Size = UDim2.new(1, 0, 0, 22),
				BackgroundTransparency = 1,
			}, self.OptionList)
			local sepLabel = label(sep, string.upper(option.Name), 10, self.Theme.Muted, Enum.Font.GothamBold)
			sepLabel.Position = UDim2.fromOffset(14, 0)
			sepLabel.Size = UDim2.new(1, -28, 1, 0)
		else
			local row = create("TextButton", {
				Name = "Option_" .. index,
				LayoutOrder = index,
				Size = UDim2.new(1, 0, 0, 32),
				BackgroundColor3 = selected and self.Theme.RowSelected or Color3.fromRGB(255, 255, 255),
				BackgroundTransparency = selected and 0.88 or 1,
				BorderSizePixel = 0,
				AutoButtonColor = false,
				Text = "",
			}, self.OptionList)

			if selected then
				create("Frame", {
					Name = "SelBar",
					Size = UDim2.new(0, 3, 1, 0),
					BackgroundColor3 = Color3.fromRGB(255, 255, 255),
					BackgroundTransparency = 0.15,
					BorderSizePixel = 0,
				}, row)
			end

			local textColor = selected and Color3.fromRGB(255, 255, 255) or self.Theme.Text
			if option.Enabled == false then
				textColor = self.Theme.Disabled
			end

			local nameLabel = label(row, option.Name, 13, textColor,
				selected and Enum.Font.GothamMedium or Enum.Font.Gotham)
			nameLabel.Position = UDim2.fromOffset(14, 0)
			nameLabel.Size = UDim2.new(0.62, -14, 1, 0)

			local valueText = ""
			local valueColor = self.Theme.Value
			if option.Type == "Toggle" then
				valueText = option.Value and "●" or "○"
				valueColor = option.Value and self.Theme.Success or self.Theme.Muted
			elseif option.Type == "List" then
				valueText = "< " .. tostring(option.Value or "—") .. " >"
			elseif option.Type == "Slider" then
				valueText = tostring(option.Value)
			elseif option.Type == "Button" then
				valueText = ""
			end

			if option.Enabled == false then
				valueColor = self.Theme.Disabled
			end

			local valueLabel = label(row, valueText, 12, valueColor, Enum.Font.Gotham)
			valueLabel.Name = "Value"
			valueLabel.AnchorPoint = Vector2.new(1, 0)
			valueLabel.Position = UDim2.new(1, -14, 0, 0)
			valueLabel.Size = UDim2.new(0.38, 0, 1, 0)
			valueLabel.TextXAlignment = Enum.TextXAlignment.Right

			row.Activated:Connect(function()
				if option.Enabled == false then return end
				self.ActiveOptionIndex = index
				self:_renderOptions()
				self:_updateDescription()
				self:ActivateSelection()
			end)

			self:_bindHover(row, selected)
			self._rowButtons[index] = row
		end
	end

	local selectedRow = self._rowButtons[self.ActiveOptionIndex]
	if selectedRow then
		local relativeY = selectedRow.AbsolutePosition.Y - self.OptionList.AbsolutePosition.Y + self.OptionList.CanvasPosition.Y
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
		or "Choose a category."
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
	self:_renderOptions()
	self:_updateHeader()
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
	if not option or option.Enabled == false then return end

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
	if not option or option.Enabled == false then return end

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
	self:SetVisible(false)
end

function ModMenu:SetStatus(text, color)
	if self.CategoryLabel then
		self.CategoryLabel.Text = tostring(text or "")
		if color then self.CategoryLabel.TextColor3 = color end
	end
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
	self:_clearHoverConnections()
	if self.Gui then self.Gui:Destroy() end
end

return ModMenu
