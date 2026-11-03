--[[
    DOORS Multiplayer QoL · v1.0（统一控制面板）

    一个主窗口 + 左侧分类导航 + 右侧内容区，六类功能全部塞进同一个面板：
      玩家信息  —— 全员血量 / 距离 / 死亡状态（沿用 v0.1 的读法与配色）
      队伍雷达  —— 以自己为中心的相对方位雷达（俯视 XZ 平面）
      道具信息  —— 队友背包 / 手持道具（只读 Backpack + Character 下的 Tool）
      事件日志  —— 加入、离开、受伤、死亡、复活、开门、实体出现…（启发式识别，逐条标注）
      动作系统  —— 快捷键跳舞，可换动作、可停止
      设置      —— 统一配置：缩放 / 透明度 / 模块开关 / 快捷键

    设计约束（本文件遵守）：
      · 只有一个窗口，分类只切换内部页面，不新开窗口、不重复初始化
      · 页面懒创建一次后缓存，切换只改 Visible
      · 窗口可拖动、可拉边角改大小，最小 420×300，内容自动适配
      · 所有配置只有一份，存 QoL_v1.json，各模块读同一套
      · 只读游戏数据，不写任何游戏状态，不碰原脚本

    同步说明（不绕权限）：
      · 血量 / 距离 / 道具：客户端可见的公开复制数据
      · 事件日志：基于实例变化 / Humanoid 变化的启发式识别，识别不了的标「未支持」
      · 跳舞：客户端 Animator 播放，只有自己看得到；让别人看到需要服务器侧播放，
        本脚本不做越权远程调用，也不碰反作弊
--]]

--=====================================================================
--  0. 配置（唯一一份）
--=====================================================================
local DEFAULT = {
	ui = {
		x = 60, y = 60, w = 620, h = 440,
		scale = 1, opacity = 0, tab = "player",
		hudOn = true, hudFont = 13, hudX = 16, hudY = 96, hudCollapsed = false,
	},
	keys = { panel = "RightShift", radar = "N", log = "L", dance = "K" },
	mods = { player = true, radar = true, inv = true, log = true, dance = true },
	radar = { range = 140, size = 210 },
	dance = { anim = 1 },
}

local CONFIG = {
	cfgFile = "QoL_v1.json",
	ui      = { x = 60, y = 60, w = 620, h = 440, scale = 1, opacity = 0, tab = "player",
	            hudOn = true, hudFont = 13, hudX = 16, hudY = 96, hudCollapsed = false },
	keys    = { panel = "RightShift", radar = "N", log = "L", dance = "K" },
	mods    = { player = true, radar = true, inv = true, log = true, dance = true },
	radar   = { range = 140, size = 210 },
	dance   = { anim = 1 },
}

local Players    = game:GetService("Players")
local UIS        = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local Lighting   = game:GetService("Lighting")

local function lp()
	return Players.LocalPlayer
end

--=====================================================================
--  1. 基础工具
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
	pcall(function()
		local hui = gethui and gethui()
		if hui then gui.Parent = hui return end
		pcall(function() gui.Parent = game:GetService("CoreGui") end)
		if gui.Parent then return end
		gui.Parent = lp():WaitForChild("PlayerGui", 5)
	end)
	if not gui.Parent and lp() then
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

local function now()
	return os.date("%H:%M:%S")
end

local function corner(inst, r)
	if not inst then return nil end
	return make("UICorner", { CornerRadius = UDim.new(0, r or 8), Parent = inst })
end

local function strokeOf(inst, col, th, tr)
	if not inst then return nil end
	return make("UIStroke", { Color = col, Thickness = th or 1, Transparency = tr or 0.5, Parent = inst })
end

local function pad(inst, l, r, t, b)
	if not inst then return nil end
	return make("UIPadding", {
		PaddingLeft = UDim.new(0, l or 0), PaddingRight = UDim.new(0, r or 0),
		PaddingTop = UDim.new(0, t or 0), PaddingBottom = UDim.new(0, b or 0),
		Parent = inst,
	})
end

-- ---- JSON（只处理本配置用得到的类型） ----
local function jsonEncode(v)
	local t = type(v)
	if t == "nil" then return "null" end
	if t == "boolean" or t == "number" then
		if t == "number" and (v ~= v or v == math.huge or v == -math.huge) then return "null" end
		return tostring(math.floor(v * 1000 + 0.5) / 1000)
	end
	if t == "string" then
		local s = v:gsub('\\', '\\\\'):gsub('"', '\\"'):gsub('\n', '\\n'):gsub('\t', '\\t')
		return '"' .. s .. '"'
	end
	if t == "table" then
		local isArr = true
		local n = 0
		for _ in pairs(v) do n = n + 1 end
		if n > 0 then
			for k in pairs(v) do
				if type(k) ~= "number" then isArr = false break end
			end
		end
		local out = {}
		if isArr then
			for i = 1, n do out[i] = jsonEncode(v[i]) end
			return "[" .. table.concat(out, ",") .. "]"
		end
		for k, val in pairs(v) do
			table.insert(out, '"' .. tostring(k) .. '":' .. jsonEncode(val))
		end
		return "{" .. table.concat(out, ",") .. "}"
	end
	return "null"
end

local function writeCfg()
	if not writefile then return end
	pcall(function() writefile(CONFIG.cfgFile, jsonEncode(CONFIG)) end)
end

local saveTimer = nil
local function saveCfg(now_)
	if now_ then
		writeCfg()
		return
	end
	if saveTimer then return end
	saveTimer = true
	task.delay(1.2, function()
		saveTimer = nil
		writeCfg()
	end)
end

local function mergeInto(dst, src)
	if type(src) ~= "table" then return end
	for k, v in pairs(src) do
		if type(v) == "table" and type(dst[k]) == "table" then
			mergeInto(dst[k], v)
		elseif type(v) == type(dst[k]) then
			dst[k] = v
		end
	end
end

local function loadCfg()
	if not (readfile and isfile) then return end
	pcall(function()
		if not isfile(CONFIG.cfgFile) then return end
		local raw = readfile(CONFIG.cfgFile)
		if type(raw) ~= "string" or #raw < 2 then return end
		local ok, data = pcall(function()
			return game:GetService("HttpService"):JSONDecode(raw)
		end)
		if ok and type(data) == "table" then mergeInto(CONFIG, data) end
	end)
end

--=====================================================================
--  2. 主题
--=====================================================================
local C_BG     = Color3.fromRGB(22, 24, 28)
local C_BG2    = Color3.fromRGB(30, 33, 38)
local C_TEXT   = Color3.fromRGB(234, 237, 242)
local C_DIM    = Color3.fromRGB(150, 158, 168)
local C_MUTE   = Color3.fromRGB(104, 112, 122)
local C_LINE   = Color3.fromRGB(64, 70, 80)
local ACCENT   = Color3.fromRGB(88, 226, 140)
local ACCENT_D = Color3.fromRGB(36, 92, 62)
local C_RED    = Color3.fromRGB(255, 96, 88)
local C_AMBER  = Color3.fromRGB(255, 196, 84)
local C_BLUE   = Color3.fromRGB(108, 176, 255)
local C_PURPLE = Color3.fromRGB(180, 140, 255)

local FONT      = Enum.Font.Gotham
local FONT_BOLD = Enum.Font.GothamSemibold

local TOPBAR = 36
local NAV_W  = 118
local MIN_W  = 420
local MIN_H  = 300

--=====================================================================
--  3. 事件日志（先建，别的模块都要往里丢）
--=====================================================================
local Log = { rows = {}, n = 0, max = 140, filterImportant = false, page = nil }

local KIND = {
	join   = { tag = "加入", col = ACCENT,    imp = true  },
	leave  = { tag = "离开", col = C_MUTE,    imp = true  },
	death  = { tag = "死亡", col = C_RED,     imp = true  },
	hurt   = { tag = "受伤", col = C_AMBER,   imp = false },
	heal   = { tag = "回复", col = ACCENT,    imp = false },
	door   = { tag = "开门", col = C_BLUE,    imp = true  },
	entity = { tag = "实体", col = C_PURPLE,  imp = true  },
	room   = { tag = "房间", col = C_BLUE,    imp = true  },
	phase  = { tag = "阶段", col = C_BLUE,    imp = true  },
	misc   = { tag = "信息", col = C_DIM,     imp = false },
}

local function logRow(entry, order)
	if not Log.page then return end
	local k = entry
	local row = make("Frame", {
		Size = UDim2.new(1, 0, 0, 18),
		BackgroundTransparency = 1,
		LayoutOrder = order or 0,
		Parent = Log.page,
	})
	if not row then return end
	make("TextLabel", {
		Text = entry.t, Size = UDim2.new(0, 56, 1, 0), BackgroundTransparency = 1,
		Font = FONT, TextSize = 11, TextColor3 = C_MUTE,
		TextXAlignment = Enum.TextXAlignment.Left, Parent = row,
	})
	make("TextLabel", {
		Text = "[" .. k.tag .. "]", Size = UDim2.new(0, 46, 1, 0), Position = UDim2.new(0, 56, 0, 0),
		BackgroundTransparency = 1, Font = FONT_BOLD, TextSize = 11, TextColor3 = k.col,
		TextXAlignment = Enum.TextXAlignment.Left, Parent = row,
	})
	make("TextLabel", {
		Text = k.text, Size = UDim2.new(1, -110, 1, 0), Position = UDim2.new(0, 106, 0, 0),
		BackgroundTransparency = 1, Font = FONT, TextSize = 12, TextColor3 = C_TEXT,
		TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, Parent = row,
	})
	entry.frame = row
	if Log.filterImportant and not entry.imp then row.Visible = false end
end

local function logAdd(kind, text)
	local k = KIND[kind] or KIND.misc
	local entry = { kind = kind, col = k.col, tag = k.tag, imp = k.imp, text = text, t = now() }
	table.insert(Log.rows, 1, entry)
	Log.n = Log.n + 1
	if Log.page and CONFIG.mods.log ~= false then logRow(entry, -1) end
	for i, e in ipairs(Log.rows) do
		if e.frame then e.frame.LayoutOrder = -i end
	end
	while #Log.rows > Log.max do
		local old = table.remove(Log.rows)
		if old and old.frame then pcall(function() old.frame:Destroy() end) end
	end
end

function Log.rebuild()
	if not Log.page then return end
	for _, e in ipairs(Log.rows) do
		if e.frame then pcall(function() e.frame:Destroy() end) end
		e.frame = nil
	end
	for i = #Log.rows, 1, -1 do logRow(Log.rows[i], -i) end
end

function Log.clear()
	for _, e in ipairs(Log.rows) do
		if e.frame then pcall(function() e.frame:Destroy() end) end
	end
	Log.rows, Log.n = {}, 0
end

--=====================================================================
--  4. 通用控件
--=====================================================================
local drag = nil     -- 滑块拖拽状态
local hudDrag = nil  -- 浮动小窗拖拽状态

local function label(parent, text, opts)
	opts = opts or {}
	return make("TextLabel", {
		Text = text,
		Size = opts.size or UDim2.new(1, 0, 0, opts.h or 18),
		Position = opts.pos or UDim2.new(0, 0, 0, 0),
		BackgroundTransparency = 1,
		Font = opts.bold and FONT_BOLD or FONT,
		TextSize = opts.ts or 12,
		TextColor3 = opts.col or C_TEXT,
		TextXAlignment = opts.x or Enum.TextXAlignment.Left,
		TextYAlignment = opts.y or Enum.TextYAlignment.Center,
		TextTruncate = opts.trunc and Enum.TextTruncate.AtEnd or Enum.TextTruncate.None,
		TextWrapped = opts.wrap or false,
		LayoutOrder = opts.order or 0,
		Parent = parent,
	})
end

local function section(parent, text, order)
	local box = make("Frame", {
		Size = UDim2.new(1, 0, 0, 26), BackgroundTransparency = 1,
		LayoutOrder = order or 0, Parent = parent,
	})
	if not box then return nil end
	label(box, text, { ts = 11, bold = true, col = ACCENT, size = UDim2.new(1, 0, 0, 14), pos = UDim2.new(0, 0, 0, 9) })
	local line = make("Frame", {
		Size = UDim2.new(1, 0, 0, 1), Position = UDim2.new(0, 0, 0, 24),
		BackgroundColor3 = C_LINE, BackgroundTransparency = 0.4, BorderSizePixel = 0, Parent = box,
	})
	return box, line
end

local function slider(parent, opts)
	local box = make("Frame", {
		Size = UDim2.new(1, 0, 0, 40), BackgroundTransparency = 1,
		LayoutOrder = opts.order or 0, Parent = parent,
	})
	if not box then return nil end
	label(box, opts.label, { ts = 12, col = C_DIM, size = UDim2.new(1, -64, 0, 16) })
	local val = label(box, "", { ts = 12, bold = true, col = C_TEXT, size = UDim2.new(0, 64, 0, 16), pos = UDim2.new(1, -64, 0, 0), x = Enum.TextXAlignment.Right })
	local track = make("Frame", {
		Size = UDim2.new(1, 0, 0, 6), Position = UDim2.new(0, 0, 0, 26),
		BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 0.86,
		BorderSizePixel = 0, Parent = box,
	})
	corner(track, 3)
	local fill = make("Frame", {
		Size = UDim2.new(0, 0, 1, 0), BackgroundColor3 = ACCENT,
		BorderSizePixel = 0, Parent = track,
	})
	corner(fill, 3)
	local knob = make("Frame", {
		Size = UDim2.new(0, 10, 0, 10), AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0, 0, 0.5, 0), BackgroundColor3 = C_TEXT,
		BorderSizePixel = 0, Parent = track,
	})
	corner(knob, 5)

	local min, max = opts.min, opts.max
	local step = opts.step or 0
	local fmt = opts.fmt or function(v) return tostring(round(v)) end
	local value = clamp(opts.value or min, min, max)

	local function paint(v)
		local ratio = (max > min) and clamp((v - min) / (max - min), 0, 1) or 0
		fill.Size = UDim2.new(ratio, 0, 1, 0)
		knob.Position = UDim2.new(ratio, 0, 0.5, 0)
		val.Text = fmt(v)
	end

	local api = { track = track }

	function api.set(v, live)
		v = clamp(v, min, max)
		if step > 0 then v = min + round((v - min) / step) * step end
		value = v
		paint(v)
		if live then
			if opts.onLive then pcall(opts.onLive, v) end
		else
			if opts.onCommit then pcall(opts.onCommit, v) end
		end
	end

	paint(value)

	track.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			drag = { track = track, min = min, max = max, step = step, set = api.set, value = value }
			local w = track.AbsoluteSize.X
			if w > 0 then
				local a = clamp((input.Position.X - track.AbsolutePosition.X) / w, 0, 1)
				api.set(min + (max - min) * a, true)
			end
		end
	end)

	return api
end

local function toggle(parent, opts)
	local box = make("Frame", {
		Size = UDim2.new(1, 0, 0, 30), BackgroundTransparency = 1,
		LayoutOrder = opts.order or 0, Parent = parent,
	})
	if not box then return nil end
	label(box, opts.label, { ts = 12, col = C_TEXT, size = UDim2.new(1, -50, 0, 16), pos = UDim2.new(0, 0, 0, 7) })
	local pill = make("TextButton", {
		Text = "", Size = UDim2.new(0, 34, 0, 16), Position = UDim2.new(1, -34, 0, 7),
		BackgroundColor3 = C_LINE, BorderSizePixel = 0, AutoButtonColor = false, Parent = box,
	})
	corner(pill, 8)
	local knob = make("Frame", {
		Size = UDim2.new(0, 12, 0, 12), Position = UDim2.new(0, 2, 0, 2),
		BackgroundColor3 = C_DIM, BorderSizePixel = 0, Parent = pill,
	})
	corner(knob, 6)

	local state = opts.value and true or false
	local api = {}

	local function paint()
		pill.BackgroundColor3 = state and ACCENT_D or C_LINE
		knob.BackgroundColor3 = state and ACCENT or C_DIM
		knob.Position = state and UDim2.new(1, -14, 0, 2) or UDim2.new(0, 2, 0, 2)
	end

	function api.set(v, silent)
		state = v and true or false
		paint()
		if not silent and opts.onChange then pcall(opts.onChange, state) end
	end

	pill.Activated:Connect(function() api.set(not state) end)
	paint()
	return api
end

local capture = nil

local function keybind(parent, opts)
	local box = make("Frame", {
		Size = UDim2.new(1, 0, 0, 30), BackgroundTransparency = 1,
		LayoutOrder = opts.order or 0, Parent = parent,
	})
	if not box then return nil end
	label(box, opts.label, { ts = 12, col = C_TEXT, size = UDim2.new(1, -92, 0, 16), pos = UDim2.new(0, 0, 0, 7) })
	local btn = make("TextButton", {
		Text = opts.value or "—", Size = UDim2.new(0, 86, 0, 22), Position = UDim2.new(1, -86, 0, 4),
		BackgroundColor3 = C_BG2, BorderSizePixel = 0, AutoButtonColor = true,
		Font = FONT_BOLD, TextSize = 12, TextColor3 = C_TEXT, Parent = box,
	})
	corner(btn, 6)
	strokeOf(btn, C_LINE, 1, 0.5)

	btn.Activated:Connect(function()
		btn.Text = "按一个键…"
		btn.TextColor3 = ACCENT
		capture = function(name)
			capture = nil
			btn.Text = name
			btn.TextColor3 = C_TEXT
			if opts.onChange then pcall(opts.onChange, name) end
		end
	end)
	return btn
end

local function button(parent, opts)
	local b = make("TextButton", {
		Text = opts.text or "",
		Size = opts.size or UDim2.new(0, 96, 0, 26),
		Position = opts.pos or UDim2.new(0, 0, 0, 0),
		BackgroundColor3 = opts.bg or C_BG2,
		BorderSizePixel = 0,
		AutoButtonColor = true,
		Font = FONT_BOLD,
		TextSize = opts.ts or 12,
		TextColor3 = opts.col or C_TEXT,
		LayoutOrder = opts.order or 0,
		Parent = parent,
	})
	if not b then return nil end
	corner(b, opts.radius or 7)
	if opts.stroke ~= false then strokeOf(b, opts.strokeCol or C_LINE, 1, 0.5) end
	if opts.onClick then b.Activated:Connect(function() pcall(opts.onClick) end) end
	return b
end

local function chip(parent, text, col, order)
	local f = make("Frame", {
		Size = UDim2.new(0, 0, 0, 18), AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = col or C_BG2, BackgroundTransparency = 0.15,
		BorderSizePixel = 0, LayoutOrder = order or 0, Parent = parent,
	})
	if not f then return nil end
	corner(f, 5)
	pad(f, 7, 7, 0, 0)
	make("TextLabel", {
		Text = text, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.new(0, 0, 1, 0),
		BackgroundTransparency = 1, Font = FONT_BOLD, TextSize = 11,
		TextColor3 = C_TEXT, Parent = f,
	})
	return f
end

--=====================================================================
--  5. 面板骨架
--=====================================================================
local TABS = {
	{ id = "player",  name = "玩家信息" },
	{ id = "radar",   name = "队伍雷达" },
	{ id = "inv",     name = "道具信息" },
	{ id = "log",     name = "事件日志" },
	{ id = "dance",   name = "动作系统" },
	{ id = "setting", name = "设置" },
}

local P = {
	gui = nil, win = nil, body = nil, pagesRoot = nil, topBar = nil,
	tab = CONFIG.ui.tab or "player",
	pages = {}, navBtns = {}, navDots = {},
	refresh = {}, open = true, minimized = false, savedH = nil,
	playerRows = {}, invRows = {}, radar = { dots = {}, size = nil },
}

local Hud  -- 前向声明：浮动血量小窗在文件后半段实现

local function pageOf(id)
	if P.pages[id] then return P.pages[id] end
	local page = make("ScrollingFrame", {
		Name = "Page_" .. id,
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		CanvasSize = UDim2.new(1, 0, 0, 0),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 4,
		ScrollBarImageColor3 = Color3.new(1, 1, 1),
		ScrollBarImageTransparency = 0.6,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		Visible = (id == P.tab),
		Parent = P.pagesRoot,
	})
	if not page then return nil end
	make("UIListLayout", {
		Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder, Parent = page,
	})
	pad(page, 10, 10, 8, 10)
	P.pages[id] = page
	return page
end

local function showTab(id)
	if not P.pagesRoot then return end
	P.tab = id
	CONFIG.ui.tab = id
	saveCfg()
	for tid, page in pairs(P.pages) do
		page.Visible = (tid == id)
	end
	for tid, btn in pairs(P.navBtns) do
		local on = (tid == id)
		btn.TextColor3 = on and C_TEXT or C_DIM
		btn.BackgroundColor3 = on and C_BG2 or C_BG
		btn.BackgroundTransparency = on and 0.15 or 1
		local dot = P.navDots[tid]
		if dot then dot.Visible = on end
	end
	local page = pageOf(id)
	if page and P.refresh[id] then pcall(P.refresh[id]) end
end

local function applyScale()
	if not P.win then return end
	local sc = P.win:FindFirstChild("UIScale")
	if not sc then
		sc = make("UIScale", { Parent = P.win })
	end
	if sc then sc.Scale = clamp(CONFIG.ui.scale or 1, 0.8, 1.5) end
end

local function applyOpacity()
	if not P.win then return end
	P.win.BackgroundTransparency = clamp(0.04 + (CONFIG.ui.opacity or 0), 0.04, 0.55)
end

local function setOpen(open)
	P.open = open and true or false
	if P.win then P.win.Visible = P.open end
end

local function setMinimized(min)
	P.minimized = min and true or false
	if not P.body or not P.win then return end
	if P.minimized then
		P.savedH = P.win.Size.Y.Offset
		P.body.Visible = false
		P.win.Size = UDim2.new(P.win.Size.X.Scale, P.win.Size.X.Offset, 0, TOPBAR)
	else
		P.body.Visible = true
		local h = P.savedH or CONFIG.ui.h
		P.win.Size = UDim2.new(P.win.Size.X.Scale, P.win.Size.X.Offset, 0, h + 8)
	end
end

local function bindDrag(obj)
	if not obj then return end
	local dragging, startPos, startMouse = false, nil, nil
	obj.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			startPos = P.win.Position
			startMouse = input.Position
		end
	end)
	UIS.InputChanged:Connect(function(input)
		if not dragging then return end
		if input.UserInputType ~= Enum.UserInputType.MouseMovement
			and input.UserInputType ~= Enum.UserInputType.Touch then return end
		local sc = clamp(CONFIG.ui.scale or 1, 0.8, 1.5)
		local d = input.Position - startMouse
		P.win.Position = UDim2.new(
			startPos.X.Scale, startPos.X.Offset + round(d.X / sc),
			startPos.Y.Scale, startPos.Y.Offset + round(d.Y / sc)
		)
	end)
	UIS.InputEnded:Connect(function(input)
		if not dragging then return end
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			dragging = false
			CONFIG.ui.x = round(P.win.Position.X.Offset)
			CONFIG.ui.y = round(P.win.Position.Y.Offset)
			saveCfg()
		end
	end)
end

local function bindResize(obj, mode)
	if not obj then return end
	local on, s0, m0 = false, nil, nil
	obj.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			on = true
			s0 = P.win.AbsoluteSize
			m0 = input.Position
		end
	end)
	UIS.InputChanged:Connect(function(input)
		if not on then return end
		if input.UserInputType ~= Enum.UserInputType.MouseMovement
			and input.UserInputType ~= Enum.UserInputType.Touch then return end
		local d = input.Position - m0
		-- AbsoluteSize 含 UIScale，先除回去再写 Size
		local sc = clamp(CONFIG.ui.scale or 1, 0.8, 1.5)
		local w = s0.X
		local h = s0.Y
		if mode ~= "b" then w = clamp(s0.X + d.X, MIN_W * sc, 1400 * sc) end
		if mode ~= "r" then h = clamp(s0.Y + d.Y, MIN_H * sc, 1000 * sc) end
		P.win.Size = UDim2.new(0, round(w / sc), 0, round(h / sc))
	end)
	UIS.InputEnded:Connect(function(input)
		if not on then return end
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			on = false
			CONFIG.ui.w = round(P.win.Size.X.Offset)
			CONFIG.ui.h = round(P.win.Size.Y.Offset)
			saveCfg()
		end
	end)
end

local function buildPanel()
	if P.gui then return P.gui end
	local ui = CONFIG.ui
	local gui = make("ScreenGui", {
		Name = "SG_QoL_v1",
		IgnoreGuiInset = true,
		ResetOnSpawn = false,
		DisplayOrder = 999996,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	})
	if not gui then return nil end
	attachGui(gui)
	P.gui = gui

	local win = make("Frame", {
		Name = "Window",
		Position = UDim2.new(0, ui.x or 60, 0, ui.y or 60),
		Size = UDim2.new(0, clamp(ui.w or 620, MIN_W, 1400), 0, clamp(ui.h or 440, MIN_H, 1000)),
		BackgroundColor3 = C_BG,
		BackgroundTransparency = 0.04,
		BorderSizePixel = 0,
		ClipsDescendants = true,
		Parent = gui,
	})
	corner(win, 12)
	strokeOf(win, C_LINE, 1, 0.35)
	make("UIScale", { Scale = clamp(ui.scale or 1, 0.8, 1.5), Parent = win })
	P.win = win
	applyOpacity()

	-- 顶栏
	local bar = make("Frame", {
		Name = "TopBar",
		Size = UDim2.new(1, 0, 0, TOPBAR),
		BackgroundColor3 = C_BG2,
		BackgroundTransparency = 0.25,
		BorderSizePixel = 0,
		Parent = win,
	})
	make("UICorner", { CornerRadius = UDim.new(0, 12), Parent = bar })
	P.topBar = bar

	label(bar, "DOORS MULTIPLAYER PANEL", {
		ts = 13, bold = true, col = C_TEXT,
		size = UDim2.new(1, -140, 1, 0), pos = UDim2.new(0, 14, 0, 0),
	})
	label(bar, "v1.0", {
		ts = 10, bold = true, col = ACCENT,
		size = UDim2.new(0, 30, 1, 0), pos = UDim2.new(1, -138, 0, 0),
	})
	button(bar, {
		text = "—", size = UDim2.new(0, 26, 0, 22), pos = UDim2.new(1, -84, 0, 7),
		bg = C_BG, onClick = function() setMinimized(not P.minimized) end,
	})
	button(bar, {
		text = "×", size = UDim2.new(0, 26, 0, 22), pos = UDim2.new(1, -52, 0, 7),
		bg = C_BG, col = C_RED, onClick = function() setOpen(false) end,
	})
	bindDrag(bar)

	-- 主体
	local body = make("Frame", {
		Name = "Body",
		Size = UDim2.new(1, 0, 1, -TOPBAR),
		Position = UDim2.new(0, 0, 0, TOPBAR),
		BackgroundTransparency = 1,
		Parent = win,
	})
	P.body = body

	local nav = make("Frame", {
		Name = "Nav",
		Size = UDim2.new(0, NAV_W, 1, 0),
		BackgroundColor3 = C_BG,
		BackgroundTransparency = 0.35,
		BorderSizePixel = 0,
		Parent = body,
	})
	make("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder, Parent = nav })
	pad(nav, 8, 8, 10, 8)

	local pagesRoot = make("Frame", {
		Name = "Pages",
		Size = UDim2.new(1, -NAV_W, 1, 0),
		Position = UDim2.new(0, NAV_W, 0, 0),
		BackgroundTransparency = 1,
		ClipsDescendants = true,
		Parent = body,
	})
	P.pagesRoot = pagesRoot

	for i, t in ipairs(TABS) do
		local btn = make("TextButton", {
			Name = "Nav_" .. t.id,
			Text = t.name,
			Size = UDim2.new(1, 0, 0, 28),
			BackgroundColor3 = C_BG,
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			AutoButtonColor = false,
			Font = FONT_BOLD,
			TextSize = 12,
			TextColor3 = C_DIM,
			TextXAlignment = Enum.TextXAlignment.Left,
			LayoutOrder = i,
			Parent = nav,
		})
		corner(btn, 7)
		pad(btn, 10, 6, 0, 0)
		local dot = make("Frame", {
			Size = UDim2.new(0, 3, 0, 14), Position = UDim2.new(0, 3, 0.5, -7),
			BackgroundColor3 = ACCENT, BorderSizePixel = 0, Visible = false, Parent = btn,
		})
		corner(dot, 2)
		P.navBtns[t.id] = btn
		P.navDots[t.id] = dot
		btn.Activated:Connect(function() showTab(t.id) end)
	end

	-- 缩放 / 拉边角
	local br = make("TextButton", {
		Name = "GripBR", Text = "", Size = UDim2.new(0, 14, 0, 14),
		Position = UDim2.new(1, -14, 1, -14), BackgroundTransparency = 1,
		AutoButtonColor = false, Parent = win,
	})
	if br then
		for i = 1, 3 do
			local l = make("Frame", {
				Size = UDim2.new(0, 2 + i * 2, 0, 2), Position = UDim2.new(0, 10 - i * 3, 0, 10 - i * 2),
				BackgroundColor3 = C_MUTE, BackgroundTransparency = 0.25, BorderSizePixel = 0, Parent = br,
			})
			corner(l, 1)
		end
		bindResize(br, "br")
	end
	local edgeR = make("TextButton", { Name = "GripR", Text = "", Size = UDim2.new(0, 6, 1, -TOPBAR),
		Position = UDim2.new(1, -6, 0, TOPBAR), BackgroundTransparency = 1, AutoButtonColor = false, Parent = win })
	bindResize(edgeR, "r")
	local edgeB = make("TextButton", { Name = "GripB", Text = "", Size = UDim2.new(1, -20, 0, 6),
		Position = UDim2.new(0, 0, 1, -6), BackgroundTransparency = 1, AutoButtonColor = false, Parent = win })
	bindResize(edgeB, "b")

	for _, t in ipairs(TABS) do pageOf(t.id) end
	showTab(P.tab)
	if not P.open then win.Visible = false end
	return gui
end

--=====================================================================
--  6. 玩家信息页（沿用 v0.1 的读法与配色）
--=====================================================================
local HP_GREEN = Color3.fromRGB(88, 226, 140)
local HP_AMBER = Color3.fromRGB(255, 196, 84)
local HP_RED   = Color3.fromRGB(255, 96, 88)
local HP_DEAD  = Color3.fromRGB(126, 140, 134)

local function hpColor(r)
	if r <= 0 then return HP_DEAD end
	if r < 0.3 then return HP_RED end
	if r < 0.6 then return HP_AMBER end
	return HP_GREEN
end

local function buildPlayerPage()
	local page = pageOf("player")
	if not page then return end
	section(page, "全员状态", 1)
	local listBox = make("Frame", {
		Name = "Rows", Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1,
		LayoutOrder = 2, Parent = page,
	})
	make("UIListLayout", { Padding = UDim.new(0, 5), SortOrder = Enum.SortOrder.LayoutOrder, Parent = listBox })
	P.playerBox = listBox

	local opts = make("Frame", {
		Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1, LayoutOrder = 3, Parent = page,
	})
	make("UIListLayout", { Padding = UDim.new(0, 2), SortOrder = Enum.SortOrder.LayoutOrder, Parent = opts })
	toggle(opts, {
		label = "名字后面显示距离", order = 1, value = true,
		onChange = function(v) P.showDist = v end,
	})
	toggle(opts, {
		label = "只列活着的玩家", order = 2, value = false,
		onChange = function(v) P.aliveOnly = v end,
	})

	P.refresh.player = function()
		local box = P.playerBox
		if not box then return end
		local me = lp()
		local myRoot
		if me and me.Character then
			myRoot = me.Character:FindFirstChild("HumanoidRootPart")
		end
		local list = {}
		for _, pl in ipairs(Players:GetPlayers()) do
			local char = pl.Character
			local hum = char and char:FindFirstChildOfClass("Humanoid")
			local hp = (hum and hum.Health) or 0
			local max = (hum and hum.MaxHealth) or 100
			if not max or max <= 0 then max = 100 end
			local dead = (not hum) or hp <= 0.01
			if not (P.aliveOnly and dead) then
				local dist
				if P.showDist ~= false and char and myRoot then
					local rp = char:FindFirstChild("HumanoidRootPart")
						or char:FindFirstChild("UpperTorso")
						or char:FindFirstChild("Torso")
					if rp then
						local ok, m = pcall(function() return (myRoot.Position - rp.Position).Magnitude end)
						if ok and m then dist = round(m) end
					end
				end
				table.insert(list, { name = pl.Name, hp = hp, max = max, dead = dead,
					dist = dist, me = (pl == me) })
			end
		end
		table.sort(list, function(a, b)
			if a.me ~= b.me then return a.me end
			if a.dead ~= b.dead then return b.dead end
			return a.name < b.name
		end)
		for i, d in ipairs(list) do
			local row = P.playerRows[i]
			if not row then
				local f = make("Frame", {
					Name = "P" .. i, Size = UDim2.new(1, 0, 0, 42),
					BackgroundColor3 = C_BG2, BackgroundTransparency = 0.35,
					BorderSizePixel = 0, LayoutOrder = i, Parent = box,
				})
				corner(f, 8)
				local nm = label(f, "", { ts = 13, bold = true, size = UDim2.new(1, -90, 0, 20), pos = UDim2.new(0, 10, 0, 3), trunc = true })
				local hpT = label(f, "", { ts = 13, bold = true, size = UDim2.new(0, 80, 0, 20), pos = UDim2.new(1, -90, 0, 3), x = Enum.TextXAlignment.Right })
				local trk = make("Frame", {
					Size = UDim2.new(1, -20, 0, 6), Position = UDim2.new(0, 10, 0, 28),
					BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 0.88,
					BorderSizePixel = 0, Parent = f,
				})
				corner(trk, 3)
				local fill = make("Frame", { Size = UDim2.new(1, 0, 1, 0), BackgroundColor3 = HP_GREEN, BorderSizePixel = 0, Parent = trk })
				corner(fill, 3)
				row = { frame = f, name = nm, hp = hpT, fill = fill }
				P.playerRows[i] = row
			end
			local f = row.frame
			f.Visible = true
			f.LayoutOrder = i
			local txt = d.name
			if d.me then txt = "你 · " .. txt end
			if d.dist then txt = txt .. "  " .. d.dist .. "m" end
			row.name.Text = txt
			row.name.TextColor3 = d.me and HP_GREEN or C_TEXT
			if d.dead then
				row.hp.Text = "已倒下"
				row.hp.TextColor3 = C_DIM
				row.fill.Size = UDim2.new(0, 0, 1, 0)
				row.fill.BackgroundColor3 = HP_DEAD
			else
				row.hp.Text = string.format("%d / %d", round(d.hp), round(d.max))
				row.hp.TextColor3 = C_TEXT
				local ratio = clamp(d.hp / d.max, 0, 1)
				row.fill.Size = UDim2.new(ratio, 0, 1, 0)
				row.fill.BackgroundColor3 = hpColor(ratio)
			end
		end
		for i = #list + 1, #P.playerRows do
			P.playerRows[i].frame.Visible = false
		end
	end
end

--=====================================================================
--  7. 队伍雷达
--=====================================================================
local function buildRadarPage()
	local page = pageOf("radar")
	if not page then return end
	section(page, "相对方位（以你为中心，上 = 你的正前方）", 1)

	local canvas = make("Frame", {
		Name = "Canvas", Size = UDim2.new(0, CONFIG.radar.size or 210, 0, CONFIG.radar.size or 210),
		BackgroundColor3 = C_BG2, BackgroundTransparency = 0.1,
		BorderSizePixel = 0, LayoutOrder = 2, Parent = page,
	})
	corner(canvas, 10)
	strokeOf(canvas, C_LINE, 1, 0.4)
	make("UICorner", { CornerRadius = UDim.new(0, 10), Parent = canvas })

	for i = 1, 3 do
		local ring = make("Frame", {
			Size = UDim2.new(i * 0.3, 0, i * 0.3, 0),
			AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, 0),
			BackgroundTransparency = 1, BorderSizePixel = 1,
			BorderColor3 = C_LINE, Parent = canvas,
		})
		corner(ring, 999)
	end
	local crossH = make("Frame", { Size = UDim2.new(1, -16, 0, 1), Position = UDim2.new(0, 8, 0.5, 0), BackgroundColor3 = C_LINE, BackgroundTransparency = 0.55, BorderSizePixel = 0, Parent = canvas })
	local crossV = make("Frame", { Size = UDim2.new(0, 1, 1, -16), Position = UDim2.new(0.5, 0, 0, 8), BackgroundColor3 = C_LINE, BackgroundTransparency = 0.55, BorderSizePixel = 0, Parent = canvas })
	local meDot = make("Frame", { Size = UDim2.new(0, 7, 0, 7), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, 0), BackgroundColor3 = ACCENT, BorderSizePixel = 0, Parent = canvas })
	corner(meDot, 4)
	label(canvas, "前", { ts = 10, bold = true, col = C_MUTE, size = UDim2.new(0, 16, 0, 12), pos = UDim2.new(0.5, -8, 0, 3), x = Enum.TextXAlignment.Center })
	label(canvas, "后", { ts = 10, bold = true, col = C_MUTE, size = UDim2.new(0, 16, 0, 12), pos = UDim2.new(0.5, -8, 1, -14), x = Enum.TextXAlignment.Center })
	P.radar.canvas = canvas

	local info = label(page, "等待角色…", { ts = 11, col = C_DIM, size = UDim2.new(1, 0, 0, 16), order = 3 })
	P.radar.info = info

	slider(page, {
		label = "雷达半径", min = 40, max = 400, step = 10, value = CONFIG.radar.range or 140,
		fmt = function(v) return round(v) .. "m" end, order = 4,
		onCommit = function(v) CONFIG.radar.range = round(v); saveCfg() end,
	})
	slider(page, {
		label = "雷达尺寸", min = 140, max = 340, step = 10, value = CONFIG.radar.size or 210,
		fmt = function(v) return round(v) .. "px" end, order = 5,
		onLive = function(v)
			canvas.Size = UDim2.new(0, round(v), 0, round(v))
		end,
		onCommit = function(v) CONFIG.radar.size = round(v); saveCfg() end,
	})

	P.refresh.radar = function()
		local me = lp()
		local char = me and me.Character
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		local root = char and (char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("UpperTorso") or char:FindFirstChild("Torso"))
		if not (hum and root) then
			if P.radar.info then P.radar.info.Text = "等待角色…" end
			for _, d in pairs(P.radar.dots) do d.frame.Visible = false end
			return
		end

		local cf = root.CFrame
		local pos = cf.Position
		local look = cf.LookVector
		local yaw = math.atan2(look.X, -look.Z)
		local range = CONFIG.radar.range or 140
		local cw = (P.radar.canvas and P.radar.canvas.AbsoluteSize.X) or (CONFIG.radar.size or 210)
		if not cw or cw < 40 then return end
		local half = cw / 2

		local rows = {}
		local idx = 0
		for _, pl in ipairs(Players:GetPlayers()) do
			if pl ~= me then
				local c = pl.Character
				local h = c and c:FindFirstChildOfClass("Humanoid")
				local r = c and (c:FindFirstChild("HumanoidRootPart") or c:FindFirstChild("UpperTorso") or c:FindFirstChild("Torso"))
				if h and r then
					local dx = r.Position.X - pos.X
					local dz = r.Position.Z - pos.Z
					local dist = math.sqrt(dx * dx + dz * dz)
					-- 世界 → 本地：fwd 为前方分量，rgt 为右方分量（上 = 正前方）
					local sy, cy = math.sin(yaw), math.cos(yaw)
					local fwd = dx * sy - dz * cy
					local rgt = dx * cy + dz * sy
					idx = idx + 1
					local dot = P.radar.dots[idx]
					if not dot then
						local f = make("Frame", {
							Size = UDim2.new(0, 8, 0, 8), AnchorPoint = Vector2.new(0.5, 0.5),
							BackgroundColor3 = C_BLUE, BorderSizePixel = 0, Parent = P.radar.canvas,
						})
						corner(f, 4)
						local nl = make("TextLabel", {
							Text = "", Size = UDim2.new(0, 60, 0, 10), Position = UDim2.new(0.5, -30, 0, 8),
							BackgroundTransparency = 1, Font = FONT, TextSize = 9, TextColor3 = C_DIM,
							TextXAlignment = Enum.TextXAlignment.Center, Parent = f,
						})
						dot = { frame = f, name = nl }
						P.radar.dots[idx] = dot
					end
					local dead = (h.Health <= 0.01)
					dot.frame.Visible = true
					dot.frame.BackgroundColor3 = dead and HP_DEAD or (h.Health / math.max(1, h.MaxHealth) < 0.35 and C_AMBER or C_BLUE)
					local px = half + (rgt / range) * half
					local pz = half - (fwd / range) * half
					local out = (math.abs(px - half) > half - 4) or (math.abs(pz - half) > half - 4)
					if out then
						dot.frame.BackgroundTransparency = 0.55
					else
						dot.frame.BackgroundTransparency = 0
					end
					dot.frame.Position = UDim2.new(0, round(clamp(px, 4, cw - 4)), 0, round(clamp(pz, 4, cw - 4)))
					dot.name.Text = pl.Name .. (dead and " †" or "")
					dot.name.TextColor3 = dead and C_MUTE or C_DIM
					table.insert(rows, string.format("%s %dm%s", pl.Name, round(dist), dead and " †" or ""))
				else
					idx = idx + 1
					local dot = P.radar.dots[idx]
					if dot then dot.frame.Visible = false end
				end
			end
		end
		for i = idx + 1, #P.radar.dots do
			P.radar.dots[i].frame.Visible = false
		end
		if P.radar.info then
			if #rows == 0 then
				P.radar.info.Text = "视野内没有其他玩家"
			else
				P.radar.info.Text = string.format("半径 %dm · %d 人：%s", range, #rows, table.concat(rows, "  "))
			end
		end
	end
end

--=====================================================================
--  8. 道具信息
--=====================================================================
local function toolNames(pl)
	local out = {}
	local bp = pl:FindFirstChildOfClass("Backpack")
	if bp then
		for _, t in ipairs(bp:GetChildren()) do
			if t:IsA("Tool") then table.insert(out, t.Name) end
		end
	end
	local ch = pl.Character
	if ch then
		for _, t in ipairs(ch:GetChildren()) do
			if t:IsA("Tool") then table.insert(out, t.Name .. "（手持）") end
		end
	end
	return out
end

local function buildInvPage()
	local page = pageOf("inv")
	if not page then return end
	section(page, "队友持有道具（读 Backpack / Character 下的 Tool）", 1)
	local box = make("Frame", {
		Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1, LayoutOrder = 2, Parent = page,
	})
	make("UIListLayout", { Padding = UDim.new(0, 5), SortOrder = Enum.SortOrder.LayoutOrder, Parent = box })
	P.invBox = box

	label(page, "说明：只读客户端可见的 Tool 实例；游戏没复制过来的数据不会去猜。", {
		ts = 11, col = C_MUTE, size = UDim2.new(1, 0, 0, 28), wrap = true, order = 3,
	})

	P.refresh.inv = function()
		if not P.invBox then return end
		local players = Players:GetPlayers()
		table.sort(players, function(a, b) return a.Name < b.Name end)
		for i, pl in ipairs(players) do
			local row = P.invRows[i]
			if not row then
				local f = make("Frame", {
					Size = UDim2.new(1, 0, 0, 26), BackgroundColor3 = C_BG2,
					BackgroundTransparency = 0.35, BorderSizePixel = 0, LayoutOrder = i, Parent = P.invBox,
				})
				corner(f, 7)
				local nm = label(f, "", { ts = 12, bold = true, size = UDim2.new(0, 110, 1, 0), pos = UDim2.new(0, 9, 0, 0), trunc = true })
				local chips = make("Frame", {
					Size = UDim2.new(1, -122, 1, 0), Position = UDim2.new(0, 118, 0, 0),
					BackgroundTransparency = 1, Parent = f,
				})
				make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 4), VerticalAlignment = Enum.VerticalAlignment.Center, Parent = chips })
				row = { frame = f, name = nm, chips = chips, sig = "" }
				P.invRows[i] = row
			end
			row.frame.Visible = true
			row.frame.LayoutOrder = i
			local me = lp()
			row.name.Text = (pl == me) and ("你 · " .. pl.Name) or pl.Name
			row.name.TextColor3 = (pl == me) and HP_GREEN or C_TEXT

			local names = toolNames(pl)
			local sig = table.concat(names, "|")
			if sig ~= row.sig then
				row.sig = sig
				for _, c in ipairs(row.chips:GetChildren()) do
					if c:IsA("GuiObject") then c:Destroy() end
				end
				if #names == 0 then
					chip(row.chips, "空手", C_LINE, 1)
				else
					for k, nm in ipairs(names) do
						chip(row.chips, nm, ACCENT_D, k)
					end
				end
			end
		end
		for i = #players + 1, #P.invRows do
			P.invRows[i].frame.Visible = false
		end
	end
end

--=====================================================================
--  9. 事件日志页
--=====================================================================
local function buildLogPage()
	local page = pageOf("log")
	if not page then return end
	local head = make("Frame", {
		Size = UDim2.new(1, 0, 0, 30), BackgroundTransparency = 1, LayoutOrder = 1, Parent = page,
	})
	label(head, "多人事件（启发式识别）", { ts = 12, bold = true, col = ACCENT, size = UDim2.new(1, -150, 1, 0) })
	button(head, {
		text = "仅重要", size = UDim2.new(0, 66, 0, 22), pos = UDim2.new(1, -140, 0, 4),
		onClick = function()
			Log.filterImportant = not Log.filterImportant
			for _, e in ipairs(Log.rows) do
				if e.frame then e.frame.Visible = (not Log.filterImportant) or e.imp end
			end
		end,
	})
	button(head, {
		text = "清空", size = UDim2.new(0, 56, 0, 22), pos = UDim2.new(1, -66, 0, 4),
		onClick = function()
			Log.clear()
		end,
	})

	local list = make("ScrollingFrame", {
		Name = "List", Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = C_BG2, BackgroundTransparency = 0.45, BorderSizePixel = 0,
		CanvasSize = UDim2.new(1, 0, 0, 0), AutomaticCanvasSize = Enum.AutomaticSize.None,
		ScrollBarThickness = 4, ScrollBarImageColor3 = Color3.new(1, 1, 1),
		ScrollBarImageTransparency = 0.6, LayoutOrder = 2, Parent = page,
	})
	corner(list, 8)
	make("UIListLayout", { Padding = UDim.new(0, 2), SortOrder = Enum.SortOrder.LayoutOrder, Parent = list })
	pad(list, 8, 8, 6, 6)
	Log.page = list

	label(page, "能识别的：加入 / 离开 / 受伤 / 死亡 / 复活 / 疑似开门 / 实体出现 / 房间切换。"
		.. "识别不了的（例如某张图的具体机关）不在日志里编造。", {
		ts = 11, col = C_MUTE, size = UDim2.new(1, 0, 0, 30), wrap = true, order = 3,
	})
end

--=====================================================================
--  10. 动作系统
--=====================================================================
local DANCES = {
	{ name = "Dance · R15",  id = "507771019" },
	{ name = "Dance2 · R15", id = "507777826" },
	{ name = "Dance3 · R15", id = "507772104" },
	{ name = "Dance · R6",   id = "182435998" },
	{ name = "Dance2 · R6",  id = "182436842" },
	{ name = "Dance3 · R6",  id = "182436216" },
}

local Dance = { track = nil, anim = nil, playing = false }

local function stopDance()
	if Dance.track then
		pcall(function() Dance.track:Stop() end)
		pcall(function() Dance.track:Destroy() end)
	end
	Dance.track = nil
	Dance.playing = false
end

local function playDance(idx)
	local me = lp()
	local char = me and me.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not hum then return false, "没有角色" end
	local pick = DANCES[clamp(idx or CONFIG.dance.anim or 1, 1, #DANCES)]
	if not pick then return false, "动作不存在" end
	stopDance()
	local ok = pcall(function()
		local animator = hum:FindFirstChildOfClass("Animator")
		if not animator then
			animator = make("Animator", { Parent = hum })
		end
		local a = Instance.new("Animation")
		a.AnimationId = "rbxassetid://" .. pick.id
		Dance.anim = a
		local t = animator:LoadAnimation(a)
		t.Looped = true
		t:Play()
		Dance.track = t
		Dance.playing = true
	end)
	if not ok then return false, "播放失败" end
	return true
end

local function buildDancePage()
	local page = pageOf("dance")
	if not page then return end
	section(page, "快捷键跳舞", 1)

	local box = make("Frame", {
		Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1, LayoutOrder = 2, Parent = page,
	})
	make("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder, Parent = box })

	keybind(box, {
		label = "跳舞快捷键", order = 1, value = CONFIG.keys.dance,
		onChange = function(name) CONFIG.keys.dance = name; saveCfg() end,
	})

	local grid = make("Frame", {
		Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1, LayoutOrder = 2, Parent = box,
	})
	make("UIGridLayout", { CellSize = UDim2.new(0.49, -3, 0, 28), CellPadding = UDim2.new(0, 6, 0, 6), Parent = grid })

	local btns = {}
	local function paint()
		for i, b in ipairs(btns) do
			local on = (i == clamp(CONFIG.dance.anim or 1, 1, #DANCES))
			b.BackgroundColor3 = on and ACCENT_D or C_BG2
			b.TextColor3 = on and ACCENT or C_TEXT
		end
	end
	for i, d in ipairs(DANCES) do
		local b = button(grid, {
			text = d.name, size = UDim2.new(1, 0, 1, 0), bg = C_BG2,
			onClick = function()
				CONFIG.dance.anim = i
				paint()
				saveCfg()
				if Dance.playing then playDance(i) end
			end,
		})
		btns[i] = b
	end
	paint()

	local row = make("Frame", {
		Size = UDim2.new(1, 0, 0, 30), BackgroundTransparency = 1, LayoutOrder = 3, Parent = box,
	})
	button(row, {
		text = "播放 / 停止", size = UDim2.new(0, 110, 0, 26), pos = UDim2.new(0, 0, 0, 2),
		bg = ACCENT_D, col = ACCENT,
		onClick = function()
			if Dance.playing then
				stopDance()
				logAdd("misc", "已停止动作")
			else
				local ok = playDance(CONFIG.dance.anim)
				logAdd("misc", ok and ("播放动作 " .. DANCES[clamp(CONFIG.dance.anim or 1, 1, #DANCES)].name) or "播放失败")
			end
		end,
	})
	button(row, {
		text = "打开游戏菜单跳舞", size = UDim2.new(0, 140, 0, 26), pos = UDim2.new(0, 118, 0, 2),
		onClick = function()
			logAdd("misc", "聊天栏输入 /e dance 也可以，游戏内动作菜单在下方表情按钮")
		end,
	})

	label(page, "同步说明：这里用客户端 Animator 播放，只有你自己看得到。"
		.. "要让别人看到必须由服务器播放动画，本系统不做越权远程调用、不碰反作弊，所以不保证围观者可见。", {
		ts = 11, col = C_MUTE, size = UDim2.new(1, 0, 0, 46), wrap = true, order = 3,
	})
end

--=====================================================================
--  11. 设置页
--=====================================================================
local function buildSettingPage()
	local page = pageOf("setting")
	if not page then return end

	section(page, "界面", 1)
	local uiBox = make("Frame", {
		Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1, LayoutOrder = 2, Parent = page,
	})
	make("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder, Parent = uiBox })

	slider(uiBox, {
		label = "面板缩放", min = 0.8, max = 1.5, step = 0.05, value = CONFIG.ui.scale or 1,
		fmt = function(v) return round(v * 100) .. "%" end, order = 1,
		onLive = function(v) CONFIG.ui.scale = v; applyScale() end,
		onCommit = function(v) CONFIG.ui.scale = v; applyScale(); saveCfg() end,
	})
	slider(uiBox, {
		label = "面板透明度", min = 0, max = 0.45, step = 0.05, value = CONFIG.ui.opacity or 0,
		fmt = function(v) return round(v * 100) .. "%" end, order = 2,
		onLive = function(v) CONFIG.ui.opacity = v; applyOpacity() end,
		onCommit = function(v) CONFIG.ui.opacity = v; applyOpacity(); saveCfg() end,
	})
	slider(uiBox, {
		label = "浮动血量字号", min = 10, max = 22, step = 1, value = CONFIG.ui.hudFont or 13,
		fmt = function(v) return round(v) .. "px" end, order = 3,
		onCommit = function(v) CONFIG.ui.hudFont = round(v); saveCfg(); Hud.ensure(true) end,
	})
	local rowDef = make("Frame", { Size = UDim2.new(1, 0, 0, 30), BackgroundTransparency = 1, LayoutOrder = 4, Parent = uiBox })
	label(rowDef, "默认打开的分类", { ts = 12, col = C_TEXT, size = UDim2.new(1, -92, 0, 16), pos = UDim2.new(0, 0, 0, 7) })
	local defBtn
	defBtn = button(rowDef, {
		text = "", size = UDim2.new(0, 86, 0, 22), pos = UDim2.new(1, -86, 0, 4),
		onClick = function()
			local cur = 1
			for i, t in ipairs(TABS) do if t.id == (CONFIG.ui.tab or "player") then cur = i end end
			local next_ = TABS[(cur % #TABS) + 1]
			CONFIG.ui.tab = next_.id
			defBtn.Text = next_.name
			saveCfg()
		end,
	})
	do
		local nm = "玩家信息"
		for _, t in ipairs(TABS) do if t.id == (CONFIG.ui.tab or "player") then nm = t.name end end
		defBtn.Text = nm
	end

	section(page, "模块开关", 3)
	local modBox = make("Frame", {
		Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1, LayoutOrder = 4, Parent = page,
	})
	make("UIListLayout", { Padding = UDim.new(0, 2), SortOrder = Enum.SortOrder.LayoutOrder, Parent = modBox })
	local modList = {
		{ key = "player", label = "玩家信息（血量 / 距离）" },
		{ key = "radar",  label = "队伍雷达" },
		{ key = "inv",    label = "道具信息" },
		{ key = "log",    label = "事件日志" },
		{ key = "dance",  label = "动作系统" },
	}
	for i, m in ipairs(modList) do
		toggle(modBox, {
			label = m.label, order = i, value = CONFIG.mods[m.key] ~= false,
			onChange = function(v)
				CONFIG.mods[m.key] = v
				saveCfg()
				if m.key == "player" then
					Hud.setVisible(v and CONFIG.ui.hudOn)
				elseif m.key == "log" then
					if Log.page then Log.page.Visible = v end
					if v then Log.rebuild() end
				elseif m.key == "radar" then
					local cv = P.radar.canvas
					if cv then cv.Visible = v end
				end
				logAdd("misc", m.label .. (v and " 已开启" or " 已关闭"))
			end,
		})
	end
	toggle(modBox, {
		label = "浮动血量小窗（游戏中常驻）", order = 6, value = CONFIG.ui.hudOn ~= false,
		onChange = function(v)
			CONFIG.ui.hudOn = v
			saveCfg()
			Hud.setVisible(v and CONFIG.mods.player ~= false)
		end,
	})

	section(page, "快捷键", 5)
	local keyBox = make("Frame", {
		Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1, LayoutOrder = 6, Parent = page,
	})
	make("UIListLayout", { Padding = UDim.new(0, 2), SortOrder = Enum.SortOrder.LayoutOrder, Parent = keyBox })
	local keyList = {
		{ key = "panel", label = "显示 / 隐藏面板" },
		{ key = "radar", label = "显示 / 隐藏雷达页" },
		{ key = "log",   label = "跳到事件日志" },
		{ key = "dance", label = "跳舞" },
	}
	for i, k in ipairs(keyList) do
		keybind(keyBox, {
			label = k.label, order = i, value = CONFIG.keys[k.key],
			onChange = function(name)
				for _, other in ipairs(keyList) do
					if other.key ~= k.key and CONFIG.keys[other.key] == name then
						CONFIG.keys[other.key] = "—"
						logAdd("misc", "快捷键冲突：" .. k.label .. " 抢了 " .. other.label .. " 的 " .. name)
					end
				end
				CONFIG.keys[k.key] = name
				saveCfg()
				P.rebuildKeys()
			end,
		})
	end

	section(page, "其他", 7)
	local misc = make("Frame", {
		Size = UDim2.new(1, 0, 0, 30), BackgroundTransparency = 1, LayoutOrder = 8, Parent = page,
	})
	button(misc, {
		text = "重置全部设置", size = UDim2.new(0, 120, 0, 26), pos = UDim2.new(0, 0, 0, 2),
		col = C_RED,
		onClick = function()
			mergeInto(CONFIG, DEFAULT)
			saveCfg(true)
			logAdd("misc", "设置已重置，重载脚本后完全生效")
			applyScale(); applyOpacity()
		end,
	})
	label(page, "配置存在 QoL_v1.json；改完立即生效并写盘（1 秒防抖）。", {
		ts = 11, col = C_MUTE, size = UDim2.new(1, 0, 0, 24), wrap = true, order = 9,
	})
end

--=====================================================================
--  12. 浮动血量小窗（保留 v0.1 的能力，默认开）
--=====================================================================
Hud = { gui = nil, root = nil, title = nil, rows = {}, collapsed = false }
local function hudMeasure()
	local fs = clamp(round(CONFIG.ui.hudFont or 13), 10, 22)
	return {
		fs = fs,
		nameH = round(fs * 1.2),
		rowPad = math.max(4, round(fs * 0.36)),
		barH = math.max(5, round(fs * 0.42)),
		rowH = math.max(4, round(fs * 0.36)) * 2 + round(fs * 1.2) + math.max(5, round(fs * 0.42)),
		headH = round(fs * 2.0),
		side = math.max(9, round(fs * 0.8)),
		hpW = round(fs * 7.4),
		width = round(fs * 20.5),
	}
end

local function hudRow(i, M)
	local f = make("Frame", {
		Name = "R" .. i, Size = UDim2.new(1, 0, 0, M.rowH),
		BackgroundColor3 = C_BG, BackgroundTransparency = 0.35,
		BorderSizePixel = 0, LayoutOrder = i, Parent = Hud.root,
	})
	corner(f, math.max(4, round(M.fs * 0.6)))
	local nm = label(f, "", { ts = M.fs, bold = true, size = UDim2.new(1, -(M.side * 2 + M.hpW), 0, M.nameH), pos = UDim2.new(0, M.side, 0, M.rowPad), trunc = true })
	local hp = label(f, "", { ts = M.fs, bold = true, size = UDim2.new(0, M.hpW, 0, M.nameH), pos = UDim2.new(1, -(M.side + M.hpW), 0, M.rowPad), x = Enum.TextXAlignment.Right })
	local trk = make("Frame", {
		Size = UDim2.new(1, -(M.side * 2), 0, M.barH), Position = UDim2.new(0, M.side, 0, M.rowPad + M.nameH),
		BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 0.86, BorderSizePixel = 0, Parent = f,
	})
	corner(trk, 3)
	local fill = make("Frame", { Size = UDim2.new(1, 0, 1, 0), BackgroundColor3 = HP_GREEN, BorderSizePixel = 0, Parent = trk })
	corner(fill, 3)
	return { frame = f, name = nm, hp = hp, fill = fill }
end

function Hud.ensure(rebuild)
	if Hud.gui and Hud.gui.Parent and not rebuild then return end
	if Hud.gui then pcall(function() Hud.gui:Destroy() end) end
	Hud.rows = {}
	local M = hudMeasure()
	local gui = make("ScreenGui", {
		Name = "SG_QoL_HUD", IgnoreGuiInset = true, ResetOnSpawn = false,
		DisplayOrder = 999997, ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	})
	if not gui then return end
	attachGui(gui)
	Hud.gui = gui

	local root = make("Frame", {
		Name = "Root", AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -(CONFIG.ui.hudX or 16), 0, CONFIG.ui.hudY or 96),
		Size = UDim2.new(0, M.width, 0, M.headH),
		AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, Parent = gui,
	})
	make("UIListLayout", { Padding = UDim.new(0, math.max(4, round(M.fs * 0.34))), SortOrder = Enum.SortOrder.LayoutOrder, Parent = root })
	Hud.root = root

	local head = make("Frame", {
		Name = "H", Size = UDim2.new(1, 0, 0, M.headH), BackgroundColor3 = C_BG,
		BackgroundTransparency = 0.22, BorderSizePixel = 0, LayoutOrder = 0, Parent = root,
	})
	corner(head, math.max(5, round(M.fs * 0.7)))
	strokeOf(head, C_LINE, 1.2, 0.45)
	Hud.title = label(head, "全员血量", { ts = M.fs, bold = true, size = UDim2.new(1, -(M.side * 2), 1, 0), pos = UDim2.new(0, M.side, 0, 0) })

	local function bind(o)
		if not o then return end
		o.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1
				or input.UserInputType == Enum.UserInputType.Touch then
				hudDrag = { root = root, gui = gui, start = root.AbsolutePosition,
					mouse = input.Position, moved = false }
			end
		end)
	end
	bind(head)
	bind(Hud.title)
	Hud.setVisible(CONFIG.ui.hudOn ~= false and CONFIG.mods.player ~= false)
	Hud.update()
end

function Hud.setVisible(v)
	if Hud.gui then Hud.gui.Enabled = v and true or false end
end

function Hud.update()
	if not (Hud.gui and Hud.gui.Parent) then return end
	if not (CONFIG.ui.hudOn ~= false and CONFIG.mods.player ~= false) then return end
	local M = hudMeasure()
	local me = lp()
	local myRoot
	if me and me.Character then
		myRoot = me.Character:FindFirstChild("HumanoidRootPart")
	end
	local list = {}
	for _, pl in ipairs(Players:GetPlayers()) do
		local char = pl.Character
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if hum then
			local hp = hum.Health
			local max = hum.MaxHealth
			if not max or max <= 0 then max = 100 end
			local dist
			if myRoot then
				local rp = char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("UpperTorso") or char:FindFirstChild("Torso")
				if rp then
					local ok, m = pcall(function() return (myRoot.Position - rp.Position).Magnitude end)
					if ok and m then dist = round(m) end
				end
			end
			table.insert(list, { name = pl.Name, hp = hp, max = max, dead = hp <= 0.01, dist = dist, me = (pl == me) })
		end
	end
	table.sort(list, function(a, b)
		if a.me ~= b.me then return a.me end
		return a.hp > b.hp
	end)
	Hud.collapsed = (CONFIG.ui.hudCollapsed == true)
	if Hud.title then
		Hud.title.Text = string.format("全员血量 · %d 人", #list) .. (Hud.collapsed and "  ▸" or "")
	end
	for i, d in ipairs(list) do
		local row = Hud.rows[i]
		if not row then
			row = hudRow(i, M)
			Hud.rows[i] = row
		end
		row.frame.Visible = not Hud.collapsed
		row.frame.LayoutOrder = i
		local txt = d.name
		if d.me then txt = "你 · " .. txt end
		if d.dist then txt = txt .. "  " .. d.dist .. "m" end
		row.name.Text = txt
		row.name.TextColor3 = d.me and HP_GREEN or C_TEXT
		if d.dead then
			row.hp.Text = "已倒下"
			row.hp.TextColor3 = C_DIM
			row.fill.Size = UDim2.new(0, 0, 1, 0)
			row.fill.BackgroundColor3 = HP_DEAD
		else
			row.hp.Text = string.format("%d / %d", round(d.hp), round(d.max))
			row.hp.TextColor3 = C_TEXT
			local r = clamp(d.hp / d.max, 0, 1)
			row.fill.Size = UDim2.new(r, 0, 1, 0)
			row.fill.BackgroundColor3 = hpColor(r)
		end
	end
	for i = #list + 1, #Hud.rows do
		Hud.rows[i].frame.Visible = false
	end
end

--=====================================================================
--  13. 事件探测（只观察，不改游戏）
--=====================================================================
local ENTITY = {
	Rush = true, Ambush = true, Screech = true, Eyes = true, Halt = true, Figure = true,
	Seek = true, Glitch = true, Timothy = true, Jack = true, Snare = true, Hide = true,
	Dupe = true, Shadow = true, Void = true, Window = true, Lookman = true, Dread = true,
	Blitz = true, Sally = true, A90 = true, A60 = true, A120 = true,
}

local seenEntity = setmetatable({}, { __mode = "k" })
local seenDoor = setmetatable({}, { __mode = "k" })
local spawned = setmetatable({}, { __mode = "k" })
local lastHurt = {}

local function wireCharacter(pl)
	local char = pl.Character
	if not char then return end
	local hum = char:FindFirstChildOfClass("Humanoid")
	if not hum then return end
	local nm = pl.Name
	if spawned[pl] then
		logAdd("phase", nm .. " 复活 / 换了角色")
	else
		spawned[pl] = true
		lastHurt[nm] = hum.Health
	end
	hum.HealthChanged:Connect(function(hp)
		local prev = lastHurt[nm] or hp
		if hp > 0.01 and hp < prev - 0.5 then
			local t = os.clock()
			if not lastHurt[nm .. "_t"] or t - lastHurt[nm .. "_t"] > 2 then
				lastHurt[nm .. "_t"] = t
				logAdd("hurt", string.format("%s 受伤 −%d（剩 %d）", nm, round(prev - hp), round(hp)))
			end
		elseif hp > prev + 0.5 and prev > 0.01 then
			logAdd("heal", string.format("%s 回了 %d 血", nm, round(hp - prev)))
		end
		lastHurt[nm] = hp
	end)
	hum.Died:Connect(function()
		if lastHurt[nm .. "_dead"] then return end
		lastHurt[nm .. "_dead"] = true
		logAdd("death", nm .. " 死亡")
		task.delay(2, function() lastHurt[nm .. "_dead"] = nil end)
	end)
end

local function wireEvents()
	Players.PlayerAdded:Connect(function(pl)
		logAdd("join", pl.Name .. " 加入服务器")
		pl.CharacterAdded:Connect(function() task.wait(0.4) wireCharacter(pl) end)
		if pl.Character then task.wait(0.2) wireCharacter(pl) end
	end)
	Players.PlayerRemoving:Connect(function(pl)
		logAdd("leave", pl.Name .. " 离开")
	end)
	for _, pl in ipairs(Players:GetPlayers()) do
		pl.CharacterAdded:Connect(function() task.wait(0.4) wireCharacter(pl) end)
		if pl.Character then pcall(wireCharacter, pl) end
	end
	if lp() then
		lp().CharacterAdded:Connect(function() task.wait(0.6) Hud.update() end)
	end

	workspace.ChildAdded:Connect(function(inst)
		pcall(function()
			local nm = inst.Name
			local key = nm:gsub("%d+", ""):gsub("%s+", "")
			if ENTITY[key] and not seenEntity[inst] then
				seenEntity[inst] = true
				logAdd("entity", "实体出现：" .. nm)
				return
			end
			local low = nm:lower()
			if (low:find("door") or low:find("gate")) and not seenDoor[inst] then
				seenDoor[inst] = true
				logAdd("door", "疑似开门：" .. nm)
				return
			end
			if low:find("room") then
				logAdd("room", "房间切换：" .. nm)
			end
		end)
	end)

	pcall(function()
		local rooms = workspace:FindFirstChild("CurrentRooms") or workspace:FindFirstChild("CurrentRoom")
		if rooms then
			rooms.ChildAdded:Connect(function(r)
				logAdd("room", "进入新房间：" .. r.Name)
			end)
			logAdd("misc", "已挂上房间变化监听（" .. rooms.Name .. "）")
		else
			logAdd("misc", "没有找到 CurrentRooms，房间事件仅靠 workspace 变化推断")
		end
	end)

	pcall(function()
		workspace:GetAttributeChangedSignal("GameState"):Connect(function()
			logAdd("phase", "阶段变化：" .. tostring(workspace:GetAttribute("GameState")))
		end)
	end)
end

--=====================================================================
--  14. 快捷键
--=====================================================================
local function keyName(input)
	if input.KeyCode and input.KeyCode ~= Enum.KeyCode.Unknown then return input.KeyCode.Name end
	return nil
end

UIS.InputBegan:Connect(function(input, processed)
	if capture then
		local nm = keyName(input)
		if nm and input.UserInputType == Enum.UserInputType.Keyboard then
			local f = capture
			capture = nil
			f(nm)
			return
		end
	end
	if input.UserInputType ~= Enum.UserInputType.Keyboard then return end
	if processed then return end
	local nm = keyName(input)
	if not nm then return end

	if nm == CONFIG.keys.panel then
		setOpen(not P.open)
	elseif nm == CONFIG.keys.dance then
		if CONFIG.mods.dance == false then return end
		if Dance.playing then stopDance() else playDance(CONFIG.dance.anim) end
	elseif nm == CONFIG.keys.radar then
		if CONFIG.mods.radar == false then return end
		if not P.open then setOpen(true) end
		showTab((P.tab == "radar") and "player" or "radar")
	elseif nm == CONFIG.keys.log then
		if CONFIG.mods.log == false then return end
		if not P.open then setOpen(true) end
		showTab("log")
	end
end)

-- 滑块 / 浮动小窗的全局拖拽收尾（模块级只挂一次）
UIS.InputChanged:Connect(function(input)
	if input.UserInputType ~= Enum.UserInputType.MouseMovement
		and input.UserInputType ~= Enum.UserInputType.Touch then return end

	if hudDrag then
		local h = hudDrag
		local d = input.Position - h.mouse
		if math.abs(d.X) > 3 or math.abs(d.Y) > 3 then h.moved = true end
		if h.moved and h.root and h.root.Parent then
			h.root.AnchorPoint = Vector2.new(0, 0)
			h.root.Position = UDim2.new(0, round(h.start.X + d.X), 0, round(h.start.Y + d.Y))
		end
	end

	if not drag then return end
	local d = drag
	if not (d.track and d.track.Parent) then drag = nil return end
	local w = d.track.AbsoluteSize.X
	if not w or w <= 0 then return end
	local a = clamp((input.Position.X - d.track.AbsolutePosition.X) / w, 0, 1)
	d.value = d.min + (d.max - d.min) * a
	d.set(d.value, true)
end)

UIS.InputEnded:Connect(function(input)
	if input.UserInputType ~= Enum.UserInputType.MouseButton1
		and input.UserInputType ~= Enum.UserInputType.Touch then return end

	if hudDrag then
		local h = hudDrag
		hudDrag = nil
		if h.moved then
			if h.gui then
				local gs = h.gui.AbsoluteSize
				CONFIG.ui.hudX = math.max(0, round((gs.X or 1280) - (h.root.AbsolutePosition.X + h.root.AbsoluteSize.X)))
				CONFIG.ui.hudY = math.max(0, round(h.root.AbsolutePosition.Y))
				saveCfg()
			end
		else
			CONFIG.ui.hudCollapsed = not (CONFIG.ui.hudCollapsed == true)
			saveCfg()
			Hud.update()
		end
	end

	if not drag then return end
	local d = drag
	drag = nil
	d.set(d.value, false)
end)

--=====================================================================
--  15. 启动
--=====================================================================
loadCfg()

P.showDist = true
P.aliveOnly = false
P.rebuildKeys = function() end

buildPanel()
buildPlayerPage()
buildRadarPage()
buildInvPage()
buildLogPage()
buildDancePage()
buildSettingPage()

task.spawn(function()
	while not lp() do task.wait(0.2) end
	Hud.ensure()
	wireEvents()
	logAdd("misc", "QoL v1.0 已启动：" .. tostring(lp().Name))
end)

-- 0.5s：玩家 / 浮动血量 / 事件日志刷新
task.spawn(function()
	while true do
		task.wait(0.5)
		pcall(function()
			if CONFIG.mods.player ~= false then Hud.update() end
			if P.pages.player and P.pages.player.Visible and P.refresh.player then P.refresh.player() end
		end)
	end
end)

-- 1s：道具
task.spawn(function()
	while true do
		task.wait(1)
		pcall(function()
			if CONFIG.mods.inv ~= false and P.pages.inv and P.pages.inv.Visible and P.refresh.inv then
				P.refresh.inv()
			end
		end)
	end
end)

-- 0.12s：雷达
task.spawn(function()
	while true do
		task.wait(0.12)
		pcall(function()
			if CONFIG.mods.radar ~= false and P.pages.radar and P.pages.radar.Visible and P.refresh.radar then
				P.refresh.radar()
			end
		end)
	end
end)

print("[QoL v1.0] 面板已加载：" .. tostring(CONFIG.keys.panel) .. " 开关面板，左侧 6 个分类切换")
print("[QoL v1.0] 快捷键：面板 " .. CONFIG.keys.panel .. " / 雷达 " .. CONFIG.keys.radar
	.. " / 日志 " .. CONFIG.keys.log .. " / 跳舞 " .. CONFIG.keys.dance)

getgenv().QoL = {
	config = CONFIG,
	open = function(v) setOpen(v ~= false) end,
	tab = function(id) showTab(id) end,
	log = logAdd,
	dance = function(i) if i then CONFIG.dance.anim = i end return playDance(CONFIG.dance.anim) end,
	stopDance = stopDance,
	hud = function(v) Hud.setVisible(v ~= false) end,
	save = function() saveCfg(true) end,
}
