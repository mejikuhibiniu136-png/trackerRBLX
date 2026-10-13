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

local WEBHOOK_URL = "https://dbdataentry.vercel.app/api/receiver/game"
-- Harus sama persis dengan RECEIVER_API_KEY di Vercel
local API_KEY = "142aef54540c4e7cd14ab0142a7783b929b666f1f06c1000"
local INTERVAL = 30

local httpRequest = (syn and syn.request) or (http and http.request) or http_request or request

if not httpRequest then
    warn("Executor tidak mendukung HTTP Request!")
    return
end

local SESSION_START = os.date("!%Y-%m-%dT%H:%M:%SZ")
local cachedGameName = nil
local warnedStatus = {}
local offlineSent = false

-- Nama game cukup diambil sekali, lalu disimpan
local function getGameName()
    if cachedGameName then
        return cachedGameName
    end

    local success, placeInfo = pcall(function()
        return MarketplaceService:GetProductInfo(game.PlaceId)
    end)

    if success and placeInfo and placeInfo.Name then
        cachedGameName = placeInfo.Name
        return cachedGameName
    end

    return "Unknown Game"
end

local function sendPayload(eventType)
    local payloadData = {
        event = eventType,
        userId = LocalPlayer.UserId,
        username = LocalPlayer.Name,
        displayName = LocalPlayer.DisplayName,
        gameName = getGameName(),
        placeId = game.PlaceId,
        jobId = game.JobId ~= "" and game.JobId or "Local/Private",
        avatarUrl = "https://www.roblox.com/headshot-thumbnail/image?userId=" .. LocalPlayer.UserId .. "&width=420&height=420&format=png",
        timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ"),
        sessionStart = SESSION_START
    }

    local ok, response = pcall(function()
        return httpRequest({
            Url = WEBHOOK_URL,
            Method = "POST",
            Headers = {
                ["Content-Type"] = "application/json",
                ["x-api-key"] = API_KEY
            },
            Body = HttpService:JSONEncode(payloadData)
        })
    end)

    -- Beri tahu sekali saja jika server menolak, supaya masalahnya mudah ketahuan
    if ok and type(response) == "table" then
        local status = response.StatusCode
        if type(status) == "number" and status >= 400 and not warnedStatus[status] then
            warnedStatus[status] = true
            if status == 401 then
                warn("[dbdataentry] API key ditolak (401). Cek API_KEY di script dan RECEIVER_API_KEY di Vercel.")
            elseif status == 503 then
                warn("[dbdataentry] Server menolak (503). RECEIVER_API_KEY belum diset di Vercel, atau receiver dimatikan.")
            else
                warn("[dbdataentry] Server membalas status " .. tostring(status))
            end
        end
    end
end

local function sendOffline()
    if offlineSent then
        return
    end
    offlineSent = true
    sendPayload("Offline")
end

sendPayload("Aktif")

task.spawn(function()
    while not offlineSent do
        task.wait(INTERVAL)
        if not offlineSent then
            sendPayload("Aktif")
        end
    end
end)

-- BindToClose hanya tersedia di server, jadi dibungkus pcall agar tidak menimbulkan error di client.
-- PlayerRemoving dipakai sebagai cadangan saat pemain keluar dari game.
pcall(function()
    game:BindToClose(sendOffline)
end)

Players.PlayerRemoving:Connect(function(player)
    if player == LocalPlayer then
        sendOffline()
    end
end)
