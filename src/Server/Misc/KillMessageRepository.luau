-- KillMessageRepository.lua - Place in ServerScriptService
local KillMessageRepository = {}

-- Table of possible kill messages
-- {victim} will be replaced with the victim's name
-- No mention of the killer in these messages
KillMessageRepository.Messages = {
	"{victim} was caught slippin'",
	"{victim} didn't check their six",
	"{victim} found out the hard way",
	"{victim} forgot how to play",
	"{victim} was promoted to spectator",
	"{victim} become a cautionary tale",
	"{victim} had skill issues",
	"{victim} didn't have a gaming chair",
	"{victim} got absolutely bodied",
	"{victim} found out they're not them",
	"{victim} was put on a poster"
}

-- Function to get a random message
function KillMessageRepository.GetRandomMessage()
	local randomIndex = math.random(1, #KillMessageRepository.Messages)
	return KillMessageRepository.Messages[randomIndex]
end

-- Function to format message with victim name
function KillMessageRepository.FormatKillMessage(messageTemplate, victimName)
	local message = string.gsub(messageTemplate, "{victim}", victimName)
	return message
end

-- Function to get a complete random kill message with victim name filled in
function KillMessageRepository.GetRandomKillMessage(victimName)
	local template = KillMessageRepository.GetRandomMessage()
	return KillMessageRepository.FormatKillMessage(template, victimName)
end

-- Allow developers to add custom messages
function KillMessageRepository.AddCustomMessage(message)
	table.insert(KillMessageRepository.Messages, message)
end

return KillMessageRepository