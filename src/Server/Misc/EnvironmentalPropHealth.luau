local CollectionService = game:GetService("CollectionService")
local HttpService = game:GetService("HttpService")

local EnvironmentalPropHealthSystem = {}

-- Configuration (Adjust these as needed)
EnvironmentalPropHealthSystem.DEFAULT_PROP_HEALTH = 100
EnvironmentalPropHealthSystem.DEFAULT_DAMAGE_MULTIPLIER = 1.0
EnvironmentalPropHealthSystem.DEBOUNCE_TIME = 0.2 -- 200ms debounce

-- Store prop health data and debounce timers
EnvironmentalPropHealthSystem.propHealthData = {}
EnvironmentalPropHealthSystem.propDebounce = {}

-- Initialize health for a prop
function EnvironmentalPropHealthSystem.initializeHealth(prop)
	local propId = prop:GetAttribute("PropId")
	if not propId then
		propId = HttpService:GenerateGUID(false)
		prop:SetAttribute("PropId", propId)
	end

	-- Check if prop already has custom health value
	local maxHealth = prop:GetAttribute("MaxHealth") or EnvironmentalPropHealthSystem.DEFAULT_PROP_HEALTH

	print("Initializing prop " .. propId .. " with " .. maxHealth .. " health")

	-- Set up health data for this prop
	EnvironmentalPropHealthSystem.propHealthData[propId] = {
		maxHealth = maxHealth,
		currentHealth = maxHealth,
		damageMultiplier = prop:GetAttribute("DamageMultiplier") or EnvironmentalPropHealthSystem.DEFAULT_DAMAGE_MULTIPLIER
	}

	-- Set attributes for client-side use
	prop:SetAttribute("MaxHealth", maxHealth)
	prop:SetAttribute("CurrentHealth", maxHealth)

	return propId
end

-- Apply damage to a prop, returns true if prop should be destroyed
function EnvironmentalPropHealthSystem.applyDamage(prop, damage)
	local propId = prop:GetAttribute("PropId")

	-- Initialize health if not already done
	if not propId or not EnvironmentalPropHealthSystem.propHealthData[propId] then
		propId = EnvironmentalPropHealthSystem.initializeHealth(prop)
	end

	-- Check debounce - prevent multiple rapid hits
	local now = tick()
	if EnvironmentalPropHealthSystem.propDebounce[propId] and 
		now - EnvironmentalPropHealthSystem.propDebounce[propId] < EnvironmentalPropHealthSystem.DEBOUNCE_TIME then
		-- Still in debounce period, ignore this hit
		print("PROP " .. propId .. " - hit ignored (debounce)")
		return false, EnvironmentalPropHealthSystem.propHealthData[propId].currentHealth
	end

	-- Set debounce
	EnvironmentalPropHealthSystem.propDebounce[propId] = now

	local healthData = EnvironmentalPropHealthSystem.propHealthData[propId]
	local effectiveDamage = damage * healthData.damageMultiplier

	-- Store previous health for diff calculation
	local previousHealth = healthData.currentHealth

	-- Reduce health
	healthData.currentHealth = math.max(0, healthData.currentHealth - effectiveDamage)

	-- Debug output
	print("PROP " .. propId .. " DAMAGED: " .. previousHealth .. " -> " .. healthData.currentHealth .. " (-" .. effectiveDamage .. ")")

	-- Update attribute for client-side use
	prop:SetAttribute("CurrentHealth", healthData.currentHealth)

	-- Return true if prop should be destroyed, plus previous health
	return healthData.currentHealth <= 0, previousHealth
end

-- Reset health when prop is restored
function EnvironmentalPropHealthSystem.resetHealth(prop)
	local propId = prop:GetAttribute("PropId")
	if not propId then return end

	local healthData = EnvironmentalPropHealthSystem.propHealthData[propId]
	if not healthData then return end

	print("PROP " .. propId .. " HEALTH RESET: " .. healthData.currentHealth .. " -> " .. healthData.maxHealth)

	-- Reset to max health
	healthData.currentHealth = healthData.maxHealth

	-- Clear debounce timer
	EnvironmentalPropHealthSystem.propDebounce[propId] = nil

	-- Update attribute
	prop:SetAttribute("CurrentHealth", healthData.maxHealth)
end

-- Clear all health data (call when map changes)
function EnvironmentalPropHealthSystem.clearAllHealthData()
	table.clear(EnvironmentalPropHealthSystem.propHealthData)
	table.clear(EnvironmentalPropHealthSystem.propDebounce)
	print("Cleared all prop health data")
end

return EnvironmentalPropHealthSystem