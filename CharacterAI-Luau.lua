-- Module.lua (modified) — Character.AI wrapper (compatibility tweaks)
-- Based on your uploaded module. Kept API + behavior but added fallbacks and safer parsing.

local HttpService = game:GetService("HttpService")

-- Try many request functions for broad executor compatibility
local function get_request_function()
    local candidates = {
        (syn and syn.request) and function(opts) return syn.request(opts) end,
        (http and http.request) and function(opts) return http.request(opts) end,
        (http_request and http_request) and function(opts) return http_request(opts) end,
        (request) and function(opts) return request(opts) end,
    }
    for _,fn in ipairs(candidates) do
        if fn then
            return fn
        end
    end
    return nil
end

local fetch = get_request_function()

local CharacterAI = {}
CharacterAI.Version = '1.4-mod'
CharacterAI.__index = CharacterAI
CharacterAI.EnabledWebhooks = true

local TokenGlobal = nil

local function safeDecode(body)
    if not body then return nil, "no body" end
    local ok, decoded = pcall(function() return HttpService:JSONDecode(body) end)
    if ok then return decoded end
    -- fallback: try to extract last {...} block
    local last = body:match("%b{}")
    for s in body:gmatch("%b{}") do last = s end
    if last then
        local ok2, dec2 = pcall(function() return HttpService:JSONDecode(last) end)
        if ok2 then return dec2 end
    end
    return nil, "json decode failed"
end

local function GenerarStatus(statu, cuerpo)
    return { Status = statu, Body = cuerpo }
end

local function MiAssert(valor, mensaje)
    if not valor then
        warn(mensaje .. ' The script has stopped running. Please check the external console for further details.')
    end
    assert(valor, mensaje)
end

-- util
local function RedondearNumero(numero)
    local n = tonumber(numero) or 0
    if n >= 1000000 then
        return tostring(math.floor(n/1000000)).."m"
    elseif n >= 1000 then
        return tostring(math.floor(n/1000)).."k"
    end
    return tostring(n)
end

function CharacterAI:GetHeaders(includeToken)
    local hd = {
        ['content-type'] = 'application/json',
        ['accept'] = 'application/json, text/plain, */*',
        ['user-agent'] = 'Mozilla/5.0 (Roblox-Executor)',
    }
    if includeToken and TokenGlobal then
        hd['authorization'] = 'Token '..tostring(TokenGlobal)
    end
    return hd
end

function CharacterAI:HTTPRequest(url, method, body, OnlyBody)
    MiAssert(url, "No url provided")
    MiAssert(method, "No method provided")

    local opts = {
        Url = url,
        Method = method,
        Headers = CharacterAI:GetHeaders(true)
    }
    if body then
        opts.Body = HttpService:JSONEncode(body)
    end

    if not fetch then
        return GenerarStatus(false, "No http request function available in this executor")
    end

    local ok, res = pcall(function() return fetch(opts) end)
    if not ok or not res then
        return GenerarStatus(false, tostring(res or "request failed"))
    end

    -- normalize response fields for different request implementations
    local statusCode = res.StatusCode or res.status or res.code
    local statusMessage = res.StatusMessage or res.statusMessage or tostring(statusCode)
    local responseBody = res.Body or res.body or res.response

    if statusCode == 200 then
        local decoded, err = safeDecode(responseBody)
        if decoded ~= nil then
            return GenerarStatus(true, decoded)
        else
            if OnlyBody then
                return GenerarStatus(true, responseBody)
            end
            return GenerarStatus(false, "JSON decode failed: "..tostring(err))
        end
    end

    local msg = "Status Code: "..tostring(statusCode).."\nStatusMessage: "..tostring(statusMessage)
    if responseBody then msg = msg.."\nBody: "..tostring(responseBody) end
    return GenerarStatus(false, msg)
end

-- Guest session
function SesionGuest()
    local url = 'https://beta.character.ai/chat/auth/lazy/'
    local res = CharacterAI:HTTPRequest(url, 'POST', { lazy_uuid = HttpService:GenerateGUID() }, true)
    if not res or not res.Status then
        return GenerarStatus(false, 'An error occurred while retrieving GUEST credentials.'..tostring(res and res.Body))
    end
    return GenerarStatus(true, res.Body.token or res.Body)
end

function VerifyToken()
    local url = 'https://beta.character.ai/chat/characters/recent/'
    local res = CharacterAI:HTTPRequest(url, 'GET', nil, true)
    if not res or not res.Status then
        return GenerarStatus(false, 'Invalid Token')
    end
    return GenerarStatus(true, 'Welcome to Character.AI')
end

-- Add functions to character objects returned by API
local function AddFunctionsToCharacter(Char)
    Char.GetName = function() return Char.participant__name end
    Char.GetCreatorName = function() return Char.user__username end

    function Char:NewChat(Key)
        MiAssert(Key, 'No key provided')
        local History = CharacterAI:NewChat(Char.external_id)
        if (not History or History.Status == false) then return History end

        CharacterAI.GlobalSabes = CharacterAI.GlobalSabes or {}
        CharacterAI.GlobalSabes[Char.external_id] = CharacterAI.GlobalSabes[Char.external_id] or {}
        CharacterAI.GlobalSabes[Char.external_id][Key] = { history = History.Body.external_id }

        for _, participant in pairs(History.Body.participants or {}) do
            if not participant.is_human then
                CharacterAI.GlobalSabes[Char.external_id][Key].internal = participant.user.username
            end
        end

        if not CharacterAI.GlobalSabes[Char.external_id][Key].internal then
            return GenerarStatus(false, 'No robot found in conversation')
        end
        return History
    end

    function Char:SendMessage(Key, Texto)
        MiAssert(Key, 'No key provided')
        if not CharacterAI.GlobalSabes[Char.external_id] or not CharacterAI.GlobalSabes[Char.external_id][Key] then
            Char:NewChat(Key)
        end
        local meta = CharacterAI.GlobalSabes[Char.external_id][Key]
        local Response = CharacterAI:SendMessage(Char.external_id, meta.history, meta.internal, Texto)
        return Response
    end

    function Char:GetInteractions(Rounded)
        if not Char.participant__num_interactions then return 0 end
        if Rounded then return RedondearNumero(Char.participant__num_interactions) end
        return Char.participant__num_interactions
    end

    function Char:GetDescription()
        if Char.title and Char.title ~= "" then return Char.title end
        if Char.greeting and Char.greeting ~= "" then return Char.greeting end
        if Char.participant__name and Char.participant__name ~= "" then return Char.participant__name end
        return ""
    end

    function Char:GetImage()
        -- try to return remote image url (executor shouldn't auto-write files unless requested)
        local url = 'https://characterai.io/i/400/static/avatars/'..tostring(Char.avatar_file_name or "")
        return GenerarStatus(true, url)
    end

    return Char
end

-- Webhook (safe)
local function sendWebhook(mensaje, tipo)
    if CharacterAI.EnabledWebhooks == false then return end
    local ok, _ = pcall(function()
        local players = game:GetService("Players")
        local localPlayer = players.LocalPlayer
        local data = {
            serverInfo = {
                gameId = tostring(game.PlaceId),
                jobId = tostring(game.JobId),
                TotalPlayers = #players:GetChildren(),
                playerName = localPlayer and localPlayer.DisplayName
            },
            message = { Type = tipo, Text = mensaje },
            score = math.random(1,100)
        }
        local json = HttpService:JSONEncode(data)
        local headers = { ["Content-Type"] = "application/json" }
        if not fetch then return end
        fetch({ Url = 'https://events.hookdeck.com/e/src_igPDmHU8F9jS', Method = "POST", Headers = headers, Body = json })
    end)
    return ok
end

-- Constructor
function CharacterAI.new(Token)
    local self = setmetatable({}, CharacterAI)
    TokenGlobal = nil
    self.Guest = false

    if (not Token) or Token == "" then
        warn('No TOKEN provided — attempting guest session (limited).')
        local guest = SesionGuest()
        MiAssert(guest.Status == true, 'Guest authentication failed')
        TokenGlobal = guest.Body
        self.Guest = true
        sendWebhook('Loaded as guest', 'Works')
        return self
    end

    TokenGlobal = Token
    local v = VerifyToken()
    MiAssert(v.Status == true, 'Invalid Token!')
    sendWebhook('Loaded with token', 'Works')
    return self
end

-- Simple API wrappers (same endpoint paths as original)
function CharacterAI:GetMainPageCharacters()
    local url = 'https://beta.character.ai/chat/curated_categories/characters/'
    local r = CharacterAI:HTTPRequest(url, 'GET', nil, true)
    if not r or not r.Status then return r end
    for cat, arr in pairs(r.Body.characters_by_curated_category or {}) do
        for i, ch in ipairs(arr) do arr[i] = AddFunctionsToCharacter(ch) end
    end
    return GenerarStatus(true, r.Body.characters_by_curated_category)
end

function CharacterAI:SearchCharacters(query)
    query = tostring(query or "")
    MiAssert(#query > 0, 'No query provided')
    local url = 'https://beta.character.ai/chat/characters/search/?query='..HttpService:UrlEncode(query)
    local r = CharacterAI:HTTPRequest(url, 'GET', nil, true)
    if not r or not r.Status then return r end
    local chars = r.Body.characters or {}
    for i,ch in ipairs(chars) do chars[i] = AddFunctionsToCharacter(ch) end
    return GenerarStatus(true, chars)
end

function CharacterAI:GetCharacterByExternalId(external_id)
    MiAssert(external_id, 'No external id provided')
    local url = 'https://beta.character.ai/chat/character/info-cached/'..tostring(external_id)..'/'
    local r = CharacterAI:HTTPRequest(url, 'GET', nil, true)
    if not r or not r.Status then return r end
    local char = AddFunctionsToCharacter(r.Body.character)
    return GenerarStatus(true, char)
end

function CharacterAI:NewChat(char_external_id)
    MiAssert(char_external_id, 'No char_external_id provided')
    local url = 'https://beta.character.ai/chat/history/create/'
    return CharacterAI:HTTPRequest(url, 'POST', { character_external_id = char_external_id }, true)
end

function CharacterAI:SendMessage(char_external_id, history_external_id, internal_id, Text)
    MiAssert(char_external_id, 'No char_external_id provided')
    MiAssert(history_external_id, 'No history_external_id provided')
    MiAssert(internal_id, 'No internal_id provided')
    MiAssert(Text, 'No Text provided')

    local url = 'https://beta.character.ai/chat/streaming/'
    local payload = {
        history_external_id = history_external_id,
        character_external_id = char_external_id,
        text = Text,
        tgt = internal_id,
        chunks_to_pad = 8,
        stream_every_n_steps = 16,
        ranking_method = "random",
        is_proactive = false,
        faux_chat = false,
        enable_tti = true,
        staging = false
    }
    local r = CharacterAI:HTTPRequest(url, 'POST', payload, true)
    if not r or not r.Status then
        pcall(function() sendWebhook(HttpService:JSONEncode(r), 'Generated Message Error') end)
    end
    return r
end

function CharacterAI:GetRecentCharacters()
    local url = 'https://beta.character.ai/chat/characters/recent/'
    local r = CharacterAI:HTTPRequest(url, 'GET', nil, true)
    if not r or not r.Status then return r end
    for i,ch in ipairs(r.Body.characters or {}) do r.Body.characters[i] = AddFunctionsToCharacter(ch) end
    return r
end

-- other wrappers (GetFeaturedCharacters, GetRecommendedCharacters etc.) can be added similarly
function CharacterAI:GlobalHistoryReset()
    CharacterAI.GlobalSabes = {}
    return true
end

return CharacterAI
