PLUGIN = nil
ToggleState = {}
Settings = {}
Cooldowns = {}
Database = nil

SettingsPath = "Settings.ini"
DatabasePath = "TPA.sqlite3"
CooldownTableName = "CooldownLog"
TransactionTableName = "Transactions"
CleanupTime = 0
CleanupCooldown = 5 * 60

-- constants for easier readability
RequestCooldown = 2
SuccessCooldown = 3

function Initialize(Plugin)
	Plugin:SetName("TPA")
	Plugin:SetVersion(1)

	PLUGIN = Plugin -- NOTE: only needed if you want OnDisable() to use GetName() or something like that

	-- Use the InfoReg shared library to process the Info.lua file:
	dofile(cPluginManager:GetPluginsPath() .. cFile:GetPathSeparator() .. "InfoReg.lua")
	RegisterPluginInfoCommands()
	RegisterPluginInfoConsoleCommands()

	local PluginFolder = cPluginManager:GetPluginsPath() .. cFile:GetPathSeparator() .. Plugin:GetFolderName() .. cFile:GetPathSeparator()

	-- Load settings
	LoadSettings(PluginFolder .. SettingsPath)

	-- Creates/Loads Database
	Database = sqlite3.open(PluginFolder .. DatabasePath)

	-- Creates the table if does not exist
	Database:exec([[CREATE TABLE IF NOT EXISTS ]] .. CooldownTableName ..
	[[
		(
			PlayerUUID TEXT PRIMARY KEY,
			LastRequest INT DEFAULT 0,
			LastSuccess INT DEFAULT 0,
		)
	]])
	
	Database:exec([[CREATE TABLE IF NOT EXISTS ]] .. TransactionTableName ..
	[[
		(
			TransactionId TEXT PRIMARY KEY,
			Source TEXT,
			Destination TEXT,
			Timestamp INT DEFAULT 0
		)
	]])

	-- Hooks
	cPluginManager:AddHook(cPluginManager.HOOK_PLAYER_JOINED, OnPlayerJoined)
	cPluginManager:AddHook(cPluginManager.HOOK_TICK,          OnTick)

	LOG("[" .. Plugin:GetName() .. "] Version " .. Plugin:GetVersion() .. " initialized")
	return true
end

function OnDisable()
	LOG("[" .. PLUGIN:GetName() .."] shutting down...")

	-- Store database
	Database:exec("DROP TABLE IF EXISTS ".. TransactionTableName)
	Database:close()
end

function LoadSettings(path)
	os.remove(path) -- Todo: remove
	local IniFile = cIniFile()
	if not IniFile:ReadFile(path, false) then
		-- File does not exist
		LOG("[" .. PLUGIN:GetName() .."] Didn't find settings file. Creating a new one.")
		IniFile:AddHeaderComment("This is the settings file for the TPA plugin. Lines starting with \";\" are comments.") 
		IniFile:AddHeaderComment("To reset stop the server, delete this and restart.")

		IniFile:AddKeyName("Cooldown")
		IniFile:AddKeyComment("Cooldown", "Sets the cooldown the players have to wait after sending a request or successfully teleporting")
		IniFile:AddKeyComment("Cooldown", "Times maybe be set in the format of %h%m%s.")
		IniFile:AddValue("Cooldown", "Request", "10s")
		IniFile:AddValue("Cooldown", "Sucess", "60s")

		IniFile:AddKeyName("Logging")
		IniFile:AddKeyComment("Logging", "Sets if the plugin should log it's activity to the console")
		IniFile:AddValueB("Logging", "VerboseLogging", false)
	end

	local RequestCooldownString = IniFile:GetValue("Cooldown", "Request", "10s")
	local SucessCooldownString = IniFile:GetValue("Cooldown", "Sucess", "60s")
	Settings["VerboseLogging"] = IniFile:GetValueB("Logging", "VerboseLogging", false)
	Settings["RequestCooldown"] = StringToSeconds(RequestCooldownString)
	Settings["SuccessCooldown"] = StringToSeconds(SucessCooldownString)

	IniFile:WriteFile(path)
end
--------------------------------------------------------------------------------------------------------------------------------

-- utility
function StringToSeconds(String)
	local TotalSecondCount = 0
	String = String:gsub(" ", "")
	String = String:lower()

	local hours = String:match("(%d+)h")
	if hours ~= nil then
		TotalSecondCount = TotalSecondCount + tonumber(hours) * 60 * 60
	end

	local minutes = String:match("(%d+)m")
	if minutes ~= nil then
		TotalSecondCount = TotalSecondCount + tonumber(minutes) * 60
	end

	local seconds = String:match("(%d+)s")
	if seconds ~= nil then
		TotalSecondCount = TotalSecondCount + tonumber(seconds)
	end

	return TotalSecondCount
end

function SendToBothParticipiants(Player, Destination, Message)
	cRoot:Get():FindAndDoWithPlayer(Destination, function(OtherPlayer)
		OtherPlayer:SendMessageRaw(Message:CreateJsonString(), Message:GetMessageType())
	end)
	Player:SendMessageRaw(Message:CreateJsonString(), Message:GetMessageType())
end

--------------------------------------------------------------------------------------------------------------------------------
-- Hooks

function OnPlayerJoined(Player)
	StoreCooldown(Player:GetUUID(), RequestCooldown, 1)
	StoreCooldown(Player:GetUUID(), SuccessCooldown, 1)
end

function OnTick(TimeDelta)
	if os.time() - CleanupTime > CleanupCooldown then
		CleanupTime = os.time()
		CleanupTransaction()
	end
end

--------------------------------------------------------------------------------------------------------------------------------

-- handles sending teleport requests
function SendRequest(Split, Player)
	if #Split ~= 2 then
		Player:SendMessage("Usage: /tpa [Player]")
		return true
	end

	if Player:GetName() == Split[2] then
		Player:SendMessage("You can't teleport to yourself. The universe will implode!!!")
		-- return true
	end

	-- check for cooldown
	local NowTime = os.time()
	if NowTime - GetCooldown(Player:GetUUID(), RequestCooldown) < Settings["RequestCooldown"] and not Player:HasPermission("tpa.overrideCoolDown") then
		local Message = cCompositeChat()
		Message:AddTextPart("Sending request failed. Please wait for your cooldown to send a request to run out!", "@6")
		Player:SendMessageRaw(Message:CreateJsonString(), Message:GetMessageType())
		return true
	end

	if NowTime - GetCooldown(Player:GetUUID(), SuccessCooldown) < Settings["SuccessCooldown"] and not Player:HasPermission("tpa.overrideCoolDown") then
		local Message = cCompositeChat()
		Message:AddTextPart("Sending request failed. Please wait for your cooldown to teleport to run out!")
		Player:SendMessageRaw(Message:CreateJsonString(), Message:GetMessageType())
		return true
	end
	StoreCooldown(Player:GetUUID(), RequestCooldown, NowTime)

	-- check for hiding
	-- send request
	if not cRoot:Get():FindAndDoWithPlayer(Split[2], 
		function (OtherPlayer)
			if OtherPlayer:HasPermission("tpa.hide") then
				local Message = cCompositeChat()
				Message:AddTextPart("Player ", "@6")
				Message:AddTextPart(Split[2], "b@6")
				Message:AddTextPart(" was not found, aborting...", "@6")
				Player:SendMessageRaw(Message:CreateJsonString(), Message:GetMessageType())
				--return false
			end
			if (Player:HasPermission("tpa.override")) then
				local Message = cCompositeChat()
				Message:AddTextPart("Teleporting...", "@b")
				Player:SendMessageRaw(Message:CreateJsonString(), Message:GetMessageType())
				Player:TeleportToEntity(OtherPlayer)
				--return true
			end
			ID = CreateTransaction(Player, OtherPlayer)

			local Message = cCompositeChat()
			Message:AddTextPart("Sent request to " .. Split[2], "b@6")
			Player:SendMessageRaw(Message:CreateJsonString(), Message:GetMessageType())

			Message = cCompositeChat()
			Message:AddTextPart("Player " .. Player:GetName() .. " has sent you a teleport request. ", "b@6")
			Message:AddRunCommandPart("Accept", "/tpaccept " .. ID, "u@a")
			Message:AddTextPart(" ")
			Message:AddRunCommandPart("Deny", "/tpdeny " .. ID, "u@c")
			OtherPlayer:SendMessageRaw(Message:CreateJsonString(), Message:GetMessageType())
			return true
		end
	) then
		-- failed
		local Message = cCompositeChat()
		Message:AddTextPart("Player ", "@6")
		Message:AddTextPart(Split[2], "b@6")
		Message:AddTextPart(" was not found, aborting...", "@6")
		Player:SendMessageRaw(Message:CreateJsonString(), Message:GetMessageType())
	end
	return true
end

-- handles accepting teleport requests
function AcceptRequest(Split, Player)
	if #Split ~= 2 then
		Player:SendMessage("Usage: /tpaccept [Player|ID]")
		return true
	end
	local ID = cUUID()

	local RowCount = 0

	local Destination = ""
	local Source = ""
	local Transaction = ""
	local Timestamp = 0

	if not ID:FromString(Split[2]) then
		-- Got Player
		for row in Database:nrows("SELECT * FROM " .. TransactionTableName .. " WHERE Source = '" .. Split[2] .. "' ORDER BY TimeStamp DESC") do
			RowCount = RowCount + 1
			Destination = row["Destination"]
			Source = row["Source"]
			Timestamp = tonumber(row["Timestamp"])
			Transaction =  row["TransactionId"]
			-- Remove the TransactionId
			Database:exec("DELETE FROM " .. TransactionTableName .. " WHERE TransactionId = '" .. Transaction .. "'")
		end
	else
		-- Got UUID
		for row in Database:nrows("SELECT * FROM " .. TransactionTableName .. " WHERE TransactionId = '" .. Split[2] .. "'") do
			RowCount = RowCount + 1
			Destination = row["Destination"]
			Source = row["Source"]
			Timestamp = tonumber(row["Timestamp"])
			-- Remove the TransactionId
			Database:exec("DELETE FROM " .. TransactionTableName .. " WHERE TransactionId = '" .. Split[2] .. "'")
		end
	end

	if RowCount == 0 then
		local Message = cCompositeChat()
		Message:AddTextPart("The request with timed out. Please resend the request!", "@b")
		Player:SendMessageRaw(Message:CreateJsonString(), Message:GetMessageType())
	else
		if Destination ~= Player:GetName() then
			local Message = cCompositeChat()
			Message:AddTextPart("An internal error occurred. Please resend the request!", "@b")
			Player:SendMessageRaw(Message:CreateJsonString(), Message:GetMessageType())
			SendToBothParticipiants(Player, Source, Message)
			return true
		end

		cRoot:Get():FindAndDoWithPlayer(Destination, function(OtherPlayer)
			Player:TeleportToEntity(OtherPlayer)
			StoreCooldown(OtherPlayer:GetUUID(), SuccessCooldown, Settings["SuccessCooldown"])
		end)
		local Message = cCompositeChat()
		Message:AddTextPart("Teleporting...", "@b")
		Player:SendMessageRaw(Message:CreateJsonString(), Message:GetMessageType())
	end

	return true
end

--handles denying teleport requests
function DenyRequest(Split, Player)
	if #Split ~= 2 then
		Player:SendMessage("Usage: /tpaccept [Player|ID]")
		return true
	end

	local ID = cUUID()

	local RowCount = 0

	local Destination = ""
	local Source = ""
	local Transaction = ""
	local Timestamp = 0

	if not ID:FromString(Split[2]) then
		-- Got Player
		for row in Database:nrows("SELECT * FROM " .. TransactionTableName .. " WHERE Source = '" .. Split[2] .. "' ORDER BY TimeStamp DESC") do
			RowCount = RowCount + 1
			Destination = row["Destination"]
			Source = row["Source"]
			Timestamp = tonumber(row["Timestamp"])
			Transaction =  row["TransactionId"]
			-- Remove the TransactionId
			Database:exec("DELETE FROM " .. TransactionTableName .. " WHERE TransactionId = '" .. Transaction .. "'")
		end
	else
		-- Got UUID
		for row in Database:nrows("SELECT * FROM " .. TransactionTableName .. " WHERE TransactionId = '" .. Split[2] .. "'") do
			RowCount = RowCount + 1
			Destination = row["Destination"]
			Source = row["Source"]
			Timestamp = tonumber(row["Timestamp"])
			-- Remove the TransactionId
			Database:exec("DELETE FROM " .. TransactionTableName .. " WHERE TransactionId = '" .. Split[2] .. "'")
		end
	end

	if RowCount == 0 then
		local Message = cCompositeChat()
		Message:AddTextPart("The request with timed out. Please resend the request!", "@b")
		Player:SendMessageRaw(Message:CreateJsonString(), Message:GetMessageType())
	else
		if Destination ~= Player:GetName() then
			local Message = cCompositeChat()
			Message:AddTextPart("An internal error occurred. Please resend the request!", "@b")
			SendToBothParticipiants(Player, Source, Message)
			return true
		end

		local Message = cCompositeChat()
		Message:AddTextPart("Your request to ".. Destination .." was denied", "@b")
		cRoot:Get():FindAndDoWithPlayer(Destination, function(OtherPlayer)
			OtherPlayer:SendMessageRaw(Message:CreateJsonString(), Message:GetMessageType())
		end)
		Message:Clear()
		Message:AddTextPart("Denied request from " .. Source, "@b")
		Player:SendMessageRaw(Message:CreateJsonString(), Message:GetMessageType())
	end

	return true
end

-- handles writing to database
function StoreCooldown(PlayerUUID, CooldownType, Cooldown)
	if CooldownType == RequestCooldown then
		Database:exec("INSERT OR REPLACE INTO " .. CooldownTableName .. " (PlayerUUID, LastRequest) VALUES('" .. PlayerUUID .."', " .. Cooldown .. ")")
	elseif CooldownType == SuccessCooldown then
		Database:exec("INSERT OR REPLACE INTO " .. CooldownTableName .. " (PlayerUUID, LastSuccess) VALUES('" .. PlayerUUID .."', " .. Cooldown .. ")")
	end
end

-- gets last action from database
function GetCooldown(PlayerUUID, CooldownType)
	for rows in Database:nrows("SELECT * FROM ".. CooldownTableName .. " WHERE PlayerUUID = '".. PlayerUUID .. "'") do
		for k, v in pairs(rows) do
			if CooldownType == RequestCooldown and k == "LastRequest" then
				return v
			elseif CooldownType == SuccessCooldown and k == "LastSuccess" then
				return v
			end
		end
	end
	return 0
end

function CreateTransaction(From, To)
	-- create UUID
	local ID = cUUID:GenerateVersion3(From:GetName() .. To:GetName() .. math.random(100000)):ToShortString()
	-- store to database
	Database:exec("INSERT OR REPLACE INTO " .. TransactionTableName .. " (TransactionId, Source, Destination, Timestamp) VALUES('" .. ID .. "', '".. From:GetName() .."', '" .. To:GetName() .."', " .. os.time() ..")")

	return ID
end

function CleanupTransaction()
	Database:exec("DELETE FROM " .. TransactionTableName .. " WHERE Timestamp < " .. os.time() - CleanupCooldown)
end
