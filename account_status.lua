--[[
  dbdataentry - klien status akun Roblox (v3)
  Backend: POST /api/receiver/account  (header x-api-key)

  Kolom yang dikirim, sama dengan skema database:
    username, displayName, state, gameName, userId, placeId, jobId,
    event, latencyMs, sessionStart   (+ avatarUrl, timestamp)
  `lastUpdate` TIDAK dikirim: server mengisinya sendiri dari jamnya (kebal jam klien yang miring).

  PENTING: API key di script yang berjalan di executor selalu bisa dibaca siapa pun yang
  memegang script ini. Gunakan key khusus script ini (RECEIVER_API_KEY), jangan dipakai di
  tempat lain, dan ganti bila script pernah dibagikan.
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
local CONFIG = {
	URL = "https://dbdataentry.vercel.app/api/receiver/account",
	API_KEY = "ISI_API_KEY_BARU_DI_SINI",
	INTERVAL = 20, -- detik. Server: STALLED > 30 dtk, OFFLINE > 45 dtk. Jangan lebih dari 25.
	MAX_ATTEMPTS = 4, -- percobaan per pengiriman Aktif
	OFFLINE_ATTEMPTS = 2, -- Offline dikirim saat game menutup, waktunya sempit
	BASE_DELAY = 1.5, -- jeda retry awal (detik), dikali 2 tiap gagal
	MAX_DELAY = 12,
}
-- =======================

local httpRequest = (syn and syn.request) or (http and http.request) or http_request or request
if not httpRequest then
	warn("[dbdataentry] Executor tidak mendukung HTTP Request!")
	return
end

if CONFIG.API_KEY == "ISI_API_KEY_BARU_DI_SINI" then
	warn("[dbdataentry] Isi CONFIG.API_KEY dulu.")
	return
end

-- Cegah dua instance berjalan bersamaan (auto-execute + manual): yang lama dihentikan.
local sharedEnv = (getgenv and getgenv()) or _G
if type(sharedEnv.__dbdataentry_stop) == "function" then
	pcall(sharedEnv.__dbdataentry_stop)
end

local stopped = false
local offlineSent = false
local lastLatencyMs = nil -- RTT pengiriman sukses terakhir, dilaporkan di payload berikutnya
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
		warn("[dbdataentry] API key ditolak (401). Cocokkan CONFIG.API_KEY dengan RECEIVER_API_KEY di Vercel.")
	elseif status == 400 then
		warn("[dbdataentry] Payload ditolak (400): " .. tostring(body))
	elseif status == 429 then
		warn("[dbdataentry] Terkena rate limit (429). Naikkan CONFIG.INTERVAL.")
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
		latencyMs = lastLatencyMs, -- nil di pengiriman pertama: field dilewati
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

-- Kirim satu payload dengan retry (backoff eksponensial + jitter). Mengembalikan true jika sukses.
local function send(eventType, maxAttempts)
	local body = buildPayload(eventType)
	if not body then
		warn("[dbdataentry] Gagal meng-encode payload")
		return false
	end

	local delay = CONFIG.BASE_DELAY
	for attempt = 1, maxAttempts do
		-- Jika Offline sudah dikirim, retry Aktif yang tertinggal tidak boleh menimpanya.
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
				return false -- 400/401/403/404: mengulang tidak akan membantu
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
		-- jitter kecil agar banyak akun tidak mengirim serentak
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
