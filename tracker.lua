local Players = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")
local HttpService = game:GetService("HttpService")
local LocalPlayer = Players.LocalPlayer

-- URL Webhook Vercel
local WEBHOOK_URL = "https://dbdataentry.vercel.app/api/receiver/game"
local INTERVAL = 30 -- Mengirim pembaruan status setiap 30 detik

-- Deteksi fungsi HTTP executor
local httpRequest = (syn and syn.request) or (http and http.request) or http_request or request

if not httpRequest then
    warn("Executor tidak mendukung HTTP Request!")
    return
end

-- Simpan waktu pertama kali skrip di-execute
local SESSION_START = os.date("!%Y-%m-%dT%H:%M:%SZ")

local function sendPayload(eventType)
    local gameName = "Unknown Game"
    
    local success, placeInfo = pcall(function()
        return MarketplaceService:GetProductInfo(game.PlaceId)
    end)
    
    if success and placeInfo then
        gameName = placeInfo.Name
    end

    local payloadData = {
        event = eventType, -- "Aktif" atau "Offline"
        userId = LocalPlayer.UserId,
        username = LocalPlayer.Name,
        displayName = LocalPlayer.DisplayName,
        gameName = gameName,
        placeId = game.PlaceId,
        jobId = game.JobId ~= "" and game.JobId or "Local/Private",
        avatarUrl = "https://www.roblox.com/headshot-thumbnail/image?userId=" .. LocalPlayer.UserId .. "&width=420&height=420&format=png",
        timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ"),
        sessionStart = SESSION_START -- Mengirim waktu start yang konsisten
    }

    pcall(function()
        httpRequest({
            Url = WEBHOOK_URL,
            Method = "POST",
            Headers = { ["Content-Type"] = "application/json" },
            Body = HttpService:JSONEncode(payloadData)
        })
    end)
end

-- 1. Kirim status Aktif pertama kali saat di-execute
sendPayload("Aktif")

-- 2. Kirim update status secara berkala (Heartbeat)
task.spawn(function()
    while true do
        task.wait(INTERVAL)
        sendPayload("Aktif")
    end
end)

-- 3. Kirim status Offline saat game ditutup atau leave
game:BindToClose(function()
    sendPayload("Offline")
end)
