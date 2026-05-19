--[[
	Withdraw / KuromiWare UI adapter for Compkiller (NewUI.lua).
	Exposes the same API surface as test.lua (GUI:Load, Tab, SubTab, Section, flags, configs).
]]

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")

local COMPKILLER_URL = "https://raw.githubusercontent.com/kitty92pm/AirHub-V2/refs/heads/main/beta/NewUI.lua"

local function httpGet(url)
	if typeof(game.HttpGet) == "function" then
		return game:HttpGet(url)
	end
	if typeof(game.HttpGetAsync) == "function" then
		return game:HttpGetAsync(url)
	end
	error("[KWUI] HttpGet is not available")
end

local function loadCompkiller()
	if getgenv().KW_Compkiller then
		return getgenv().KW_Compkiller
	end
	local ok, result = pcall(function()
		local src = httpGet(COMPKILLER_URL)
		local fn, err = loadstring(src, "NewUI.lua")
		if not fn then
			error(err or "loadstring failed")
		end
		return fn()
	end)
	if ok and result then
		getgenv().KW_Compkiller = result
		return result
	end
	error("[KWUI] Could not load Compkiller: " .. tostring(result))
end

local Compkiller = loadCompkiller()

local TAB_ICONS = {
	["Aim"] = "crosshair",
	["Silent"] = "target",
	["Visual"] = "eye",
	["Exploits"] = "zap",
	["Misc"] = "package",
	["World"] = "globe",
	["Effects"] = "sparkles",
	["HUD"] = "layout-dashboard",
	["Settings"] = "settings",
}

local function keyToEnum(key)
	if typeof(key) == "EnumItem" then
		return key
	end
	if type(key) == "string" and key ~= "" and Enum.KeyCode[key] then
		return Enum.KeyCode[key]
	end
	return key
end

local function keyToString(key)
	if typeof(key) == "EnumItem" then
		return key.Name
	end
	return tostring(key or "")
end

local function colorFromHex(hex)
	if typeof(hex) ~= "string" then
		return Color3.new(1, 1, 1)
	end
	hex = hex:gsub("#", "")
	if #hex >= 6 and Color3.fromHex then
		local ok, c = pcall(Color3.fromHex, hex)
		if ok then
			return c
		end
	end
	if #hex >= 6 then
		return Color3.fromRGB(
			tonumber(hex:sub(1, 2), 16) or 255,
			tonumber(hex:sub(3, 4), 16) or 255,
			tonumber(hex:sub(5, 6), 16) or 255
		)
	end
	return Color3.new(1, 1, 1)
end

local function flagRead(entry)
	if not entry or not entry.GetValue then
		return nil
	end
	local v = entry:GetValue()
	if type(v) == "table" and v.ColorPicker then
		return v.ColorPicker.Color
	end
	if type(v) == "string" and Enum.KeyCode[v] then
		return Enum.KeyCode[v]
	end
	return v
end

local function flagWrite(entry, value)
	if not entry or not entry.SetValue then
		return
	end
	if typeof(value) == "EnumItem" then
		entry:SetValue(value.Name)
	elseif typeof(value) == "Color3" then
		entry:SetValue(value, 0)
	elseif type(value) == "table" and value.color then
		entry:SetValue(colorFromHex(value.color), value.alpha or 0)
	else
		entry:SetValue(value)
	end
end

local GUI = {
	folder = "withdraw",
	extension = "cfg",
	_window = nil,
	open = false,
}

GUI.flags = setmetatable({}, {
	__index = function(_, flag)
		return flagRead(Compkiller.Flags[flag])
	end,
	__newindex = function(_, flag, value)
		flagWrite(Compkiller.Flags[flag], value)
	end,
})

local function notify(title, content, duration)
	local win = GUI._window
	if win and win.Notify and win.Notify.new then
		pcall(function()
			win.Notify.new({
				Title = title or "Notice",
				Content = content or "",
				Duration = duration or 3,
				Icon = Compkiller.Logo,
			})
		end)
	end
end

function GUI:Notify(title, content, duration)
	notify(title, content, duration)
end

local function wrapSection(sectionApi)
	local api = {}

	function api:Toggle(opt)
		opt = opt or {}
		local onToggle = opt.Callback or opt.callback
		local elem = sectionApi:AddToggle({
			Name = opt.Name or "Toggle",
			Default = opt.Default == true,
			Flag = opt.Flag,
			Risky = opt.Risky,
			Callback = function(v)
				if onToggle then
					onToggle(v)
				end
			end,
		})
		return elem
	end

	function api:Slider(opt)
		opt = opt or {}
		local elem = sectionApi:AddSlider({
			Name = opt.Name or "Slider",
			Min = opt.Min or 0,
			Max = opt.Max or 100,
			Default = opt.Default or opt.Min or 0,
			Round = 0,
			Type = opt.Type or "",
			Flag = opt.Flag,
			Callback = function(v)
				if opt.Callback then
					opt.Callback(v)
				end
			end,
		})
		return elem
	end

	function api:Dropdown(opt)
		opt = opt or {}
		local values = opt.Content or opt.Values or {}
		local default = opt.Default
		if default == nil and values[1] then
			default = values[1]
		end
		local elem = sectionApi:AddDropdown({
			Name = opt.Name or "Dropdown",
			Default = default,
			Values = values,
			Multi = opt.Multi == true,
			Flag = opt.Flag,
			Callback = function(v)
				if opt.Multi then
					return
				end
				if opt.Callback then
					opt.Callback(v)
				end
			end,
		})
		local wrap = { _elem = elem }
		function wrap:Refresh(list)
			if self._elem and self._elem.SetValues then
				self._elem:SetValues(list or {})
			end
		end
		function wrap:Set(v)
			if self._elem and self._elem.SetValue then
				self._elem:SetValue(v)
			end
		end
		return wrap
	end

	function api:Colorpicker(opt)
		opt = opt or {}
		local elem = sectionApi:AddColorPicker({
			Name = opt.Name or "Color",
			Default = opt.Default or Color3.new(1, 1, 1),
			Transparency = opt.Transparency or 0,
			Flag = opt.Flag,
			Callback = function(c, _)
				if opt.Callback then
					opt.Callback(c)
				end
			end,
		})
		return elem
	end

	function api:Button(opt)
		opt = opt or {}
		return sectionApi:AddButton({
			Name = opt.Name or "Button",
			Callback = function()
				if opt.Callback then
					opt.Callback()
				end
			end,
		})
	end

	function api:Box(opt)
		opt = opt or {}
		local elem = sectionApi:AddTextBox({
			Name = opt.Name or "Input",
			Default = opt.Default or "",
			Placeholder = opt.Placeholder or "",
			Numeric = opt.Numeric == true,
			Flag = opt.Flag,
			Callback = function(v)
				if opt.Callback then
					opt.Callback(v)
				end
			end,
		})
		local wrap = { _elem = elem }
		function wrap:Set(v)
			if self._elem and self._elem.SetValue then
				self._elem:SetValue(v or "")
			end
		end
		return wrap
	end

	function api:Keybind(opt)
		opt = opt or {}
		local elem = sectionApi:AddKeybind({
			Name = opt.Name or "Keybind",
			Default = keyToString(opt.Default or "RightShift"),
			Flag = opt.Flag,
			Blacklist = opt.Blacklist or {},
			Callback = function(keyName)
				local key = keyToEnum(keyName)
				if opt.Callback then
					opt.Callback(key, key)
				end
			end,
		})
		return elem
	end

	return api
end

local function wrapSubTab(tabApi)
	local sub = {}
	function sub:Section(cfg)
		cfg = cfg or {}
		local side = cfg.Side or cfg.Position or "Left"
		local sectionApi = tabApi:DrawSection({
			Name = cfg.Name or "",
			Position = string.lower(side) == "right" and "right" or "left",
		})
		return wrapSection(sectionApi)
	end
	return sub
end

local containerRegistry = {}

local function wrapContainer(containerApi)
	containerApi.__kwSubSignals = containerApi.__kwSubSignals or {}
	table.insert(containerRegistry, containerApi)

	local tab = {}
	function tab:SubTab(name)
		local subApi = containerApi:DrawTab({
			Name = name,
			Type = "Double",
			EnableScrolling = true,
		})
		if subApi and subApi.__subSignal then
			table.insert(containerApi.__kwSubSignals, subApi.__subSignal)
			if #containerApi.__kwSubSignals > 1 then
				subApi.__subSignal:Fire(false)
			end
		end
		return wrapSubTab(subApi)
	end
	return tab
end

function GUI:FinalizeSubTabs()
	for _, containerApi in ipairs(containerRegistry) do
		local signals = containerApi.__kwSubSignals
		if signals then
			for i, signal in ipairs(signals) do
				signal:Fire(i == 1)
			end
		end
	end
end

function GUI:Load(options)
	options = options or {}
	if options.folder then
		self.folder = options.folder
	end
	if options.extension then
		self.extension = options.extension
	end

	pcall(function()
		Compkiller:SetTheme("Purple Rose")
	end)
	pcall(function()
		Compkiller:CustomIconHighlight()
	end)

	local w = options.sizex or 540
	local h = options.sizey or 720
	local lp = Players.LocalPlayer

	local window = Compkiller.new({
		Name = "withdraw.cc",
		Keybind = Enum.KeyCode.RightShift,
		Logo = Compkiller.Logo,
		Scale = UDim2.fromOffset(w, h),
		TextSize = 15,
	})

	window:Update({
		Username = lp and lp.DisplayName or "User",
		WindowName = "withdraw.cc",
		ExpireDate = "KuromiWare",
	})

	self._window = window
	self.open = true
	getgenv().LibraryOpen = true

	local root = {}
	function root:Tab(name)
		local icon = TAB_ICONS[name] or "layout"
		local container = window:DrawContainerTab({
			Name = name,
			Icon = icon,
		})
		return wrapContainer(container)
	end

	return root
end

function GUI:Close()
	local window = self._window
	if window and window._ToggleUI then
		window:_ToggleUI()
	end
	self.open = not self.open
	getgenv().LibraryOpen = self.open
end

function GUI:GetAutoloadPath()
	return string.format("%s//autoload.json", self.folder)
end

function GUI:GetAutoloadSettings()
	local defaults = { enabled = false, name = "default" }
	if typeof(readfile) ~= "function" or typeof(isfile) ~= "function" then
		return defaults.enabled, defaults.name
	end
	local path = self:GetAutoloadPath()
	if not isfile(path) then
		return defaults.enabled, defaults.name
	end
	local ok, data = pcall(function()
		return HttpService:JSONDecode(readfile(path))
	end)
	if ok and type(data) == "table" then
		local enabled = data.enabled == true
		local name = type(data.name) == "string" and data.name:gsub("%s", "_") or defaults.name
		if name == "" then
			name = defaults.name
		end
		return enabled, name
	end
	return defaults.enabled, defaults.name
end

function GUI:SetAutoloadSettings(enabled, name)
	name = type(name) == "string" and name:gsub("%s", "_") or ""
	if name == "" then
		name = "default"
	end
	if typeof(makefolder) == "function" and not isfolder(self.folder) then
		makefolder(self.folder)
	end
	if typeof(writefile) == "function" then
		writefile(self:GetAutoloadPath(), HttpService:JSONEncode({
			enabled = enabled == true,
			name = name,
		}))
	end
	return true
end

function GUI:ConfigExists(name)
	if type(name) ~= "string" or name == "" then
		return false
	end
	name = name:gsub("%s", "_")
	local filepath = string.format("%s//%s.%s", self.folder, name, self.extension)
	return isfolder(self.folder) and isfile(filepath)
end

function GUI:GetConfigs()
	local configs = {}
	if typeof(listfiles) ~= "function" or not isfolder(self.folder) then
		return configs
	end
	for _, path in ipairs(listfiles(self.folder)) do
		local name = path:gsub(self.folder .. "\\", ""):gsub(self.folder .. "/", ""):gsub("%." .. self.extension .. "$", "")
		if name ~= "" and name ~= "autoload" and not name:find("autoload") then
			table.insert(configs, name)
		end
	end
	table.sort(configs)
	return configs
end

function GUI:SaveConfig(name)
	if type(name) ~= "string" or not name:find("%S") then
		return false, "improper name"
	end
	name = name:gsub("%s", "_")
	if typeof(makefolder) == "function" and not isfolder(self.folder) then
		makefolder(self.folder)
	end

	local configtbl = {}
	for flag, entry in pairs(Compkiller.Flags) do
		if flag and entry and entry.GetValue then
			local value = flagRead(entry)
			if typeof(value) == "EnumItem" then
				configtbl[flag] = tostring(value)
			elseif typeof(value) == "Color3" then
				configtbl[flag] = { color = value:ToHex(), alpha = 0 }
			else
				configtbl[flag] = value
			end
		end
	end

	local filepath = string.format("%s//%s.%s", self.folder, name, self.extension)
	writefile(filepath, HttpService:JSONEncode(configtbl))
	return true
end

function GUI:LoadConfig(name)
	if type(name) ~= "string" or not name:find("%w") then
		return
	end
	name = name:gsub("%s", "_")
	local filepath = string.format("%s//%s.%s", self.folder, name, self.extension)
	if not isfolder(self.folder) or not isfile(filepath) then
		return
	end

	local ok, config = pcall(function()
		return HttpService:JSONDecode(readfile(filepath))
	end)
	if not ok or type(config) ~= "table" then
		return
	end

	for flag, v in pairs(config) do
		local entry = Compkiller.Flags[flag]
		if entry then
			if type(v) == "table" and v.color then
				flagWrite(entry, v)
			elseif type(v) == "string" and v:find("Enum%.KeyCode") then
				local keyName = v:match("Enum%.KeyCode%.(%w+)")
				if keyName then
					flagWrite(entry, keyName)
				end
			else
				flagWrite(entry, v)
			end
		end
	end

	rawset(GUI.flags, "Config Dropdown", name)
	if Compkiller.Flags["Config Dropdown"] and Compkiller.Flags["Config Dropdown"].SetValue then
		Compkiller.Flags["Config Dropdown"]:SetValue(name)
	end
end

function GUI:DeleteConfig(name)
	if type(name) ~= "string" then
		return
	end
	name = name:gsub("%s", "_")
	local filepath = string.format("%s//%s.%s", self.folder, name, self.extension)
	if isfile(filepath) and typeof(delfile) == "function" then
		delfile(filepath)
	end
end

function GUI:AutoloadConfig()
	local enabled, name = self:GetAutoloadSettings()
	if not enabled or name == "" then
		return false, "disabled"
	end
	if not self:ConfigExists(name) then
		return false, "missing"
	end
	self:LoadConfig(name)
	return true, name
end

return GUI
