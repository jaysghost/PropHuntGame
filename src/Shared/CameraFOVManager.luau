-- Create a new script: CameraFOVManager.lua
local RunService = game:GetService("RunService")
local camera = workspace.CurrentCamera

local CameraFOVManager = {}
CameraFOVManager.DEFAULT_FOV = 70
CameraFOVManager.recoilOffset = 0
CameraFOVManager.speedOffset = 0
CameraFOVManager.activeSystem = nil -- Which system is currently controlling FOV

function CameraFOVManager.init()
	RunService:BindToRenderStep(
		"CameraFOVManager", 
		Enum.RenderPriority.Camera.Value + 10, -- Highest priority
		function(dt)
			local targetFOV = CameraFOVManager.DEFAULT_FOV

			-- Determine which effect to use
			if CameraFOVManager.activeSystem == "recoil" then
				targetFOV = targetFOV + CameraFOVManager.recoilOffset
			elseif CameraFOVManager.activeSystem == "speed" then
				targetFOV = targetFOV + CameraFOVManager.speedOffset
			else
				-- Use the larger effect if no active system
				targetFOV = targetFOV + math.max(CameraFOVManager.recoilOffset, CameraFOVManager.speedOffset)
			end

			camera.FieldOfView = math.lerp(camera.FieldOfView, targetFOV, math.min(dt * 5, 1))
		end
	)
end

-- Methods for BlasterUtilities to use
function CameraFOVManager.setRecoilOffset(offset)
	CameraFOVManager.recoilOffset = offset
	if offset > 0.1 then
		CameraFOVManager.activeSystem = "recoil"
		-- Auto release after short delay
		task.delay(0.3, function() 
			if CameraFOVManager.activeSystem == "recoil" then
				CameraFOVManager.activeSystem = nil
			end
		end)
	end
end

-- Methods for QuakePhysics to use
function CameraFOVManager.setSpeedOffset(offset)
	CameraFOVManager.speedOffset = offset
	if offset > 3 and CameraFOVManager.activeSystem ~= "recoil" then
		CameraFOVManager.activeSystem = "speed"
	elseif offset < 1 and CameraFOVManager.activeSystem == "speed" then
		CameraFOVManager.activeSystem = nil
	end
end

CameraFOVManager.init()
return CameraFOVManager