--[[
  dbdataentry - klien status akun Roblox (v3)
  Backend: POST /api/receiver/account  (header x-api-key)
]]

local Players = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")
local HttpService = game:GetService("HttpService")

if not game:IsLoaded() then
	game.Loaded:Wait()
end

local LocalPlayer = Players.LocalPlayer
while not LocalPlayer do
	task.wait()
	LocalPlayer = Players.LocalPlayer
end

-- ===== KONFIGURASI =====
local sharedEnv = (getgenv and getgenv()) or _G
local USER_CONFIG = type(sharedEnv.DBDATAENTRY) == "table" and sharedEnv.DBDATAENTRY or {}

local CONFIG = {
	URL = USER_CONFIG.URL or "https://dbdataentry.vercel.app/api/receiver/account",
	API_KEY = USER_CONFIG.API_KEY,
	INTERVAL = USER_CONFIG.INTERVAL or 20,
	MAX_ATTEMPTS = 4,
	OFFLINE_ATTEMPTS = 2,
	BASE_DELAY = 1.5,
	MAX_DELAY = 12,
}
-- =======================

local httpRequest = (syn and syn.request) or (http and http.request) or http_request or request
if not httpRequest then
	warn("[dbdataentry] Executor tidak mendukung HTTP Request!")
	return
end

if type(CONFIG.API_KEY) ~= "string" or #CONFIG.API_KEY < 16 then
	warn('[dbdataentry] API key belum diset. Jalankan: getgenv().DBDATAENTRY = { API_KEY = "..." } sebelum loadstring.')
	return
end

if type(sharedEnv.__dbdataentry_stop) == "function" then
	pcall(sharedEnv.__dbdataentry_stop)
end

local stopped = false
local offlineSent = false
local lastLatencyMs = nil
local warnedStatus = {}
local cachedGameName = nil

local SESSION_START = os.date("!%Y-%m-%dT%H:%M:%SZ")

sharedEnv.__dbdataentry_stop = function()
	stopped = true
end

local function getGameName()
	if cachedGameName then
		return cachedGameName
	end
	local ok, info = pcall(function()
		return MarketplaceService:GetProductInfo(game.PlaceId)
	end)
	if ok and info and info.Name then
		cachedGameName = info.Name
		return cachedGameName
	end
	return "Unknown Game"
end

local function warnOnce(status, body)
	if warnedStatus[status] then
		return
	end
	warnedStatus[status] = true
	if status == 401 then
		warn("[dbdataentry] API key ditolak (401). Cocokkan API_KEY dengan RECEIVER_API_KEY di Vercel.")
	elseif status == 400 then
		warn("[dbdataentry] Payload ditolak (400): " .. tostring(body))
	elseif status == 429 then
		warn("[dbdataentry] Terkena rate limit (429). Naikkan INTERVAL.")
	elseif status == 503 then
		warn("[dbdataentry] Server belum dikonfigurasi (503). RECEIVER_API_KEY belum diset di Vercel.")
	else
		warn("[dbdataentry] Server membalas status " .. tostring(status))
	end
end

local function shouldRetry(status)
	return status == nil or status == 408 or status == 429 or status >= 500
end

local function buildPayload(eventType)
	local payload = {
		username = LocalPlayer.Name,
		displayName = LocalPlayer.DisplayName,
		state = (eventType == "Offline") and "OFFLINE" or "ONLINE",
		gameName = getGameName(),
		userId = LocalPlayer.UserId,
		placeId = game.PlaceId,
		jobId = game.JobId ~= "" and game.JobId or "Local/Private",
		event = eventType,
		latencyMs = lastLatencyMs,
		sessionStart = SESSION_START,
		timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ"),
		avatarUrl = "https://www.roblox.com/headshot-thumbnail/image?userId="
			.. LocalPlayer.UserId
			.. "&width=420&height=420&format=png",
	}
	local ok, encoded = pcall(function()
		return HttpService:JSONEncode(payload)
	end)
	return ok and encoded or nil
end

local function send(eventType, maxAttempts)
	local body = buildPayload(eventType)
	if not body then
		warn("[dbdataentry] Gagal meng-encode payload")
		return false
	end

	local delay = CONFIG.BASE_DELAY
	for attempt = 1, maxAttempts do
		if eventType ~= "Offline" and (offlineSent or stopped) then
			return false
		end

		local startedAt = os.clock()
		local ok, res = pcall(httpRequest, {
			Url = CONFIG.URL,
			Method = "POST",
			Headers = {
				["Content-Type"] = "application/json",
				["x-api-key"] = CONFIG.API_KEY,
			},
			Body = body,
		})
		local rtt = math.floor((os.clock() - startedAt) * 1000 + 0.5)

		local status = (ok and type(res) == "table" and type(res.StatusCode) == "number") and res.StatusCode or nil

		if status and status >= 200 and status < 300 then
			lastLatencyMs = rtt
			return true
		end

		if status then
			warnOnce(status, type(res) == "table" and res.Body or nil)
			if not shouldRetry(status) then
				return false
			end
		end

		if attempt < maxAttempts then
			local wait = delay
			local headers = type(res) == "table" and res.Headers or nil
			local retryAfter = headers and tonumber(headers["Retry-After"] or headers["retry-after"])
			if retryAfter then
				wait = math.min(retryAfter, CONFIG.MAX_DELAY)
			end
			task.wait(wait + math.random() * 0.5)
			delay = math.min(delay * 2, CONFIG.MAX_DELAY)
		end
	end
	return false
end

local function sendOffline()
	if offlineSent then
		return
	end
	offlineSent = true
	send("Offline", CONFIG.OFFLINE_ATTEMPTS)
end

send("Aktif", CONFIG.MAX_ATTEMPTS)

task.spawn(function()
	while not offlineSent and not stopped do
		task.wait(CONFIG.INTERVAL + math.random() * 2)
		if not offlineSent and not stopped then
			send("Aktif", CONFIG.MAX_ATTEMPTS)
		end
	end
end)

pcall(function()
	game:BindToClose(sendOffline)
end)

Players.PlayerRemoving:Connect(function(player)
	if player == LocalPlayer then
		sendOffline()
	end
end)
