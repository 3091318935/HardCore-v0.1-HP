--[[
    硬核 v0.1 · 单功能版（只加一个「全员血量」）

    源脚本：https://pastefy.app/Bf6hbDY4/raw
    这里只做一件事：右上角把所有人的血量画出来（名字 + 87/100 + 血条）。
    换肤 / 壁纸 / 光影 / 音乐 / 翻译 一概没有，原脚本的界面、逻辑、回调一行都不动。

    手势：拖标题栏 = 挪位置；点标题栏 = 折叠 / 展开
          标题上方那条「− 〇 大小 100% ＋」= 调整个 HUD 的大小（点 −/＋、拖滑条、点百分比重置 100%）
    刷新：默认 0.25s；只读 Humanoid.Health / MaxHealth，不写任何游戏状态
--]]

local CONFIG = {
	scriptUrl   = "https://pastefy.app/Bf6hbDY4/raw",
	fallbackUrl = "https://raw.githubusercontent.com/Zero0Star/RipperNewSound/master/Doors-HardCore.lua",
	runOriginal = true,
	waitTimeout = 30,

	refresh   = 0.25,   -- 轮询间隔（秒）
	showDist  = true,   -- 名字后面带距离
	aliveOnly = false,  -- true = 只列活人
	sortByHp  = false,  -- true = 按血量降序

	width     = 320,    -- 字号 = fontSize 时的面板宽度；调大小按比例走
	fontSize  = 15,     -- 默认字号（10 → 15）；行高、血条、标题栏、内边距全部按它推
	sizeMin   = 10,     -- 「大小」调节下限（字号）
	sizeMax   = 26,     -- 「大小」调节上限（字号）
	topX      = 16,     -- 距右边缘
	topY      = 96,     -- 距顶部
	scale     = 1,      -- 整体再缩放 0.8 ~ 1.4

	cfgFile   = "SG_HP_v01.json",
}

local Players      = game:GetService("Players")
local UIS          = game:GetService("UserInputService")

-- 注入时机不一定已经有 LocalPlayer，一律现取，不要缓存
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
			vs = '"' .. v:gsub('"', '\\"') .. '"'
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

local function writeCfg(tbl)
	if not (writefile and CONFIG.cfgFile) then return end
	pcall(function() writefile(CONFIG.cfgFile, jsonEncode(tbl)) end)
end

local function readCfg()
	if not (readfile and isfile) then return nil end
	local ok, rawText = pcall(function()
		if isfile(CONFIG.cfgFile) then return readfile(CONFIG.cfgFile) end
	end)
	if not ok or type(rawText) ~= "string" then return nil end
	local ok2, data = pcall(function() return game:GetService("HttpService"):JSONDecode(rawText) end)
	if ok2 and type(data) == "table" then return data end
	return nil
end

--=====================================================================
--  颜色
--=====================================================================
local C_BG     = Color3.fromRGB(24, 26, 30)
local C_TEXT   = Color3.fromRGB(234, 237, 242)
local C_DIM    = Color3.fromRGB(150, 158, 168)
local C_LINE   = Color3.fromRGB(70, 76, 86)
local HP_GREEN = Color3.fromRGB(88, 226, 140)
local HP_AMBER = Color3.fromRGB(255, 196, 84)
local HP_RED   = Color3.fromRGB(255, 96, 88)
local HP_DEAD  = Color3.fromRGB(126, 140, 134)

local FONT_BODY = Enum.Font.Gotham
local FONT_BOLD = Enum.Font.GothamSemibold

--=====================================================================
--  尺寸表：全部由「字号」推出来 —— 改大小 = 换一个字号 + 重算这张表
--=====================================================================
local SIZE_MIN = math.max(8, round(CONFIG.sizeMin or 10))
local SIZE_MAX = math.max(SIZE_MIN + 2, round(CONFIG.sizeMax or 26))
local BASE_FS  = math.max(8, round(CONFIG.fontSize or 15))

local function measure(fs)
	local f      = clamp(round(fs), SIZE_MIN, SIZE_MAX)
	local nameH  = round(f * 1.20)                 -- 名字 / 数字那一行的行高
	local rowPad = math.max(4, round(f * 0.38))    -- 行内上下留白
	local barH   = math.max(5, round(f * 0.42))    -- 血条厚度
	return {
		fs      = f,
		nameH   = nameH,
		rowPad  = rowPad,
		barH    = barH,
		rowH    = rowPad * 2 + nameH + barH,         -- 每行总高
		headH   = round(f * 2.05),                   -- 标题栏 / 调节条高度基准
		side    = math.max(10, round(f * 0.80)),     -- 左右内边距
		hpW     = round(f * 7.6),                    -- 右侧「87 / 100」宽度
		gap     = math.max(4, round(f * 0.35)),      -- 行与行间距
		radius  = math.max(4, round(f * 0.67)),      -- 圆角
		width   = math.max(240, round((CONFIG.width or 320) * f / BASE_FS)),
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
--  全员血量 HUD
--=====================================================================
local HPHud = {
	gui = nil, root = nil, header = nil, title = nil, bar = nil,
	rows = {}, count = 0, running = false, collapsed = false,
	posX = nil, posY = nil,
}

-- 大小调节条的拖拽状态（模块级的 UIS 连接只建一次，重建 GUI 时不重复挂）
local sizeDrag = { on = false, fs = nil, track = nil, fill = nil, label = nil }

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
		BackgroundTransparency = 0,
		BorderSizePixel = 0,
		Parent = track,
	})
	make("UICorner", { CornerRadius = UDim.new(1, 0), Parent = fill })

	return { frame = frame, name = name, hp = hp, fill = fill }
end

local function saveState()
	writeCfg({
		x = HPHud.posX or CONFIG.topX,
		y = HPHud.posY or CONFIG.topY,
		fs = M.fs,
		collapsed = HPHud.collapsed and true or false,
	})
end

-- 改大小：换字号 → 重算尺寸表 → 拆掉旧 GUI，下一帧按新尺寸重画
local function applySize(fs, noSave)
	local f = clamp(round(fs), SIZE_MIN, SIZE_MAX)
	if f == M.fs then return end
	M = measure(f)

	sizeDrag.on, sizeDrag.track, sizeDrag.fill, sizeDrag.label = false, nil, nil, nil
	if HPHud.gui then pcall(function() HPHud.gui:Destroy() end) end
	HPHud.gui, HPHud.root, HPHud.header, HPHud.title, HPHud.bar = nil, nil, nil, nil, nil
	HPHud.rows = {}

	if not noSave then saveState() end
	if lp() then pcall(HPHud.ensure) end
	if HPHud.update then pcall(HPHud.update) end
end

HPHud.setSize = applySize

--=====================================================================
--  调节条的拖拽（滑条）
--=====================================================================
local function sizeFromX(x)
	local track = sizeDrag.track
	if not (track and track.Parent) then return nil end
	local w = track.AbsoluteSize.X
	if not w or w <= 0 then return nil end
	local t = clamp((x - track.AbsolutePosition.X) / w, 0, 1)
	return SIZE_MIN + t * (SIZE_MAX - SIZE_MIN)
end

local function sizePreview(fs)
	local f = clamp(round(fs), SIZE_MIN, SIZE_MAX)
	sizeDrag.fs = f
	if sizeDrag.fill then
		sizeDrag.fill.Size = UDim2.new((f - SIZE_MIN) / math.max(1, SIZE_MAX - SIZE_MIN), 0, 1, 0)
	end
	if sizeDrag.label then
		sizeDrag.label.Text = string.format("大小 %d%%", pct(f))
	end
end

UIS.InputChanged:Connect(function(input)
	if not sizeDrag.on then return end
	if input.UserInputType ~= Enum.UserInputType.MouseMovement
		and input.UserInputType ~= Enum.UserInputType.Touch then return end
	local v = sizeFromX(input.Position.X)
	if v then sizePreview(v) end
end)

UIS.InputEnded:Connect(function(input)
	if not sizeDrag.on then return end
	if input.UserInputType ~= Enum.UserInputType.MouseButton1
		and input.UserInputType ~= Enum.UserInputType.Touch then return end
	sizeDrag.on = false
	local v = sizeFromX(input.Position.X) or sizeDrag.fs
	if v then applySize(v) end
end)

function HPHud.ensure()
	if HPHud.gui and HPHud.gui.Parent then return HPHud.gui end
	if HPHud.gui and not HPHud.gui.Parent and lp() then
		attachGui(HPHud.gui)
		if HPHud.gui.Parent then return HPHud.gui end
	end

	local gui = make("ScreenGui", {
		Name = "SG_HP_v01",
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
		Position = UDim2.new(1, -(HPHud.posX or CONFIG.topX), 0, HPHud.posY or CONFIG.topY),
		Size = UDim2.new(0, M.width, 0, M.headH),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Parent = gui,
	})
	make("UIListLayout", {
		Padding = UDim.new(0, M.gap),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = root,
	})
	if math.abs((CONFIG.scale or 1) - 1) > 0.01 then
		make("UIScale", { Scale = clamp(CONFIG.scale, 0.7, 1.8), Parent = root })
	end
	HPHud.root = root

	--=============================================================
	--  大小调节条（在「全员血量」标题上面一行）
	--  LayoutOrder = -1 → 永远排在最上面
	--=============================================================
	local barH  = clamp(round(M.fs * 1.75), 26, 40)
	local btn   = clamp(round(barH * 0.85), 20, 32)
	local lbW   = clamp(round(M.fs * 5.6), 72, 104)
	local lbTS  = clamp(round(M.fs * 0.72), 12, 17)

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
			AutoButtonColor = true,
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
	if minus then
		minus.Activated:Connect(function() applySize(M.fs - 1) end)
	end
	if plus then
		plus.Activated:Connect(function() applySize(M.fs + 1) end)
	end

	-- 滑条
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

	-- 百分比（点一下回到 100%）
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
	if sLabel then
		sLabel.Activated:Connect(function() applySize(BASE_FS) end)
	end

	-- 拖拽只改预览（fill + 百分比），松手才真正重建，避免拖到一半控件被销毁
	sizeDrag.track, sizeDrag.fill, sizeDrag.label = sTrack, sFill, sLabel
	sizeDrag.fs, sizeDrag.on = M.fs, false

	local function bindTrack(obj)
		if not obj then return end
		obj.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1
				or input.UserInputType == Enum.UserInputType.Touch then
				sizeDrag.on = true
				local v = sizeFromX(input.Position.X)
				if v then sizePreview(v) end
			end
		end)
	end
	bindTrack(sTrack)
	bindTrack(sFill)

	local header = make("Frame", {
		Name = "Header",
		Size = UDim2.new(1, 0, 0, M.headH),
		BackgroundColor3 = C_BG,
		BackgroundTransparency = 0.28,
		BorderSizePixel = 0,
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

	-- 拖动 + 单击折叠（标题文字是子节点，两边都绑，点哪都能拖）
	local dragStart, startPos, moved = nil, nil, false
	local function bindDrag(obj)
		if not obj then return end
		obj.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1
				or input.UserInputType == Enum.UserInputType.Touch then
				dragStart = input.Position
				startPos = Vector2.new(root.AbsolutePosition.X, root.AbsolutePosition.Y)
				moved = false
			end
		end)
	end
	bindDrag(header)
	bindDrag(HPHud.title)
	UIS.InputChanged:Connect(function(input)
		if not dragStart then return end
		if input.UserInputType ~= Enum.UserInputType.MouseMovement
			and input.UserInputType ~= Enum.UserInputType.Touch then return end
		local d = input.Position - dragStart
		if math.abs(d.X) + math.abs(d.Y) > 4 then moved = true end
		if not moved then return end
		local nx = clamp(startPos.X + d.X, 0, (gui.AbsoluteSize.X or 1280) - 40)
		local ny = clamp(startPos.Y + d.Y, 0, (gui.AbsoluteSize.Y or 720) - 30)
		root.AnchorPoint = Vector2.new(0, 0)
		root.Position = UDim2.new(0, round(nx), 0, round(ny))
	end)
	local function endDrag()
		if not dragStart then return end
		dragStart = nil
		local abs, size = root.AbsolutePosition, gui.AbsoluteSize
		HPHud.posX = math.max(0, round((size.X or 1280) - (abs.X + (root.AbsoluteSize.X or M.width))))
		HPHud.posY = math.max(0, round(abs.Y))
		if not moved then
			HPHud.collapsed = not HPHud.collapsed
		end
		saveState()
	end
	UIS.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			endDrag()
		end
	end)

	return gui
end

function HPHud.update()
	if not (HPHud.gui and HPHud.gui.Parent) then return end
	HPHud.ensure()

	local lpRoot
	local me = lp()
	if me and me.Character then
		lpRoot = me.Character:FindFirstChild("HumanoidRootPart")
	end

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
			table.insert(data, { name = pl.Name, hp = hp, max = max, dead = dead,
				dist = dist, me = (pl == me) })
		end
	end

	if CONFIG.sortByHp then
		table.sort(data, function(a, b)
			if a.dead ~= b.dead then return b.dead end
			return a.hp > b.hp
		end)
	end

	HPHud.count = #data
	if HPHud.bar then HPHud.bar.Visible = not HPHud.collapsed end
	if HPHud.title then
		HPHud.title.Text = string.format("全员血量 · %d 人%s", #data, HPHud.collapsed and "  ▸" or "")
	end

	for i, d in ipairs(data) do
		local r = HPHud.rows[i]
		if not r then
			r = hpRow(i)
			HPHud.rows[i] = r
		end
		if r.frame.Parent ~= HPHud.root then r.frame.Parent = HPHud.root end
		r.frame.Visible = (not HPHud.collapsed)
		r.frame.Size = UDim2.new(1, 0, 0, M.rowH)
		r.frame.LayoutOrder = i
		r.frame.BackgroundColor3 = C_BG
		r.name.TextColor3 = d.me and HP_GREEN or C_TEXT
		r.hp.TextColor3 = d.dead and C_DIM or C_TEXT

		local label = d.name
		if d.me then label = "你 · " .. label end
		if d.dist then label = label .. "  " .. d.dist .. "m" end
		r.name.Text = label

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

function HPHud.stop()
	HPHud.running = false
end

function HPHud.destroy()
	HPHud.running = false
	pcall(function()
		if HPHud.gui then HPHud.gui:Destroy() end
	end)
	HPHud.gui, HPHud.root, HPHud.header, HPHud.title, HPHud.bar = nil, nil, nil, nil, nil
	sizeDrag.on, sizeDrag.track, sizeDrag.fill, sizeDrag.label = false, nil, nil, nil
	HPHud.rows = {}
end

function HPHud.getSize()
	return M.fs, pct(M.fs)
end

--=====================================================================
--  载入原脚本（不接受任何 UI 改造）
--=====================================================================
local function runOriginal()
	local urls = { CONFIG.scriptUrl, CONFIG.fallbackUrl }
	local tried = {}
	for _, url in ipairs(urls) do
		local ok, body = pcall(function() return game:HttpGet(url, true) end)
		if ok and type(body) == "string" and #body > 200 then
			local chunk, err = loadstring(body)
			if chunk then
				print("[硬核v0.1] 源脚本: " .. url)
				local ok2, e2 = pcall(chunk)
				if not ok2 then
					warn("[硬核v0.1] 源脚本运行报错: " .. tostring(e2))
				end
				return true
			end
			table.insert(tried, url .. " (loadstring: " .. tostring(err) .. ")")
		else
			table.insert(tried, url .. " (下载失败)")
		end
	end
	warn("[硬核v0.1] 原始脚本没能起来 -> " .. table.concat(tried, " | "))
	return false
end

--=====================================================================
--  启动
--=====================================================================
local cfg = readCfg()
if cfg then
	HPHud.posX = tonumber(cfg.x) or HPHud.posX
	HPHud.posY = tonumber(cfg.y) or HPHud.posY
	HPHud.collapsed = cfg.collapsed and true or false
	if tonumber(cfg.fs) then
		M = measure(tonumber(cfg.fs))
	end
end

HPHud.start()

print(string.format("[硬核v0.1] 单功能版已启动：全员血量 HUD（当前 %d%%，上方「− 大小 ＋」可调 %d~%d）",
	pct(M.fs), SIZE_MIN, SIZE_MAX))

if CONFIG.runOriginal then
	task.spawn(function()
		local waited = 0
		while not lp() and waited < CONFIG.waitTimeout do
			task.wait(0.2)
			waited = waited + 0.2
		end
		runOriginal()
	end)
end

getgenv().HPHud = HPHud
