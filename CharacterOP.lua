-- glory_rework.lua | 2025
-- Compatível com TextChatService e Chat clássico. Pensado para Solara/Synapse/etc.
-- Baseado em conceito do glory.lua original (UI + busca + auto-reply com Character.AI).

-- ===================[ CONFIG ]===================
local CONFIG = {
    token            = (getgenv and getgenv().GloryToken) or (getfenv and getfenv().YourToken) or nil,
    prefix           = "!",            -- prefixo pra forçar resposta (ex: !pergunta)
    proximityRadius  = 8,              -- metros para auto-responder por proximidade
    enableProximity  = true,           -- auto-responder por proximidade
    waitBetweenParts = 3,              -- segundos entre partes da resposta
    maxChunkChars    = 190,            -- tamanho máximo de cada mensagem enviada
    uiHotkey         = Enum.KeyCode.RightShift,
    logoUrl          = "https://beta.character.ai/static/media/logo-dark.77b3a5cc8e42a91f021f.png",
}
-- =================================================

repeat task.wait() until game:IsLoaded()

-- ===== serviços
local Players             = game:GetService("Players")
local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local TextChatService     = game:GetService("TextChatService")
local TweenService        = game:GetService("TweenService")
local UserInputService    = game:GetService("UserInputService")
local Lighting            = game:GetService("Lighting")

local LP = Players.LocalPlayer

-- ===== helpers executor
local customAsset = (getcustomasset or getsynasset)
local canFS       = (writefile and isfile and delfile)

local function safeSetIcon(url, name)
    if not customAsset or not canFS then return url end
    name = (name or "logo"):gsub("%p","")
    local fname = name..".png"
    if not isfile(fname) then
        local ok, body = pcall(function() return game:HttpGet(url) end)
        if ok and body then writefile(fname, body) end
    end
    local src = isfile(fname) and customAsset(fname) or url
    task.delay(5, function() pcall(function() if isfile(fname) then delfile(fname) end end) end)
    return src
end

-- ===== carregar módulo CharacterAI com fallback
local CharacterAI
do
    local ok, mod = pcall(function()
        return loadstring(game:HttpGet(
            "https://raw.githubusercontent.com/1lRzo/ReworkCharacter/refs/heads/main/CharacterAI-Luau.lua",
            true))()
    end)
    if ok and mod then
        CharacterAI = mod
    else
        -- stub mínimo pra não quebrar tudo se o módulo estiver fora do ar
        CharacterAI = {
            new = function()
                return {
                    SearchCharacters = function() return {Status=false, Body="offline"} end,
                    GetMainPageCharacters = function() return {Status=false} end,
                    GetRecentCharacters = function() return {Status=false} end,
                    GetFeaturedCharacters = function() return {Status=false} end,
                    GetRecommendedCharacters = function() return {Status=false} end,
                    GetUserCharacters = function() return {Status=false} end,
                    GetCharacterByExternalId = function() return {Status=false} end,
                    GlobalHistoryReset = function() end,
                }
            end,
            IsOnline = function() return false end,
            SplitText = function(txt)
                -- fallback splitter
                local t, cur = {}, {}
                for word in tostring(txt):gmatch("%S+") do
                    local tentative = table.concat(cur, " ")
                    if #tentative + #word + 1 > CONFIG.maxChunkChars then
                        table.insert(t, {Texto=table.clone(cur)})
                        table.clear(cur)
                    end
                    table.insert(cur, word)
                end
                if #cur > 0 then table.insert(t, {Texto=table.clone(cur)}) end
                return t
            end
        }
    end
end

local Session = CharacterAI.new(CONFIG.token)

-- ============ UI BÁSICA ============
local screen = Instance.new("ScreenGui")
screen.Name = "GloryReworkUI"
screen.ResetOnSpawn = false
screen.IgnoreGuiInset = true

-- tenta usar gethui() se existir, senão CoreGui/PlayerGui
local okMount = false
pcall(function() local hui = gethui and gethui(); if hui then screen.Parent = hui okMount = true end end)
if not okMount then
    pcall(function() screen.Parent = game:GetService("CoreGui"); okMount = true end)
end
if not okMount then
    screen.Parent = LP:WaitForChild("PlayerGui")
end

local frame = Instance.new("Frame")
frame.Size = UDim2.fromOffset(640, 420)
frame.Position = UDim2.fromScale(0.5, 0.5)
frame.AnchorPoint = Vector2.new(0.5, 0.5)
frame.BackgroundColor3 = Color3.fromRGB(36,37,37)
frame.Parent = screen

local uiCorner = Instance.new("UICorner", frame); uiCorner.CornerRadius = UDim.new(0,12)

-- topo
local top = Instance.new("Frame", frame)
top.Size = UDim2.new(1,0,0,56)
top.BackgroundTransparency = 1

local logo = Instance.new("ImageLabel", top)
logo.BackgroundTransparency = 1
logo.Size = UDim2.fromOffset(160, 40)
logo.Position = UDim2.fromOffset(12,8)
logo.Image = safeSetIcon(CONFIG.logoUrl, "glory_logo")

local title = Instance.new("TextLabel", top)
title.BackgroundTransparency = 1
title.Position = UDim2.fromOffset(180, 10)
title.Size = UDim2.new(1,-260,0,36)
title.Font = Enum.Font.GothamBold
title.TextScaled = true
title.TextXAlignment = Enum.TextXAlignment.Left
title.TextColor3 = Color3.fromRGB(230,224,217)
title.Text = "Glory Rework — Character.AI bridge"

local closeBtn = Instance.new("TextButton", top)
closeBtn.Size = UDim2.fromOffset(28,28)
closeBtn.Position = UDim2.new(1,-36,0,14)
closeBtn.Text = "×"
closeBtn.Font = Enum.Font.GothamBold
closeBtn.TextScaled = true
closeBtn.TextColor3 = Color3.fromRGB(230,224,217)
closeBtn.BackgroundColor3 = Color3.fromRGB(48,49,49)
local cbCorner = Instance.new("UICorner", closeBtn); cbCorner.CornerRadius = UDim.new(0,8)

-- conteúdo
local body = Instance.new("Frame", frame)
body.BackgroundTransparency = 1
body.Position = UDim2.fromOffset(12, 64)
body.Size = UDim2.new(1,-24,1,-76)

local status = Instance.new("TextLabel", body)
status.BackgroundTransparency = 1
status.Size = UDim2.new(1,0,0,24)
status.Font = Enum.Font.Gotham
status.TextXAlignment = Enum.TextXAlignment.Left
status.TextColor3 = Color3.fromRGB(195,190,184)
status.Text = "Status: inicializando…"

local row1 = Instance.new("Frame", body)
row1.BackgroundTransparency = 1
row1.Position = UDim2.fromOffset(0,32)
row1.Size = UDim2.new(1,0,0,40)

local input = Instance.new("TextBox", row1)
input.Size = UDim2.new(1,-130,1,0)
input.PlaceholderText = "Buscar personagens (Enter) ou colar external_id"
input.Text = ""
input.TextColor3 = Color3.new(1,1,1)
input.PlaceholderColor3 = Color3.fromRGB(195,190,184)
input.BackgroundColor3 = Color3.fromRGB(50,50,50)
local ic = Instance.new("UICorner", input); ic.CornerRadius = UDim.new(0,8)

local searchBtn = Instance.new("TextButton", row1)
searchBtn.Size = UDim2.fromOffset(110,40)
searchBtn.Position = UDim2.new(1,-110,0,0)
searchBtn.Text = "Buscar"
searchBtn.Font = Enum.Font.GothamBold
searchBtn.TextColor3 = Color3.new(1,1,1)
searchBtn.BackgroundColor3 = Color3.fromRGB(0,122,255)
local sbc = Instance.new("UICorner", searchBtn); sbc.CornerRadius = UDim.new(0,8)

local options = Instance.new("Frame", body)
options.BackgroundTransparency = 1
options.Position = UDim2.fromOffset(0, 80)
options.Size = UDim2.new(1,0,0,30)

local proxToggle = Instance.new("TextButton", options)
proxToggle.Size = UDim2.fromOffset(220,30)
proxToggle.Text = "Proximidade: " .. (CONFIG.enableProximity and "ON" or "OFF")
proxToggle.Font = Enum.Font.GothamBold
proxToggle.TextColor3 = Color3.new(1,1,1)
proxToggle.BackgroundColor3 = CONFIG.enableProximity and Color3.fromRGB(0,170,80) or Color3.fromRGB(50,50,50)
local ptc = Instance.new("UICorner", proxToggle); ptc.CornerRadius = UDim.new(0,8)

local prefixLabel = Instance.new("TextLabel", options)
prefixLabel.BackgroundTransparency = 1
prefixLabel.Position = UDim2.fromOffset(230,0)
prefixLabel.Size = UDim2.fromOffset(350,30)
prefixLabel.Font = Enum.Font.Gotham
prefixLabel.TextXAlignment = Enum.TextXAlignment.Left
prefixLabel.TextColor3 = Color3.fromRGB(195,190,184)
prefixLabel.Text = ("Prefixo manual: %s  |  Raio: %dm"):format(CONFIG.prefix, CONFIG.proximityRadius)

local results = Instance.new("ScrollingFrame", body)
results.Position = UDim2.fromOffset(0,120)
results.Size = UDim2.new(1,0,1,-140)
results.CanvasSize = UDim2.new(0,0,0,0)
results.ScrollBarThickness = 4
results.BackgroundTransparency = 1

local layout = Instance.new("UIListLayout", results)
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.Padding = UDim.new(0,6)

-- mostrar/ocultar UI
local uiVisible = true
local function setVisible(b)
    uiVisible = b
    frame.Visible = b
end
setVisible(true)

UserInputService.InputBegan:Connect(function(i,gp)
    if gp then return end
    if i.KeyCode == CONFIG.uiHotkey then
        setVisible(not uiVisible)
    end
end)

closeBtn.MouseButton1Click:Connect(function() setVisible(false) end)

-- ===== utilidades
local function chunkText(s, maxChars)
    s = tostring(s or "")
    local parts, cur = {}, {}
    for w in s:gmatch("%S+") do
        local joined = table.concat(cur, " ")
        if #joined + #w + 1 > (maxChars or CONFIG.maxChunkChars) then
            table.insert(parts, table.concat(cur, " "))
            cur = {}
        end
        table.insert(cur, w)
    end
    if #cur > 0 then table.insert(parts, table.concat(cur, " ")) end
    return parts
end

local function rbxSay(text)
    -- tenta chat novo primeiro
    local okNew = pcall(function()
        if TextChatService.ChatVersion == Enum.ChatVersion.TextChatService then
            local chan = TextChatService:FindFirstChild("TextChannels")
                and TextChatService.TextChannels:FindFirstChild("RBXGeneral")
            if chan then chan:SendAsync(text) return true end
        end
        error("no-ts")
    end)
    if okNew then return end
    -- fallback chat clássico
    pcall(function()
        ReplicatedStorage.DefaultChatSystemChatEvents.SayMessageRequest:FireServer(text, "All")
    end)
end

-- ===== estado/globals
local SelectedCharacter = nil
local FocusedCharacter  = nil
local WaitingAnswer     = false

-- ===== UI: célula de resultado
local function makeResult(name, desc, creator, interactions, image)
    local item = Instance.new("Frame")
    item.Size = UDim2.new(1,0,0,80)
    item.BackgroundTransparency = 1

    local icon = Instance.new("ImageLabel", item)
    icon.BackgroundTransparency = 1
    icon.Size = UDim2.fromOffset(60,60)
    icon.Position = UDim2.fromOffset(0,10)
    icon.Image = image or ""

    local nameL = Instance.new("TextLabel", item)
    nameL.BackgroundTransparency = 1
    nameL.Position = UDim2.fromOffset(70,6)
    nameL.Size = UDim2.new(1,-80,0,22)
    nameL.Font = Enum.Font.GothamBold
    nameL.TextScaled = true
    nameL.TextXAlignment = Enum.TextXAlignment.Left
    nameL.TextColor3 = Color3.fromRGB(230,224,217)
    nameL.Text = name or "Character"

    local descL = Instance.new("TextLabel", item)
    descL.BackgroundTransparency = 1
    descL.Position = UDim2.fromOffset(70,28)
    descL.Size = UDim2.new(1,-80,0,22)
    descL.Font = Enum.Font.Gotham
    descL.TextXAlignment = Enum.TextXAlignment.Left
    descL.TextColor3 = Color3.fromRGB(200,196,190)
    descL.Text = (desc and #desc>0 and desc) or ("por @"..(creator or "unknown").."  -  "..(interactions or ""))

    local pick = Instance.new("TextButton", item)
    pick.Size = UDim2.new(0,110,0,28)
    pick.Position = UDim2.new(1,-110,0,26)
    pick.Text = "Selecionar"
    pick.Font = Enum.Font.GothamBold
    pick.TextColor3 = Color3.new(1,1,1)
    pick.BackgroundColor3 = Color3.fromRGB(0,170,80)
    local pc = Instance.new("UICorner", pick); pc.CornerRadius = UDim.new(0,8)

    return item, pick, icon
end

-- ===== busca
local function clearResults()
    for _,c in ipairs(results:GetChildren()) do
        if c:IsA("Frame") then c:Destroy() end
    end
    results.CanvasSize = UDim2.new(0,0,0,0)
end

local function addCanvasH(h) results.CanvasSize = UDim2.new(0,0,0,results.CanvasSize.Y.Offset + h) end

local function setStatus(t) status.Text = "Status: "..t end

local function pickCharacter(characterObj)
    SelectedCharacter = characterObj
    setStatus("personagem selecionado: "..(characterObj and characterObj:GetName() or "nil"))
end

local function doSearch(query)
    clearResults()
    setStatus("buscando \""..query.."\"…")
    local res
    if #query > 25 then
        -- parece external_id
        res = Session:GetCharacterByExternalId(query)
        if res.Status then
            res = {Status=true, Body={res.Body}}
        end
    else
        res = Session:SearchCharacters(query)
    end

    if not res or not res.Status then
        setStatus("nenhum resultado ou API offline")
        return
    end

    for _,ch in ipairs(res.Body) do
        local img = ""
        local got = ch:GetImage()
        if got.Status then img = got.Body end
        local cell, pickBtn = makeResult(
            ch:GetName(),
            ch:GetDescription(),
            ch:GetCreatorName(),
            ch:GetInteractions(true),
            img
        )
        cell.Parent = results
        addCanvasH(86)
        pickBtn.MouseButton1Click:Connect(function() pickCharacter(ch) end)
    end
    setStatus(("encontrados: %d"):format(#res.Body))
end

searchBtn.MouseButton1Click:Connect(function()
    local q = input.Text
    if q and #q>0 then doSearch(q) end
end)
input.FocusLost:Connect(function(enter)
    if enter then
        local q = input.Text
        if q and #q>0 then doSearch(q) end
    end
end)

proxToggle.MouseButton1Click:Connect(function()
    CONFIG.enableProximity = not CONFIG.enableProximity
    proxToggle.Text = "Proximidade: "..(CONFIG.enableProximity and "ON" or "OFF")
    proxToggle.BackgroundColor3 = CONFIG.enableProximity and Color3.fromRGB(0,170,80) or Color3.fromRGB(50,50,50)
end)

-- ===== clique para focar players (highlight) similar ao original
local function attachClickToCharacter(char)
    if not char:FindFirstChild("HumanoidRootPart") then return end
    local root = char.HumanoidRootPart
    if root:FindFirstChild("GR_Click") then return end
    local cd = Instance.new("ClickDetector", root)
    cd.Name = "GR_Click"
    cd.MaxActivationDistance = 32
    cd.MouseClick:Connect(function()
        if FocusedCharacter == char then
            FocusedCharacter = nil
            if char:FindFirstChild("Head") and char.Head:FindFirstChild("GR_High") then
                char.Head.GR_High:Destroy()
            end
            return
        end
        if FocusedCharacter and FocusedCharacter:FindFirstChild("Head") and FocusedCharacter.Head:FindFirstChild("GR_High") then
            FocusedCharacter.Head.GR_High:Destroy()
        end
        FocusedCharacter = char
        if char:FindFirstChild("Head") then
            local h = Instance.new("Highlight", char.Head)
            h.Name = "GR_High"
            h.FillColor = Color3.fromRGB(255,255,127)
            h.FillTransparency = 0.5
            h.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
        end
    end)
end

for _,plr in ipairs(Players:GetPlayers()) do
    if plr.Character then attachClickToCharacter(plr.Character) end
    plr.CharacterAdded:Connect(function(c) task.wait(1) attachClickToCharacter(c) end)
end
Players.PlayerAdded:Connect(function(plr)
    plr.CharacterAdded:Connect(function(c) task.wait(1) attachClickToCharacter(c) end)
end)

-- ===== receber mensagens do chat (novo e clássico)
local function handleMessage(fromPlayer, text)
    if not fromPlayer or not text or #text == 0 then return end
    if not SelectedCharacter then return end
    if WaitingAnswer then return end

    local isFromMe = (fromPlayer == LP)
    local nearEnough = false
    if fromPlayer.Character and LP.Character and fromPlayer.Character:FindFirstChild("HumanoidRootPart") and LP.Character:FindFirstChild("HumanoidRootPart") then
        local mag = (fromPlayer.Character.HumanoidRootPart.Position - LP.Character.HumanoidRootPart.Position).Magnitude
        nearEnough = (mag <= CONFIG.proximityRadius)
    end

    -- regras de disparo:
    -- 1) se eu falar com prefixo
    if isFromMe and text:sub(1, #CONFIG.prefix) == CONFIG.prefix then
        text = text:sub(#CONFIG.prefix+1)
    elseif CONFIG.enableProximity and (not isFromMe) and nearEnough and (FocusedCharacter == nil or FocusedCharacter == fromPlayer.Character) then
        -- dispara por proximidade
        -- ok
    else
        return
    end

    WaitingAnswer = true
    setStatus("gerando resposta…")

    -- pedir resposta ao Character.AI
    local ok, res = pcall(function()
        return SelectedCharacter:SendMessage(fromPlayer.Name, (fromPlayer.DisplayName or fromPlayer.Name)..": "..text)
    end)

    if not ok or not res or res.Status == false then
        setStatus("erro na geração (API offline?)")
        WaitingAnswer = false
        return
    end

    local replies = res.Body and res.Body.replies or {}
    local first = replies and replies[1]
    if not first or not first.text then
        setStatus("sem conteúdo na resposta")
        WaitingAnswer = false
        return
    end

    -- dividir e enviar
    local parts = chunkText(first.text, CONFIG.maxChunkChars)
    for _,p in ipairs(parts) do
        rbxSay(p)
        task.wait(CONFIG.waitBetweenParts)
    end

    setStatus("pronto")
    WaitingAnswer = false
end

-- Chat novo
local function hookTextChat()
    if TextChatService.ChatVersion ~= Enum.ChatVersion.TextChatService then return end
    TextChatService.MessageReceived:Connect(function(msg)
        local src = msg.TextSource
        local plr = src and Players:GetPlayerByUserId(src.UserId)
        local txt = msg.Text
        handleMessage(plr, txt)
    end)
end

-- Chat clássico
local function hookLegacyChat()
    local ok = pcall(function()
        ReplicatedStorage.DefaultChatSystemChatEvents.OnMessageDoneFiltering.OnClientEvent:Connect(function(data)
            local plr = Players:FindFirstChild(data.FromSpeaker)
            handleMessage(plr, data.Message)
        end)
    end)
    return ok
end

-- ligar hooks
local function initChatHooks()
    local hookedNew = false
    pcall(function()
        if TextChatService.ChatVersion == Enum.ChatVersion.TextChatService then
            hookTextChat(); hookedNew = true
        end
    end)
    if not hookedNew then hookLegacyChat() end
end
initChatHooks()

-- ===== tela de loading leve + checagens
local blur = Instance.new("BlurEffect", Lighting); blur.Size = 0
TweenService:Create(blur, TweenInfo.new(0.6), {Size = 10}):Play()
task.delay(1.4, function() TweenService:Create(blur, TweenInfo.new(0.8), {Size = 0}):Play(); task.delay(0.9, function() pcall(function() blur:Destroy() end) end) end)

-- ping Character.AI
if CONFIG.token and #tostring(CONFIG.token) > 0 then
    setStatus("token ok — conectando…")
else
    setStatus("sem token (modo convidado, sujeito a limites)")
end

-- Pré-carregar algumas listas (com tolerância a falhas)
task.spawn(function()
    local mp = Session:GetMainPageCharacters()
    if mp and mp.Status and mp.Body then
        setStatus("catálogo disponível — faça uma busca")
    else
        setStatus("API possivelmente offline — você ainda pode tentar external_id")
    end
end)

-- Dica de uso
local tip = Instance.new("TextLabel", body)
tip.BackgroundTransparency = 1
tip.Position = UDim2.new(0,0,1,-18)
tip.Size = UDim2.new(1,0,0,18)
tip.Font = Enum.Font.Gotham
tip.TextColor3 = Color3.fromRGB(150,146,140)
tip.TextXAlignment = Enum.TextXAlignment.Left
tip.Text = ("Dica: use \"%s\" para forçar resposta (ex.: %sOlá). Hotkey UI: %s")
    :format(CONFIG.prefix, CONFIG.prefix, tostring(CONFIG.uiHotkey))
