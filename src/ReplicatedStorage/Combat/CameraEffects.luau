local Theme = require(script.Parent.Theme)

local CameraEffects = {}

local SPRING_STIFFNESS = 140
local SPRING_DAMPING = 14
local FOV_DECAY = 9
local MAX_DIP = 1.2

local shakes = {}
local fovImpulse = 0
local dipPosition = 0
local dipVelocity = 0
local clock = 0

local function scale()
	if Theme.ReducedMotion then
		return 0
	end
	return Theme.ShakeScale
end

function CameraEffects.Shake(amplitude, duration, frequency)
	local strength = amplitude * scale()
	if strength <= 0 then
		return
	end
	table.insert(shakes, {
		Amplitude = strength,
		Duration = math.max(duration, 0.01),
		Frequency = frequency or 18,
		Elapsed = 0,
		Seed = math.random() * 1000,
	})
end

function CameraEffects.Kick(fov)
	fovImpulse += fov * (if Theme.ReducedMotion then 0.4 else 1)
end

function CameraEffects.Dip(speed)
	dipVelocity -= speed * scale()
end

function CameraEffects.Step(dt)
	clock += dt

	local pitch, yaw, roll = 0, 0, 0
	for i = #shakes, 1, -1 do
		local shake = shakes[i]
		shake.Elapsed += dt
		local life = 1 - shake.Elapsed / shake.Duration
		if life <= 0 then
			table.remove(shakes, i)
		else
			local strength = shake.Amplitude * life * life
			local t = clock * shake.Frequency
			pitch += math.noise(shake.Seed, t, 0) * strength
			yaw += math.noise(shake.Seed, 0, t) * strength
			roll += math.noise(t, shake.Seed, 0) * strength * 0.5
		end
	end

	fovImpulse *= math.exp(-FOV_DECAY * dt)

	local step = math.min(dt, 1 / 30)
	dipVelocity += (-SPRING_STIFFNESS * dipPosition - SPRING_DAMPING * dipVelocity) * step
	dipPosition = math.clamp(dipPosition + dipVelocity * step, -MAX_DIP, MAX_DIP)

	local rotation = CFrame.Angles(math.rad(pitch), math.rad(yaw), math.rad(roll))
	return rotation, fovImpulse, Vector3.new(0, dipPosition, 0)
end

return CameraEffects
