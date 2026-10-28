-- source.luau
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")

local ModMenu = {}
ModMenu.__index = ModMenu

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
local SEPARATOR_HEIGHT = 24
local DEFAULT_WIDTH = 360
local DEFAULT_HEIGHT = 440
local CONFIG_VERSION = 1

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

local function roundToStep(value, step)
	local precision = 0
	local stepString = tostring(step)
	local decimal = string.find(stepString, "%.")
	if decimal then precision = #stepString - decimal end
	return tonumber(string.format("%." .. math.min(precision, 6) .. "f", value)) or value
end

local function sanitizeName(name)
	return (tostring(name):gsub("[^%w_%-]", "_"))
end

local function envFunction(name)
	local ok, env = pcall(getfenv)
	if ok and type(env) == "table" then
		local fn = env[name]
		if type(fn) == "function" then return fn end
	end
	return nil
end

local function createDefaultStorage(folder)
	local writeFile = envFunction("writefile")
	local readFile = envFunction("readfile")
	local isFile = envFunction("isfile")

	if writeFile and readFile and isFile then
		local isFolder = envFunction("isfolder")
		local makeFolder = envFunction("makefolder")
		local delFile = envFunction("delfile")
		pcall(function()
			if isFolder and makeFolder and not isFolder(folder) then makeFolder(folder) end
		end)

		local function pathFor(name)
			return folder .. "/" .. sanitizeName(name) .. ".json"
		end

		return {
			Persistent = true,
			Save = function(name, text)
				writeFile(pathFor(name), text)
			end,
			Load = function(name)
				local path = pathFor(name)
				if isFile(path) then return readFile(path) end
				return nil
			end,
			Delete = function(name)
				local path = pathFor(name)
				if delFile and isFile(path) then
					delFile(path)
					return true
				end
				return false
			end,
		}
	end

	local memory = {}
	return {
		Persistent = false,
		Save = function(name, text) memory[name] = text end,
		Load = function(name) return memory[name] end,
		Delete = function(name)
			local existed = memory[name] ~= nil
			memory[name] = nil
			return existed
		end,
	}
end

local function coerceValue(option, value)
	if option.Type == "Toggle" then
		if type(value) == "boolean" then return true, value end
	elseif option.Type == "List" then
		if table.find(option.Values, value) ~= nil then return true, value end
	elseif option.Type == "Slider" then
		if type(value) == "number" then
			return true, roundToStep(math.clamp(value, option.Min, option.Max), option.Step)
		end
	end
	return false, nil
end

local function isPersistable(option)
	return (option.Type == "Toggle" or option.Type == "List" or option.Type == "Slider")
		and option.Persist ~= false
end

local function baseKey(tab, option)
	return option.Flag or (tab.Name .. "/" .. option.Name)
end

local function optionKey(tab, index)
	local base = baseKey(tab, tab.Options[index])
	local count = 0
	for i = 1, index do
		if baseKey(tab, tab.Options[i]) == base then count += 1 end
	end
	return count > 1 and (base .. "#" .. count) or base
end

local function getRegistry()
	local getGenv = envFunction("getgenv")
	local holder = getGenv and getGenv() or _G
	if type(holder) ~= "table" then holder = _G end
	if type(holder.__ModMenuInstances) ~= "table" then
		holder.__ModMenuInstances = {}
	end
	return holder.__ModMenuInstances
end

function ModMenu.new(config)
	config = config or {}

	local player = Players.LocalPlayer
	assert(player, "ModMenu.new() must be called from a LocalScript")
	local playerGui = player:WaitForChild("PlayerGui")

	local guiName = config.GuiName or "iSPLOIT"
	local registry = getRegistry()
	local previous = registry[guiName]
	local carry = nil
	if previous then
		carry = {
			Visible = previous.Visible,
			Position = previous._position,
			UserMoved = previous._userMoved,
		}
		pcall(function() previous:Destroy() end)
		registry[guiName] = nil
	end
	local stale = playerGui:FindFirstChild(guiName)
	if stale then stale:Destroy() end

	local self = setmetatable({}, ModMenu)
	self._guiName = guiName
	registry[guiName] = self

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
	self._sliderHits = {}
	self._hoverConnections = {}
	self._dim = config.Dim or 1 

	local touchDevice = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
	if config.TouchMode ~= nil then touchDevice = config.TouchMode == true end
	self._isTouch = touchDevice
	self._rowHeight = touchDevice and 38 or 32          -- bigger tap targets on touch
	self._refHeight = config.ReferenceHeight or (touchDevice and 520 or 720)
	self._minScale = config.MinScale or (touchDevice and 0.8 or 0.6)
	self._maxScale = config.MaxScale or 1
	self._userScale = config.Scale or 1
	self._baseWidth = (config.Size and config.Size.X.Offset > 0) and config.Size.X.Offset or DEFAULT_WIDTH
	self._baseHeight = (config.Size and config.Size.Y.Offset > 0) and config.Size.Y.Offset or DEFAULT_HEIGHT
	self._height = self._baseHeight
	self._scale = 1
	self._position = Vector2.new(0, 0)
	self._userMoved = false
	self._configPosition = config.Position
	self._dragging = false

	self.ConfigName = config.ConfigName or "Slot 1"
	self.ConfigFolder = config.ConfigFolder or "ModMenu"
	self.Storage = config.Storage or createDefaultStorage(self.ConfigFolder)
	self.AutoSave = config.AutoSave == true
	self._autoSavePending = false
	self._loaded = nil
	self._notifyToken = 0

	self.Gui = create("ScreenGui", {
		Name = guiName,
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = config.DisplayOrder or 50,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Enabled = true,
	}, playerGui)
	pcall(function()
		self.Gui.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets
	end)

	self.Overlay = create("Frame", {
		Name = "Overlay",
		BackgroundColor3 = self.Theme.Overlay,
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Visible = false,
		BorderSizePixel = 0,
	}, self.Gui)

	self.Main = create("Frame", {
		Name = "Main",
		AnchorPoint = Vector2.new(0, 0),
		Position = UDim2.fromOffset(0, 0),
		Size = UDim2.fromOffset(self._baseWidth, self._baseHeight),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Visible = false,
		ClipsDescendants = true,
	}, self.Overlay)
	self.MainScale = create("UIScale", { Scale = 1 }, self.Main)

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

	self.SubtitleLabel = label(self.Header, string.upper(self.Subtitle), 10,
		Color3.fromRGB(215, 225, 235), Enum.Font.GothamMedium)
	self.SubtitleLabel.Name = "Subtitle"
	self.SubtitleLabel.AnchorPoint = Vector2.new(0, 1)
	self.SubtitleLabel.Position = UDim2.new(0, 16, 1, -6)
	self.SubtitleLabel.Size = UDim2.new(1, -32, 0, 14)
	self.SubtitleLabel.TextXAlignment = Enum.TextXAlignment.Center
	self.SubtitleLabel.Visible = self.Subtitle ~= ""

	self.DragArea = create("Frame", {
		Name = "DragArea",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Active = true,
		ZIndex = 3,
	}, self.Header)
	self.DragArea.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			self:_beginDrag(input)
		end
	end)

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
	self.CategoryLabel.Size = UDim2.new(1, -124, 1, 0)

	local function tabButton(name, text, xOffset)
		local button = create("TextButton", {
			Name = name,
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, xOffset, 0, 0),
			Size = UDim2.fromOffset(30, SUBBAR_HEIGHT),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			AutoButtonColor = false,
			Text = text,
			TextColor3 = self.Theme.Text,
			Font = Enum.Font.GothamBold,
			TextSize = 14,
		}, self.SubBar)
		return button
	end

	self.NextTabButton = tabButton("NextTab", ">", -4)
	self.NextTabButton.Activated:Connect(function() self:ChangeTab(1) end)

	self.PageLabel = label(self.SubBar, "1 / 1", 11, self.Theme.Muted, Enum.Font.GothamMedium)
	self.PageLabel.Name = "Page"
	self.PageLabel.AnchorPoint = Vector2.new(1, 0)
	self.PageLabel.Position = UDim2.new(1, -34, 0, 0)
	self.PageLabel.Size = UDim2.fromOffset(44, SUBBAR_HEIGHT)
	self.PageLabel.TextXAlignment = Enum.TextXAlignment.Center

	self.PrevTabButton = tabButton("PrevTab", "<", -78)
	self.PrevTabButton.Activated:Connect(function() self:ChangeTab(-1) end)

	local listTop = HEADER_HEIGHT + SUBBAR_HEIGHT
	self.OptionList = create("ScrollingFrame", {
		Name = "OptionList",
		Position = UDim2.fromOffset(0, listTop),
		Size = UDim2.new(1, 0, 1, -(listTop + FOOTER_HEIGHT)),
		BackgroundColor3 = self.Theme.Panel,
		BackgroundTransparency = PANEL_TRANSPARENCY,
		BorderSizePixel = 0,
		ScrollBarThickness = self._isTouch and 4 or 3,
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

	if config.MobileButton == true or (config.MobileButton ~= false and self._isTouch) then
		self._showButton = true
		local button = create("TextButton", {
			Name = "MobileToggle",
			AnchorPoint = Vector2.new(1, 0.5),
			Position = config.ButtonPosition or UDim2.new(1, -12, 0.5, 0),
			Size = UDim2.fromOffset(46, 46),
			BackgroundColor3 = Color3.fromRGB(0, 0, 0),
			BackgroundTransparency = 0.35,
			BorderSizePixel = 0,
			AutoButtonColor = false,
			Text = "",
			Visible = true,
		}, self.Gui)
		create("UIStroke", {
			Color = Color3.fromRGB(255, 255, 255),
			Thickness = 1,
			Transparency = 0.6,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		}, button)
		for i = 0, 2 do
			create("Frame", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.new(0.5, 0, 0.5, (i - 1) * 7),
				Size = UDim2.fromOffset(20, 2),
				BackgroundColor3 = Color3.fromRGB(255, 255, 255),
				BorderSizePixel = 0,
			}, button)
		end
		self.MobileScale = create("UIScale", { Scale = 1 }, button)
		button.Activated:Connect(function()
			self:Toggle()
		end)
		self.MobileButton = button
	end

	self:_connectInput()

	table.insert(self._connections, self.Gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		self:_updateLayout()
	end))
	self:_updateLayout()
	self:SetVisible(false)

	if carry then
		if carry.UserMoved then
			self._userMoved = true
			self._position = self:_clampPosition(carry.Position)
		end
		if carry.Visible then self:SetVisible(true) end
	end

	if config.AutoLoad then
		self:LoadConfig(nil, true)
	end

	return self
end

function ModMenu:_getViewport()
	local size = self.Gui.AbsoluteSize
	if size.X > 0 and size.Y > 0 then return size end
	local camera = workspace.CurrentCamera
	if camera then return camera.ViewportSize end
	return Vector2.new(1280, 720)
end

function ModMenu:_clampPosition(position)
	local viewport = self:_getViewport()
	local width = self._baseWidth * self._scale
	local height = self._height * self._scale
	return Vector2.new(
		math.clamp(position.X, 0, math.max(viewport.X - width, 0)),
		math.clamp(position.Y, 0, math.max(viewport.Y - height, 0))
	)
end

function ModMenu:_isCentered()
	return not self._userMoved and not self._configPosition
end

function ModMenu:_positionProps(xShift)
	if self:_isCentered() then
		return Vector2.new(0.5, 0.5), UDim2.new(0.5, xShift, 0.5, 0)
	end
	return Vector2.new(0, 0), UDim2.fromOffset(self._position.X + xShift, self._position.Y)
end

function ModMenu:_applyPosition()
	local anchor, position = self:_positionProps(0)
	self.Main.AnchorPoint = anchor
	self.Main.Position = position
end

function ModMenu:_updateLayout()
	if self._destroyed then return end
	local viewport = self:_getViewport()

	local scale = math.clamp(viewport.Y / self._refHeight, self._minScale, self._maxScale) * self._userScale
	local maxWidth = viewport.X * 0.96
	if self._baseWidth * scale > maxWidth then
		scale = maxWidth / self._baseWidth
	end
	scale = math.max(scale, 0.3)

	local height = math.min(self._baseHeight, (viewport.Y * 0.94) / scale)

	self._scale = scale
	self._height = height
	self.MainScale.Scale = scale
	self.Main.Size = UDim2.fromOffset(self._baseWidth, height)
	if self.MobileScale then
		self.MobileScale.Scale = math.clamp(scale, 0.9, 1.2)
	end

	if not self._userMoved and self._configPosition then
		local cp = self._configPosition
		self._position = Vector2.new(
			cp.X.Scale * viewport.X + cp.X.Offset,
			cp.Y.Scale * viewport.Y + cp.Y.Offset
		)
	end
	if not self:_isCentered() then
		self._position = self:_clampPosition(self._position)
	end
	if self.Visible then self:_applyPosition() end
end

function ModMenu:_beginDrag(input)
	if self._slideTween then self._slideTween:Cancel() end
	if self:_isCentered() then
		self._position = self.Main.AbsolutePosition - self.Overlay.AbsolutePosition
		self._userMoved = true
		self:_applyPosition()
	end
	self._dragging = true
	self._dragInput = input
	self._dragStart = Vector2.new(input.Position.X, input.Position.Y)
	self._dragOrigin = self._position
end

function ModMenu:_updateDrag(input)
	local delta = Vector2.new(input.Position.X, input.Position.Y) - self._dragStart
	self._userMoved = true
	self._position = self:_clampPosition(self._dragOrigin + delta)
	self:_applyPosition()
end

function ModMenu:ResetPosition()
	self._userMoved = false
	self:_updateLayout()
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

	table.insert(self._connections, UserInputService.InputChanged:Connect(function(input)
		if self._destroyed then return end

		if self._dragging
			and (input == self._dragInput or input.UserInputType == Enum.UserInputType.MouseMovement) then
			self:_updateDrag(input)
		end

		local drag = self._sliderDrag
		if drag and (input == drag.input or input.UserInputType == Enum.UserInputType.MouseMovement) then
			local hit = self._sliderHits[drag.index]
			if hit and hit.Parent then
				local value = self:_sliderValueFromX(drag.option, hit, input.Position.X)
				if value ~= drag.option.Value then
					self:_setOptionValue(drag.option, value)
				end
			end
		end
	end))

	table.insert(self._connections, UserInputService.InputEnded:Connect(function(input)
		if input.KeyCode == Enum.KeyCode.ButtonL1 then self._lbDown = false end
		if input.KeyCode == Enum.KeyCode.ButtonR3 then self._r3Down = false end

		if self._dragging
			and (input == self._dragInput or input.UserInputType == Enum.UserInputType.MouseButton1) then
			self._dragging = false
		end

		local drag = self._sliderDrag
		if drag and (input == drag.input or input.UserInputType == Enum.UserInputType.MouseButton1) then
			self._sliderDrag = nil
		end
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

	if not self.Visible then
		self._dragging = false
		self._sliderDrag = nil
	else
		self.Overlay.BackgroundTransparency = 1
		local anchor, startPosition = self:_positionProps(-24)
		local _, endPosition = self:_positionProps(0)
		self.Main.AnchorPoint = anchor
		self.Main.Position = startPosition
		if self._dim < 1 then
			tween(self.Overlay, { BackgroundTransparency = self._dim }, 0.15)
		end
		if self._slideTween then self._slideTween:Cancel() end
		self._slideTween = tween(self.Main, { Position = endPosition }, 0.14)
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
	if isPersistable(option) then
		option.Default = option.Value
	end
	table.insert(tab.Options, option)

	if self._loaded and isPersistable(option) then
		local stored = self._loaded[optionKey(tab, #tab.Options)]
		if stored ~= nil then
			local ok, value = coerceValue(option, stored)
			if ok then
				option.Value = value
				self:_fireCallback(option)
			end
		end
	end

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

function ModMenu:AddConfigTab(tabName, slotCount)
	local tab = self:AddTab(tabName or "Config")

	local slots = {}
	for i = 1, math.max(slotCount or 5, 1) do
		slots[i] = "Slot " .. i
	end
	if not table.find(slots, self.ConfigName) then
		table.insert(slots, 1, self.ConfigName)
	end

	self:AddSeparator("Profile", tab)
	local slotOption = self:AddList("Save Slot", slots, self.ConfigName, function(value)
		self.ConfigName = tostring(value)
	end, "Choose which save slot Save, Load and Delete use.", tab)
	slotOption.Persist = false

	self:AddButton("Save Configuration", function()
		self:SaveConfig()
	end, "Save every toggle, list and slider to the selected slot.", tab)
	self:AddButton("Load Configuration", function()
		self:LoadConfig()
	end, "Load the selected slot and apply it.", tab)
	self:AddButton("Delete Configuration", function()
		self:DeleteConfig()
	end, "Delete the selected slot.", tab)

	self:AddSeparator("Options", tab)
	local autoSave = self:AddToggle("Auto Save", self.AutoSave, function(value)
		self.AutoSave = value
		if value then self:_queueAutoSave() end
	end, "Automatically save to the selected slot whenever a value changes.", tab)
	autoSave.Persist = false

	self:AddButton("Reset To Defaults", function()
		self:ResetConfig()
	end, "Put every option back to the value it was created with.", tab)

	return tab
end

function ModMenu:_fireCallback(option)
	if type(option.Callback) == "function" then
		task.spawn(function()
			local ok, err = pcall(option.Callback, option.Value, option)
			if not ok then warn("Option callback failed:", err) end
		end)
	end
end

function ModMenu:_collectOptions()
	local result = {}
	for _, tab in ipairs(self.Tabs) do
		for index, option in ipairs(tab.Options) do
			if isPersistable(option) then
				result[optionKey(tab, index)] = option
			end
		end
	end
	return result
end

function ModMenu:Notify(text, duration)
	self._notifyToken += 1
	local token = self._notifyToken
	self.Description.Text = tostring(text or "")
	task.delay(duration or 2, function()
		if not self._destroyed and self._notifyToken == token then
			self:_updateDescription()
		end
	end)
end

function ModMenu:ExportConfig()
	local values = {}
	for key, option in pairs(self:_collectOptions()) do
		local valueType = type(option.Value)
		if valueType == "string" or valueType == "number" or valueType == "boolean" then
			values[key] = option.Value
		end
	end
	local ok, encoded = pcall(function()
		return HttpService:JSONEncode({ Version = CONFIG_VERSION, Values = values })
	end)
	if ok then return encoded end
	return nil, tostring(encoded)
end

function ModMenu:ImportConfig(text)
	local ok, decoded = pcall(function()
		return HttpService:JSONDecode(text)
	end)
	if not ok or type(decoded) ~= "table" or type(decoded.Values) ~= "table" then
		return false, "Invalid configuration data"
	end

	self._loaded = decoded.Values
	local applied = 0
	for key, option in pairs(self:_collectOptions()) do
		local stored = self._loaded[key]
		if stored ~= nil then
			local valid, value = coerceValue(option, stored)
			if valid then
				option.Value = value
				applied += 1
				self:_fireCallback(option)
			end
		end
	end

	self:_renderOptions()
	self:_updateDescription()
	return true, applied
end

function ModMenu:SaveConfig(name, silent)
	name = name or self.ConfigName
	local encoded, encodeError = self:ExportConfig()
	if not encoded then
		warn("Could not encode configuration:", encodeError)
		if not silent then self:Notify("Save failed") end
		return false
	end

	local ok, err = pcall(self.Storage.Save, name, encoded)
	if not ok then
		warn("Could not save configuration:", err)
		if not silent then self:Notify("Save failed") end
		return false
	end

	if self.Storage.Persistent == false and not self._warnedMemory then
		self._warnedMemory = true
	end
	if not silent then
		self:Notify(self.Storage.Persistent == false and "Saved (this session only)" or ("Saved: " .. name))
	end
	return true
end

function ModMenu:LoadConfig(name, silent)
	name = name or self.ConfigName
	local ok, text = pcall(self.Storage.Load, name)
	if not ok then
		warn("Could not load configuration:", text)
		if not silent then self:Notify("Load failed") end
		return false
	end
	if type(text) ~= "string" or text == "" then
		if not silent then self:Notify("No save found: " .. name) end
		return false
	end

	local imported, info = self:ImportConfig(text)
	if not imported then
		warn("", info)
		if not silent then self:Notify("Save is corrupted") end
		return false
	end
	if not silent then self:Notify("Loaded: " .. name) end
	return true
end

function ModMenu:DeleteConfig(name, silent)
	name = name or self.ConfigName
	local deleted = false
	if type(self.Storage.Delete) == "function" then
		local ok, result = pcall(self.Storage.Delete, name)
		deleted = ok and result ~= false
	end
	if not silent then
		self:Notify(deleted and ("Deleted: " .. name) or ("Nothing to delete: " .. name))
	end
	return deleted
end

function ModMenu:ResetConfig(silent)
	self._loaded = nil
	for _, option in pairs(self:_collectOptions()) do
		if option.Default ~= nil and option.Value ~= option.Default then
			option.Value = option.Default
			self:_fireCallback(option)
		end
	end
	self:_renderOptions()
	self:_updateDescription()
	if not silent then self:Notify("Defaults restored") end
end

function ModMenu:_queueAutoSave()
	if not self.AutoSave or self._autoSavePending or self._destroyed then return end
	self._autoSavePending = true
	task.delay(1, function()
		self._autoSavePending = false
		if not self._destroyed and self.AutoSave then
			self:SaveConfig(nil, true)
		end
	end)
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
	self._sliderHits = {}
	self:_clearHoverConnections()
end

function ModMenu:_buildCheckbox(row, isOn, color)
	local box = create("Frame", {
		Name = "Checkbox",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -14, 0.5, 0),
		Size = UDim2.fromOffset(18, 18),
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
			Size = UDim2.fromOffset(10, 10),
			BackgroundColor3 = color,
			BorderSizePixel = 0,
		}, box)
	end
	return box
end

function ModMenu:_makeArrow(parent, text, anchorX, color, height, callback)
	local button = create("TextButton", {
		Name = anchorX == 0 and "Prev" or "Next",
		AnchorPoint = Vector2.new(anchorX, 0),
		Position = UDim2.new(anchorX, 0, 0, 0),
		Size = UDim2.fromOffset(26, height),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Text = text,
		TextColor3 = color,
		Font = Enum.Font.GothamBold,
		TextSize = 14,
	}, parent)
	button.Activated:Connect(callback)
	return button
end

function ModMenu:_sliderValueFromX(option, hit, x)
	local fraction = math.clamp((x - hit.AbsolutePosition.X) / math.max(hit.AbsoluteSize.X, 1), 0, 1)
	local raw = option.Min + fraction * (option.Max - option.Min)
	local stepped = option.Min + math.floor((raw - option.Min) / option.Step + 0.5) * option.Step
	return roundToStep(math.clamp(stepped, option.Min, option.Max), option.Step)
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
	local rowHeight = self._rowHeight
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
				Size = UDim2.new(1, 0, 0, rowHeight),
				BackgroundColor3 = theme.Highlight,
				BackgroundTransparency = selected and 0 or 1,
				BorderSizePixel = 0,
				AutoButtonColor = false,
				Text = "",
			}, self.OptionList)

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
				reserve = 148
			elseif option.Type == "Slider" then
				reserve = 182
			end

			local nameLabel = label(row, option.Name, 13, textColor,
				selected and Enum.Font.GothamMedium or Enum.Font.Gotham)
			nameLabel.Position = UDim2.fromOffset(14, 0)
			nameLabel.Size = UDim2.new(1, -(14 + reserve), 1, 0)

			local function step(direction)
				return function()
					if option.Enabled == false then return end
					self.ActiveOptionIndex = index
					self:AdjustSelection(direction)
				end
			end

			if option.Type == "Toggle" then
				self:_buildCheckbox(row, option.Value == true, valueColor)

			elseif option.Type == "List" then
				local area = create("Frame", {
					Name = "ValueArea",
					AnchorPoint = Vector2.new(1, 0),
					Position = UDim2.new(1, -8, 0, 0),
					Size = UDim2.fromOffset(126, rowHeight),
					BackgroundTransparency = 1,
					BorderSizePixel = 0,
				}, row)
				self:_makeArrow(area, "<", 0, valueColor, rowHeight, step(-1))
				self:_makeArrow(area, ">", 1, valueColor, rowHeight, step(1))
				local valueLabel = label(area, tostring(option.Value or "-"), 12, valueColor, Enum.Font.Gotham)
				valueLabel.Name = "Value"
				valueLabel.Position = UDim2.fromOffset(26, 0)
				valueLabel.Size = UDim2.new(1, -52, 1, 0)
				valueLabel.TextXAlignment = Enum.TextXAlignment.Center

			elseif option.Type == "Slider" then
				local area = create("Frame", {
					Name = "ValueArea",
					AnchorPoint = Vector2.new(1, 0),
					Position = UDim2.new(1, -8, 0, 0),
					Size = UDim2.fromOffset(160, rowHeight),
					BackgroundTransparency = 1,
					BorderSizePixel = 0,
				}, row)
				self:_makeArrow(area, "<", 0, valueColor, rowHeight, step(-1))
				self:_makeArrow(area, ">", 1, valueColor, rowHeight, step(1))

				local hit = create("TextButton", {
					Name = "Track",
					Position = UDim2.fromOffset(30, 0),
					Size = UDim2.fromOffset(56, rowHeight),
					BackgroundTransparency = 1,
					BorderSizePixel = 0,
					AutoButtonColor = false,
					Text = "",
				}, area)
				local bar = create("Frame", {
					Name = "Bar",
					AnchorPoint = Vector2.new(0, 0.5),
					Position = UDim2.fromScale(0, 0.5),
					Size = UDim2.new(1, 0, 0, 4),
					BackgroundColor3 = selected and Color3.fromRGB(190, 190, 190) or Color3.fromRGB(70, 74, 78),
					BorderSizePixel = 0,
				}, hit)
				local range = option.Max - option.Min
				local fraction = range > 0 and (option.Value - option.Min) / range or 0
				create("Frame", {
					Name = "Fill",
					Size = UDim2.fromScale(math.clamp(fraction, 0, 1), 1),
					BackgroundColor3 = disabled and theme.Disabled
						or (selected and theme.SelectedText or theme.Accent),
					BorderSizePixel = 0,
				}, bar)
				self._sliderHits[index] = hit

				hit.InputBegan:Connect(function(input)
					if option.Enabled == false then return end
					if input.UserInputType ~= Enum.UserInputType.MouseButton1
						and input.UserInputType ~= Enum.UserInputType.Touch then
						return
					end
					self._sliderDrag = { option = option, index = index, input = input }
					self.ActiveOptionIndex = index
					local value = self:_sliderValueFromX(option, hit, input.Position.X)
					if value ~= option.Value then
						self:_setOptionValue(option, value)
					else
						self:_renderOptions()
						self:_updateDescription()
					end
				end)

				local valueLabel = label(area, tostring(option.Value), 12, valueColor, Enum.Font.Gotham)
				valueLabel.Name = "Value"
				valueLabel.Position = UDim2.fromOffset(90, 0)
				valueLabel.Size = UDim2.fromOffset(44, rowHeight)
				valueLabel.TextXAlignment = Enum.TextXAlignment.Center
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
			offsetY += rowHeight
		end
	end

	local rowTop = self._rowOffsets[self.ActiveOptionIndex]
	if rowTop then
		local rowSize = (tab.Options[self.ActiveOptionIndex].Type == "Separator") and SEPARATOR_HEIGHT or rowHeight
		local viewTop = self.OptionList.CanvasPosition.Y
		local viewHeight = self.OptionList.AbsoluteWindowSize.Y / math.max(self._scale, 0.01)
		if rowTop < viewTop then
			self.OptionList.CanvasPosition = Vector2.new(0, rowTop)
		elseif rowTop + rowSize > viewTop + viewHeight then
			self.OptionList.CanvasPosition = Vector2.new(0, rowTop + rowSize - viewHeight)
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
	self._sliderDrag = nil
	self.ActiveTabIndex = ((self.ActiveTabIndex - 1 + direction) % #self.Tabs) + 1
	self.ActiveOptionIndex = 1
	self.OptionList.CanvasPosition = Vector2.new(0, 0)
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
	self:_fireCallback(option)
	self:_queueAutoSave()
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
		self:_setOptionValue(option, roundToStep(nextValue, option.Step))
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
				if not ok then warn("Button callback failed:", err) end
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
	if not suppressCallback then
		self:_fireCallback(option)
	end
	self:_queueAutoSave()
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
	local registry = getRegistry()
	if registry[self._guiName] == self then registry[self._guiName] = nil end
	if self.Gui then self.Gui:Destroy() end
end

return ModMenu
