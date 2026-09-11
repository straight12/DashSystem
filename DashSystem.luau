-- Discord: monsterchugger67 | Roblox: mitchzxz
-- Github: Straight12
-- jukedash v3, dash for my game
-- Q + WASD. W goes forward, A/D goes sideways, S goes back. just Q goes forward
-- this is only the dash system from an interconnected parkour system with many mechanics. i did some slight mods to make this work alone.
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local Debris = game:GetService("Debris")
local TweenService = game:GetService("TweenService")

local plr = Players.LocalPlayer
local char = script.Parent
local hum = char:WaitForChild("Humanoid")
local root = char:WaitForChild("HumanoidRootPart")
local anim = hum:WaitForChild("Animator")
local cam = workspace.CurrentCamera

-- all my tuning numbers in one place
-- cooldown 1.45 cus below 1.2 u can basically fly across the whole map lol
local TUNE = {}
TUNE.key = Enum.KeyCode.Q
TUNE.cooldown = 1.45
TUNE.buffer = 0.22 -- pressing Q a hair early still dashes. best feel change i made
TUNE.frontSpeed = 62
TUNE.sideSpeed = 66 -- sides faster but shorter
TUNE.backSpeed = 53 -- back is slower on purpose, retreating shouldnt be free
TUNE.frontTime = 0.45696
TUNE.sideTime = 0.387
TUNE.backTime = 0.628875 -- back lasts longer so u actually get away
TUNE.frontGrav = 0.05 -- front dash basically ignores gravity so u float
TUNE.sideGrav = 0.25
TUNE.keepMomentum = 0.15 -- keeps some of ur run speed. chaining sprint into dash feels so much better
TUNE.wallDist = 5
TUNE.fov = 8
TUNE.fovTime = 0.25
TUNE.shakeTime = 0.15
TUNE.shakeSize = 1.2

-- my anims. front has 2 (normal one + spinny one) so it doesnt look the same every dash
local ANIMS = {}
ANIMS.front = {"rbxassetid://136740523504887", "rbxassetid://107282381216422"}
ANIMS.left = "rbxassetid://136961258400118"
ANIMS.right = "rbxassetid://102166185387319"
ANIMS.back = "rbxassetid://74993314986279"

local SFX = {}
SFX.front = "rbxassetid://123548647357247"
SFX.side = "rbxassetid://123548647357247"
SFX.back = "rbxassetid://125473933827561" -- back has its own sound

-- dash object. one per character so respawns start fresh and dont share cooldowns
local Dash = {}
Dash.__index = Dash

function Dash.new(model)
	local d = setmetatable({}, Dash)
	d.model = model
	d.hum = model:WaitForChild("Humanoid")
	d.root = model:WaitForChild("HumanoidRootPart")
	d.anim = d.hum:WaitForChild("Animator")
	d.active = false
	d.last = 0
	d.qCount = 0 -- press counter so queued chains fire exactly once
	d.flip = 1 -- swaps between the 2 front anims
	d.tracks = {front = {}}
	d.sounds = {}
	d.sideParams = RaycastParams.new()
	d.sideParams.FilterDescendantsInstances = {model}
	d.sideParams.FilterType = Enum.RaycastFilterType.Exclude
	d.sideParams.IgnoreWater = true
	d.downParams = RaycastParams.new()
	d.downParams.FilterDescendantsInstances = {model}
	d.downParams.FilterType = Enum.RaycastFilterType.Exclude
	d.downParams.IgnoreWater = true
	d:loadAnims()
	d:loadSounds()
	return d
end
-- loads everything at spawn. i used to load on first dash and it froze for a split sec
-- Action4 so dash always beats the run anim. Looped false cus its a burst not a cycle
function Dash:loadAnims()
	local function one(id)
		local a = Instance.new("Animation")
		a.AnimationId = id
		local ok, t = pcall(function()
			return self.anim:LoadAnimation(a)
		end)
		if ok and t then
			t.Priority = Enum.AnimationPriority.Action4
			t.Looped = false
			return t
		end
		warn("[jukedash] anim wouldnt load: " .. tostring(id))
		return nil
	end
	for _, id in ipairs(ANIMS.front) do
		local t = one(id)
		if t then
			table.insert(self.tracks.front, t)
		end
	end
	self.tracks.left = one(ANIMS.left)
	self.tracks.right = one(ANIMS.right)
	self.tracks.back = one(ANIMS.back)
end

-- parks the sounds in the rootpart so theyre positional
-- low volume, spam gets loud fast
function Dash:loadSounds()
	local function one(id, vol)
		local snd = Instance.new("Sound")
		snd.SoundId = id
		snd.Volume = vol
		snd.RollOffMaxDistance = 100
		snd.RollOffMinDistance = 10
		snd.RollOffMode = Enum.RollOffMode.Inverse
		snd.Parent = self.root
		return snd
	end
	self.sounds.front = one(SFX.front, 0.15)
	self.sounds.side = one(SFX.side, 0.15)
	self.sounds.back = one(SFX.back, 0.12)
end

-- figures out front/side/back from keys + which way ur actually moving
-- S first cus backdash is the oh-shit button, it should always win ties
-- MoveDirection fallback is for mobile sticks where no keys are held
function Dash:pickType()
	local move = self.hum.MoveDirection
	local rel = self.root.CFrame:VectorToObjectSpace(move)
	if UserInputService:IsKeyDown(Enum.KeyCode.S) or rel.Z > 0.5 then
		return "back"
	end
	if UserInputService:IsKeyDown(Enum.KeyCode.A) or rel.X < -0.5 then
		return "left"
	end
	if UserInputService:IsKeyDown(Enum.KeyCode.D) or rel.X > 0.5 then
		return "right"
	end
	if UserInputService:IsKeyDown(Enum.KeyCode.W) then
		return "front"
	end
	if move.Magnitude > 0.1 then
		if math.abs(rel.X) <= 0.5 then
			return "front"
		end
		return rel.X < 0 and "left" or "right"
	end
	return "front"
end
-- world direction for the dash.
-- sides/back stay flat so slopes dont launch u into orbit lol
-- front goes where the crosshair points. aiming down just goes flat instead,
-- cus dashing into the floor felt awful in testing. up keeps a little lift tho
function Dash:aimDir(kind)
	local cf = self.root.CFrame
	if kind == "left" or kind == "right" then
		local v = cf.RightVector * (kind == "left" and -1 or 1)
		local flat = Vector3.new(v.X, 0, v.Z)
		if flat.Magnitude < 0.01 then
			flat = Vector3.new(0, 0, 1)
		end
		return flat.Unit
	end
	if kind == "back" then
		local v = -cf.LookVector
		local flat = Vector3.new(v.X, 0, v.Z)
		if flat.Magnitude < 0.01 then
			flat = -cf.LookVector
		end
		return flat.Unit
	end
	local vp = cam.ViewportSize
	local dir = cam:ViewportPointToRay(vp.X * 0.5, vp.Y * 0.5).Direction.Unit
	if dir.Y < 0 then
		local flat = Vector3.new(dir.X, 0, dir.Z)
		dir = flat.Magnitude > 0.01 and flat.Unit or Vector3.new(cf.LookVector.X, 0, cf.LookVector.Z).Unit
	end
	return self:capUp(dir)
end

-- caps vertical so u cant helicopter looking straight up
-- same cap runs every frame mid dash too, or aiming up mid dash would skip it
function Dash:capUp(dir)
	if dir.Y <= 0.85 then
		return dir
	end
	local flat = Vector3.new(dir.X, 0, dir.Z)
	if flat.Magnitude < 0.01 then
		return dir
	end
	local h = math.sqrt(math.max(0, 1 - 0.49))
	return Vector3.new(flat.Unit.X * h, 0.7, flat.Unit.Z * h).Unit
end

-- cheapest checks first. attribute read is basically free so it goes top
function Dash:canGo()
	if self.active or self.model:GetAttribute("IsDashing") == true then
		return false
	end
	if tick() - self.last < TUNE.cooldown then
		return false
	end
	if self.hum.Health <= 0 then
		return false
	end
	local st = self.hum:GetState()
	if st == Enum.HumanoidStateType.Seated or st == Enum.HumanoidStateType.Climbing then
		return false
	end
	return self.root:FindFirstChild("DashAttachment") == nil
end

-- front alternates 2 anims. restart if spammed so they dont overlap and look broken
function Dash:playAnim(kind)
	local track = self.tracks[kind]
	if kind == "front" then
		if #self.tracks.front == 0 then
			return nil
		end
		track = self.tracks.front[self.flip]
		self.flip = self.flip % #self.tracks.front + 1
	end
	if track then
		if track.IsPlaying then
			track:Stop(0)
		end
		track.TimePosition = 0
		track:Play(0.12, 1, 1)
	end
	return track
end

-- random pitch so repeat dashes dont sound identical
function Dash:playSfx(kind)
	local snd = self.sounds.front
	if kind == "back" then
		snd = self.sounds.back
	elseif kind == "left" or kind == "right" then
		snd = self.sounds.side
	end
	if snd then
		snd.PlaybackSpeed = math.random(90, 110) / 100
		snd:Play()
	end
end
-- cheap camera shake, no modules needed. fades out fast
function Dash:shakeCam()
	task.spawn(function()
		local start = os.clock()
		while os.clock() - start < TUNE.shakeTime do
			local k = 1 - (os.clock() - start) / TUNE.shakeTime
			local rx = math.rad((math.random() - 0.5) * 2 * TUNE.shakeSize * k)
			local ry = math.rad((math.random() - 0.5) * 2 * TUNE.shakeSize * k)
			cam.CFrame = cam.CFrame * CFrame.Angles(rx, ry, 0)
			RunService.Heartbeat:Wait()
		end
	end)
end

-- fov punch for speed feel
function Dash:feel()
	self:shakeCam()
	pcall(function() -- fov tween can fail if camera is being funny, dont care, dash anyway
		local base = cam.FieldOfView
		local tw = TweenService:Create(cam, TweenInfo.new(TUNE.fovTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {FieldOfView = base + TUNE.fov})
		tw:Play()
		tw.Completed:Once(function()
			TweenService:Create(cam, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {FieldOfView = base}):Play()
		end)
	end)
end

-- ends dash early at walls so u slide along em instead of clipping through
function Dash:wallAhead(dir)
	return workspace:Raycast(self.root.Position, dir * TUNE.wallDist, self.sideParams) ~= nil
end

-- peeks down so front dash cant drill u through the floor on hills
function Dash:floorNear()
	return workspace:Raycast(self.root.Position, Vector3.new(0, -3, 0), self.downParams) ~= nil
end

-- TODO: slide momentum into dash later, slide script is gone rn so skip
function Dash:fire(kind, dir)
	self.active = true
	self.model:SetAttribute("IsDashing", true)
	self.model:SetAttribute("DashType", kind) -- my combat script reads this later for dash attacks
	self.last = tick()
	local myPress = self.qCount -- presses after this point get chained at the end
	local speed = TUNE.frontSpeed
	local dur = TUNE.frontTime
	if kind == "left" or kind == "right" then
		speed = TUNE.sideSpeed
		dur = TUNE.sideTime
	elseif kind == "back" then
		speed = TUNE.backSpeed
		dur = TUNE.backTime
	end
	local entry = self.root.AssemblyLinearVelocity
	if entry.Y < 0 then -- falling into a dash kept all the fall speed and it felt broken
		local cut = kind == "front" and TUNE.frontGrav or TUNE.sideGrav
		self.root.AssemblyLinearVelocity = Vector3.new(entry.X, entry.Y * cut, entry.Z)
	end
	-- momentum carry. sprint -> dash keeps 15% of run speed on top, decays out
	local carry = Vector3.new(entry.X, 0, entry.Z) * TUNE.keepMomentum
	if carry.Magnitude > 25 then -- cap it, downhill sprint + dash was silly fast
		carry = carry.Unit * 25
	end
	self:playAnim(kind)
	self:playSfx(kind)
	self:feel()
	local att = Instance.new("Attachment")
	att.Name = "DashAttachment"
	att.Parent = self.root
	local lv = Instance.new("LinearVelocity")
	-- lv.MaxForce = 50000 -- old value, too weak, char just vibrated in place lol
	lv.MaxForce = 100000
	lv.ForceLimitsEnabled = true
	lv.RelativeTo = Enum.ActuatorRelativeTo.World
	lv.Attachment0 = att
	lv.VectorVelocity = dir * speed
	lv.Parent = att
	local grav = Instance.new("VectorForce")
	grav.Name = "DashGravHelp"
	grav.Attachment0 = att
	grav.RelativeTo = Enum.ActuatorRelativeTo.World
	grav.ApplyAtCenterOfMass = true
	grav.Force = Vector3.zero
	grav.Parent = att
	Debris:AddItem(att, dur + 0.15)
	local align = nil
	if kind == "front" then -- turn body toward crosshair mid dash, looks way better
		local rootAtt = self.model:FindFirstChild("RootAttachment", true)
		if rootAtt then
			align = Instance.new("AlignOrientation")
			align.Mode = Enum.OrientationAlignmentMode.OneAttachment
			align.Attachment0 = rootAtt
			align.Responsiveness = 60
			align.MaxTorque = 100000
			align.MaxAngularVelocity = math.rad(360)
			align.CFrame = CFrame.lookAt(Vector3.zero, dir, Vector3.yAxis)
			align.Parent = self.root
			self.hum.AutoRotate = false
			Debris:AddItem(align, dur + 0.1)
		end
	end
	local t0 = os.clock()
	local prev = t0
	local vy = self.root.AssemblyLinearVelocity.Y
	-- drive until time runs out or a wall stops us
	while os.clock() - t0 < dur do
		if self:wallAhead(dir) then
			break
		end
		if kind == "front" then -- re-aim every frame so u can curve it slightly
			local fresh = cam:ViewportPointToRay(cam.ViewportSize.X * 0.5, cam.ViewportSize.Y * 0.5).Direction.Unit
			if fresh.Y >= 0 then
				dir = self:capUp(fresh)
			end
			if align and align.Parent then
				local up = Vector3.yAxis
				if math.abs(dir:Dot(up)) > 0.99 then
					up = Vector3.xAxis
				end
				align.CFrame = align.CFrame:Lerp(CFrame.lookAt(Vector3.zero, dir, up), 0.28)
			end
		end
		local now = os.clock()
		local dt = math.min(now - prev, 0.05)
		prev = now
		local a = (now - t0) / dur
		local spd = speed * (1.2 - a * 0.7) -- bursts then eases, hard stops felt cheap
		local push = carry * (1 - a)
		if kind == "front" then
			local g = 1
			if vy + dir.Y * spd <= 0 then
				g = TUNE.frontGrav
			end
			vy = vy - workspace.Gravity * g * dt
			local vel = dir * spd + Vector3.new(push.X, vy, push.Z)
			-- kill downward speed near ground so hills dont eat u
			if vel.Y < 0 and self:floorNear() then
				vel = Vector3.new(vel.X, 0, vel.Z)
				vy = math.max(vy, 0)
			end
			if lv.Parent then
				lv.VectorVelocity = vel
			else
				break
			end
		else
			-- side/back: hold altitude while falling
			grav.Force = self.root.AssemblyLinearVelocity.Y <= 0
				and Vector3.new(0, self.root.AssemblyMass * workspace.Gravity * (1 - TUNE.sideGrav), 0)
				or Vector3.zero
			if lv.Parent then
				lv.VectorVelocity = dir * spd + push
			else
				break
			end
		end
		RunService.Heartbeat:Wait()
	end
	-- teardown, remove forces and hand camera control back
	if att.Parent then
		att:Destroy()
	end
	if align and align.Parent then
		align:Destroy()
	end
	self.hum.AutoRotate = true
	self.active = false
	self.model:SetAttribute("IsDashing", false)
	if self.qCount ~= myPress then -- Q was hit mid dash, chain one more after cooldown
		local press = self.qCount
		local waitLeft = TUNE.cooldown - (tick() - self.last) + 0.05 -- overshoot a hair so cooldown fully passes, or canGo drops it
		if waitLeft < 0 then
			waitLeft = 0
		end
		task.delay(waitLeft, function()
			if press == self.qCount and self:canGo() then
				local kind = self:pickType()
				self:fire(kind, self:aimDir(kind))
			end
		end)
	end
end

-- Q handler. Q mid-dash queues one more, fires after cooldown. newest press wins
function Dash:tryDash()
	self.qCount = self.qCount + 1
	local press = self.qCount
	if self.active then
		return -- fire() sees the new press when it ends
	end
	if self:canGo() then
		local kind = self:pickType()
		task.spawn(function()
			self:fire(kind, self:aimDir(kind))
		end)
		return
	end
	local left = TUNE.cooldown - (tick() - self.last) + 0.05 -- same overshoot, delay imprecision is real
	if left > 0 and left <= TUNE.buffer then
		task.delay(left, function()
			if press == self.qCount and self:canGo() then
				local kind = self:pickType()
				self:fire(kind, self:aimDir(kind))
			end
		end)
	end
end

-- touch button for touch screens, built here so no gui needed in startergui
-- touch only, keyboard players never see it
function Dash:touchButton()
	if not UserInputService.TouchEnabled or UserInputService.KeyboardEnabled then
		return
	end
	local pg = plr:WaitForChild("PlayerGui")
	local old = pg:FindFirstChild("DashGui") -- rebuild every spawn or the button stays wired to the dead character
	if old then
		old:Destroy()
	end
	local gui = Instance.new("ScreenGui")
	gui.Name = "DashGui"
	gui.ResetOnSpawn = true -- reset each spawn so the new character gets a fresh button
	gui.Parent = pg
	local btn = Instance.new("TextButton")
	btn.Name = "DashButton"
	btn.Text = "DASH"
	btn.Size = UDim2.fromOffset(84, 84)
	btn.Position = UDim2.new(1, -104, 1, -200) -- bottom right, clear of the thumbstick
	btn.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
	btn.BackgroundTransparency = 0.3
	btn.TextColor3 = Color3.fromRGB(255, 255, 255)
	btn.Font = Enum.Font.GothamBold
	btn.TextSize = 20
	btn.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = btn
	btn.Activated:Connect(function()
		self:tryDash()
	end)
end

-- input hookup. Q on keyboard, touch button built above
function Dash:hookInput()
	self:touchButton()
	UserInputService.InputBegan:Connect(function(input, gpe)
		if gpe then
			return -- game already used this input (chat etc), skip
		end
		if input.KeyCode == TUNE.key then
			self:tryDash()
		end
	end)
end

local myDash = Dash.new(char)
myDash:hookInput()
