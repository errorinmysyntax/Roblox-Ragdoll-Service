--[[
	SimpleRagdollService
	A modular, production-ready ragdoll system for Roblox
	
	GitHub: https://github.com/ErrorInMySyntax/SimpleRagdollService
	License: MIT
	
	Features:
	- Supports both R6 and R15 character rigs
	- Fully configurable joint limits and stiffness
	- Automatic script management during ragdoll
	- Smooth recovery transitions
	- Network ownership management
	- Collision state preservation
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

-- ============================================================================
-- MODULE SETUP
-- ============================================================================

local SimpleRagdollService = {}
SimpleRagdollService.__index = SimpleRagdollService

-- Version
SimpleRagdollService.VERSION = "2.0.0"

-- ============================================================================
-- DEFAULT CONFIGURATION
-- ============================================================================

local DEFAULT_CONFIG = {
	-- Scripts to disable during ragdoll (empty by default, users can customize)
	scriptsToDisable = {},
	
	-- Ragdoll stiffness: 0.1 (very loose) to 5.0 (very stiff)
	-- 1.0 = balanced (default)
	stiffnessMultiplier = 1.0,
	
	-- Hotbar locking (can be string reason or nil to disable)
	hotbarLockReason = nil,
	
	-- Recovery settings
	recoveryLiftOffset = 1.15,
	recoveryBlendDuration = 0.24,
	recoveryMobilityLock = 0.3,
	
	-- Collision stabilization
	collisionStabilizeRetries = 4,
	collisionStabilizeStep = 0.08,
	
	-- Joint limits configuration
	jointLimits = {
		Default = { upper = 55, twistLower = -30, twistUpper = 30, friction = 200 },
		Neck = { upper = 35, twistLower = -20, twistUpper = 20, friction = 250 },
		["Left Shoulder"] = { upper = 90, twistLower = -70, twistUpper = 70, friction = 150 },
		["Right Shoulder"] = { upper = 90, twistLower = -70, twistUpper = 70, friction = 150 },
		["Left Hip"] = { upper = 75, twistLower = -35, twistUpper = 35, friction = 220 },
		["Right Hip"] = { upper = 75, twistLower = -35, twistUpper = 35, friction = 220 },
		RootJoint = { upper = 25, twistLower = -15, twistUpper = 15, friction = 300 },
		Waist = { upper = 30, twistLower = -20, twistUpper = 20, friction = 280 },
		LeftShoulder = { upper = 90, twistLower = -70, twistUpper = 70, friction = 150 },
		RightShoulder = { upper = 90, twistLower = -70, twistUpper = 70, friction = 150 },
		LeftHip = { upper = 75, twistLower = -35, twistUpper = 35, friction = 220 },
		RightHip = { upper = 75, twistLower = -35, twistUpper = 35, friction = 220 },
	},
	
	-- R6 collision parts (only these parts collide when ragdolled in R6)
	r6CollisionParts = {
		["Head"] = true,
		["Torso"] = true,
		["Left Arm"] = true,
		["Right Arm"] = true,
		["Left Leg"] = true,
		["Right Leg"] = true,
	},
	
	-- Attachment names for ragdoll joints
	attachmentNames = {
		a0 = "SimpleRagdollA0",
		a1 = "SimpleRagdollA1",
	},
	
	-- Socket constraint name
	socketName = "SimpleRagdollSocket",
}

-- ============================================================================
-- STATE MANAGEMENT
-- ============================================================================

local ragdollState = setmetatable({}, { __mode = "k" })
local humanoidStateBackup = setmetatable({}, { __mode = "k" })
local ragdollDeathConnection = setmetatable({}, { __mode = "k" })
local ragdollScriptState = setmetatable({}, { __mode = "k" })

-- ============================================================================
-- CONSTRUCTOR
-- ============================================================================

function SimpleRagdollService.new(config: table?)
	local self = setmetatable({}, SimpleRagdollService)
	
	-- Merge user config with defaults
	self.config = {}
	for key, value in pairs(DEFAULT_CONFIG) do
		if config and config[key] ~= nil then
			if typeof(value) == "table" then
				self.config[key] = {}
				for k, v in pairs(value) do
					self.config[key][k] = v
				end
				for k, v in pairs(config[key]) do
					self.config[key][k] = v
				end
			else
				self.config[key] = config[key]
			end
		else
			if typeof(value) == "table" then
				self.config[key] = {}
				for k, v in pairs(value) do
					self.config[key][k] = v
				end
			else
				self.config[key] = value
			end
		end
	end
	
	-- Apply stiffness multiplier to joint limits
	self:_applyStiffnessToJoints()
	
	-- State tables per instance
	self.ragdollState = setmetatable({}, { __mode = "k" })
	self.humanoidStateBackup = setmetatable({}, { __mode = "k" })
	self.ragdollDeathConnection = setmetatable({}, { __mode = "k" })
	self.ragdollScriptState = setmetatable({}, { __mode = "k" })
	
	return self
end

-- ============================================================================
-- VALIDATION UTILITIES
-- ============================================================================

local function isValidCharacter(character: Instance?): boolean
	return typeof(character) == "Instance" and character:IsA("Model") and character.Parent ~= nil
end

local function isValidHumanoid(humanoid: Humanoid?): boolean
	return humanoid ~= nil and humanoid.Parent ~= nil and humanoid.Health > 0
end

local function isAccessoryPart(part: BasePart): boolean
	return part:FindFirstAncestor("Attachments") ~= nil
end

-- ============================================================================
-- UTILITY FUNCTIONS
-- ============================================================================

function SimpleRagdollService:_applyStiffnessToJoints()
	local multiplier = math.max(0.1, math.min(5.0, self.config.stiffnessMultiplier))
	
	for jointName, limits in pairs(self.config.jointLimits) do
		if typeof(limits) == "table" then
			limits.friction = math.floor((DEFAULT_CONFIG.jointLimits[jointName].friction or 200) * multiplier)
		end
	end
end

local function getRootPart(character: Model): BasePart?
	if not isValidCharacter(character) then
		return nil
	end
	
	local root = character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root
	end
	
	local torso = character:FindFirstChild("Torso")
	if torso and torso:IsA("BasePart") then
		return torso
	end
	
	return nil
end

local function canSetNetworkOwner(part: BasePart): boolean
	if part.Anchored then
		return false
	end
	
	local ok, connected = pcall(function()
		return part:GetConnectedParts(true)
	end)
	
	if ok then
		for _, p in ipairs(connected) do
			if p:IsA("BasePart") and p.Anchored then
				return false
			end
		end
	end
	
	return true
end

local function setNetworkOwnerToServer(character: Model)
	if not isValidCharacter(character) then
		return
	end
	
	for _, part in ipairs(character:GetDescendants()) do
		if part:IsA("BasePart") and part.Name ~= "HumanoidRootPart" and not isAccessoryPart(part) then
			if canSetNetworkOwner(part) then
				pcall(function()
					part:SetNetworkOwner(nil)
				end)
			end
		end
	end
end

local function setNetworkOwnerToPlayer(character: Model, player: Player?)
	if not isValidCharacter(character) or not player then
		return
	end
	
	for _, part in ipairs(character:GetDescendants()) do
		if part:IsA("BasePart") and canSetNetworkOwner(part) then
			pcall(function()
				part:SetNetworkOwner(player)
			end)
		end
	end
end

-- ============================================================================
-- COLLISION MANAGEMENT
-- ============================================================================

local function captureCollisionState(character: Model): { [BasePart]: { CanCollide: boolean, Massless: boolean, CollisionGroup: string } }
	local snapshot = {}
	if not isValidCharacter(character) then
		return snapshot
	end
	
	for _, part in ipairs(character:GetDescendants()) do
		if part:IsA("BasePart") then
			snapshot[part] = {
				CanCollide = part.CanCollide,
				Massless = part.Massless,
				CollisionGroup = part.CollisionGroup,
			}
		end
	end
	
	return snapshot
end

local function restoreCollisionState(snapshot: { [BasePart]: { CanCollide: boolean, Massless: boolean, CollisionGroup: string } }?)
	if typeof(snapshot) ~= "table" then
		return
	end
	
	for part, data in pairs(snapshot) do
		if part and part.Parent and typeof(data) == "table" then
			pcall(function()
				part.CanCollide = data.CanCollide == true
				part.Massless = data.Massless == true
				if typeof(data.CollisionGroup) == "string" and data.CollisionGroup ~= "" then
					part.CollisionGroup = data.CollisionGroup
				end
			end)
		end
	end
end

function SimpleRagdollService:_setAccessoryCollision(character: Model, canCollide: boolean)
	if not isValidCharacter(character) then
		return
	end
	
	for _, inst in ipairs(character:GetDescendants()) do
		if inst:IsA("BasePart") and isAccessoryPart(inst) then
			inst.CanCollide = canCollide
			if not canCollide then
				inst.Massless = true
			end
		end
	end
end

function SimpleRagdollService:_shouldForceRagdollCollision(part: BasePart, rigType: Enum.HumanoidRigType?): boolean
	if part.Name == "HumanoidRootPart" then
		return false
	end
	if isAccessoryPart(part) then
		return false
	end
	if rigType == Enum.HumanoidRigType.R6 then
		return self.config.r6CollisionParts[part.Name] == true
	end
	return true
end

function SimpleRagdollService:_setRagdollCollisions(character: Model, humanoid: Humanoid?, enabled: boolean)
	if not isValidCharacter(character) then
		return
	end
	
	local rigType = humanoid and humanoid.RigType
	for _, part in ipairs(character:GetDescendants()) do
		if part:IsA("BasePart") then
			if self:_shouldForceRagdollCollision(part, rigType) then
				part.CanCollide = enabled
				if enabled then
					part.Massless = false
					part.CollisionGroup = "Default"
				end
			end
		end
	end
end

-- ============================================================================
-- RAGDOLL BUILDING & CLEANUP
-- ============================================================================

function SimpleRagdollService:_cleanupRagdollArtifacts(character: Model)
	if not isValidCharacter(character) then
		return
	end
	
	for _, inst in ipairs(character:GetDescendants()) do
		if inst:IsA("Attachment") and (inst.Name == self.config.attachmentNames.a0 or inst.Name == self.config.attachmentNames.a1) then
			inst:Destroy()
		elseif inst:IsA("BallSocketConstraint") and inst.Name == self.config.socketName then
			inst:Destroy()
		end
	end
end

function SimpleRagdollService:_applyRagdollJointLimits(socket: BallSocketConstraint, motorName: string)
	local limits = self.config.jointLimits[motorName] or self.config.jointLimits.Default
	socket.LimitsEnabled = true
	socket.UpperAngle = limits.upper
	socket.TwistLimitsEnabled = true
	socket.TwistLowerAngle = limits.twistLower
	socket.TwistUpperAngle = limits.twistUpper
	socket.MaxFrictionTorque = limits.friction
	socket.Restitution = 0
end

function SimpleRagdollService:_buildRagdollFromMotors(character: Model): ({ { Name: string, Part0: BasePart, Part1: BasePart, C0: CFrame, C1: CFrame, Parent: Instance } }, { Instance })
	local motorData = {}
	local created = {}
	
	self:_cleanupRagdollArtifacts(character)
	
	for _, inst in ipairs(character:GetDescendants()) do
		if inst:IsA("Motor6D") then
			local motor = inst
			if motor.Part0 and motor.Part1 then
				table.insert(motorData, {
					Name = motor.Name,
					Part0 = motor.Part0,
					Part1 = motor.Part1,
					C0 = motor.C0,
					C1 = motor.C1,
					Parent = motor.Parent,
				})
				
				local a0 = Instance.new("Attachment")
				a0.Name = self.config.attachmentNames.a0
				a0.CFrame = motor.C0
				a0.Parent = motor.Part0
				table.insert(created, a0)
				
				local a1 = Instance.new("Attachment")
				a1.Name = self.config.attachmentNames.a1
				a1.CFrame = motor.C1
				a1.Parent = motor.Part1
				table.insert(created, a1)
				
				local socket = Instance.new("BallSocketConstraint")
				socket.Name = self.config.socketName
				socket.Attachment0 = a0
				socket.Attachment1 = a1
				self:_applyRagdollJointLimits(socket, motor.Name)
				socket.Parent = motor.Part0
				table.insert(created, socket)
			end
			
			motor:Destroy()
		end
	end
	
	return motorData, created
end

function SimpleRagdollService:_restoreMotorsFromData(character: Model, motorData: { { Name: string, Part0: BasePart, Part1: BasePart, C0: CFrame, C1: CFrame, Parent: Instance } })
	for _, data in ipairs(motorData or {}) do
		if data.Part0 and data.Part1 and data.Parent then
			local motor = Instance.new("Motor6D")
			motor.Name = data.Name
			motor.Part0 = data.Part0
			motor.Part1 = data.Part1
			motor.C0 = data.C0
			motor.C1 = data.C1
			motor.Parent = data.Parent
		end
	end
end

-- ============================================================================
-- CHARACTER RECOVERY
-- ============================================================================

function SimpleRagdollService:_standCharacterUp(character: Model, humanoid: Humanoid, yOffset: number?, blendDuration: number?)
	if not isValidCharacter(character) or not isValidHumanoid(humanoid) then
		return
	end
	
	local lift = typeof(yOffset) == "number" and yOffset or 2.75
	local blendTime = typeof(blendDuration) == "number" and math.max(0, blendDuration) or 0
	local root = getRootPart(character)
	
	if not root then
		return
	end
	
	-- Calculate target position with raycast
	local targetPos = root.Position + Vector3.new(0, lift, 0)
	do
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = { character }
		params.IgnoreWater = false
		
		local probeOrigin = targetPos + Vector3.new(0, 8, 0)
		local probeDir = Vector3.new(0, -80, 0)
		local hit = workspace:Raycast(probeOrigin, probeDir, params)
		
		if hit then
			local halfRoot = root.Size.Y * 0.5
			local safeY = hit.Position.Y + halfRoot + math.max(0, humanoid.HipHeight) + 0.15
			if targetPos.Y < safeY then
				targetPos = Vector3.new(targetPos.X, safeY, targetPos.Z)
			end
		end
	end
	
	-- Calculate orientation
	local look = root.CFrame.LookVector
	local planar = Vector3.new(look.X, 0, look.Z)
	if planar.Magnitude < 0.05 then
		planar = Vector3.new(0, 0, -1)
	else
		planar = planar.Unit
	end
	
	local targetCFrame = CFrame.lookAt(targetPos, targetPos + planar, Vector3.new(0, 1, 0))
	
	-- Smooth blend
	if blendTime > 0 then
		local startCFrame = root.CFrame
		local elapsed = 0
		
		while elapsed < blendTime do
			if not isValidCharacter(character) or not isValidHumanoid(humanoid) then
				break
			end
			
			local dt = RunService.Heartbeat:Wait()
			elapsed += dt
			local alpha = math.clamp(elapsed / blendTime, 0, 1)
			local eased = alpha * alpha * (3 - 2 * alpha)
			
			root.CFrame = startCFrame:Lerp(targetCFrame, eased)
			root.AssemblyLinearVelocity = Vector3.zero
			root.AssemblyAngularVelocity = Vector3.zero
		end
	end
	
	root.CFrame = targetCFrame
	root.AssemblyLinearVelocity = Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero
	
	-- Restore flags
	local function restoreFlags()
		if not isValidHumanoid(humanoid) then
			return
		end
		self:_setStateMachineEnabled(humanoid, true)
		self:_setSeatedStateBlocked(humanoid, false)
		humanoid.Sit = false
		humanoid.PlatformStand = false
		humanoid.AutoRotate = true
		self.humanoidStateBackup[humanoid] = nil
	end
	
	restoreFlags()
	
	if humanoid.RigType == Enum.HumanoidRigType.R6 then
		humanoid.HipHeight = 0
	end
	
	humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
	
	local settleDelay = blendTime > 0 and math.max(0.05, blendTime * 0.5) or 0
	local function applyRunningState()
		if not isValidHumanoid(humanoid) or self.ragdollState[character] then
			return
		end
		restoreFlags()
		humanoid:ChangeState(Enum.HumanoidStateType.Running)
	end
	
	if settleDelay > 0 then
		task.delay(settleDelay, applyRunningState)
	else
		applyRunningState()
	end
	
	for _, delaySeconds in ipairs({ 0.03, 0.08, 0.18 }) do
		task.delay(delaySeconds + settleDelay, function()
			if isValidHumanoid(humanoid) and not self.ragdollState[character] then
				restoreFlags()
			end
		end)
	end
end

-- ============================================================================
-- SCRIPT MANAGEMENT
-- ============================================================================

local function getCharacterScript(character: Model?, scriptName: string): Instance?
	if not isValidCharacter(character) then
		return nil
	end
	return character:FindFirstChild(scriptName)
end

function SimpleRagdollService:_disableCharacterScripts(character: Model?)
	if not isValidCharacter(character) then
		return
	end
	
	local state = self.ragdollScriptState[character] or {}
	
	for _, scriptName in ipairs(self.config.scriptsToDisable) do
		local script = getCharacterScript(character, scriptName)
		if script and (script:IsA("Script") or script:IsA("LocalScript")) then
			state[scriptName] = script.Enabled == true
			script.Enabled = false
		end
	end
	
	self.ragdollScriptState[character] = state
end

function SimpleRagdollService:_restoreCharacterScripts(character: Model?)
	if not isValidCharacter(character) then
		return
	end
	
	local state = self.ragdollScriptState[character]
	if not state then
		return
	end
	
	for _, scriptName in ipairs(self.config.scriptsToDisable) do
		if state[scriptName] then
			local script = getCharacterScript(character, scriptName)
			if script then
				script.Enabled = true
			end
		end
	end
	
	self.ragdollScriptState[character] = nil
end

-- ============================================================================
-- HUMANOID STATE MANAGEMENT
-- ============================================================================

function SimpleRagdollService:_setStateMachineEnabled(humanoid: Humanoid?, enabled: boolean)
	if not humanoid then
		return
	end
	
	local ok, current = pcall(function()
		return humanoid.EvaluateStateMachine
	end)
	
	if not ok then
		return
	end
	
	if enabled then
		humanoid.EvaluateStateMachine = true
		self.humanoidStateBackup[humanoid] = nil
	else
		if not self.humanoidStateBackup[humanoid] then
			self.humanoidStateBackup[humanoid] = { evaluate = current }
		end
		humanoid.EvaluateStateMachine = false
	end
end

function SimpleRagdollService:_setSeatedStateBlocked(humanoid: Humanoid?, blocked: boolean)
	if not humanoid then
		return
	end
	
	pcall(function()
		humanoid:SetStateEnabled(Enum.HumanoidStateType.Seated, not blocked)
	end)
	
	if blocked then
		humanoid.Sit = false
		if humanoid.Health > 0 then
			humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
		end
	end
end

-- ============================================================================
-- COLLISION REFRESH
-- ============================================================================

function SimpleRagdollService:_scheduleCollisionRefresh(character: Model, humanoid: Humanoid?)
	if not isValidCharacter(character) then
		return
	end
	
	for step = 1, self.config.collisionStabilizeRetries do
		task.delay(step * self.config.collisionStabilizeStep, function()
			if not isValidCharacter(character) or not self.ragdollState[character] then
				return
			end
			
			local hum = humanoid
			if not hum or hum.Parent ~= character then
				hum = character:FindFirstChildOfClass("Humanoid")
			end
			
			if not hum then
				return
			end
			
			self:_setRagdollCollisions(character, hum, true)
			local root = getRootPart(character)
			if root then
				root.CanCollide = false
			end
		end)
	end
end

-- ============================================================================
-- DEATH CLEANUP
-- ============================================================================

function SimpleRagdollService:_setupDeathCleanup(character: Model, humanoid: Humanoid, player: Player?)
	if self.ragdollDeathConnection[character] then
		self.ragdollDeathConnection[character]:Disconnect()
		self.ragdollDeathConnection[character] = nil
	end
	
	self.ragdollDeathConnection[character] = humanoid.Died:Connect(function()
		if self.ragdollDeathConnection[character] then
			self.ragdollDeathConnection[character]:Disconnect()
			self.ragdollDeathConnection[character] = nil
		end
		
		self.ragdollState[character] = nil
		self.ragdollScriptState[character] = nil
	end)
end

-- ============================================================================
-- PUBLIC API
-- ============================================================================

function SimpleRagdollService:IsRagdolled(character: Model): boolean
	return self.ragdollState[character] ~= nil
end

function SimpleRagdollService:Ragdoll(character: Model): (boolean, string?)
	if typeof(character) ~= "Instance" or not character:IsA("Model") then
		return false, "InvalidCharacter"
	end
	
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return false, "NoHumanoid"
	end
	
	local player = Players:GetPlayerFromCharacter(character)
	
	-- Already ragdolled - reapply physics
	if self.ragdollState[character] then
		self:_applyRagdollPhysics(character, humanoid)
		self:_setStateMachineEnabled(humanoid, false)
		self:_setSeatedStateBlocked(humanoid, true)
		humanoid.PlatformStand = true
		humanoid.AutoRotate = false
		humanoid:ChangeState(Enum.HumanoidStateType.Physics)
		self:_scheduleCollisionRefresh(character, humanoid)
		self:_disableCharacterScripts(character)
		self:_setupDeathCleanup(character, humanoid, player)
		
		return true, nil
	end
	
	-- Build ragdoll
	local collisionState = captureCollisionState(character)
	local motorData, created = self:_buildRagdollFromMotors(character)
	
	if #motorData == 0 then
		return false, "NoMotor6D"
	end
	
	-- Store state
	self.ragdollState[character] = {
		motorData = motorData,
		parts = created,
		collisionState = collisionState,
	}
	
	-- Apply physics
	self:_applyRagdollPhysics(character, humanoid)
	
	local root = getRootPart(character)
	if root then
		root.AssemblyLinearVelocity = Vector3.zero
		root.AssemblyAngularVelocity = Vector3.zero
	end
	
	self:_setStateMachineEnabled(humanoid, false)
	self:_setSeatedStateBlocked(humanoid, true)
	humanoid.PlatformStand = true
	humanoid.AutoRotate = false
	humanoid:ChangeState(Enum.HumanoidStateType.Physics)
	self:_scheduleCollisionRefresh(character, humanoid)
	self:_disableCharacterScripts(character)
	self:_setupDeathCleanup(character, humanoid, player)
	
	-- R6 specific
	if humanoid.RigType == Enum.HumanoidRigType.R6 then
		task.delay(0.05, function()
			if not isValidCharacter(character) or not self.ragdollState[character] then
				return
			end
			for _, inst in ipairs(character:GetDescendants()) do
				if inst:IsA("Motor6D") then
					inst.Enabled = false
				end
			end
			humanoid.PlatformStand = true
			humanoid.AutoRotate = false
			humanoid:ChangeState(Enum.HumanoidStateType.Physics)
		end)
	end
	
	return true, nil
end

function SimpleRagdollService:Unragdoll(character: Model): (boolean, string?)
	if typeof(character) ~= "Instance" or not character:IsA("Model") then
		return false, "InvalidCharacter"
	end
	
	local state = self.ragdollState[character]
	local player = Players:GetPlayerFromCharacter(character)
	
	if not state then
		self:_restoreCharacterScripts(character)
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			self:_setSeatedStateBlocked(humanoid, false)
			self:_standCharacterUp(character, humanoid, 0.5)
		end
		return false, "NotRagdolled"
	end
	
	-- Clean up
	for _, inst in ipairs(state.parts or {}) do
		if inst and inst.Parent then
			inst:Destroy()
		end
	end
	
	-- Restore motors
	self:_restoreMotorsFromData(character, state.motorData)
	
	self.ragdollState[character] = nil
	self:_cleanupRagdollArtifacts(character)
	self:_setAccessoryCollision(character, true)
	restoreCollisionState(state.collisionState)
	
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid and not state.collisionState then
		self:_setRagdollCollisions(character, humanoid, false)
	end
	
	self:_setSeatedStateBlocked(humanoid, false)
	
	self:_restoreCharacterScripts(character)
	
	if player then
		setNetworkOwnerToPlayer(character, player)
	end
	
	-- Recovery
	if humanoid then
		local previousWalkSpeed = humanoid.WalkSpeed
		local previousJumpPower = humanoid.JumpPower
		humanoid.WalkSpeed = 0
		humanoid.JumpPower = 0
		
		self:_standCharacterUp(character, humanoid, self.config.recoveryLiftOffset, self.config.recoveryBlendDuration)
		
		task.delay(self.config.recoveryMobilityLock, function()
			if isValidHumanoid(humanoid) and not self.ragdollState[character] then
				humanoid.WalkSpeed = previousWalkSpeed
				humanoid.JumpPower = previousJumpPower
			end
		end)
	end
	
	-- Disconnect death handler
	if self.ragdollDeathConnection[character] then
		self.ragdollDeathConnection[character]:Disconnect()
		self.ragdollDeathConnection[character] = nil
	end
	
	return true, nil
end

function SimpleRagdollService:Toggle(character: Model, enabled: boolean?): (boolean, string?)
	if enabled == nil then
		enabled = not self:IsRagdolled(character)
	end
	
	if enabled then
		return self:Ragdoll(character)
	else
		return self:Unragdoll(character)
	end
end

function SimpleRagdollService:_applyRagdollPhysics(character: Model, humanoid: Humanoid?)
	if not isValidCharacter(character) then
		return
	end
	
	self:_setRagdollCollisions(character, humanoid, true)
	setNetworkOwnerToServer(character)
	self:_setAccessoryCollision(character, false)
	
	local root = getRootPart(character)
	if root then
		root.CanCollide = false
	end
end

return SimpleRagdollService
