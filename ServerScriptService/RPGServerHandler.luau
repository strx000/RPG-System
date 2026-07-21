local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Debris = game:GetService("Debris")

local GunRemotes = ReplicatedStorage:WaitForChild("GunRemotes")
local RPGFireEvent = GunRemotes:WaitForChild("RPGFireEvent")
local RPGReloadEvent = GunRemotes:WaitForChild("RPGReloadEvent")
local ConfigModule = require(ReplicatedStorage:WaitForChild("GunConfig"))
local RPGAssets = ReplicatedStorage:WaitForChild("RPGAssets")

local playerStates = {}

local function getDebrisFolder()
	local folder = workspace:FindFirstChild("GunDebris")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "GunDebris"
		folder.Parent = workspace
	end
	return folder
end

local function getState(player)
	local state = playerStates[player]
	if not state then
		state = {
			LastFire = 0,
			Reloading = {},
			Cooldown = {},
		}
		playerStates[player] = state
	end
	return state
end

local function getRoot(model)
	return model and (model:FindFirstChild("HumanoidRootPart") or model:FindFirstChild("Torso") or model:FindFirstChild("UpperTorso"))
end

local function playSoundAt(position, soundTemplate)
	if not soundTemplate then return end
	local soundPart = Instance.new("Part")
	soundPart.Name = "RPGSoundPoint"
	soundPart.Size = Vector3.new(0.5, 0.5, 0.5)
	soundPart.Transparency = 1
	soundPart.Anchored = true
	soundPart.CanCollide = false
	soundPart.CanTouch = false
	soundPart.CanQuery = false
	soundPart.Position = position
	soundPart.Parent = getDebrisFolder()

	local s = soundTemplate:Clone()
	s.Parent = soundPart
	s:Play()
	Debris:AddItem(soundPart, (s.TimeLength > 0 and s.TimeLength or 3) + 1)
end

local function setRocketParts(model, anchored)
	for _, inst in ipairs(model:GetDescendants()) do
		if inst:IsA("BasePart") then
			inst.Anchored = anchored
			inst.CanCollide = false
			inst.CanTouch = false
			inst.CanQuery = false
			inst.Massless = true
		end
	end
end

local function getPrimaryPart(model)
	if model.PrimaryPart then return model.PrimaryPart end
	local part = model:FindFirstChildWhichIsA("BasePart", true)
	if part then
		model.PrimaryPart = part
	end
	return part
end

local function createFallbackRocket()
	local model = Instance.new("Model")
	model.Name = "RPG7RocketProjectile"
	local body = Instance.new("Part")
	body.Name = "RocketBody"
	body.Size = Vector3.new(0.35, 0.35, 2.2)
	body.Material = Enum.Material.Metal
	body.Color = Color3.fromRGB(70, 85, 65)
	body.Parent = model
	model.PrimaryPart = body
	return model
end

local function addRocketFX(projectile)
	local primary = getPrimaryPart(projectile)
	if not primary then return end

	local attachment = Instance.new("Attachment")
	attachment.Name = "RocketTrailAttachment"
	attachment.Parent = primary

	local smoke = Instance.new("ParticleEmitter")
	smoke.Name = "RocketSmoke"
	smoke.Texture = "rbxassetid://242201991"
	smoke.Color = ColorSequence.new(Color3.fromRGB(190, 190, 190), Color3.fromRGB(95, 95, 95))
	smoke.Size = NumberSequence.new({NumberSequenceKeypoint.new(0, 0.7), NumberSequenceKeypoint.new(1, 2.8)})
	smoke.Transparency = NumberSequence.new({NumberSequenceKeypoint.new(0, 0.15), NumberSequenceKeypoint.new(0.65, 0.55), NumberSequenceKeypoint.new(1, 1)})
	smoke.Lifetime = NumberRange.new(0.45, 0.85)
	smoke.Speed = NumberRange.new(1, 4)
	smoke.SpreadAngle = Vector2.new(18, 18)
	smoke.Drag = 2
	smoke.Rate = 90
	smoke.Parent = attachment

	local flame = Instance.new("ParticleEmitter")
	flame.Name = "RocketFlame"
	flame.Texture = "rbxassetid://243728104"
	flame.Color = ColorSequence.new(Color3.fromRGB(255, 190, 65), Color3.fromRGB(255, 60, 25))
	flame.Size = NumberSequence.new({NumberSequenceKeypoint.new(0, 0.8), NumberSequenceKeypoint.new(1, 0)})
	flame.Transparency = NumberSequence.new(0.1, 1)
	flame.Lifetime = NumberRange.new(0.08, 0.16)
	flame.Speed = NumberRange.new(8, 14)
	flame.SpreadAngle = Vector2.new(12, 12)
	flame.Rate = 120
	flame.LightEmission = 1
	flame.Parent = attachment

	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 135, 45)
	light.Brightness = 2.5
	light.Range = 10
	light.Parent = primary
end

local function createCrater(position, hitNormal, craterTemplate)
	if not craterTemplate then return end
	if not hitNormal or hitNormal.Magnitude < 0.01 then return end

	local craterSize = 8
	local craterPart = Instance.new("Part")
	craterPart.Name = "RPGCrater"
	craterPart.Size = Vector3.new(craterSize, craterSize, 0.05)
	craterPart.Transparency = 1
	craterPart.CanCollide = false
	craterPart.CanTouch = false
	craterPart.CanQuery = false
	craterPart.CastShadow = false
	craterPart.Anchored = true
	craterPart.CFrame = CFrame.lookAt(position, position + hitNormal)

	if craterTemplate:IsA("Decal") or craterTemplate:IsA("Texture") then
		local decal = craterTemplate:Clone()
		decal.Face = Enum.NormalId.Front
		decal.Parent = craterPart
	else
		craterPart = craterTemplate:Clone()
		craterPart.Size = Vector3.new(craterSize, craterSize, craterPart.Size.Z)
		craterPart.CanCollide = false
		craterPart.CanTouch = false
		craterPart.CanQuery = false
		craterPart.CastShadow = false
		craterPart.Anchored = true
		craterPart.CFrame = CFrame.lookAt(position, position + hitNormal) * CFrame.new(0, 0, -0.01)
	end

	craterPart.Parent = getDebrisFolder()
	Debris:AddItem(craterPart, 20)
end

local function makeExplosionFX(position, config, soundTemplate, hitNormal, craterTemplate)
	local explosion = Instance.new("Explosion")
	explosion.Position = position
	explosion.BlastRadius = math.max(8, config.KillRadius or 8)
	explosion.BlastPressure = 0
	explosion.DestroyJointRadiusPercent = 0
	explosion.Parent = workspace

	local fxPart = Instance.new("Part")
	fxPart.Name = "RPGExplosionFX"
	fxPart.Size = Vector3.new(1, 1, 1)
	fxPart.Transparency = 1
	fxPart.Anchored = true
	fxPart.CanCollide = false
	fxPart.CanTouch = false
	fxPart.CanQuery = false
	fxPart.Position = position
	fxPart.Parent = getDebrisFolder()

	local fire = Instance.new("ParticleEmitter")
	fire.Texture = "rbxassetid://243728104"
	fire.Color = ColorSequence.new(Color3.fromRGB(255, 210, 90), Color3.fromRGB(255, 70, 25))
	fire.Size = NumberSequence.new({NumberSequenceKeypoint.new(0, 5), NumberSequenceKeypoint.new(1, 0)})
	fire.Transparency = NumberSequence.new(0, 1)
	fire.Lifetime = NumberRange.new(0.25, 0.45)
	fire.Speed = NumberRange.new(30, 52)
	fire.SpreadAngle = Vector2.new(180, 180)
	fire.Rate = 0
	fire.LightEmission = 1
	fire.Parent = fxPart

	local smoke = Instance.new("ParticleEmitter")
	smoke.Texture = "rbxassetid://242201991"
	smoke.Color = ColorSequence.new(Color3.fromRGB(125, 125, 125), Color3.fromRGB(45, 45, 45))
	smoke.Size = NumberSequence.new({NumberSequenceKeypoint.new(0, 4), NumberSequenceKeypoint.new(1, 13)})
	smoke.Transparency = NumberSequence.new({NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(0.65, 0.65), NumberSequenceKeypoint.new(1, 1)})
	smoke.Lifetime = NumberRange.new(1.1, 1.8)
	smoke.Speed = NumberRange.new(14, 26)
	smoke.SpreadAngle = Vector2.new(180, 180)
	smoke.Drag = 4
	smoke.Rate = 0
	smoke.Parent = fxPart

	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 130, 45)
	light.Brightness = 9
	light.Range = 34
	light.Parent = fxPart

	fire:Emit(42)
	smoke:Emit(55)
	playSoundAt(position, soundTemplate)

	task.delay(0.15, function()
		if light then light.Enabled = false end
	end)
	Debris:AddItem(fxPart, 4)

	createCrater(position, hitNormal, craterTemplate)
end

local function applyBlastDamage(shooter, position, config)
	local shooterCharacter = shooter and shooter.Character
	local radius = config.BlastRadius or 28
	local killRadius = config.KillRadius or 8
	local maxDamage = config.Damage or 140
	local minDamage = config.MinDamage or 35

	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = {getDebrisFolder()}

	local parts = workspace:GetPartBoundsInRadius(position, radius, params)
	local hitModels = {}

	for _, part in ipairs(parts) do
		local model = part:FindFirstAncestorOfClass("Model")
		local humanoid = model and model:FindFirstChildOfClass("Humanoid")
		local root = getRoot(model)
		if humanoid and root and humanoid.Health > 0 and not hitModels[model] then
			hitModels[model] = true
			local dist = (root.Position - position).Magnitude
			local damage
			if dist <= killRadius then
				damage = maxDamage
			else
				local alpha = math.clamp((dist - killRadius) / math.max(1, radius - killRadius), 0, 1)
				damage = maxDamage + (minDamage - maxDamage) * alpha
			end
			if Players:GetPlayerFromCharacter(model) == shooter then
				damage = damage * 0.45
			end
			humanoid:TakeDamage(damage)

			local away = root.Position - position
			if away.Magnitude < 0.1 then
				away = Vector3.new(0, 1, 0)
			end
			local push = (away.Unit + Vector3.new(0, 0.45, 0)).Unit
			local strength = math.clamp((1 - dist / radius) * 95, 28, 95)
			for _, bodyPart in ipairs(model:GetDescendants()) do
				if bodyPart:IsA("BasePart") and not bodyPart.Anchored then
					bodyPart:ApplyImpulse(push * strength * bodyPart.AssemblyMass)
				end
			end
		elseif part:IsA("BasePart") and not part.Anchored and not (shooterCharacter and part:IsDescendantOf(shooterCharacter)) then
			local away = part.Position - position
			if away.Magnitude > 0.1 then
				part:ApplyImpulse(away.Unit * math.max(20, (radius - away.Magnitude) * 4) * part.AssemblyMass)
			end
		end
	end
end

local function applyBackblast(player, tool, config)
	local point = tool:FindFirstChild("BackblastPoint")
	if not point then return end

	local radius = config.BackblastRadius or 10
	local damage = config.BackblastDamage or 45
	local backward = -point.CFrame.LookVector
	local parts = workspace:GetPartBoundsInRadius(point.Position, radius)
	local hitModels = {}

	for _, part in ipairs(parts) do
		local model = part:FindFirstAncestorOfClass("Model")
		local humanoid = model and model:FindFirstChildOfClass("Humanoid")
		local root = getRoot(model)
		if humanoid and root and model ~= player.Character and not hitModels[model] then
			local dir = root.Position - point.Position
			if dir.Magnitude > 0.1 and dir.Unit:Dot(backward) > 0.25 then
				hitModels[model] = true
				humanoid:TakeDamage(damage)
				root:ApplyImpulse((dir.Unit + Vector3.new(0, 0.25, 0)).Unit * 55 * root.AssemblyMass)
			end
		end
	end
end

local function explodeRocket(projectile, position, config, soundTemplate)
	if projectile and projectile.Parent then
		projectile:Destroy()
	end
	makeExplosionFX(position, config, soundTemplate)
	applyBlastDamage(nil, position, config)
end

local function launchProjectile(player, tool, origin, direction, config)
	local template = RPGAssets:FindFirstChild("RPG7RocketTemplate")
	local projectile = template and template:Clone() or createFallbackRocket()
	projectile.Name = "RPG7RocketProjectile"
	setRocketParts(projectile, true)
	local primary = getPrimaryPart(projectile)
	if not primary then
		projectile:Destroy()
		return
	end

	local launchCFrame = CFrame.lookAt(origin, origin + direction) * CFrame.Angles(0, math.rad(-90), 0)
	projectile:PivotTo(launchCFrame)
	projectile.Parent = getDebrisFolder()
	addRocketFX(projectile)

	local sounds = tool:FindFirstChild("Sounds")
	local explosionSound = sounds and sounds:FindFirstChild("ExplosionSound")
	local startPosition = origin
	local lastPosition = origin
	local traveled = 0
	local speed = config.BulletSpeed or 185
	local maxDistance = config.MaxDistance or 850
	local alive = true

	local raycastParams = RaycastParams.new()
	local filter = {projectile, tool, getDebrisFolder()}
	if player.Character then table.insert(filter, player.Character) end
	raycastParams.FilterDescendantsInstances = filter
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude

	local connection
	connection = RunService.Heartbeat:Connect(function(dt)
		if not alive then return end
		if not projectile.Parent then
			alive = false
			if connection then connection:Disconnect() end
			return
		end

		local step = direction * speed * dt
		local nextPosition = lastPosition + step
		local result = workspace:Raycast(lastPosition, step, raycastParams)

		if result then
			alive = false
			if connection then connection:Disconnect() end
			local hitDistance = (result.Position - startPosition).Magnitude
			local craterTemplate = tool:FindFirstChild("Assets") and tool.Assets:FindFirstChild("Crater")
			if hitDistance < (config.ArmDistance or 10) then
				projectile:Destroy()
				makeExplosionFX(result.Position, {KillRadius = 2, BlastRadius = 4}, nil, result.Normal, craterTemplate)
			else
				projectile:Destroy()
				makeExplosionFX(result.Position, config, explosionSound, result.Normal, craterTemplate)
				applyBlastDamage(player, result.Position, config)
			end
			return
		end

		traveled += step.Magnitude
		if traveled >= maxDistance then
			alive = false
			if connection then connection:Disconnect() end
			projectile:Destroy()
			makeExplosionFX(nextPosition, config, explosionSound)
			applyBlastDamage(player, nextPosition, config)
			return
		end

		projectile:PivotTo(CFrame.lookAt(nextPosition, nextPosition + direction) * CFrame.Angles(0, math.rad(-90), 0))
		lastPosition = nextPosition
	end)

	Debris:AddItem(projectile, math.max(8, maxDistance / speed + 2))
end

local function validateFire(player, tool, origin, direction)
	if typeof(origin) ~= "Vector3" or typeof(direction) ~= "Vector3" then return nil end
	if direction.Magnitude < 0.5 then return nil end
	local config = ConfigModule[tool and tool.Name]
	if not config or config.MainMode ~= "Rocket" then return nil end
	local character = player.Character
	if not character or tool.Parent ~= character then return nil end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then return nil end
	local root = getRoot(character)
	if not root or (origin - root.Position).Magnitude > 35 then return nil end
	local barrel = tool:FindFirstChild("Barrel")
	if not barrel or (origin - barrel.Position).Magnitude > 8 then return nil end

	local state = getState(player)
	local now = os.clock()
	if now - state.LastFire < (config.FireRate or 4.5) then return nil end
	if state.Reloading[tool] then return nil end
	local mag = tool:GetAttribute("CurrentMag") or config.MagSize
	if mag <= 0 then return nil end

	state.LastFire = now
	tool:SetAttribute("CurrentMag", 0)
	tool:SetAttribute("Loaded", false)
	return config
end

RPGFireEvent.OnServerEvent:Connect(function(player, tool, origin, direction)
	local config = validateFire(player, tool, origin, direction)
	if not config then return end
	direction = direction.Unit

	local state = getState(player)
	state.Cooldown[tool] = true
	local cooldownTime = config.Cooldown or 75
	task.delay(cooldownTime, function()
		if state.Cooldown[tool] then
			state.Cooldown[tool] = nil
			if player.Parent and tool.Parent == player.Character then
				RPGReloadEvent:FireClient(player, tool, "CooldownDone")
			end
		end
	end)

	applyBackblast(player, tool, config)
	RPGFireEvent:FireAllClients("LaunchFX", tool)
	launchProjectile(player, tool, origin, direction, config)
end)

RPGReloadEvent.OnServerEvent:Connect(function(player, tool)
	local config = ConfigModule[tool and tool.Name]
	if not config or config.MainMode ~= "Rocket" then return end
	local character = player.Character
	if not character or tool.Parent ~= character then return end

	local state = getState(player)
	if state.Reloading[tool] then return end
	if state.Cooldown[tool] then
		RPGReloadEvent:FireClient(player, tool, "Denied")
		return
	end
	if (tool:GetAttribute("CurrentMag") or 0) >= config.MagSize then
		RPGReloadEvent:FireClient(player, tool, "Denied")
		return
	end

	state.Reloading[tool] = true
	local reloadTime = config.ReloadTime or 4.8
	local sounds = tool:FindFirstChild("Sounds")
	local reloadSound = sounds and sounds:FindFirstChild("ReloadSound")
	if reloadSound then
		playSoundAt(tool.Handle.Position, reloadSound)
	end

	task.delay(reloadTime, function()
		if player.Parent and tool.Parent == player.Character and state.Reloading[tool] then
			tool:SetAttribute("CurrentMag", config.MagSize)
			tool:SetAttribute("Loaded", true)
			RPGReloadEvent:FireClient(player, tool, "Done")
		end
		state.Reloading[tool] = nil
	end)
end)

Players.PlayerAdded:Connect(function(player)
	getState(player)
end)

Players.PlayerRemoving:Connect(function(player)
	playerStates[player] = nil
end)

for _, player in ipairs(Players:GetPlayers()) do
	getState(player)
end
