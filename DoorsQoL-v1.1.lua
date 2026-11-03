--[[
    硬核 QoL v1.1 · 「v0.1 血条 + 独立雷达 + 迷你面板」

    和 v1.0 的区别（按需求改的）：
      · 主面板缩到 360x300，默认不弹（右下角一个 QoL 小按钮，点开才有）
      · 地图/雷达 = 独立小窗，自己开关（默认 M），可拖、可缩放，不塞进面板
      · 多人事件日志：整个删掉
      · 玩家信息页：删掉，用 v0.1 那条全员血条就够
      · 道具信息页：删掉，改成血条每一行下方一行小字（拿/用/丢实时变）
      · 动作系统：保留
      · 原版硬核脚本：修复 v0.1 里失效的备用地址，加载失败会在设置页写明原因

    手势：
      血条：拖标题挪位置 / 点标题折叠 / 上方「− 滑条 大小 100% ＋」调字号
      雷达：拖标题挪位置 / 点标题旁边的 × 关掉（M 再开）
      面板：右下角 QoL 按钮开关（RightShift 也行），拖顶栏移动

    只读 Humanoid.Health、Backpack 里的 Tool、CFrame 位置；不写任何游戏状态。
--]]

local CONFIG = {
	-- 原版硬核脚本：按顺序试，第一个成功的算数
	runOriginal = true,
	srcList = {
		"https://pastefy.app/Bf6hbDY4/raw",
		"https://raw.githubusercontent.com/Zero0Star/RipperNewSound/master/HardCoreLua.lua",
		"https://raw.githubusercontent.com/Zero0Star/RipperNewSound/master/HardCore-Mode.lua",
	},
	waitTimeout = 30,

	-- 血条 HUD
	refresh   = 0.25,
	showDist  = true,
	aliveOnly = false,
	sortByHp  = false,
	showItems = true,      -- 血条下方显示道具
	width     = 320,
	fontSize  = 15,
	sizeMin   = 10,
	sizeMax   = 26,
	topX      = 16,
	topY      = 96,

	-- 雷达小窗
	radarOn     = true,
	radarSize   = 168,
	radarSizeMin = 120,
	radarSizeMax = 320,
	radarRange  = 140,
	radarTopX   = 16,
	radarTopY   = 300,

	-- 迷你面板
	panelW = 360,
	panelH = 300,

	keys = { panel = "RightShift", radar = "M", dance = "K" },

	cfgFile = "QoL_v11.json",
}

local Players = game:GetService("Players")
local UIS     = game:GetService("UserInputService")
local HS      = game:GetService("HttpService")

local function lp()
	return Players.LocalPlayer
end

--=====================================================================
--  小工具
--=====================================================================
local function make(class, props, children)
	local inst
	local ok = pcall(function() inst = Instance.new(class) end)
	if not ok or not inst then return nil end
	if props then
		for k, v in pairs(props) do
			if k ~= "Parent" then pcall(function() inst[k] = v end) end
		end
	end
	if children then
		for _, c in ipairs(children) do
			if c then pcall(function() c.Parent = inst end) end
		end
	end
	if props and props.Parent then pcall(function() inst.Parent = props.Parent end) end
	return inst
end

local function attachGui(gui)
	local ok = pcall(function()
		local hui = gethui and gethui()
		if hui then gui.Parent = hui return end
		pcall(function() gui.Parent = game:GetService("CoreGui") end)
		if gui.Parent then return end
		gui.Parent = lp():WaitForChild("PlayerGui", 5)
	end)
	if not ok and lp() then
		pcall(function() gui.Parent = lp():WaitForChild("PlayerGui", 5) end)
	end
end

local function clamp(v, lo, hi)
	if v < lo then return lo end
	if v > hi then return hi end
	return v
end

local function round(n)
	return math.floor(n + 0.5)
end

local function jsonEncode(t)
	local parts = {}
	for k, v in pairs(t) do
		local vs
		if type(v) == "string" then
			vs = '"' .. v:gsub('\\', '\\\\'):gsub('"', '\\"') .. '"'
		elseif type(v) == "boolean" then
			vs = tostring(v)
		elseif type(v) == "number" then
			vs = tostring(round(v * 1000) / 1000)
		else
			vs = "null"
		end
		table.insert(parts, '"' .. k .. '":' .. vs)
	end
	return "{" .. table.concat(parts, ",") .. "}"
end

local function readCfg()
	if not (readfile and isfile) then return nil end
	local ok, raw = pcall(function()
		if isfile(CONFIG.cfgFile) then return readfile(CONFIG.cfgFile) end
	end)
	if not ok or type(raw) ~= "string" then return nil end
	local ok2, data = pcall(function() return HS:JSONDecode(raw) end)
	if ok2 and type(data) == "table" then return data end
	return nil
end

--=====================================================================
--  颜色 / 字体
--=====================================================================
local C_BG     = Color3.fromRGB(24, 26, 30)
local C_BG2    = Color3.fromRGB(32, 35, 41)
local C_TEXT   = Color3.fromRGB(234, 237, 242)
local C_DIM    = Color3.fromRGB(150, 158, 168)
local C_MUTE   = Color3.fromRGB(104, 112, 122)
local C_LINE   = Color3.fromRGB(70, 76, 86)
local ACCENT   = Color3.fromRGB(88, 226, 140)
local ACCENT_D = Color3.fromRGB(36, 92, 62)
local HP_GREEN = ACCENT
local HP_AMBER = Color3.fromRGB(255, 196, 84)
local HP_RED   = Color3.fromRGB(255, 96, 88)
local HP_DEAD  = Color3.fromRGB(126, 140, 134)
local C_BLUE   = Color3.fromRGB(108, 176, 255)

local FONT_BODY = Enum.Font.Gotham
local FONT_BOLD = Enum.Font.GothamSemibold

--=====================================================================
--  尺寸表：一切都从「字号」推
--=====================================================================
local SIZE_MIN = math.max(8, round(CONFIG.sizeMin or 10))
local SIZE_MAX = math.max(SIZE_MIN + 2, round(CONFIG.sizeMax or 26))
local BASE_FS  = math.max(8, round(CONFIG.fontSize or 15))

local function measure(fs)
	local f      = clamp(round(fs), SIZE_MIN, SIZE_MAX)
	local nameH  = round(f * 1.20)
	local rowPad = math.max(4, round(f * 0.38))
	local barH   = math.max(5, round(f * 0.42))
	local itemH  = round(f * 1.05)
	return {
		fs     = f,
		nameH  = nameH,
		rowPad = rowPad,
		barH   = barH,
		itemH  = itemH,
		rowH   = rowPad * 2 + nameH + barH,
		headH  = round(f * 2.05),
		side   = math.max(10, round(f * 0.80)),
		hpW    = round(f * 7.6),
		gap    = math.max(4, round(f * 0.35)),
		radius = math.max(4, round(f * 0.67)),
		width  = math.max(240, round((CONFIG.width or 320) * f / BASE_FS)),
	}
end

local M = measure(BASE_FS)

local function hpColor(r)
	if r <= 0 then return HP_DEAD end
	if r < 0.3 then return HP_RED end
	if r < 0.6 then return HP_AMBER end
	return HP_GREEN
end

local function pct(fs)
	return math.floor(fs / BASE_FS * 100 + 0.5)
end

--=====================================================================
--  运行状态（会写进配置文件）
--=====================================================================
local ST = {
	hudOn     = true,
	showItems = CONFIG.showItems and true or false,
	hudX      = nil,
	hudY      = nil,
	collapsed = false,

	radarOn   = CONFIG.radarOn and true or false,
	radarSize = CONFIG.radarSize,
	radarRange = CONFIG.radarRange,
	radarX    = nil,
	radarY    = nil,

	panelX    = nil,
	panelY    = nil,
	panelOpen = false,

	keys      = { panel = CONFIG.keys.panel, radar = CONFIG.keys.radar, dance = CONFIG.keys.dance },
	anim      = 1,
}

local function saveState()
	if not writefile then return end
	pcall(function()
		writefile(CONFIG.cfgFile, jsonEncode({
			hudOn = ST.hudOn, showItems = ST.showItems,
			hudX = ST.hudX or CONFIG.topX, hudY = ST.hudY or CONFIG.topY,
			collapsed = ST.collapsed, fs = M.fs,
			radarOn = ST.radarOn, radarSize = ST.radarSize, radarRange = ST.radarRange,
			radarX = ST.radarX or CONFIG.radarTopX, radarY = ST.radarY or CONFIG.radarTopY,
			panelX = ST.panelX or 40, panelY = ST.panelY or 120,
			anim = ST.anim,
			kPanel = ST.keys.panel, kRadar = ST.keys.radar, kDance = ST.keys.dance,
		}))
	end)
end

--=====================================================================
--  前向声明（下面的拖动回调要引用这些表）
--=====================================================================
local HPHud, Radar, Panel, Dance, loadOriginal
local ORIGINAL_STATUS = "尝试中…"

--=====================================================================
--  拖动 / 滑块：全模块只挂一套输入
--=====================================================================
local DRAG = { mode = nil }

local function dragEnd()
	local mode = DRAG.mode
	DRAG.mode = nil
	if mode == "size" and HPHud.applySize then
		local v = DRAG.fs
		DRAG.fs = nil
		if v then HPHud.applySize(v) end
	elseif mode == "slider" then
		local cb, v = DRAG.commit, DRAG.value
		DRAG.commit, DRAG.value = nil, nil
		if cb and v then pcall(cb, v) end
	elseif mode == "hud" then
		local obj = DRAG.obj
		if obj then
			local abs, size = obj.AbsolutePosition, (HPHud.gui and HPHud.gui.AbsoluteSize) or Vector2.new(1280, 720)
			ST.hudX = math.max(0, round((size.X or 1280) - (abs.X + obj.AbsoluteSize.X)))
			ST.hudY = math.max(0, round(abs.Y))
			if not DRAG.moved then
				ST.collapsed = not ST.collapsed
				if HPHud.update then pcall(HPHud.update) end
			end
			saveState()
		end
	elseif mode == "radar" then
		local obj = DRAG.obj
		if obj then
			local abs, size = obj.AbsolutePosition, (Radar.gui and Radar.gui.AbsoluteSize) or Vector2.new(1280, 720)
			ST.radarX = math.max(0, round((size.X or 1280) - (abs.X + obj.AbsoluteSize.X)))
			ST.radarY = math.max(0, round(abs.Y))
			saveState()
		end
	elseif mode == "panel" then
		local obj = DRAG.obj
		if obj then
			local abs = obj.AbsolutePosition
			ST.panelX = round(abs.X)
			ST.panelY = round(abs.Y)
			saveState()
		end
	end
	DRAG.obj, DRAG.moved = nil, false
end

UIS.InputChanged:Connect(function(input)
	if not DRAG.mode then return end
	if input.UserInputType ~= Enum.UserInputType.MouseMovement
		and input.UserInputType ~= Enum.UserInputType.Touch then return end
	local d = input.Position - (DRAG.start or input.Position)
	if math.abs(d.X) + math.abs(d.Y) > 3 then DRAG.moved = true end

	if DRAG.mode == "size" then
		local track = DRAG.track
		if track and track.Parent then
			local w = track.AbsoluteSize.X
			if w and w > 0 then
				local t = clamp((input.Position.X - track.AbsolutePosition.X) / w, 0, 1)
				local fs = SIZE_MIN + t * (SIZE_MAX - SIZE_MIN)
				DRAG.fs = clamp(round(fs), SIZE_MIN, SIZE_MAX)
				if DRAG.fill then
					DRAG.fill.Size = UDim2.new((DRAG.fs - SIZE_MIN) / math.max(1, SIZE_MAX - SIZE_MIN), 0, 1, 0)
				end
				if DRAG.label then DRAG.label.Text = string.format("大小 %d%%", pct(DRAG.fs)) end
			end
		end
	elseif DRAG.mode == "slider" then
		local track = DRAG.track
		if track and track.Parent then
			local w = track.AbsoluteSize.X
			if w and w > 0 then
				local t = clamp((input.Position.X - track.AbsolutePosition.X) / w, 0, 1)
				local v = DRAG.min + t * (DRAG.max - DRAG.min)
				if DRAG.step then v = round(v / DRAG.step) * DRAG.step end
				DRAG.value = v
				if DRAG.fill then DRAG.fill.Size = UDim2.new(t, 0, 1, 0) end
				if DRAG.label then DRAG.label.Text = DRAG.fmt and DRAG.fmt(v) or tostring(v) end
				if DRAG.onLive then pcall(DRAG.onLive, v) end
			end
		end
	elseif DRAG.moved and DRAG.obj then
		local d2 = input.Position - (DRAG.start or input.Position)
		local nx = (DRAG.sx or 0) + d2.X
		local ny = (DRAG.sy or 0) + d2.Y
		DRAG.obj.Position = UDim2.new(0, round(nx), 0, round(ny))
	end
end)

UIS.InputEnded:Connect(function(input)
	if not DRAG.mode then return end
	if input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch then
		dragEnd()
	end
end)

local function beginMove(mode, obj, input)
	if not obj then return end
	DRAG.mode  = mode
	DRAG.obj   = obj
	DRAG.start = input.Position
	DRAG.sx    = obj.AbsolutePosition.X
	DRAG.sy    = obj.AbsolutePosition.Y
	DRAG.moved = false
	obj.AnchorPoint = Vector2.new(0, 0)
end

local function beginSlider(conf, input)
	DRAG.mode  = "slider"
	DRAG.start = input.Position
	DRAG.track = conf.track
	DRAG.fill  = conf.fill
	DRAG.label = conf.label
	DRAG.min, DRAG.max = conf.min, conf.max
	DRAG.step  = conf.step
	DRAG.fmt   = conf.fmt
	DRAG.onLive = conf.onLive
	DRAG.commit = conf.onCommit
	DRAG.value  = conf.value
	if conf.track and conf.track.Parent then
		local w = conf.track.AbsoluteSize.X
		if w and w > 0 then
			local t = clamp((input.Position.X - conf.track.AbsolutePosition.X) / w, 0, 1)
			local v = conf.min + t * (conf.max - conf.min)
			if conf.step then v = round(v / conf.step) * conf.step end
			DRAG.value = v
			if conf.fill then conf.fill.Size = UDim2.new(t, 0, 1, 0) end
			if conf.label then conf.label.Text = conf.fmt and conf.fmt(v) or tostring(v) end
		end
	end
end

--=====================================================================
--  道具读取（只读 Tool 名字，不猜内容）
--=====================================================================
local function toolNames(pl)
	local out, seen = {}, {}
	local function add(container, suffix)
		if not container then return end
		local ok, kids = pcall(function() return container:GetChildren() end)
		if not ok or not kids then return end
		for _, t in ipairs(kids) do
			if t:IsA("Tool") and not seen[t] then
				seen[t] = true
				table.insert(out, t.Name .. (suffix or ""))
			end
		end
	end
	if pl.Character then add(pl.Character, "（手持）") end
	local bp = pl:FindFirstChildOfClass("Backpack")
	if bp then add(bp, "") end
	table.sort(out)
	return out
end

--=====================================================================
--  全员血量 HUD（v0.1 的底子 + 道具行）
--=====================================================================
HPHud = {
	gui = nil, root = nil, header = nil, title = nil, bar = nil,
	rows = {}, running = false,
}

local function hpRow(i)
	local frame = make("Frame", {
		Name = "R" .. i,
		Size = UDim2.new(1, 0, 0, M.rowH),
		BackgroundColor3 = C_BG,
		BackgroundTransparency = 0.42,
		BorderSizePixel = 0,
		LayoutOrder = i,
		Visible = false,
	})
	make("UICorner", { CornerRadius = UDim.new(0, M.radius), Parent = frame })

	local name = make("TextLabel", {
		Text = "",
		Size = UDim2.new(1, -(M.side * 2 + M.hpW), 0, M.nameH),
		Position = UDim2.new(0, M.side, 0, M.rowPad),
		BackgroundTransparency = 1,
		Font = FONT_BOLD,
		TextSize = M.fs,
		TextColor3 = C_TEXT,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Parent = frame,
	})
	local hp = make("TextLabel", {
		Text = "",
		Size = UDim2.new(0, M.hpW, 0, M.nameH),
		Position = UDim2.new(1, -(M.side + M.hpW), 0, M.rowPad),
		BackgroundTransparency = 1,
		Font = FONT_BOLD,
		TextSize = M.fs,
		TextColor3 = C_TEXT,
		TextXAlignment = Enum.TextXAlignment.Right,
		Parent = frame,
	})

	local track = make("Frame", {
		Name = "Track",
		Size = UDim2.new(1, -(M.side * 2), 0, M.barH),
		Position = UDim2.new(0, M.side, 0, M.rowPad + M.nameH),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 0.86,
		BorderSizePixel = 0,
		Parent = frame,
	})
	make("UICorner", { CornerRadius = UDim.new(1, 0), Parent = track })
	local fill = make("Frame", {
		Name = "Fill",
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundColor3 = HP_GREEN,
		BorderSizePixel = 0,
		Parent = track,
	})
	make("UICorner", { CornerRadius = UDim.new(1, 0), Parent = fill })

	-- 道具行（血条下面那行小字）
	local items = make("TextLabel", {
		Name = "Items",
		Text = "",
		Size = UDim2.new(1, -(M.side * 2), 0, M.itemH),
		Position = UDim2.new(0, M.side, 0, M.rowPad + M.nameH + M.barH + 1),
		BackgroundTransparency = 1,
		Font = FONT_BODY,
		TextSize = math.max(9, round(M.fs * 0.74)),
		TextColor3 = C_MUTE,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Visible = false,
		Parent = frame,
	})

	return { frame = frame, name = name, hp = hp, fill = fill, items = items }
end

function HPHud.ensure()
	if HPHud.gui and HPHud.gui.Parent then return HPHud.gui end
	if HPHud.gui and not HPHud.gui.Parent and lp() then
		attachGui(HPHud.gui)
		if HPHud.gui.Parent then return HPHud.gui end
	end

	local gui = make("ScreenGui", {
		Name = "SG_HP_v11",
		IgnoreGuiInset = true,
		ResetOnSpawn = false,
		DisplayOrder = 999997,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	})
	attachGui(gui)
	HPHud.gui = gui

	local root = make("Frame", {
		Name = "Root",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -(ST.hudX or CONFIG.topX), 0, ST.hudY or CONFIG.topY),
		Size = UDim2.new(0, M.width, 0, M.headH),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Visible = ST.hudOn,
		Parent = gui,
	})
	make("UIListLayout", {
		Padding = UDim.new(0, M.gap),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = root,
	})
	HPHud.root = root

	-- 大小条
	local barH = clamp(round(M.fs * 1.75), 26, 40)
	local btn  = clamp(round(barH * 0.85), 20, 32)
	local lbW  = clamp(round(M.fs * 5.6), 72, 104)
	local lbTS = clamp(round(M.fs * 0.72), 12, 17)

	local bar = make("Frame", {
		Name = "SizeBar",
		Size = UDim2.new(1, 0, 0, barH),
		BackgroundColor3 = C_BG,
		BackgroundTransparency = 0.30,
		BorderSizePixel = 0,
		LayoutOrder = -1,
		Parent = root,
	})
	make("UICorner", { CornerRadius = UDim.new(0, M.radius), Parent = bar })
	make("UIStroke", { Color = C_LINE, Thickness = 1, Transparency = 0.55, Parent = bar })
	HPHud.bar = bar

	local function stepBtn(text, rightSide)
		local b = make("TextButton", {
			Text = text,
			Size = UDim2.new(0, btn, 0, btn),
			Position = rightSide and UDim2.new(1, -6, 0.5, 0) or UDim2.new(0, 6, 0.5, 0),
			AnchorPoint = rightSide and Vector2.new(1, 0.5) or Vector2.new(0, 0.5),
			BackgroundColor3 = Color3.new(1, 1, 1),
			BackgroundTransparency = 0.86,
			BorderSizePixel = 0,
			Font = FONT_BOLD,
			TextSize = clamp(round(btn * 0.80), 13, 22),
			TextColor3 = C_TEXT,
			Parent = bar,
		})
		make("UICorner", { CornerRadius = UDim.new(0, 6), Parent = b })
		return b
	end

	local minus = stepBtn("−", false)
	local plus  = stepBtn("+", true)
	if minus then minus.Activated:Connect(function() HPHud.applySize(M.fs - 1) end) end
	if plus then plus.Activated:Connect(function() HPHud.applySize(M.fs + 1) end) end

	local sTrack = make("Frame", {
		Name = "SizeTrack",
		Size = UDim2.new(1, -(2 * btn + lbW + 28), 0, 8),
		Position = UDim2.new(0, btn + 12, 0.5, 0),
		AnchorPoint = Vector2.new(0, 0.5),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 0.86,
		BorderSizePixel = 0,
		Parent = bar,
	})
	make("UICorner", { CornerRadius = UDim.new(1, 0), Parent = sTrack })
	local sFill = make("Frame", {
		Name = "Fill",
		Size = UDim2.new((M.fs - SIZE_MIN) / math.max(1, SIZE_MAX - SIZE_MIN), 0, 1, 0),
		BackgroundColor3 = HP_GREEN,
		BorderSizePixel = 0,
		Parent = sTrack,
	})
	make("UICorner", { CornerRadius = UDim.new(1, 0), Parent = sFill })

	local sLabel = make("TextButton", {
		Name = "SizeLabel",
		Text = string.format("大小 %d%%", pct(M.fs)),
		Size = UDim2.new(0, lbW, 1, 0),
		Position = UDim2.new(1, -(btn + 10), 0.5, 0),
		AnchorPoint = Vector2.new(1, 0.5),
		AutoButtonColor = false,
		BackgroundTransparency = 1,
		Font = FONT_BOLD,
		TextSize = lbTS,
		TextColor3 = C_DIM,
		Parent = bar,
	})
	if sLabel then sLabel.Activated:Connect(function() HPHud.applySize(BASE_FS) end) end

	local function bindTrack(obj)
		if not obj then return end
		obj.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1
				or input.UserInputType == Enum.UserInputType.Touch then
				DRAG.mode  = "size"
				DRAG.start = input.Position
				DRAG.track = sTrack
				DRAG.fill  = sFill
				DRAG.label = sLabel
				DRAG.fs    = M.fs
			end
		end)
	end
	bindTrack(sTrack)
	bindTrack(sFill)

	-- 标题栏
	local header = make("Frame", {
		Name = "Header",
		Size = UDim2.new(1, 0, 0, M.headH),
		BackgroundColor3 = C_BG,
		BackgroundTransparency = 0.28,
		BorderSizePixel = 0,
		Active = true,
		LayoutOrder = 0,
		Parent = root,
	})
	make("UICorner", { CornerRadius = UDim.new(0, M.radius + 1), Parent = header })
	make("UIStroke", { Color = C_LINE, Thickness = 1.5, Transparency = 0.45, Parent = header })
	HPHud.header = header

	HPHud.title = make("TextLabel", {
		Text = "全员血量",
		Size = UDim2.new(1, -(M.side * 2), 1, 0),
		Position = UDim2.new(0, M.side, 0, 0),
		BackgroundTransparency = 1,
		Font = FONT_BOLD,
		TextSize = M.fs,
		TextColor3 = C_TEXT,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = header,
	})

	local function bindDrag(obj)
		if not obj then return end
		obj.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1
				or input.UserInputType == Enum.UserInputType.Touch then
				beginMove("hud", root, input)
			end
		end)
	end
	bindDrag(header)
	bindDrag(HPHud.title)

	return gui
end

function HPHud.applySize(fs, noSave)
	local f = clamp(round(fs), SIZE_MIN, SIZE_MAX)
	if f == M.fs then return end
	M = measure(f)
	DRAG.mode = nil
	if HPHud.gui then pcall(function() HPHud.gui:Destroy() end) end
	HPHud.gui, HPHud.root, HPHud.header, HPHud.title, HPHud.bar = nil, nil, nil, nil, nil
	HPHud.rows = {}
	if not noSave then saveState() end
	if lp() then pcall(HPHud.ensure) end
	if HPHud.update then pcall(HPHud.update) end
end

function HPHud.setVisible(on)
	ST.hudOn = on and true or false
	if HPHud.root then HPHud.root.Visible = ST.hudOn end
	if not ST.hudOn then
		if HPHud.gui then pcall(function() HPHud.gui.Enabled = false end) end
	else
		if HPHud.gui then pcall(function() HPHud.gui.Enabled = true end) end
	end
	saveState()
end

function HPHud.update()
	if not ST.hudOn then return end
	if not (HPHud.gui and HPHud.gui.Parent) then return end
	HPHud.ensure()

	local me = lp()
	local lpRoot = me and me.Character and me.Character:FindFirstChild("HumanoidRootPart")

	local data = {}
	for _, pl in ipairs(Players:GetPlayers()) do
		local char = pl.Character
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		local hp = (hum and hum.Health) or 0
		local max = (hum and hum.MaxHealth) or 100
		if not max or max <= 0 then max = 100 end
		local dead = (not hum) or hp <= 0.01
		if not (CONFIG.aliveOnly and dead) then
			local dist
			if CONFIG.showDist and char and lpRoot then
				local rp = char:FindFirstChild("HumanoidRootPart")
					or char:FindFirstChild("UpperTorso")
					or char:FindFirstChild("Torso")
				if rp then
					local ok, m = pcall(function() return (lpRoot.Position - rp.Position).Magnitude end)
					if ok and m then dist = round(m) end
				end
			end
			local items
			if ST.showItems then
				local ok, names = pcall(toolNames, pl)
				if ok and names and #names > 0 then items = table.concat(names, " · ") end
			end
			table.insert(data, { name = pl.Name, hp = hp, max = max, dead = dead,
				dist = dist, me = (pl == me), items = items })
		end
	end

	if CONFIG.sortByHp then
		table.sort(data, function(a, b)
			if a.dead ~= b.dead then return b.dead end
			return a.hp > b.hp
		end)
	end

	if HPHud.bar then HPHud.bar.Visible = not ST.collapsed end
	if HPHud.title then
		HPHud.title.Text = string.format("全员血量 · %d 人%s", #data, ST.collapsed and "  ▸" or "")
	end

	for i, d in ipairs(data) do
		local r = HPHud.rows[i]
		if not r then
			r = hpRow(i)
			HPHud.rows[i] = r
		end
		if r.frame.Parent ~= HPHud.root then r.frame.Parent = HPHud.root end

		local rowH = M.rowH + (d.items and (M.itemH + 2) or 0)
		r.frame.Visible = not ST.collapsed
		r.frame.Size = UDim2.new(1, 0, 0, rowH)
		r.frame.LayoutOrder = i
		r.frame.BackgroundColor3 = C_BG

		r.name.TextColor3 = d.me and HP_GREEN or C_TEXT
		r.hp.TextColor3 = d.dead and C_DIM or C_TEXT

		local label = d.name
		if d.me then label = "你 · " .. label end
		if d.dist then label = label .. "  " .. d.dist .. "m" end
		r.name.Text = label

		if r.items then
			r.items.Visible = (d.items ~= nil) and not ST.collapsed
			if d.items then
				r.items.Text = "道具  " .. d.items
				r.items.TextColor3 = d.dead and C_MUTE or C_DIM
				r.items.TextSize = math.max(9, round(M.fs * 0.74))
			end
		end

		if d.dead then
			r.hp.Text = "已倒下"
			r.fill.Size = UDim2.new(0, 0, 1, 0)
			r.fill.BackgroundColor3 = HP_DEAD
		else
			r.hp.Text = string.format("%d / %d", round(d.hp), round(d.max))
			local ratio = clamp(d.hp / d.max, 0, 1)
			r.fill.Size = UDim2.new(ratio, 0, 1, 0)
			r.fill.BackgroundColor3 = hpColor(ratio)
		end
	end

	for i = #data + 1, #HPHud.rows do
		HPHud.rows[i].frame.Visible = false
	end
end

function HPHud.start()
	if HPHud.running then return end
	HPHud.running = true
	task.spawn(function()
		local waited = 0
		while not lp() and waited < CONFIG.waitTimeout do
			task.wait(0.2)
			waited = waited + 0.2
		end
		if lp() then pcall(HPHud.ensure) end
		while HPHud.running do
			pcall(HPHud.update)
			task.wait(CONFIG.refresh)
		end
	end)
end

--=====================================================================
--  雷达（独立小窗，自己开关）
--=====================================================================
Radar = { gui = nil, root = nil, canvas = nil, dots = {}, rings = {}, title = nil, running = false }

local function radarPoint(rel, half, range)
	local px = half + (rel.X / range) * half
	local pz = half - (-rel.Z / range) * half   -- rel.Z 是「向后」，取负 = 向前 → 屏幕上
	return px, pz
end

function Radar.build()
	if Radar.gui and Radar.gui.Parent then return Radar.gui end

	local gui = make("ScreenGui", {
		Name = "SG_QoL_Radar",
		IgnoreGuiInset = true,
		ResetOnSpawn = false,
		DisplayOrder = 999996,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	})
	attachGui(gui)
	Radar.gui = gui

	local size = clamp(round(ST.radarSize or CONFIG.radarSize), CONFIG.radarSizeMin, CONFIG.radarSizeMax)
	local headH = 18

	local root = make("Frame", {
		Name = "Root",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -(ST.radarX or CONFIG.radarTopX), 0, ST.radarY or CONFIG.radarTopY),
		Size = UDim2.new(0, size, 0, size + headH),
		BackgroundColor3 = C_BG,
		BackgroundTransparency = 0.35,
		BorderSizePixel = 0,
		Visible = ST.radarOn,
		Parent = gui,
	})
	make("UICorner", { CornerRadius = UDim.new(0, 8), Parent = root })
	make("UIStroke", { Color = C_LINE, Thickness = 1, Transparency = 0.5, Parent = root })
	Radar.root = root

	local head = make("Frame", {
		Name = "Head",
		Size = UDim2.new(1, 0, 0, headH),
		BackgroundColor3 = C_BG2,
		BackgroundTransparency = 0.2,
		BorderSizePixel = 0,
		Active = true,
		Parent = root,
	})
	make("UICorner", { CornerRadius = UDim.new(0, 7), Parent = head })
	Radar.title = make("TextLabel", {
		Text = "雷达",
		Size = UDim2.new(1, -30, 1, 0),
		Position = UDim2.new(0, 8, 0, 0),
		BackgroundTransparency = 1,
		Font = FONT_BOLD,
		TextSize = 11,
		TextColor3 = C_DIM,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = head,
	})
	local close = make("TextButton", {
		Text = "×",
		Size = UDim2.new(0, 18, 0, headH),
		Position = UDim2.new(1, -20, 0, 0),
		BackgroundTransparency = 1,
		Font = FONT_BOLD,
		TextSize = 13,
		TextColor3 = C_MUTE,
		Parent = head,
	})
	if close then
		close.Activated:Connect(function() Radar.setVisible(false) end)
	end

	local function bindDrag(obj)
		if not obj then return end
		obj.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1
				or input.UserInputType == Enum.UserInputType.Touch then
				beginMove("radar", root, input)
			end
		end)
	end
	bindDrag(head)
	bindDrag(Radar.title)

	local canvas = make("Frame", {
		Name = "Canvas",
		Size = UDim2.new(0, size, 0, size),
		Position = UDim2.new(0, 0, 0, headH),
		BackgroundTransparency = 1,
		Parent = root,
	})
	Radar.canvas = canvas

	for i = 1, 3 do
		local r = make("Frame", {
			Name = "Ring" .. i,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, 0, 0.5, 0),
			Size = UDim2.new(0, size * i / 3.2, 0, size * i / 3.2),
			BackgroundTransparency = 1,
			Parent = canvas,
		})
		make("UICorner", { CornerRadius = UDim.new(1, 0), Parent = r })
		make("UIStroke", { Color = C_LINE, Thickness = 1, Transparency = 0.55, Parent = r })
		Radar.rings[i] = r
	end

	make("Frame", {
		Name = "CrossH",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 0),
		Size = UDim2.new(1, -12, 0, 1),
		BackgroundColor3 = C_LINE,
		BackgroundTransparency = 0.5,
		BorderSizePixel = 0,
		Parent = canvas,
	})
	make("Frame", {
		Name = "CrossV",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 0),
		Size = UDim2.new(0, 1, 1, -12),
		BackgroundColor3 = C_LINE,
		BackgroundTransparency = 0.5,
		BorderSizePixel = 0,
		Parent = canvas,
	})
	local selfDot = make("Frame", {
		Name = "Self",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 0),
		Size = UDim2.new(0, 5, 0, 5),
		BackgroundColor3 = ACCENT,
		BorderSizePixel = 0,
		Parent = canvas,
	})
	make("UICorner", { CornerRadius = UDim.new(1, 0), Parent = selfDot })

	return gui
end

function Radar.setVisible(on)
	ST.radarOn = on and true or false
	if not ST.radarOn then
		if Radar.root then Radar.root.Visible = false end
	else
		if not (Radar.gui and Radar.gui.Parent) then pcall(Radar.build) end
		if Radar.root then Radar.root.Visible = true end
	end
	saveState()
end

function Radar.applySize(px)
	ST.radarSize = clamp(round(px), CONFIG.radarSizeMin, CONFIG.radarSizeMax)
	if Radar.root then
		local s = ST.radarSize
		Radar.root.Size = UDim2.new(0, s, 0, s + 18)
		if Radar.canvas then Radar.canvas.Size = UDim2.new(0, s, 0, s) end
		for i, r in ipairs(Radar.rings) do
			r.Size = UDim2.new(0, s * i / 3.2, 0, s * i / 3.2)
		end
	end
	saveState()
end

function Radar.update()
	if not ST.radarOn then return end
	if not (Radar.gui and Radar.gui.Parent) then return end
	local canvas = Radar.canvas
	if not canvas then return end

	local me = lp()
	local myRoot = me and me.Character and me.Character:FindFirstChild("HumanoidRootPart")
	if not myRoot then return end

	local abs = canvas.AbsoluteSize.X
	if not abs or abs < 40 then return end
	local half = abs / 2
	local range = clamp(ST.radarRange or CONFIG.radarRange, 20, 800)
	local cf = myRoot.CFrame

	local idx = 0
	for _, pl in ipairs(Players:GetPlayers()) do
		if pl ~= me then
			local char = pl.Character
			local rp = char and (char:FindFirstChild("HumanoidRootPart")
				or char:FindFirstChild("UpperTorso") or char:FindFirstChild("Torso"))
			local hum = char and char:FindFirstChildOfClass("Humanoid")
			if rp and hum then
				idx = idx + 1
				local dot = Radar.dots[idx]
				if not dot then
					dot = make("Frame", {
						Name = "D" .. idx,
						AnchorPoint = Vector2.new(0.5, 0.5),
						Size = UDim2.new(0, 6, 0, 6),
						BackgroundColor3 = C_BLUE,
						BorderSizePixel = 0,
						Parent = canvas,
					})
					make("UICorner", { CornerRadius = UDim.new(1, 0), Parent = dot })
					Radar.dots[idx] = dot
				end
				local rel = cf:PointToObjectSpace(rp.Position)
				local px, pz = radarPoint(rel, half, range)
				local over = (px < 2 or px > abs - 2 or pz < 2 or pz > abs - 2)
				px = clamp(px, 4, abs - 4)
				pz = clamp(pz, 4, abs - 4)
				dot.Position = UDim2.new(0, round(px), 0, round(pz))
				local dead = hum.Health <= 0.01
				dot.BackgroundColor3 = dead and HP_DEAD or C_BLUE
				dot.BackgroundTransparency = over and 0.55 or (dead and 0.3 or 0)
				dot.Visible = true
			end
		end
	end

	for i = idx + 1, #Radar.dots do
		Radar.dots[i].Visible = false
	end

	if Radar.title then
		Radar.title.Text = string.format("雷达 · %d 人 · %dm", idx, round(range))
	end
end

function Radar.start()
	if Radar.running then return end
	Radar.running = true
	task.spawn(function()
		local waited = 0
		while not lp() and waited < CONFIG.waitTimeout do
			task.wait(0.2)
			waited = waited + 0.2
		end
		if lp() then pcall(Radar.build) end
		while Radar.running do
			pcall(Radar.update)
			task.wait(0.2)
		end
	end)
end

--=====================================================================
--  动作系统
--=====================================================================
local DANCES = {
	{ name = "挥拳", r15 = 507771019, r6 = 182435998 },
	{ name = "摇摆", r15 = 507777826, r6 = 182436842 },
	{ name = "街舞", r15 = 507772104, r6 = 182436216 },
	{ name = "弹跳", r15 = 507770929, r6 = 182435251 },
	{ name = "鼓掌", r15 = 507770818, r6 = 182435293 },
	{ name = "指点", r15 = 507770677, r6 = 182436353 },
}

Dance = { track = nil, playing = nil }

local function danceAnimId(idx)
	local d = DANCES[idx]
	if not d then return nil end
	local me = lp()
	local hum = me and me.Character and me.Character:FindFirstChildOfClass("Humanoid")
	local r15 = hum and hum.RigType == Enum.HumanoidRigType.R15
	return r15 and d.r15 or d.r6
end

function Dance.stop()
	if Dance.track then
		pcall(function() Dance.track:Stop() end)
		pcall(function() Dance.track:Destroy() end)
	end
	Dance.track, Dance.playing = nil, nil
end

function Dance.play(idx)
	local me = lp()
	local hum = me and me.Character and me.Character:FindFirstChildOfClass("Humanoid")
	if not hum then return false, "没有角色" end
	local animator = hum:FindFirstChildOfClass("Animator")
	if not animator then return false, "没有 Animator" end
	local id = danceAnimId(idx)
	if not id then return false, "动作序号不对" end
	Dance.stop()
	local ok, track = pcall(function()
		local a = Instance.new("Animation")
		a.AnimationId = "rbxassetid://" .. id
		local t = animator:LoadAnimation(a)
		a:Destroy()
		return t
	end)
	if not ok or not track then return false, "动画加载失败" end
	pcall(function() track.Looped = true end)
	pcall(function() track:Play() end)
	Dance.track, Dance.playing = track, idx
	ST.anim = idx
	saveState()
	return true
end

function Dance.toggle()
	if Dance.playing then
		Dance.stop()
		return
	end
	Dance.play(ST.anim or 1)
end

--=====================================================================
--  迷你面板（动作 + 设置）
--=====================================================================
Panel = { gui = nil, win = nil, pages = {}, tab = "dance", open = false, status = nil, danceBtns = {} }

local function label(parent, text, size, color, bold, x, y, w, h)
	return make("TextLabel", {
		Text = text,
		Size = UDim2.new(0, w or 200, 0, h or 16),
		Position = UDim2.new(0, x or 0, 0, y or 0),
		BackgroundTransparency = 1,
		Font = bold and FONT_BOLD or FONT_BODY,
		TextSize = size or 12,
		TextColor3 = color or C_TEXT,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Parent = parent,
	})
end

local function section(parent, text, order)
	local head = make("TextLabel", {
		Text = text,
		Size = UDim2.new(1, -20, 0, 26),
		BackgroundTransparency = 1,
		Font = FONT_BOLD,
		TextSize = 11,
		TextColor3 = ACCENT,
		TextXAlignment = Enum.TextXAlignment.Left,
		LayoutOrder = order or 0,
		Parent = parent,
	})
	return head
end

local function toggleRow(parent, order, text, value, onChange)
	local row = make("Frame", {
		Size = UDim2.new(1, -20, 0, 26),
		BackgroundTransparency = 1,
		LayoutOrder = order,
		Parent = parent,
	})
	label(row, text, 12, C_TEXT, false, 0, 5, 200, 16)
	local pill = make("TextButton", {
		Text = "",
		Size = UDim2.new(0, 32, 0, 16),
		Position = UDim2.new(1, -34, 0.5, -8),
		BackgroundColor3 = value and ACCENT_D or C_LINE,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Parent = row,
	})
	make("UICorner", { CornerRadius = UDim.new(1, 0), Parent = pill })
	local knob = make("Frame", {
		Size = UDim2.new(0, 12, 0, 12),
		Position = value and UDim2.new(1, -14, 0.5, -6) or UDim2.new(0, 2, 0.5, -6),
		BackgroundColor3 = value and ACCENT or C_MUTE,
		BorderSizePixel = 0,
		Parent = pill,
	})
	make("UICorner", { CornerRadius = UDim.new(1, 0), Parent = knob })
	if pill then
		pill.Activated:Connect(function()
			value = not value
			pill.BackgroundColor3 = value and ACCENT_D or C_LINE
			knob.Position = value and UDim2.new(1, -14, 0.5, -6) or UDim2.new(0, 2, 0.5, -6)
			knob.BackgroundColor3 = value and ACCENT or C_MUTE
			pcall(onChange, value)
		end)
	end
	return row
end

local function sliderRow(parent, order, text, min, max, step, value, fmt, onLive, onCommit)
	local row = make("Frame", {
		Size = UDim2.new(1, -20, 0, 34),
		BackgroundTransparency = 1,
		LayoutOrder = order,
		Parent = parent,
	})
	label(row, text, 12, C_TEXT, false, 0, 2, 180, 16)
	local val = label(row, fmt and fmt(value) or tostring(value), 12, C_DIM, true, 180, 2, 160, 16)
	val.TextXAlignment = Enum.TextXAlignment.Right
	val.Size = UDim2.new(1, -180, 0, 16)

	local track = make("Frame", {
		Size = UDim2.new(1, 0, 0, 6),
		Position = UDim2.new(0, 0, 0, 22),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 0.86,
		BorderSizePixel = 0,
		Parent = row,
	})
	make("UICorner", { CornerRadius = UDim.new(1, 0), Parent = track })
	local t = (value - min) / math.max(0.0001, (max - min))
	local fill = make("Frame", {
		Size = UDim2.new(t, 0, 1, 0),
		BackgroundColor3 = ACCENT,
		BorderSizePixel = 0,
		Parent = track,
	})
	make("UICorner", { CornerRadius = UDim.new(1, 0), Parent = fill })

	local conf = { track = track, fill = fill, label = val, min = min, max = max,
		step = step, fmt = fmt, value = value, onLive = onLive, onCommit = onCommit,
		onLiveWrap = onLive }
	local function bind(obj)
		if not obj then return end
		obj.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1
				or input.UserInputType == Enum.UserInputType.Touch then
				beginSlider(conf, input)
			end
		end)
	end
	bind(track)
	bind(fill)
	return row
end

local function buttonRow(parent, order, text, onClick, w)
	local b = make("TextButton", {
		Text = text,
		Size = UDim2.new(0, w or 90, 0, 26),
		BackgroundColor3 = C_BG2,
		BorderSizePixel = 0,
		AutoButtonColor = true,
		Font = FONT_BOLD,
		TextSize = 12,
		TextColor3 = C_TEXT,
		LayoutOrder = order,
		Parent = parent,
	})
	make("UICorner", { CornerRadius = UDim.new(0, 7), Parent = b })
	make("UIStroke", { Color = C_LINE, Thickness = 1, Transparency = 0.4, Parent = b })
	if b then b.Activated:Connect(function() pcall(onClick) end) end
	return b
end

local keyCapture = nil

local function keyCapRow(parent, order, text, getKey, onSet)
	local row = make("Frame", {
		Size = UDim2.new(1, -20, 0, 26),
		BackgroundTransparency = 1,
		LayoutOrder = order,
		Parent = parent,
	})
	label(row, text, 12, C_TEXT, false, 0, 5, 180, 16)
	local cap = make("TextButton", {
		Text = getKey(),
		Size = UDim2.new(0, 84, 0, 22),
		Position = UDim2.new(1, -84, 0.5, -11),
		BackgroundColor3 = C_BG2,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Font = FONT_BOLD,
		TextSize = 11,
		TextColor3 = C_TEXT,
		Parent = row,
	})
	make("UICorner", { CornerRadius = UDim.new(0, 6), Parent = cap })
	make("UIStroke", { Color = C_LINE, Thickness = 1, Transparency = 0.45, Parent = cap })
	if cap then
		cap.Activated:Connect(function()
			keyCapture = { btn = cap, onSet = onSet, old = cap.Text }
			cap.Text = "按一个键…"
		end)
	end
	return row
end

function Panel.build()
	if Panel.gui and Panel.gui.Parent then return Panel.gui end

	local gui = make("ScreenGui", {
		Name = "SG_QoL_Panel",
		IgnoreGuiInset = true,
		ResetOnSpawn = false,
		DisplayOrder = 999998,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	})
	attachGui(gui)
	Panel.gui = gui

	local W, H = CONFIG.panelW, CONFIG.panelH
	local win = make("Frame", {
		Name = "Win",
		Position = UDim2.new(0, ST.panelX or 40, 0, ST.panelY or 120),
		Size = UDim2.new(0, W, 0, H),
		BackgroundColor3 = C_BG,
		BorderSizePixel = 0,
		Visible = Panel.open,
		Parent = gui,
	})
	make("UICorner", { CornerRadius = UDim.new(0, 10), Parent = win })
	make("UIStroke", { Color = C_LINE, Thickness = 1, Transparency = 0.35, Parent = win })
	Panel.win = win

	local top = make("Frame", {
		Name = "Top",
		Size = UDim2.new(1, 0, 0, 30),
		BackgroundColor3 = C_BG2,
		BorderSizePixel = 0,
		Active = true,
		Parent = win,
	})
	make("UICorner", { CornerRadius = UDim.new(0, 10), Parent = top })
	label(top, "QoL v1.1", 12, C_TEXT, true, 10, 7, 120, 16)
	local close = make("TextButton", {
		Text = "×",
		Size = UDim2.new(0, 24, 0, 22),
		Position = UDim2.new(1, -28, 0, 4),
		BackgroundTransparency = 1,
		Font = FONT_BOLD,
		TextSize = 14,
		TextColor3 = C_MUTE,
		Parent = top,
	})
	if close then close.Activated:Connect(function() Panel.setOpen(false) end) end
	top.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			beginMove("panel", win, input)
		end
	end)

	-- 页签
	local tabRow = make("Frame", {
		Size = UDim2.new(1, -20, 0, 26),
		Position = UDim2.new(0, 10, 0, 36),
		BackgroundTransparency = 1,
		Parent = win,
	})
	local tabs = { { id = "dance", text = "动作" }, { id = "setting", text = "设置" } }
	local tabBtns = {}
	for i, t in ipairs(tabs) do
		local b = make("TextButton", {
			Text = t.text,
			Size = UDim2.new(0, 64, 0, 24),
			Position = UDim2.new(0, (i - 1) * 70, 0, 0),
			BackgroundColor3 = (Panel.tab == t.id) and C_BG2 or C_BG,
			BorderSizePixel = 0,
			AutoButtonColor = false,
			Font = FONT_BOLD,
			TextSize = 12,
			TextColor3 = (Panel.tab == t.id) and ACCENT or C_DIM,
			Parent = tabRow,
		})
		make("UICorner", { CornerRadius = UDim.new(0, 7), Parent = b })
		make("UIStroke", { Color = C_LINE, Thickness = 1, Transparency = 0.5, Parent = b })
		tabBtns[t.id] = b
		b.Activated:Connect(function() Panel.showTab(t.id) end)
	end
	Panel.tabBtns = tabBtns

	-- 内容区
	local body = make("Frame", {
		Size = UDim2.new(1, -20, 1, -76),
		Position = UDim2.new(0, 10, 0, 66),
		BackgroundTransparency = 1,
		Parent = win,
	})
	Panel.body = body

	local function page(id)
		local sc = make("ScrollingFrame", {
			Name = id,
			Size = UDim2.new(1, 0, 1, 0),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			ScrollBarThickness = 3,
			ScrollBarImageColor3 = C_LINE,
			CanvasSize = UDim2.new(0, 0, 0, 0),
			AutomaticCanvasSize = Enum.AutomaticSize.Y,
			Visible = (Panel.tab == id),
			Parent = body,
		})
		make("UIListLayout", {
			Padding = UDim.new(0, 6),
			SortOrder = Enum.SortOrder.LayoutOrder,
			Parent = sc,
		})
		make("UIPadding", {
			PaddingTop = UDim.new(0, 2),
			PaddingBottom = UDim.new(0, 6),
			Parent = sc,
		})
		Panel.pages[id] = sc
		return sc
	end

	-- 动作页
	local dancePage = page("dance")
	section(dancePage, "动作（再按一次快捷键停止）", 0)
	local grid = make("Frame", {
		Size = UDim2.new(1, -20, 0, 96),
		BackgroundTransparency = 1,
		LayoutOrder = 1,
		Parent = dancePage,
	})
	make("UIGridLayout", {
		CellSize = UDim2.new(0, 100, 0, 28),
		CellPadding = UDim2.new(0, 6, 0, 6),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = grid,
	})
	for i, d in ipairs(DANCES) do
		local b = make("TextButton", {
			Text = d.name,
			BackgroundColor3 = C_BG2,
			BorderSizePixel = 0,
			AutoButtonColor = false,
			Font = FONT_BOLD,
			TextSize = 12,
			TextColor3 = C_TEXT,
			LayoutOrder = i,
			Parent = grid,
		})
		make("UICorner", { CornerRadius = UDim.new(0, 7), Parent = b })
		make("UIStroke", { Color = C_LINE, Thickness = 1, Transparency = 0.45, Parent = b })
		Panel.danceBtns[i] = b
		b.Activated:Connect(function()
			if Dance.playing == i then
				Dance.stop()
			else
				local ok, err = Dance.play(i)
				if not ok then print("[QoL v1.1] 动作失败: " .. tostring(err)) end
			end
			Panel.refreshDance()
		end)
	end

	local actRow = make("Frame", {
		Size = UDim2.new(1, -20, 0, 30),
		BackgroundTransparency = 1,
		LayoutOrder = 2,
		Parent = dancePage,
	})
	local playBtn = buttonRow(actRow, 1, "播放", function()
		Dance.play(ST.anim or 1)
		Panel.refreshDance()
	end, 80)
	if playBtn then playBtn.Position = UDim2.new(0, 0, 0, 0) end
	local stopBtn = buttonRow(actRow, 2, "停止", function()
		Dance.stop()
		Panel.refreshDance()
	end, 80)
	if stopBtn then stopBtn.Position = UDim2.new(0, 88, 0, 0) end
	local hint = label(dancePage, "快捷键按一下播放，再按一下停。只有自己看得到。", 11, C_MUTE, false, 0, 0, 300, 14)
	if hint then hint.LayoutOrder = 3 end

	-- 设置页
	local setPage = page("setting")
	local o = 0
	section(setPage, "血条面板", o) o = o + 1
	toggleRow(setPage, o, "显示全员血量", ST.hudOn, function(v) HPHud.setVisible(v) end) o = o + 1
	toggleRow(setPage, o, "血条下方显示道具", ST.showItems, function(v)
		ST.showItems = v
		saveState()
		if HPHud.update then pcall(HPHud.update) end
	end) o = o + 1
	sliderRow(setPage, o, "字号", SIZE_MIN, SIZE_MAX, 1, M.fs,
		function(v) return string.format("%dpx · %d%%", round(v), pct(round(v))) end,
		nil,
		function(v) HPHud.applySize(v) end) o = o + 1

	o = o + 1
	section(setPage, "雷达小窗", o) o = o + 1
	toggleRow(setPage, o, "显示雷达", ST.radarOn, function(v) Radar.setVisible(v) end) o = o + 1
	sliderRow(setPage, o, "尺寸", CONFIG.radarSizeMin, CONFIG.radarSizeMax, 2, ST.radarSize,
		function(v) return round(v) .. "px" end, nil,
		function(v) Radar.applySize(v) end) o = o + 1
	sliderRow(setPage, o, "半径", 40, 400, 5, ST.radarRange,
		function(v) return round(v) .. "m" end, nil,
		function(v) ST.radarRange = round(v); saveState() end) o = o + 1

	o = o + 1
	section(setPage, "快捷键", o) o = o + 1
	keyCapRow(setPage, o, "面板", function() return ST.keys.panel end, function(k)
		ST.keys.panel = k; saveState()
	end) o = o + 1
	keyCapRow(setPage, o, "雷达", function() return ST.keys.radar end, function(k)
		ST.keys.radar = k; saveState()
	end) o = o + 1
	keyCapRow(setPage, o, "跳舞", function() return ST.keys.dance end, function(k)
		ST.keys.dance = k; saveState()
	end) o = o + 1

	o = o + 1
	section(setPage, "原版硬核脚本", o) o = o + 1
	Panel.status = label(setPage, ORIGINAL_STATUS, 11, C_DIM, false, 0, 0, 300, 16)
	if Panel.status then
		Panel.status.Size = UDim2.new(1, -20, 0, 16)
		Panel.status.LayoutOrder = o
	end
	o = o + 1
	local retry = buttonRow(setPage, o, "重新加载", function() loadOriginal() end, 100)
	if retry then retry.Size = UDim2.new(0, 100, 0, 26) end

	Panel.showTab(Panel.tab)
	return gui
end

function Panel.showTab(id)
	Panel.tab = id
	for k, sc in pairs(Panel.pages) do sc.Visible = (k == id) end
	for k, b in pairs(Panel.tabBtns or {}) do
		b.TextColor3 = (k == id) and ACCENT or C_DIM
		b.BackgroundColor3 = (k == id) and C_BG2 or C_BG
	end
end

function Panel.refreshDance()
	for i, b in ipairs(Panel.danceBtns or {}) do
		local on = (Dance.playing == i)
		b.BackgroundColor3 = on and ACCENT_D or C_BG2
		b.TextColor3 = on and ACCENT or C_TEXT
	end
end

function Panel.setOpen(on)
	Panel.open = on and true or false
	if Panel.open and not (Panel.gui and Panel.gui.Parent) then pcall(Panel.build) end
	if Panel.win then Panel.win.Visible = Panel.open end
	if Panel.open then Panel.refreshDance() end
	if Panel.pill then Panel.pill.Visible = not Panel.open end
end

--=====================================================================
--  右下角小按钮（面板关着的时候挂这里，尽量不挡视线）
--=====================================================================
function Panel.buildPill()
	if Panel.pill and Panel.pill.Parent then return end
	local gui = Panel.gui
	if not (gui and gui.Parent) then pcall(Panel.build) gui = Panel.gui end
	if not gui then return end

	local pill = make("TextButton", {
		Name = "Pill",
		Text = "QoL",
		Size = UDim2.new(0, 40, 0, 24),
		Position = UDim2.new(1, -52, 1, -36),
		BackgroundColor3 = C_BG,
		BackgroundTransparency = 0.25,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Font = FONT_BOLD,
		TextSize = 11,
		TextColor3 = C_DIM,
		Visible = not Panel.open,
		Parent = gui,
	})
	make("UICorner", { CornerRadius = UDim.new(1, 0), Parent = pill })
	make("UIStroke", { Color = C_LINE, Thickness = 1, Transparency = 0.5, Parent = pill })
	if pill then
		pill.Activated:Connect(function() Panel.setOpen(true) end)
	end
	Panel.pill = pill
end

--=====================================================================
--  原版硬核脚本
--=====================================================================
function loadOriginal()
	if not CONFIG.runOriginal then
		ORIGINAL_STATUS = "已在配置里关闭"
		if Panel.status then Panel.status.Text = ORIGINAL_STATUS end
		return false
	end
	local tried = {}
	for _, url in ipairs(CONFIG.srcList) do
		local ok, body = pcall(function() return game:HttpGet(url, true) end)
		if ok and type(body) == "string" and #body > 200 then
			local chunk, err = loadstring(body)
			if chunk then
				print("[QoL v1.1] 原版硬核脚本: " .. url .. string.format(" (%d 字节)", #body))
				local ok2, e2 = pcall(chunk)
				if ok2 then
					ORIGINAL_STATUS = "已加载: " .. url:match("^https?://([^/]+)") 
					if Panel.status then Panel.status.Text = ORIGINAL_STATUS end
					return true
				end
				table.insert(tried, "运行报错(" .. tostring(e2):sub(1, 60) .. ")")
			else
				table.insert(tried, "编译失败(" .. tostring(err):sub(1, 40) .. ")")
			end
		else
			table.insert(tried, "下载失败")
		end
	end
	ORIGINAL_STATUS = "没起来: " .. table.concat(tried, " / ")
	if Panel.status then Panel.status.Text = ORIGINAL_STATUS end
	warn("[QoL v1.1] 原版硬核脚本加载失败 -> " .. ORIGINAL_STATUS)
	return false
end

--=====================================================================
--  按键
--=====================================================================
local function matches(key)
	return key ~= nil and key ~= ""
end

UIS.InputBegan:Connect(function(input, processed)
	if processed then return end
	if input.UserInputType ~= Enum.UserInputType.Keyboard then return end
	local nm = input.KeyCode.Name

	if keyCapture then
		local c = keyCapture
		keyCapture = nil
		if nm ~= "Escape" then
			c.btn.Text = nm
			pcall(c.onSet, nm)
		else
			c.btn.Text = c.old or "—"
		end
		return
	end

	if matches(ST.keys.panel) and nm == ST.keys.panel then
		Panel.setOpen(not Panel.open)
	elseif matches(ST.keys.radar) and nm == ST.keys.radar then
		Radar.setVisible(not ST.radarOn)
	elseif matches(ST.keys.dance) and nm == ST.keys.dance then
		Dance.toggle()
		if Panel.open then Panel.refreshDance() end
	end
end)

--=====================================================================
--  启动
--=====================================================================
local cfg = readCfg()
if cfg then
	ST.hudOn     = (cfg.hudOn ~= false)
	ST.showItems = (cfg.showItems ~= false)
	ST.hudX      = tonumber(cfg.hudX) or ST.hudX
	ST.hudY      = tonumber(cfg.hudY) or ST.hudY
	ST.collapsed = cfg.collapsed and true or false
	ST.radarOn   = (cfg.radarOn ~= false)
	ST.radarSize = tonumber(cfg.radarSize) or ST.radarSize
	ST.radarRange = tonumber(cfg.radarRange) or ST.radarRange
	ST.radarX    = tonumber(cfg.radarX) or ST.radarX
	ST.radarY    = tonumber(cfg.radarY) or ST.radarY
	ST.panelX    = tonumber(cfg.panelX) or ST.panelX
	ST.panelY    = tonumber(cfg.panelY) or ST.panelY
	ST.anim      = tonumber(cfg.anim) or ST.anim
	if tonumber(cfg.fs) then M = measure(tonumber(cfg.fs)) end
	if type(cfg.kPanel) == "string" then ST.keys.panel = cfg.kPanel end
	if type(cfg.kRadar) == "string" then ST.keys.radar = cfg.kRadar end
	if type(cfg.kDance) == "string" then ST.keys.dance = cfg.kDance end
end

HPHud.start()
Radar.start()

task.spawn(function()
	local waited = 0
	while not lp() and waited < CONFIG.waitTimeout do
		task.wait(0.2)
		waited = waited + 0.2
	end
	pcall(Panel.build)
	pcall(Panel.buildPill)
	Panel.setOpen(false)
end)

task.spawn(function()
	local waited = 0
	while not lp() and waited < CONFIG.waitTimeout do
		task.wait(0.2)
		waited = waited + 0.2
	end
	loadOriginal()
end)

print(string.format("[QoL v1.1] 已启动: 血条 %d%% · 雷达 %dpx · 面板 %s",
	pct(M.fs), round(ST.radarSize), ST.keys.panel))
print("[QoL v1.1] 快捷键: 面板 " .. tostring(ST.keys.panel)
	.. " · 雷达 " .. tostring(ST.keys.radar)
	.. " · 跳舞 " .. tostring(ST.keys.dance))

HPHud.setSize = HPHud.applySize

getgenv().HPHud = HPHud
getgenv().QoL = {
	config = ST,
	hud = HPHud,
	radar = Radar,
	panel = Panel,
	dance = Dance,
	open = function(on) Panel.setOpen(on ~= false) end,
	stopDance = Dance.stop,
	original = loadOriginal,
	save = saveState,
}
