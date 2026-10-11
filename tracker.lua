local Players = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")
local HttpService = game:GetService("HttpService")
local LocalPlayer = Players.LocalPlayer

local WEBHOOK_URL = "https://dbdataentry.vercel.app/api/receiver/game"
local INTERVAL = 30

local httpRequest = (syn and syn.request) or (http and http.request) or http_request or request

if not httpRequest then
    warn("Executor tidak mendukung HTTP Request!")
    return
end

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
        event = eventType,
        userId = LocalPlayer.UserId,
        username = LocalPlayer.Name,
        displayName = LocalPlayer.DisplayName,
        gameName = gameName,
        placeId = game.PlaceId,
        jobId = game.JobId ~= "" and game.JobId or "Local/Private",
        avatarUrl = "https://www.roblox.com/headshot-thumbnail/image?userId=" .. LocalPlayer.UserId .. "&width=420&height=420&format=png",
        timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ"),
        sessionStart = SESSION_START
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

sendPayload("Aktif")

task.spawn(function()
    while true do
        task.wait(INTERVAL)
        sendPayload("Aktif")
    end
end)

game:BindToClose(function()
    sendPayload("Offline")
end)
