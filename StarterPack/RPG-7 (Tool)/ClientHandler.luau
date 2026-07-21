local Tool = script.Parent
local Handle = Tool:WaitForChild("Handle")
local Barrel = Tool:WaitForChild("Barrel")
local BackblastPoint = Tool:WaitForChild("BackblastPoint")
local GunModel = Tool:WaitForChild("GunModel")
local Sounds = Tool:WaitForChild("Sounds")
local Animations = Tool:WaitForChild("Animations")
local EquipAnim = Animations:WaitForChild("EquipAnim")
local EquippedAnim = Animations:WaitForChild("EquippedAnim")
local ReloadAnim = Animations:WaitForChild("ReloadAnim")
local ActivateSafetyAnim = Animations:WaitForChild("ActivateSafetyAnim")
local SafetyActivatedAnim = Animations:WaitForChild("SafetyActivatedAnim")

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local mouse = player:GetMouse()

local ConfigModule = require(ReplicatedStorage:WaitForChild("GunConfig"))
local Config = ConfigModule[Tool.Name]

local GunRemotes = ReplicatedStorage:WaitForChild("GunRemotes")
local RPGFireEvent = GunRemotes:WaitForChild("RPGFireEvent")
local RPGReloadEvent = GunRemotes:WaitForChild("RPGReloadEvent")

local playerGui = player:WaitForChild("PlayerGui")
local gunGui = playerGui:WaitForChild("GunGUI")
local mainframe = gunGui:WaitForChild("Mainframe")
local gunNameLabel = mainframe:WaitForChild("GunNameLabel")
local ammoLabel = mainframe:WaitForChild("AmmoLabel")
local gunModeLabel = mainframe:WaitForChild("GunModeLabel")
local originalTextSize = ammoLabel.TextSize

local crosshair = gunGui:FindFirstChild("Crosshair")

local equipped = false
local reloading = false
local safety = false
local lastFire = 0
local reloadEndTime = 0
local cooldownActive = false
local cooldownEndTime = 0

local equipTrack = nil
local equippedTrack = nil
local reloadTrack = nil
local activateSafetyTrack = nil
local safetyActivatedTrack = nil

local originalToolNoneId = nil
local animPlayedConnection = nil

local function loadSafeAnimation(animator, animObj)
	if not animObj then return nil end
	if animObj:IsA("Animation") then
		return animator:LoadAnimation(animObj)
	elseif animObj:IsA("KeyframeSequence") then
		local provider = game:GetService("KeyframeSequenceProvider")
		local assetId = provider:RegisterKeyframeSequence(animObj)
		local newAnim = Instance.new("Animation")
		newAnim.AnimationId = assetId
		return animator:LoadAnimation(newAnim)
	elseif animObj:IsA("StringValue") or animObj:IsA("IntValue") or animObj:IsA("NumberValue") then
		local newAnim = Instance.new("Animation")
		local id = tostring(animObj.Value)
		if not string.find(id, "rbxassetid://") then
			id = "rbxassetid://" .. id
		end
		newAnim.AnimationId = id
		return animator:LoadAnimation(newAnim)
	end
	return nil
end

local function playSound(name, parentOverride)
	local template = Sounds:FindFirstChild(name)
	if not template then return nil end
	local s = template:Clone()
	s.Parent = parentOverride or Handle
	s:Play()
	task.delay((s.TimeLength > 0 and s.TimeLength or 2) + 0.5, function()
		if s then s:Destroy() end
	end)
	return s
end

local function setRocketVisible(visible)
	local rocket = GunModel:FindFirstChild("Rocket")
	if not rocket then return end
	for _, inst in ipairs(rocket:GetDescendants()) do
		if inst:IsA("BasePart") then
			inst.Transparency = visible and 0 or 1
		end
	end
end

local function updateGui()
	local mag = Tool:GetAttribute("CurrentMag")
	if mag == nil then mag = Config.MagSize end

	gunNameLabel.Text = Tool.Name
	if cooldownActive then
		ammoLabel.TextSize = originalTextSize * 0.75
		ammoLabel.Text = math.max(1, math.ceil(cooldownEndTime - os.clock())) .. "s"
	elseif reloading then
		ammoLabel.TextSize = originalTextSize * 0.75
		ammoLabel.Text = math.max(1, math.ceil(reloadEndTime - os.clock())) .. "s"
	elseif safety then
		ammoLabel.TextSize = originalTextSize
		ammoLabel.Text = tostring(mag) .. " | " .. tostring(Config.MagSize)
	else
		ammoLabel.TextSize = originalTextSize
		ammoLabel.Text = tostring(mag) .. " | " .. tostring(Config.MagSize)
	end

	if safety then
		gunModeLabel.Text = "Safety"
	elseif cooldownActive then
		gunModeLabel.Text = "Cooldown"
	elseif reloading then
		gunModeLabel.Text = "Reloading"
	else
		gunModeLabel.Text = "Rocket"
	end
end

local function setGuiVisible(visible)
	gunGui.Enabled = visible
	if crosshair then
		crosshair.Visible = visible
	end
	UserInputService.MouseIconEnabled = not visible
	mouse.Icon = visible and "rbxassetid://0" or ""
end

local function createBackblastPuff()
	local puffPart = Instance.new("Part")
	puffPart.Size = Vector3.new(0.2, 0.2, 0.2)
	puffPart.Transparency = 1
	puffPart.Anchored = true
	puffPart.CanCollide = false
	puffPart.CanTouch = false
	puffPart.CanQuery = false
	puffPart.CFrame = BackblastPoint.CFrame
	puffPart.Parent = workspace

	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = "rbxassetid://242201991"
	emitter.Color = ColorSequence.new(Color3.fromRGB(160, 160, 160), Color3.fromRGB(80, 80, 80))
	emitter.Size = NumberSequence.new({NumberSequenceKeypoint.new(0, 1.8), NumberSequenceKeypoint.new(1, 5)})
	emitter.Transparency = NumberSequence.new({NumberSequenceKeypoint.new(0, 0.25), NumberSequenceKeypoint.new(1, 1)})
	emitter.Lifetime = NumberRange.new(0.45, 0.8)
	emitter.Speed = NumberRange.new(18, 32)
	emitter.SpreadAngle = Vector2.new(28, 28)
	emitter.Drag = 4
	emitter.Rate = 0
	emitter.Parent = puffPart
	emitter:Emit(28)

	task.delay(1.3, function()
		if puffPart then puffPart:Destroy() end
	end)
end

local function createSparkBurst(cframe, opts)
	opts = opts or {}
	local sparkPart = Instance.new("Part")
	sparkPart.Size = Vector3.new(0.2, 0.2, 0.2)
	sparkPart.Transparency = 1
	sparkPart.Anchored = true
	sparkPart.CanCollide = false
	sparkPart.CanTouch = false
	sparkPart.CanQuery = false
	sparkPart.CFrame = cframe
	sparkPart.Parent = workspace

	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = "rbxassetid://243728104"
	emitter.Color = ColorSequence.new(Color3.fromRGB(255, 235, 150), Color3.fromRGB(255, 110, 20))
	emitter.Size = NumberSequence.new({NumberSequenceKeypoint.new(0, 0.18), NumberSequenceKeypoint.new(1, 0)})
	emitter.Transparency = NumberSequence.new({NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 0.6)})
	emitter.Lifetime = NumberRange.new(0.15, 0.4)
	emitter.Speed = NumberRange.new(opts.minSpeed or 20, opts.maxSpeed or 40)
	emitter.SpreadAngle = opts.spread or Vector2.new(25, 25)
	emitter.Acceleration = Vector3.new(0, -60, 0)
	emitter.Drag = 1.5
	emitter.Rate = 0
	emitter.LightEmission = 1
	emitter.Rotation = NumberRange.new(0, 360)
	emitter.RotSpeed = NumberRange.new(-180, 180)
	emitter.Parent = sparkPart
	emitter:Emit(opts.count or 20)

	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 180, 90)
	light.Brightness = 3
	light.Range = 12
	light.Parent = sparkPart
	task.delay(0.08, function()
		if light then light.Enabled = false end
	end)

	task.delay(1, function()
		if sparkPart then sparkPart:Destroy() end
	end)

	return sparkPart
end

local function toggleSafety()
	if reloading then return end
	safety = not safety

	if safety then
		if equippedTrack then equippedTrack:Stop(0) end
		if equipTrack then equipTrack:Stop(0) end

		if activateSafetyTrack then
			activateSafetyTrack.Looped = false
			activateSafetyTrack:Play(0)
			activateSafetyTrack:AdjustSpeed(1)

			task.spawn(function()
				if activateSafetyTrack.Length == 0 then
					repeat task.wait() until activateSafetyTrack.Length > 0
				end
				local startT = os.clock()
				while os.clock() - startT < activateSafetyTrack.Length - 0.02 do
					task.wait()
					if not safety or not equipped then return end
				end
				if safety and equipped and safetyActivatedTrack then
					safetyActivatedTrack:Play(0)
				end
			end)
		else
			if safetyActivatedTrack then safetyActivatedTrack:Play(0) end
		end
	else
		if safetyActivatedTrack then safetyActivatedTrack:Stop(0) end

		if activateSafetyTrack then
			activateSafetyTrack.Looped = false
			activateSafetyTrack:Play(0)
			activateSafetyTrack:AdjustSpeed(-1)
			activateSafetyTrack.TimePosition = activateSafetyTrack.Length > 0 and activateSafetyTrack.Length or 0.5

			task.spawn(function()
				local duration = activateSafetyTrack.Length > 0 and activateSafetyTrack.Length or 0.5
				local startT = os.clock()
				while os.clock() - startT < duration - 0.02 do
					task.wait()
					if safety or not equipped then return end
				end
				if not safety and equipped and equippedTrack then
					equippedTrack:Play(0)
				end
			end)
		else
			if equippedTrack then equippedTrack:Play(0) end
		end
	end
	updateGui()
end

local function reload()
	local mag = Tool:GetAttribute("CurrentMag") or Config.MagSize
	if cooldownActive or reloading or mag >= Config.MagSize then return end
	reloading = true
	reloadEndTime = os.clock() + Config.ReloadTime
	updateGui()

	local reloadSound = Sounds:FindFirstChild("ReloadSound")
	if reloadSound then
		playSound("ReloadSound", Handle)
	end

	if reloadTrack then
		reloadTrack.Looped = false
		local soundDuration = reloadSound and reloadSound.TimeLength > 0 and reloadSound.TimeLength or 2
		local animDuration = reloadTrack.Length > 0 and reloadTrack.Length or 1
		reloadTrack:AdjustSpeed(animDuration / soundDuration)
		reloadTrack:Play(0)
	end

	RPGReloadEvent:FireServer(Tool)

	task.spawn(function()
		while reloading and os.clock() < reloadEndTime do
			if equipped then
				ammoLabel.Text = math.max(1, math.ceil(reloadEndTime - os.clock())) .. "s"
			end
			task.wait(0.25)
		end
	end)
end

local function startCooldown()
	cooldownActive = true
	cooldownEndTime = os.clock() + (Config.Cooldown or 75)
	if equipped then updateGui() end

	task.spawn(function()
		while cooldownActive and os.clock() < cooldownEndTime do
			if equipped then
				ammoLabel.Text = math.max(1, math.ceil(cooldownEndTime - os.clock())) .. "s"
			end
			task.wait(0.25)
		end
		if cooldownActive then
			cooldownActive = false
			if equipped then updateGui() end
		end
	end)
end

local function fireRocket()
	if reloading or safety then return end
	local mag = Tool:GetAttribute("CurrentMag") or Config.MagSize
	if mag <= 0 then
		playSound("DryFireSound", Handle)
		reload()
		return
	end

	local now = os.clock()
	if now - lastFire < Config.FireRate then return end
	lastFire = now

	local origin = Barrel.Position
	local targetPosition = mouse.Hit.Position
	local direction = targetPosition - origin
	if direction.Magnitude < 1 then
		direction = Barrel.CFrame.LookVector
	else
		direction = direction.Unit
	end

	playSound("LaunchSound", Barrel)
	createBackblastPuff()
	createSparkBurst(Barrel.CFrame, {count = 22, minSpeed = 25, maxSpeed = 55, spread = Vector2.new(14, 14)})
	createSparkBurst(BackblastPoint.CFrame, {count = 28, minSpeed = 18, maxSpeed = 42, spread = Vector2.new(32, 32)})
	setRocketVisible(false)
	Tool:SetAttribute("CurrentMag", 0)
	Tool:SetAttribute("Loaded", false)
	updateGui()
	startCooldown()

	RPGFireEvent:FireServer(Tool, origin, direction)
end

Tool.Equipped:Connect(function()
	equipped = true
	playerGui = player:WaitForChild("PlayerGui")
	gunGui = playerGui:WaitForChild("GunGUI")
	mainframe = gunGui:WaitForChild("Mainframe")
	gunNameLabel = mainframe:WaitForChild("GunNameLabel")
	ammoLabel = mainframe:WaitForChild("AmmoLabel")
	gunModeLabel = mainframe:WaitForChild("GunModeLabel")
	crosshair = gunGui:FindFirstChild("Crosshair")
	updateGui()
	setGuiVisible(true)
	setRocketVisible((Tool:GetAttribute("CurrentMag") or Config.MagSize) > 0)

	local character = player.Character
	local animateScript = character and character:FindFirstChild("Animate")
	if animateScript then
		local toolNone = animateScript:FindFirstChild("toolnone")
		local animObj = toolNone and toolNone:FindFirstChildOfClass("Animation")
		if animObj then
			if not originalToolNoneId or originalToolNoneId == "" or originalToolNoneId == "rbxassetid://0" then
				originalToolNoneId = animObj.AnimationId
			end
			animObj.AnimationId = ""
		end
	end

	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")

	if animator then
		for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
			if track.Name == "toolnone" or string.find(string.lower(track.Animation.AnimationId), "tool") then
				track:Stop(0)
			end
		end

		animPlayedConnection = animator.AnimationPlayed:Connect(function(track)
			if track.Name == "toolnone" or string.find(string.lower(track.Animation.AnimationId), "tool") then
				track:Stop(0)
			end
		end)

		equipTrack = loadSafeAnimation(animator, EquipAnim)
		equippedTrack = loadSafeAnimation(animator, EquippedAnim)
		reloadTrack = loadSafeAnimation(animator, ReloadAnim)
		activateSafetyTrack = loadSafeAnimation(animator, ActivateSafetyAnim)
		safetyActivatedTrack = loadSafeAnimation(animator, SafetyActivatedAnim)

		if equipTrack then equipTrack.Priority = Enum.AnimationPriority.Action2 end
		if equippedTrack then equippedTrack.Priority = Enum.AnimationPriority.Action end
		if reloadTrack then reloadTrack.Priority = Enum.AnimationPriority.Action3 end
		if activateSafetyTrack then activateSafetyTrack.Priority = Enum.AnimationPriority.Action2 end
		if safetyActivatedTrack then
			safetyActivatedTrack.Priority = Enum.AnimationPriority.Action2
			safetyActivatedTrack.Looped = true
		end

		if equippedTrack then
			equippedTrack.Looped = true
		end

		if equipTrack then
			equipTrack:Play(0)
			equipTrack.Stopped:Connect(function()
				if equipped and not reloading and not safety and equippedTrack then
					equippedTrack:Play(0)
				end
			end)
		else
			if equippedTrack then
				equippedTrack:Play(0)
			end
		end
	end
end)

Tool.Unequipped:Connect(function()
	equipped = false
	safety = false
	setGuiVisible(false)

	if animPlayedConnection then
		animPlayedConnection:Disconnect()
		animPlayedConnection = nil
	end

	local character = player.Character
	local animateScript = character and character:FindFirstChild("Animate")
	if animateScript and originalToolNoneId and originalToolNoneId ~= "" and originalToolNoneId ~= "rbxassetid://0" then
		local toolNone = animateScript:FindFirstChild("toolnone")
		local animObj = toolNone and toolNone:FindFirstChildOfClass("Animation")
		if animObj then
			animObj.AnimationId = originalToolNoneId
		end
	end

	if equipTrack then equipTrack:Stop(0) end
	if equippedTrack then equippedTrack:Stop(0) end
	if reloadTrack then reloadTrack:Stop(0) end
	if activateSafetyTrack then activateSafetyTrack:Stop(0) end
	if safetyActivatedTrack then safetyActivatedTrack:Stop(0) end

	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
	if animator then
		local unequipTrack = loadSafeAnimation(animator, EquipAnim)
		if unequipTrack then
			unequipTrack.Priority = Enum.AnimationPriority.Action
			unequipTrack:Play(0)
			unequipTrack:AdjustSpeed(-1)
			unequipTrack.TimePosition = unequipTrack.Length
			task.delay(unequipTrack.Length > 0 and unequipTrack.Length or 0.5, function()
				unequipTrack:Stop(0)
				unequipTrack:Destroy()
			end)
		end
	end
end)

Tool.Activated:Connect(function()
	if equipped then
		fireRocket()
	end
end)

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed or not equipped then return end
	if input.KeyCode == Enum.KeyCode.R then
		reload()
	elseif input.KeyCode == Enum.KeyCode.Q then
		toggleSafety()
	end
end)

Tool:GetAttributeChangedSignal("CurrentMag"):Connect(function()
	setRocketVisible((Tool:GetAttribute("CurrentMag") or 0) > 0)
	if equipped then updateGui() end
end)

Tool:GetAttributeChangedSignal("Loaded"):Connect(function()
	setRocketVisible(Tool:GetAttribute("Loaded") == true)
end)

RPGFireEvent.OnClientEvent:Connect(function(action, sourceTool)
	if action == "LaunchFX" and sourceTool ~= Tool then
		local sourceBarrel = sourceTool and sourceTool:FindFirstChild("Barrel")
		local sourceBackblast = sourceTool and sourceTool:FindFirstChild("BackblastPoint")
		local sourceSounds = sourceTool and sourceTool:FindFirstChild("Sounds")
		local launch = sourceSounds and sourceSounds:FindFirstChild("LaunchSound")
		if sourceBarrel and launch then
			local s = launch:Clone()
			s.Parent = sourceBarrel
			s:Play()
			task.delay((s.TimeLength > 0 and s.TimeLength or 2) + 0.5, function()
				if s then s:Destroy() end
			end)
		end
		if sourceBackblast then
			local puffPart = Instance.new("Part")
			puffPart.Size = Vector3.new(0.2, 0.2, 0.2)
			puffPart.Transparency = 1
			puffPart.Anchored = true
			puffPart.CanCollide = false
			puffPart.CanTouch = false
			puffPart.CanQuery = false
			puffPart.CFrame = sourceBackblast.CFrame
			puffPart.Parent = workspace
			local emitter = Instance.new("ParticleEmitter")
			emitter.Texture = "rbxassetid://242201991"
			emitter.Lifetime = NumberRange.new(0.45, 0.8)
			emitter.Speed = NumberRange.new(18, 32)
			emitter.SpreadAngle = Vector2.new(28, 28)
			emitter.Size = NumberSequence.new(4)
			emitter.Rate = 0
			emitter.Parent = puffPart
			emitter:Emit(24)
			task.delay(1.3, function() if puffPart then puffPart:Destroy() end end)
		end
		if sourceBarrel then
			createSparkBurst(sourceBarrel.CFrame, {count = 22, minSpeed = 25, maxSpeed = 55, spread = Vector2.new(14, 14)})
		end
		if sourceBackblast then
			createSparkBurst(sourceBackblast.CFrame, {count = 28, minSpeed = 18, maxSpeed = 42, spread = Vector2.new(32, 32)})
		end
	end
end)

RPGReloadEvent.OnClientEvent:Connect(function(sourceTool, message)
	if sourceTool ~= Tool then return end
	if message == "Done" then
		reloading = false
		Tool:SetAttribute("Loaded", true)
		setRocketVisible(true)
		if equipped and not safety and equippedTrack then
			equippedTrack:Play(0)
		end
		if equipped then updateGui() end
	elseif message == "Denied" then
		reloading = false
		if equipped then updateGui() end
	elseif message == "CooldownDone" then
		cooldownActive = false
		if equipped then updateGui() end
	end
end)

RunService.RenderStepped:Connect(function()
	if equipped and crosshair then
		crosshair.Position = UDim2.new(0, mouse.X, 0, mouse.Y)
	end
end)
