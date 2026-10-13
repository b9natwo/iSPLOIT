-- source.luau
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")

local ModMenu = {}
ModMenu.__index = ModMenu

-- GTA V interaction-menu look:
-- black translucent rows, white selected row with dark text,
-- one muted accent colour used only on the header, slider fill and scrollbar.
local DEFAULT_THEME = {
	Accent       = Color3.fromRGB(88, 140, 196),  -- header / slider fill / scrollbar
	Panel        = Color3.fromRGB(0, 0, 0),       -- list + footer + sub bar background
	Highlight    = Color3.fromRGB(255, 255, 255), -- selected row
	SelectedText = Color3.fromRGB(12, 12, 12),    -- text on selected row
	Text         = Color3.fromRGB(235, 235, 235),
	Muted        = Color3.fromRGB(150, 155, 160),
	Disabled     = Color3.fromRGB(85, 88, 92),
	Overlay      = Color3.fromRGB(0, 0, 0),
}

local PANEL_TRANSPARENCY = 0.4
local HEADER_HEIGHT = 66
local SUBBAR_HEIGHT = 28
local FOOTER_HEIGHT = 56
local ROW_HEIGHT = 32
local SEPARATOR_HEIGHT = 24

local function create(className, properties, parent)
	local object = Instance.new(className)
	for key, value in pairs(properties or {}) do
		object[key] = value
	end
	object.Parent = parent
	return object
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

local function darken(color, amount)
	return Color3.new(color.R * (1 - amount), color.G * (1 - amount), color.B * (1 - amount))
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
	self._rowOffsets = {}
	self._hoverConnections = {}
	self._dim = config.Dim or 1 -- background transparency of the full-screen dim (1 = none)

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

	self.Overlay = create("Frame", {
		Name = "Overlay",
		BackgroundColor3 = self.Theme.Overlay,
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Visible = false,
		BorderSizePixel = 0,
	}, self.Gui)

	-- Main container (transparent; each section draws its own background)
	self._basePosition = config.Position or UDim2.new(0, 40, 0.5, 0)
	self.Main = create("Frame", {
		Name = "Main",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = self._basePosition,
		Size = config.Size or UDim2.fromOffset(330, 440),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Visible = false,
		ClipsDescendants = true,
	}, self.Overlay)

	-- Header banner
	self.Header = create("Frame", {
		Name = "Header",
		Size = UDim2.new(1, 0, 0, HEADER_HEIGHT),
		BackgroundColor3 = self.Theme.Accent,
		BorderSizePixel = 0,
	}, self.Main)
	create("UIGradient", {
		Color = ColorSequence.new(self.Theme.Accent, darken(self.Theme.Accent, 0.55)),
		Rotation = 90,
	}, self.Header)

	self.TitleLabel = label(self.Header, self.Title, 24, Color3.fromRGB(255, 255, 255), Enum.Font.GothamBlack)
	self.TitleLabel.Name = "Title"
	self.TitleLabel.Position = UDim2.fromOffset(16, 0)
	self.TitleLabel.Size = UDim2.new(1, -32, 1, self.Subtitle ~= "" and -16 or 0)
	self.TitleLabel.TextXAlignment = Enum.TextXAlignment.Center
	self.TitleLabel.TextTransparency = 0

	self.SubtitleLabel = label(self.Header, string.upper(self.Subtitle), 10,
		Color3.fromRGB(215, 225, 235), Enum.Font.GothamMedium)
	self.SubtitleLabel.Name = "Subtitle"
	self.SubtitleLabel.AnchorPoint = Vector2.new(0, 1)
	self.SubtitleLabel.Position = UDim2.new(0, 16, 1, -6)
	self.SubtitleLabel.Size = UDim2.new(1, -32, 0, 14)
	self.SubtitleLabel.TextXAlignment = Enum.TextXAlignment.Center
	self.SubtitleLabel.Visible = self.Subtitle ~= ""

	-- Category bar (category name + page)
	self.SubBar = create("Frame", {
		Name = "SubBar",
		Position = UDim2.fromOffset(0, HEADER_HEIGHT),
		Size = UDim2.new(1, 0, 0, SUBBAR_HEIGHT),
		BackgroundColor3 = self.Theme.Panel,
		BackgroundTransparency = 0.2,
		BorderSizePixel = 0,
	}, self.Main)

	self.CategoryLabel = label(self.SubBar, "", 12, self.Theme.Text, Enum.Font.GothamBold)
	self.CategoryLabel.Name = "Category"
	self.CategoryLabel.Position = UDim2.fromOffset(14, 0)
	self.CategoryLabel.Size = UDim2.new(1, -90, 1, 0)

	self.PageLabel = label(self.SubBar, "1 / 1", 11, self.Theme.Muted, Enum.Font.GothamMedium)
	self.PageLabel.Name = "Page"
	self.PageLabel.AnchorPoint = Vector2.new(1, 0)
	self.PageLabel.Position = UDim2.new(1, -14, 0, 0)
	self.PageLabel.Size = UDim2.fromOffset(60, SUBBAR_HEIGHT)
	self.PageLabel.TextXAlignment = Enum.TextXAlignment.Right

	-- Option list
	local listTop = HEADER_HEIGHT + SUBBAR_HEIGHT
	self.OptionList = create("ScrollingFrame", {
		Name = "OptionList",
		Position = UDim2.fromOffset(0, listTop),
		Size = UDim2.new(1, 0, 1, -(listTop + FOOTER_HEIGHT)),
		BackgroundColor3 = self.Theme.Panel,
		BackgroundTransparency = PANEL_TRANSPARENCY,
		BorderSizePixel = 0,
		ScrollBarThickness = 3,
		ScrollBarImageColor3 = self.Theme.Accent,
		ScrollBarImageTransparency = 0,
		CanvasSize = UDim2.fromOffset(0, 0),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
	}, self.Main)
	create("UIListLayout", {
		Padding = UDim.new(0, 0),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, self.OptionList)

	-- Footer: description + item counter
	self.DescriptionBar = create("Frame", {
		Name = "DescriptionBar",
		Position = UDim2.new(0, 0, 1, -FOOTER_HEIGHT),
		Size = UDim2.new(1, 0, 0, FOOTER_HEIGHT),
		BackgroundColor3 = self.Theme.Panel,
		BackgroundTransparency = 0.2,
		BorderSizePixel = 0,
	}, self.Main)

	self.CounterLabel = label(self.DescriptionBar, "", 11, self.Theme.Muted, Enum.Font.GothamMedium)
	self.CounterLabel.Name = "Counter"
	self.CounterLabel.AnchorPoint = Vector2.new(1, 0)
	self.CounterLabel.Position = UDim2.new(1, -14, 0, 6)
	self.CounterLabel.Size = UDim2.fromOffset(60, 14)
	self.CounterLabel.TextXAlignment = Enum.TextXAlignment.Right

	self.Description = label(self.DescriptionBar, "Select an option.", 12,
		self.Theme.Text, Enum.Font.Gotham)
	self.Description.Position = UDim2.fromOffset(14, 6)
	self.Description.Size = UDim2.new(1, -90, 1, -12)
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
		-- quick slide-in from the left, like the game menu
		self.Overlay.BackgroundTransparency = 1
		self.Main.Position = self._basePosition - UDim2.fromOffset(24, 0)
		if self._dim < 1 then
			tween(self.Overlay, { BackgroundTransparency = self._dim }, 0.15)
		end
		tween(self.Main, { Position = self._basePosition }, 0.14)
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
		tween(button, { BackgroundTransparency = 0.88 }, 0.08)
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
	self.CategoryLabel.TextColor3 = self.Theme.Text
	self.TitleLabel.Text = self.Title
end

function ModMenu:_updateCounter()
	local tab = self:_activeTab()
	if not tab or #tab.Options == 0 then
		self.CounterLabel.Text = ""
		return
	end
	-- count only selectable rows so separators don't skew the number
	local total, current = 0, 0
	for index, option in ipairs(tab.Options) do
		if option.Type ~= "Separator" then
			total += 1
			if index == self.ActiveOptionIndex then current = total end
		end
	end
	self.CounterLabel.Text = string.format("%d / %d", current, total)
end

function ModMenu:_clearOptionRows()
	for _, child in ipairs(self.OptionList:GetChildren()) do
		if child:IsA("GuiObject") then child:Destroy() end
	end
	self._rowButtons = {}
	self._rowOffsets = {}
	self:_clearHoverConnections()
end

-- Plain checkbox: outlined square, filled when on. No colour coding.
function ModMenu:_buildCheckbox(row, isOn, color)
	local box = create("Frame", {
		Name = "Checkbox",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -14, 0.5, 0),
		Size = UDim2.fromOffset(16, 16),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
	}, row)
	create("UIStroke", {
		Color = color,
		Thickness = 1.5,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	}, box)
	if isOn then
		create("Frame", {
			Name = "Fill",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(8, 8),
			BackgroundColor3 = color,
			BorderSizePixel = 0,
		}, box)
	end
	return box
end

function ModMenu:_renderOptions()
	self:_clearOptionRows()
	self:_updateCounter()
	local tab = self:_activeTab()
	if not tab then return end

	if #tab.Options == 0 then
		local empty = label(self.OptionList, "No options.", 13, self.Theme.Muted)
		empty.Size = UDim2.new(1, -20, 0, 36)
		empty.Position = UDim2.fromOffset(14, 0)
		return
	end

	self.ActiveOptionIndex = math.clamp(self.ActiveOptionIndex, 1, #tab.Options)

	local theme = self.Theme
	local offsetY = 0

	for index, option in ipairs(tab.Options) do
		local selected = index == self.ActiveOptionIndex
		self._rowOffsets[index] = offsetY

		if option.Type == "Separator" then
			local sep = create("Frame", {
				Name = "Separator_" .. index,
				LayoutOrder = index,
				Size = UDim2.new(1, 0, 0, SEPARATOR_HEIGHT),
				BackgroundColor3 = Color3.fromRGB(0, 0, 0),
				BackgroundTransparency = 0.45,
				BorderSizePixel = 0,
			}, self.OptionList)
			local sepLabel = label(sep, string.upper(option.Name), 10, theme.Muted, Enum.Font.GothamBold)
			sepLabel.Position = UDim2.fromOffset(14, 0)
			sepLabel.Size = UDim2.new(1, -28, 1, 0)
			offsetY += SEPARATOR_HEIGHT
		else
			local disabled = option.Enabled == false

			local row = create("TextButton", {
				Name = "Option_" .. index,
				LayoutOrder = index,
				Size = UDim2.new(1, 0, 0, ROW_HEIGHT),
				BackgroundColor3 = theme.Highlight,
				BackgroundTransparency = selected and 0 or 1,
				BorderSizePixel = 0,
				AutoButtonColor = false,
				Text = "",
			}, self.OptionList)

			-- text colour: dark on the white selected row, light otherwise
			local textColor = selected and theme.SelectedText or theme.Text
			local valueColor = selected and theme.SelectedText or theme.Text
			if disabled then
				textColor = theme.Disabled
				valueColor = theme.Disabled
			end

			local reserve = 14
			if option.Type == "Toggle" then
				reserve = 46
			elseif option.Type == "List" then
				reserve = 130
			elseif option.Type == "Slider" then
				reserve = 170
			end

			local nameLabel = label(row, option.Name, 13, textColor,
				selected and Enum.Font.GothamMedium or Enum.Font.Gotham)
			nameLabel.Position = UDim2.fromOffset(14, 0)
			nameLabel.Size = UDim2.new(1, -(14 + reserve), 1, 0)

			if option.Type == "Toggle" then
				self:_buildCheckbox(row, option.Value == true, valueColor)

			elseif option.Type == "List" then
				local valueLabel = label(row, "<  " .. tostring(option.Value or "-") .. "  >", 12,
					valueColor, Enum.Font.Gotham)
				valueLabel.Name = "Value"
				valueLabel.AnchorPoint = Vector2.new(1, 0)
				valueLabel.Position = UDim2.new(1, -14, 0, 0)
				valueLabel.Size = UDim2.fromOffset(120, ROW_HEIGHT)
				valueLabel.TextXAlignment = Enum.TextXAlignment.Right

			elseif option.Type == "Slider" then
				local valueLabel = label(row, tostring(option.Value), 12, valueColor, Enum.Font.Gotham)
				valueLabel.Name = "Value"
				valueLabel.AnchorPoint = Vector2.new(1, 0)
				valueLabel.Position = UDim2.new(1, -14, 0, 0)
				valueLabel.Size = UDim2.fromOffset(44, ROW_HEIGHT)
				valueLabel.TextXAlignment = Enum.TextXAlignment.Right

				local track = create("Frame", {
					Name = "Track",
					AnchorPoint = Vector2.new(1, 0.5),
					Position = UDim2.new(1, -66, 0.5, 0),
					Size = UDim2.fromOffset(70, 4),
					BackgroundColor3 = selected and Color3.fromRGB(190, 190, 190) or Color3.fromRGB(70, 74, 78),
					BorderSizePixel = 0,
				}, row)
				local range = option.Max - option.Min
				local fraction = range > 0 and (option.Value - option.Min) / range or 0
				create("Frame", {
					Name = "Fill",
					Size = UDim2.fromScale(math.clamp(fraction, 0, 1), 1),
					BackgroundColor3 = disabled and theme.Disabled
						or (selected and theme.SelectedText or theme.Accent),
					BorderSizePixel = 0,
				}, track)
			end

			row.Activated:Connect(function()
				if option.Enabled == false then return end
				self.ActiveOptionIndex = index
				self:_renderOptions()
				self:_updateDescription()
				self:ActivateSelection()
			end)

			self:_bindHover(row, selected)
			self._rowButtons[index] = row
			offsetY += ROW_HEIGHT
		end
	end

	-- keep the selected row in view (uses computed offsets, so it's layout-independent)
	local rowTop = self._rowOffsets[self.ActiveOptionIndex]
	if rowTop then
		local rowHeight = (tab.Options[self.ActiveOptionIndex].Type == "Separator") and SEPARATOR_HEIGHT or ROW_HEIGHT
		local viewTop = self.OptionList.CanvasPosition.Y
		local viewHeight = self.OptionList.AbsoluteWindowSize.Y
		if rowTop < viewTop then
			self.OptionList.CanvasPosition = Vector2.new(0, rowTop)
		elseif rowTop + rowHeight > viewTop + viewHeight then
			self.OptionList.CanvasPosition = Vector2.new(0, rowTop + rowHeight - viewHeight)
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
	self.OptionList.CanvasPosition = Vector2.new(0, 0)
	-- land on the first selectable row
	local tab = self:_activeTab()
	if tab and tab.Options[1] and tab.Options[1].Type == "Separator" then
		for i, opt in ipairs(tab.Options) do
			if opt.Type ~= "Separator" then
				self.ActiveOptionIndex = i
				break
			end
		end
	end
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
