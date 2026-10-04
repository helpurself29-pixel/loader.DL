local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local CONFIG = {
	WalkSpeed = 16,
	SprintSpeed = 26,
	Acceleration = 6,
	SprintKeys = { Enum.KeyCode.LeftShift, Enum.KeyCode.ButtonL3 },

	BaseFOV = 70,
	SprintFOV = 8,
	SpeedFOV = 0.35,
	FallFOV = 0.15,
	FallFOVStart = 30,
	MaxFOV = 95,
	FOVSmoothing = 7,

	CameraDistance = 10,
	CameraHeight = 2,
	ShoulderOffset = 1.5,
	CollisionPadding = 0.5,
	MouseSensitivity = 0.0035,
	GamepadSensitivity = 4,
	TouchSensitivity = 0.006,
	MinPitch = math.rad(-70),
	MaxPitch = math.rad(60),
	FreeMouseKey = Enum.KeyCode.LeftAlt,

	TurnSpeed = 20,

	BobAmount = 0.06,
	BobFrequency = 9,
	StrafeTilt = math.rad(2),
	TiltSmoothing = 8,
}

local player = Players.LocalPlayer

local yaw = 0
local pitch = 0
local bodyYaw = 0
local currentFOV = CONFIG.BaseFOV
local currentTilt = 0
local bobTime = 0
local bobWeight = 0

local sprintHeld = false
local freeMouseHeld = false
local gamepadLook = Vector2.zero
local touchLookInputs = {}

local character, humanoid, rootPart

local function smooth(rate, dt)
	return 1 - math.exp(-rate * dt)
end

local function angleDifference(from, to)
	return (to - from + math.pi) % (2 * math.pi) - math.pi
end

local function isSprintKey(keyCode)
	return table.find(CONFIG.SprintKeys, keyCode) ~= nil
end

local function onCharacterAdded(newCharacter)
	character = newCharacter
	humanoid = newCharacter:WaitForChild("Humanoid")
	rootPart = newCharacter:WaitForChild("HumanoidRootPart")

	humanoid.AutoRotate = false
	humanoid.WalkSpeed = CONFIG.WalkSpeed

	local look = rootPart.CFrame.LookVector
	yaw = math.atan2(-look.X, -look.Z)
	bodyYaw = yaw
	pitch = 0
end

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if input.KeyCode == CONFIG.FreeMouseKey then
		freeMouseHeld = true
	end
	if gameProcessed then
		return
	end
	if isSprintKey(input.KeyCode) then
		sprintHeld = true
	elseif input.UserInputType == Enum.UserInputType.Touch then
		touchLookInputs[input] = true
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if input.KeyCode == CONFIG.FreeMouseKey then
		freeMouseHeld = false
	end
	if isSprintKey(input.KeyCode) then
		sprintHeld = false
	end
	if input.KeyCode == Enum.KeyCode.Thumbstick2 then
		gamepadLook = Vector2.zero
	end
	touchLookInputs[input] = nil
end)

UserInputService.InputChanged:Connect(function(input)
	if input.KeyCode == Enum.KeyCode.Thumbstick2 then
		local stick = Vector2.new(input.Position.X, input.Position.Y)
		gamepadLook = if stick.Magnitude > 0.15 then stick else Vector2.zero
	elseif touchLookInputs[input] then
		yaw -= input.Delta.X * CONFIG.TouchSensitivity
		pitch -= input.Delta.Y * CONFIG.TouchSensitivity
	end
end)

local function updateMovement(dt)
	local moving = humanoid.MoveDirection.Magnitude > 0.1
	local sprinting = sprintHeld and moving
	local targetSpeed = if sprinting then CONFIG.SprintSpeed else CONFIG.WalkSpeed
	humanoid.WalkSpeed += (targetSpeed - humanoid.WalkSpeed) * smooth(CONFIG.Acceleration, dt)
	return sprinting
end

local function updateBody(dt)
	if humanoid.Sit or humanoid.Health <= 0 or rootPart.Anchored then
		return
	end
	bodyYaw += angleDifference(bodyYaw, yaw) * smooth(CONFIG.TurnSpeed, dt)
	rootPart.CFrame = CFrame.new(rootPart.Position) * CFrame.Angles(0, bodyYaw, 0)
end

local function updateFOV(camera, dt, sprinting)
	local velocity = rootPart.AssemblyLinearVelocity
	local horizontalSpeed = Vector3.new(velocity.X, 0, velocity.Z).Magnitude

	local fov = CONFIG.BaseFOV
	if sprinting then
		fov += CONFIG.SprintFOV
	end
	fov += math.max(horizontalSpeed - CONFIG.WalkSpeed, 0) * CONFIG.SpeedFOV
	fov += math.max(-velocity.Y - CONFIG.FallFOVStart, 0) * CONFIG.FallFOV
	fov = math.min(fov, CONFIG.MaxFOV)

	currentFOV += (fov - currentFOV) * smooth(CONFIG.FOVSmoothing, dt)
	camera.FieldOfView = currentFOV
end

local function updateCamera(camera, dt)

	if UserInputService.MouseBehavior == Enum.MouseBehavior.LockCenter then
		local delta = UserInputService:GetMouseDelta()
		yaw -= delta.X * CONFIG.MouseSensitivity
		pitch -= delta.Y * CONFIG.MouseSensitivity
	end
	yaw -= gamepadLook.X * CONFIG.GamepadSensitivity * dt
	pitch += gamepadLook.Y * CONFIG.GamepadSensitivity * dt
	pitch = math.clamp(pitch, CONFIG.MinPitch, CONFIG.MaxPitch)

	local yawRotation = CFrame.Angles(0, yaw, 0)
	local rotation = yawRotation * CFrame.Angles(pitch, 0, 0)

	local pivot = rootPart.Position + Vector3.new(0, CONFIG.CameraHeight, 0)
	local offset = rotation:VectorToWorldSpace(Vector3.new(CONFIG.ShoulderOffset, 0, CONFIG.CameraDistance))

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }
	params.IgnoreWater = true

	local hit = workspace:Raycast(pivot, offset, params)
	if hit then
		local distance = math.max((hit.Position - pivot).Magnitude - CONFIG.CollisionPadding, 0.5)
		offset = offset.Unit * distance
	end

	local velocity = rootPart.AssemblyLinearVelocity
	local horizontalSpeed = Vector3.new(velocity.X, 0, velocity.Z).Magnitude
	local grounded = humanoid.FloorMaterial ~= Enum.Material.Air
	local targetBob = if grounded then math.clamp(horizontalSpeed / CONFIG.WalkSpeed, 0, 1.5) else 0
	bobWeight += (targetBob - bobWeight) * smooth(10, dt)
	bobTime += dt * CONFIG.BobFrequency * math.max(horizontalSpeed / CONFIG.WalkSpeed, 0.5)
	local bob = math.sin(bobTime) * CONFIG.BobAmount * bobWeight

	local strafe = yawRotation:VectorToObjectSpace(velocity).X
	local targetTilt = -math.clamp(strafe / CONFIG.SprintSpeed, -1, 1) * CONFIG.StrafeTilt
	currentTilt += (targetTilt - currentTilt) * smooth(CONFIG.TiltSmoothing, dt)

	camera.CFrame = CFrame.new(pivot + offset)
		* rotation
		* CFrame.Angles(0, 0, currentTilt)
		* CFrame.new(0, bob, 0)
	camera.Focus = CFrame.new(pivot)
end

player.CharacterAdded:Connect(onCharacterAdded)
if player.Character then
	task.spawn(onCharacterAdded, player.Character)
end

RunService:BindToRenderStep("MovementController", Enum.RenderPriority.Camera.Value + 1, function(dt)
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	camera.CameraType = Enum.CameraType.Scriptable

	UserInputService.MouseBehavior = if freeMouseHeld
		then Enum.MouseBehavior.Default
		else Enum.MouseBehavior.LockCenter

	if not (character and humanoid and rootPart and rootPart.Parent) then
		return
	end

	local sprinting = updateMovement(dt)
	updateCamera(camera, dt)
	updateBody(dt)
	updateFOV(camera, dt, sprinting)
end)
