--[[
    硬核 v0.1 · 单功能版（只加一个「全员血量」）

    源脚本：https://pastefy.app/Bf6hbDY4/raw
    这里只做一件事：右上角把所有人的血量画出来（名字 + 87/100 + 血条）。
    换肤 / 壁纸 / 光影 / 音乐 / 翻译 一概没有，原脚本的界面、逻辑、回调一行都不动。

    手势：拖标题栏 = 挪位置；点标题栏 = 折叠 / 展开
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

	width     = 320,    -- 面板宽度（210 → 320）
	fontSize  = 15,     -- 主体字号（10 → 15）；行高、血条、标题栏都按它推
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
--  尺寸：全部按 CONFIG.fontSize 推出来，改一个数字整块跟着变
--=====================================================================
local FS      = math.max(10, round(CONFIG.fontSize or 15))
local NAME_H  = round(FS * 1.20)               -- 名字 / 数字那一行的高度
local ROW_PAD = math.max(4, round(FS * 0.38))  -- 行内上下留白
local BAR_H   = math.max(5, round(FS * 0.42))  -- 血条厚度
local ROW_H   = ROW_PAD * 2 + NAME_H + BAR_H   -- 每行总高
local HEAD_H  = round(FS * 2.05)               -- 标题栏高
local SIDE    = math.max(10, round(FS * 0.80)) -- 左右内边距
local HP_W    = round(FS * 7.6)                -- 右侧「87 / 100」宽度

local function hpColor(r)
	if r <= 0 then return HP_DEAD end
	if r < 0.3 then return HP_RED end
	if r < 0.6 then return HP_AMBER end
	return HP_GREEN
end

--=====================================================================
--  全员血量 HUD
--=====================================================================
local HPHud = {
	gui = nil, root = nil, header = nil, title = nil,
	rows = {}, count = 0, running = false, collapsed = false,
	posX = nil, posY = nil,
}

local function hpRow(i)
	local frame = make("Frame", {
		Name = "R" .. i,
		Size = UDim2.new(1, 0, 0, ROW_H),
		BackgroundColor3 = C_BG,
		BackgroundTransparency = 0.42,
		BorderSizePixel = 0,
		LayoutOrder = i,
		Visible = false,
	})
	make("UICorner", { CornerRadius = UDim.new(0, 10), Parent = frame })

	local name = make("TextLabel", {
		Text = "",
		Size = UDim2.new(1, -(SIDE * 2 + HP_W), 0, NAME_H),
		Position = UDim2.new(0, SIDE, 0, ROW_PAD),
		BackgroundTransparency = 1,
		Font = FONT_BOLD,
		TextSize = FS,
		TextColor3 = C_TEXT,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Parent = frame,
	})
	local hp = make("TextLabel", {
		Text = "",
		Size = UDim2.new(0, HP_W, 0, NAME_H),
		Position = UDim2.new(1, -(SIDE + HP_W), 0, ROW_PAD),
		BackgroundTransparency = 1,
		Font = FONT_BOLD,
		TextSize = FS,
		TextColor3 = C_TEXT,
		TextXAlignment = Enum.TextXAlignment.Right,
		Parent = frame,
	})

	local track = make("Frame", {
		Name = "Track",
		Size = UDim2.new(1, -(SIDE * 2), 0, BAR_H),
		Position = UDim2.new(0, SIDE, 0, ROW_PAD + NAME_H),
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
		collapsed = HPHud.collapsed and true or false,
	})
end

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
		Size = UDim2.new(0, CONFIG.width, 0, HEAD_H),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Parent = gui,
	})
	make("UIListLayout", {
		Padding = UDim.new(0, math.max(4, round(FS * 0.35))),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = root,
	})
	if math.abs((CONFIG.scale or 1) - 1) > 0.01 then
		make("UIScale", { Scale = clamp(CONFIG.scale, 0.7, 1.8), Parent = root })
	end
	HPHud.root = root

	local header = make("Frame", {
		Name = "Header",
		Size = UDim2.new(1, 0, 0, HEAD_H),
		BackgroundColor3 = C_BG,
		BackgroundTransparency = 0.28,
		BorderSizePixel = 0,
		LayoutOrder = 0,
		Parent = root,
	})
	make("UICorner", { CornerRadius = UDim.new(0, 11), Parent = header })
	make("UIStroke", { Color = C_LINE, Thickness = 1.5, Transparency = 0.45, Parent = header })
	HPHud.header = header

	HPHud.title = make("TextLabel", {
		Text = "全员血量",
		Size = UDim2.new(1, -(SIDE * 2), 1, 0),
		Position = UDim2.new(0, SIDE, 0, 0),
		BackgroundTransparency = 1,
		Font = FONT_BOLD,
		TextSize = FS,
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
		HPHud.posX = math.max(0, round((size.X or 1280) - (abs.X + (root.AbsoluteSize.X or CONFIG.width))))
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
	HPHud.gui, HPHud.root, HPHud.header, HPHud.title = nil, nil, nil, nil
	HPHud.rows = {}
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
end

HPHud.start()

print("[硬核v0.1] 单功能版已启动：全员血量 HUD（拖标题栏挪位置，点一下折叠）")

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
