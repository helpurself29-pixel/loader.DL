local ReplicatedStorage = game:GetService("ReplicatedStorage")

local folder = ReplicatedStorage:WaitForChild("Animations")

local NAMES = {
	Push = "Push",
	TackleAttempt = "Tackle Attemptt",
	Tackler = "Tackler",
	Tackled = "Tackled",
}

local AnimationLookup = {}

function AnimationLookup.Get(key)
	local name = NAMES[key] or key
	for _, descendant in folder:GetDescendants() do
		if descendant:IsA("Animation") and descendant.Name == name then
			local id = descendant.AnimationId
			if id == "" or id == "rbxassetid://0" then
				return nil, `ReplicatedStorage.Animations has no ID set for "{name}" yet`
			end
			return descendant
		end
	end
	return nil, `No Animation named "{name}" in ReplicatedStorage.Animations`
end

return AnimationLookup
