--[[
    =========================================================================
    ROBLOX AUTO-CHAT AI (POLLINATIONS AI)
    Arquitetura modular em script único (Luau)
    =========================================================================
]]

-- Limpeza automática caso o script seja executado mais de uma vez
local globalEnv = (type(getgenv) == "function" and getgenv()) or _G
if type(globalEnv.__RobloxAutoAI_Cleanup) == "function" then
    pcall(globalEnv.__RobloxAutoAI_Cleanup)
end

-- Serviços do Roblox
local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local TextChatService = game:GetService("TextChatService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local CoreGui = game:GetService("CoreGui")

local LocalPlayer = Players.LocalPlayer or Players.PlayerAdded:Wait()

-- Controle de conexões para encerramento limpo
local Connections = {}
local function trackConnection(conn)
    if conn then
        table.insert(Connections, conn)
    end
    return conn
end

-- =========================================================================
-- MÓDULO 1: CONFIGURAÇÕES
-- =========================================================================
local Config = {
    Enabled = false,

    -- Integração com API (Pollinations AI - padrão OpenAI)
    ApiUrl = "https://gen.pollinations.ai/v1/chat/completions",
    ApiKey = "", -- Inserida pela interface (nunca exposta no chat)
    Model = "openai/gpt-5.4-nano", -- Modelos comuns: openai, openai/gpt-5.4-nano, deepseek/deepseek-v4.1-flash, google/gemini-2.5-flash-lite, mistralai/mistral-small-4
    Temperature = 0.85,
    MaxChars = 160, -- Limite seguro abaixo dos 200 caracteres do chat do Roblox
    Timeout = 15,

    -- Personalidade
    PersonalityPreset = "Amigável",
    CustomPersonality = "",
    Presets = {
        ["Amigável"] = "Você é gente boa, acolhedor e conversa de forma leve e simpática como um amigo jogando junto.",
        ["Engraçada"] = "Você tem senso de humor leve, faz comentários engraçados e entra nas brincadeiras sem forçar.",
        ["Séria"] = "Você é direto, calmo, objetivo e responde sem enrolação, mantendo um tom natural.",
        ["Sarcástica"] = "Você tem humor ácido sutil e dá respostas irônicas de vez em quando, mas sem ser tóxico.",
        ["Inteligente"] = "Você observa bem o que falam, dá respostas espertas e curiosas, mas sem falar como professor.",
        ["Extrovertida"] = "Você é animado, puxa assunto fácil, faz perguntas e gosta de interagir com todo mundo.",
        ["Misteriosa"] = "Você fala pouco, de um jeito enigmático e tranquilo, deixando respostas curtas e curiosas.",
    },

    -- Controle de respostas
    ResponseMode = "DirectOnly", -- "MentionOnly" | "DirectOnly" | "All"
    CooldownSeconds = 4,
    RandomReplyChance = 35, -- 0 a 100 (%)
    MaxProximityStuds = 45, -- Usado como apoio no modo DirectOnly
    ContextWindow = 12, -- Quantidade máxima de mensagens no histórico enviado à IA
    ConversationActiveWindow = 25, -- Segundos em que o último interlocutor continua considerado em conversa direta

    -- Filtros
    IgnoredPlayers = {}, -- Lista de nomes em minúsculo
    ForbiddenWords = {}, -- Lista de palavras em minúsculo

    -- Comandos locais do dono
    CommandPrefix = "!ia",
}

-- Estado em runtime
local Runtime = {
    IsGenerating = false,
    LastReplyTick = 0,
    LastDirectTalker = nil,
    LastDirectTime = 0,
    ApiStatus = "Aguardando", -- "Aguardando" | "Conectado" | "Erro"
    ApiStatusDetail = "Pronto para testar ou ligar",
    SentHistory = {}, -- Últimas mensagens enviadas (anti-repetição)
    ProcessedMessages = {}, -- Deduplicação de mensagens recebidas
    ProcessedOrder = {},
}

-- =========================================================================
-- MÓDULO 2: DETECÇÃO DE AMBIENTE E COMPATIBILIDADE
-- =========================================================================
local Environment = {}

function Environment.getHttpRequestFunction()
    local env = (type(getgenv) == "function" and getgenv()) or _G
    local candidates = {
        request,
        http_request,
        env and env.request,
        env and env.http_request,
        syn and syn.request,
        http and http.request,
        fluxus and fluxus.request,
    }
    for _, fn in ipairs(candidates) do
        if type(fn) == "function" then
            return fn
        end
    end
    return nil
end

function Environment.getSafeGuiParent()
    if type(gethui) == "function" then
        local ok, hui = pcall(gethui)
        if ok and hui then
            return hui, "gethui"
        end
    end

    local okCore = pcall(function()
        local _ = CoreGui.Name
    end)
    if okCore then
        return CoreGui, "CoreGui"
    end

    local playerGui = LocalPlayer:FindFirstChildOfClass("PlayerGui") or LocalPlayer:WaitForChild("PlayerGui", 5)
    return playerGui, "PlayerGui"
end

function Environment.getChatSystemType()
    local ok, version = pcall(function()
        return TextChatService.ChatVersion
    end)
    if ok and version == Enum.ChatVersion.TextChatService then
        return "TextChatService"
    end

    local legacyEvents = ReplicatedStorage:FindFirstChild("DefaultChatSystemChatEvents")
    if legacyEvents and legacyEvents:FindFirstChild("SayMessageRequest") then
        return "LegacyChat"
    end

    return "FallbackChatted"
end

-- =========================================================================
-- MÓDULO 3: PROTEÇÃO E SEGURANÇA
-- =========================================================================
local Security = {}

function Security.trim(str)
    if type(str) ~= "string" then
        return ""
    end
    return (str:gsub("^%s+", ""):gsub("%s+$", ""))
end

function Security.normalize(str)
    return Security.trim(str):lower()
end

-- Remove emojis e símbolos pictográficos preservando acentos do português
function Security.stripEmojis(text)
    if type(text) ~= "string" then
        return ""
    end

    local buffer = {}
    local ok = pcall(function()
        for _, codepoint in utf8.codes(text) do
            local isEmoji =
                (codepoint >= 0x1F000 and codepoint <= 0x1FAFF) or
                (codepoint >= 0x2600 and codepoint <= 0x27BF) or
                (codepoint >= 0x2300 and codepoint <= 0x23FF) or
                (codepoint >= 0x2B00 and codepoint <= 0x2BFF) or
                (codepoint >= 0xFE00 and codepoint <= 0xFE0F) or
                (codepoint == 0x200D) or
                (codepoint >= 0xE0020 and codepoint <= 0xE007F)

            if not isEmoji then
                table.insert(buffer, utf8.char(codepoint))
            end
        end
    end)

    local cleaned
    if ok then
        cleaned = table.concat(buffer)
    else
        cleaned = text:gsub("[\240-\244][\128-\191]*", "")
    end

    -- Remove quebras de linha e formatação markdown que não combinam com chat do Roblox
    cleaned = cleaned:gsub("[\r\n]+", " ")
    cleaned = cleaned:gsub("[%*_`~]+", "")
    cleaned = cleaned:gsub("%s+", " ")
    return Security.trim(cleaned)
end

-- Impede qualquer vazamento da API Key ou fragmentos sensíveis no chat público
function Security.containsSensitiveData(text)
    if type(text) ~= "string" or text == "" then
        return false
    end
    local key = Security.trim(Config.ApiKey)
    if key ~= "" and #key >= 6 then
        if text:find(key, 1, true) then
            return true
        end
        local prefix = key:sub(1, math.min(10, #key))
        if #prefix >= 6 and text:find(prefix, 1, true) then
            return true
        end
    end
    return false
end

function Security.containsForbiddenWord(text)
    local lower = Security.normalize(text)
    for _, word in ipairs(Config.ForbiddenWords) do
        if word ~= "" and lower:find(word, 1, true) then
            return true, word
        end
    end
    return false, nil
end

function Security.isPlayerIgnored(playerName, displayName)
    local n1 = Security.normalize(playerName or "")
    local n2 = Security.normalize(displayName or "")
    for _, blocked in ipairs(Config.IgnoredPlayers) do
        if blocked ~= "" and (blocked == n1 or blocked == n2) then
            return true
        end
    end
    return false
end

function Security.isDuplicateOutput(text)
    local norm = Security.normalize(text)
    if norm == "" then
        return true
    end
    for _, prev in ipairs(Runtime.SentHistory) do
        if prev == norm then
            return true
        end
    end
    return false
end

function Security.recordOutput(text)
    table.insert(Runtime.SentHistory, Security.normalize(text))
    if #Runtime.SentHistory > 8 then
        table.remove(Runtime.SentHistory, 1)
    end
end

function Security.truncateSafely(text, maxChars)
    local limit = math.clamp(tonumber(maxChars) or 160, 20, 200)
    if #text <= limit then
        return text
    end

    -- Tenta cortar sem quebrar no meio de um caractere UTF-8 ou palavra
    local cut = text:sub(1, limit)
    local lastSpace = cut:match("^(.*)%s+[^%s]*$")
    if lastSpace and #lastSpace >= math.floor(limit * 0.5) then
        cut = lastSpace
    end

    -- Garante validade UTF-8 caso corte no meio de acento multibyte
    while #cut > 0 do
        local ok = pcall(utf8.len, cut)
        if ok then
            break
        end
        cut = cut:sub(1, #cut - 1)
    end

    return Security.trim(cut)
end

function Security.sanitizeOutgoingMessage(rawText)
    if Security.containsSensitiveData(rawText) then
        return nil, "Bloqueado por conter dados sensíveis"
    end

    local cleaned = Security.stripEmojis(rawText)
    if cleaned == "" then
        return nil, "Resposta vazia após limpeza"
    end

    -- Remove prefixos artificiais caso o modelo tente colocar "Eu: " ou "[IA]: "
    cleaned = cleaned:gsub("^%[?[%w%s_-]+%]?:%s*", "")
    cleaned = Security.trim(cleaned)

    if cleaned == "" then
        return nil, "Resposta vazia"
    end

    local hasForbidden, word = Security.containsForbiddenWord(cleaned)
    if hasForbidden then
        return nil, "Bloqueado por palavra proibida (" .. tostring(word) .. ")"
    end

    cleaned = Security.truncateSafely(cleaned, Config.MaxChars)

    if Security.isDuplicateOutput(cleaned) then
        return nil, "Bloqueado para evitar mensagem repetida"
    end

    return cleaned, nil
end

function Security.markMessageProcessed(msgKey)
    if Runtime.ProcessedMessages[msgKey] then
        return false
    end
    Runtime.ProcessedMessages[msgKey] = true
    table.insert(Runtime.ProcessedOrder, msgKey)
    if #Runtime.ProcessedOrder > 150 then
        local oldest = table.remove(Runtime.ProcessedOrder, 1)
        Runtime.ProcessedMessages[oldest] = nil
    end
    return true
end

function Security.parseCommaList(rawText)
    local list = {}
    for item in string.gmatch(rawText or "", "([^,]+)") do
        local cleaned = Security.normalize(item)
        if cleaned ~= "" then
            table.insert(list, cleaned)
        end
    end
    return list
end

-- =========================================================================
-- MÓDULO 4: GERENCIAMENTO DE CONTEXTO
-- =========================================================================
local ContextManager = {
    Messages = {}, -- { role = "user" | "assistant", author = string, content = string, timestamp = number }
}

function ContextManager.addMessage(role, author, content)
    table.insert(ContextManager.Messages, {
        role = role,
        author = author or "Desconhecido",
        content = content,
        timestamp = os.time(),
    })

    while #ContextManager.Messages > Config.ContextWindow do
        table.remove(ContextManager.Messages, 1)
    end
end

function ContextManager.clear()
    table.clear(ContextManager.Messages)
    Runtime.LastDirectTalker = nil
    Runtime.LastDirectTime = 0
end

function ContextManager.buildSystemPrompt()
    local myDisplay = LocalPlayer.DisplayName or LocalPlayer.Name
    local myUser = LocalPlayer.Name

    local personalityText = Config.Presets[Config.PersonalityPreset] or Config.Presets["Amigável"]
    if Config.PersonalityPreset == "Personalizada" or Security.trim(Config.CustomPersonality) ~= "" then
        local custom = Security.trim(Config.CustomPersonality)
        if custom ~= "" then
            personalityText = custom
        end
    end

    return table.concat({
        "Você é um jogador real no Roblox conversando no chat com outras pessoas.",
        string.format("Seu nome de exibição é '%s' e seu usuário é '@%s'.", myDisplay, myUser),
        "Personalidade: " .. personalityText,
        "Regras obrigatórias de comportamento:",
        "1. Aja 100% como uma pessoa normal jogando Roblox, nunca como uma IA, bot ou assistente virtual.",
        "2. Se alguém perguntar se você é IA ou bot, reaja de forma natural e casual como um humano normal.",
        "3. NUNCA use emojis, figurinhas ou símbolos gráficos.",
        "4. Escreva frases curtas, naturais e informais (ex: 'kk', 'blz', 'pq', 'to aqui'), combinando com o idioma de quem falou com você.",
        "5. Entenda abreviações, gírias e erros de digitação normalmente sem corrigir ninguém.",
        "6. Não use formatação markdown, listas ou textos longos.",
        "7. Não invente informações sobre o jogo, mapa, itens ou sobre o dono da conta. Se não souber algo, diga que não sabe ou pergunte.",
        string.format("8. Sua resposta DEVE ter no máximo %d caracteres.", Config.MaxChars),
        "9. Retorne apenas a fala exata que será enviada no chat, sem colocar seu nome na frente.",
    }, "\n")
end

function ContextManager.buildApiPayloadMessages(latestSpeaker, latestText)
    local payload = {
        { role = "system", content = ContextManager.buildSystemPrompt() }
    }

    for _, entry in ipairs(ContextManager.Messages) do
        if entry.role == "assistant" then
            table.insert(payload, {
                role = "assistant",
                content = entry.content,
            })
        else
            table.insert(payload, {
                role = "user",
                content = string.format("[%s]: %s", entry.author, entry.content),
            })
        end
    end

    if latestSpeaker and latestText then
        table.insert(payload, {
            role = "user",
            content = string.format("[%s]: %s", latestSpeaker, latestText),
        })
    end

    return payload
end

-- =========================================================================
-- MÓDULO 5: COMUNICAÇÃO COM A API (POLLINATIONS AI)
-- =========================================================================
local AIClient = {}
local OnStatusChangedCallback = nil

local function updateApiStatus(status, detail)
    Runtime.ApiStatus = status
    Runtime.ApiStatusDetail = detail or ""
    if OnStatusChangedCallback then
        pcall(OnStatusChangedCallback, status, detail)
    end
end

function AIClient.setStatusCallback(cb)
    OnStatusChangedCallback = cb
end

function AIClient.requestCompletion(messages)
    local httpRequest = Environment.getHttpRequestFunction()
    if not httpRequest then
        updateApiStatus("Erro", "Executor sem função HTTP (request)")
        return false, "Ambiente atual não fornece função HTTP no cliente."
    end

    local headers = {
        ["Content-Type"] = "application/json",
        ["Accept"] = "application/json",
    }

    local apiKey = Security.trim(Config.ApiKey)
    if apiKey ~= "" then
        headers["Authorization"] = "Bearer " .. apiKey
    end

    local bodyTable = {
        model = Security.trim(Config.Model) ~= "" and Security.trim(Config.Model) or "openai/gpt-5.4-nano",
        messages = messages,
        temperature = math.clamp(tonumber(Config.Temperature) or 0.85, 0, 2),
        max_tokens = 120,
        stream = false,
    }

    local okEncode, encodedBody = pcall(HttpService.JSONEncode, HttpService, bodyTable)
    if not okEncode then
        updateApiStatus("Erro", "Falha ao codificar JSON")
        return false, "Erro ao montar JSON da requisição."
    end

    updateApiStatus("Aguardando", "Consultando API...")

    local done = false
    local reqSuccess = false
    local responseData = nil
    local startTick = os.clock()
    local timeoutLimit = math.clamp(tonumber(Config.Timeout) or 15, 3, 60)

    task.spawn(function()
        local ok, res = pcall(httpRequest, {
            Url = Security.trim(Config.ApiUrl),
            Method = "POST",
            Headers = headers,
            Body = encodedBody,
        })
        if not done then
            done = true
            reqSuccess = ok
            responseData = res
        end
    end)

    while not done and (os.clock() - startTick) < timeoutLimit do
        task.wait(0.05)
    end

    if not done then
        done = true
        updateApiStatus("Erro", "Tempo limite excedido (" .. tostring(timeoutLimit) .. "s)")
        return false, "Tempo máximo de resposta excedido."
    end

    if not reqSuccess or type(responseData) ~= "table" then
        updateApiStatus("Erro", "Falha na chamada HTTP")
        return false, "Falha de rede ao chamar a API."
    end

    local statusCode = tonumber(responseData.StatusCode or responseData.status) or 0
    local rawBody = tostring(responseData.Body or responseData.body or "")

    if statusCode == 401 or statusCode == 403 then
        updateApiStatus("Erro", "HTTP " .. statusCode .. " (Chave inválida/ausente)")
        return false, "Acesso negado (HTTP " .. statusCode .. "). Verifique sua API Key do Pollinations."
    elseif statusCode == 429 then
        updateApiStatus("Erro", "HTTP 429 (Limite de requisições)")
        return false, "Muitas requisições em sequência (HTTP 429)."
    elseif statusCode < 200 or statusCode >= 300 then
        updateApiStatus("Erro", "HTTP " .. tostring(statusCode))
        return false, "Erro da API (HTTP " .. tostring(statusCode) .. ")."
    end

    local okDecode, decoded = pcall(HttpService.JSONDecode, HttpService, rawBody)
    if okDecode and type(decoded) == "table" then
        if type(decoded.choices) == "table" and decoded.choices[1] then
            local choice = decoded.choices[1]
            local content = (type(choice.message) == "table" and choice.message.content) or choice.text
            if type(content) == "string" and Security.trim(content) ~= "" then
                updateApiStatus("Conectado", "Resposta recebida")
                return true, content
            end
        elseif type(decoded.content) == "string" and Security.trim(decoded.content) ~= "" then
            updateApiStatus("Conectado", "Resposta recebida")
            return true, decoded.content
        elseif type(decoded.error) == "table" and decoded.error.message then
            updateApiStatus("Erro", "Erro retornado pela API")
            return false, tostring(decoded.error.message)
        end
    elseif Security.trim(rawBody) ~= "" and not rawBody:match("^%s*<") then
        -- Caso algum proxy retorne texto puro
        updateApiStatus("Conectado", "Resposta em texto recebida")
        return true, rawBody
    end

    updateApiStatus("Erro", "Formato de resposta inválido")
    return false, "Não foi possível interpretar a resposta da API."
end

-- =========================================================================
-- MÓDULO 6: ENVIO DE RESPOSTAS NO CHAT
-- =========================================================================
local ChatSender = {}

function ChatSender.send(messageText)
    local chatType = Environment.getChatSystemType()

    if chatType == "TextChatService" then
        local channels = TextChatService:FindFirstChild("TextChannels")
        local general = channels and (channels:FindFirstChild("RBXGeneral") or channels:FindFirstChildOfClass("TextChannel"))
        if general then
            local ok, err = pcall(function()
                general:SendAsync(messageText)
            end)
            if ok then
                return true
            end
            return false, tostring(err)
        end
        return false, "Canal RBXGeneral não encontrado"
    end

    local legacyEvents = ReplicatedStorage:FindFirstChild("DefaultChatSystemChatEvents")
    local sayRequest = legacyEvents and legacyEvents:FindFirstChild("SayMessageRequest")
    if sayRequest and sayRequest:IsA("RemoteEvent") then
        local ok, err = pcall(function()
            sayRequest:FireServer(messageText, "All")
        end)
        if ok then
            return true
        end
        return false, tostring(err)
    end

    return false, "Nenhum canal de envio suportado encontrado"
end

-- =========================================================================
-- MÓDULO 7: INTERFACE GRÁFICA (TEMA ESCURO, TRANSPARENTE E ARRASTÁVEL)
-- =========================================================================
local UI = {
    Root = nil,
    LogCallback = nil,
    Elements = {},
}

local function addLog(tag, text, color)
    if UI.LogCallback then
        pcall(UI.LogCallback, tag, text, color)
    end
end

local function makeCorner(parent, radius)
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, radius or 8)
    corner.Parent = parent
    return corner
end

local function makeStroke(parent, color, thickness, transparency)
    local stroke = Instance.new("UIStroke")
    stroke.Color = color or Color3.fromRGB(60, 68, 88)
    stroke.Thickness = thickness or 1
    stroke.Transparency = transparency or 0.35
    stroke.Parent = parent
    return stroke
end

function UI.build(callbacks)
    local parentGui = Environment.getSafeGuiParent()
    if not parentGui then
        return
    end

    local screenGui = Instance.new("ScreenGui")
    screenGui.Name = "AutoChatAI_UI"
    screenGui.ResetOnSpawn = false
    screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    screenGui.Parent = parentGui
    UI.Root = screenGui

    -- Janela principal
    local mainFrame = Instance.new("Frame")
    mainFrame.Name = "MainFrame"
    mainFrame.Size = UDim2.fromOffset(480, 430)
    mainFrame.Position = UDim2.new(0.5, -240, 0.5, -215)
    mainFrame.BackgroundColor3 = Color3.fromRGB(16, 18, 24)
    mainFrame.BackgroundTransparency = 0.12
    mainFrame.ClipsDescendants = true
    mainFrame.Parent = screenGui
    makeCorner(mainFrame, 12)
    makeStroke(mainFrame, Color3.fromRGB(72, 82, 110), 1, 0.35)

    -- Barra superior (arrastável)
    local topBar = Instance.new("Frame")
    topBar.Name = "TopBar"
    topBar.Size = UDim2.new(1, 0, 0, 42)
    topBar.BackgroundColor3 = Color3.fromRGB(22, 25, 34)
    topBar.BackgroundTransparency = 0.15
    topBar.BorderSizePixel = 0
    topBar.Parent = mainFrame

    local titleLabel = Instance.new("TextLabel")
    titleLabel.Size = UDim2.new(0, 190, 1, 0)
    titleLabel.Position = UDim2.fromOffset(14, 0)
    titleLabel.BackgroundTransparency = 1
    titleLabel.Font = Enum.Font.GothamBold
    titleLabel.Text = "Chat Automático IA"
    titleLabel.TextColor3 = Color3.fromRGB(238, 240, 246)
    titleLabel.TextSize = 14
    titleLabel.TextXAlignment = Enum.TextXAlignment.Left
    titleLabel.Parent = topBar

    -- Indicador de status da API
    local statusBadge = Instance.new("Frame")
    statusBadge.Size = UDim2.fromOffset(145, 24)
    statusBadge.Position = UDim2.new(1, -218, 0.5, -12)
    statusBadge.BackgroundColor3 = Color3.fromRGB(28, 32, 43)
    statusBadge.BackgroundTransparency = 0.2
    statusBadge.Parent = topBar
    makeCorner(statusBadge, 12)

    local statusDot = Instance.new("Frame")
    statusDot.Size = UDim2.fromOffset(8, 8)
    statusDot.Position = UDim2.new(0, 9, 0.5, -4)
    statusDot.BackgroundColor3 = Color3.fromRGB(250, 166, 26)
    statusDot.BorderSizePixel = 0
    statusDot.Parent = statusBadge
    makeCorner(statusDot, 4)

    local statusText = Instance.new("TextLabel")
    statusText.Size = UDim2.new(1, -24, 1, 0)
    statusText.Position = UDim2.fromOffset(22, 0)
    statusText.BackgroundTransparency = 1
    statusText.Font = Enum.Font.GothamMedium
    statusText.Text = "Aguardando"
    statusText.TextColor3 = Color3.fromRGB(210, 214, 224)
    statusText.TextSize = 11
    statusText.TextXAlignment = Enum.TextXAlignment.Left
    statusText.TextTruncate = Enum.TextTruncate.AtEnd
    statusText.Parent = statusBadge

    -- Botões Minimizar e Fechar
    local minBtn = Instance.new("TextButton")
    minBtn.Size = UDim2.fromOffset(28, 26)
    minBtn.Position = UDim2.new(1, -66, 0.5, -13)
    minBtn.BackgroundColor3 = Color3.fromRGB(36, 40, 54)
    minBtn.Font = Enum.Font.GothamBold
    minBtn.Text = "-"
    minBtn.TextColor3 = Color3.fromRGB(220, 224, 235)
    minBtn.TextSize = 15
    minBtn.Parent = topBar
    makeCorner(minBtn, 6)

    local closeBtn = Instance.new("TextButton")
    closeBtn.Size = UDim2.fromOffset(28, 26)
    closeBtn.Position = UDim2.new(1, -34, 0.5, -13)
    closeBtn.BackgroundColor3 = Color3.fromRGB(165, 52, 58)
    closeBtn.Font = Enum.Font.GothamBold
    closeBtn.Text = "X"
    closeBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
    closeBtn.TextSize = 12
    closeBtn.Parent = topBar
    makeCorner(closeBtn, 6)

    -- Sistema de arrastar (PC + Mobile)
    local dragging = false
    local dragStart, startPos
    trackConnection(topBar.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            dragStart = input.Position
            startPos = mainFrame.Position
        end
    end))
    trackConnection(UserInputService.InputChanged:Connect(function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
            local delta = input.Position - dragStart
            mainFrame.Position = UDim2.new(
                startPos.X.Scale,
                startPos.X.Offset + delta.X,
                startPos.Y.Scale,
                startPos.Y.Offset + delta.Y
            )
        end
    end))
    trackConnection(UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = false
        end
    end))

    -- Barra de Abas
    local tabBar = Instance.new("Frame")
    tabBar.Size = UDim2.new(1, -20, 0, 32)
    tabBar.Position = UDim2.fromOffset(10, 48)
    tabBar.BackgroundColor3 = Color3.fromRGB(22, 25, 34)
    tabBar.BackgroundTransparency = 0.25
    tabBar.Parent = mainFrame
    makeCorner(tabBar, 8)

    local tabLayout = Instance.new("UIListLayout")
    tabLayout.FillDirection = Enum.FillDirection.Horizontal
    tabLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
    tabLayout.VerticalAlignment = Enum.VerticalAlignment.Center
    tabLayout.Padding = UDim.new(0, 4)
    tabLayout.Parent = tabBar

    local contentHolder = Instance.new("Frame")
    contentHolder.Size = UDim2.new(1, -20, 1, -92)
    contentHolder.Position = UDim2.fromOffset(10, 86)
    contentHolder.BackgroundTransparency = 1
    contentHolder.Parent = mainFrame

    local tabs = {}
    local tabButtons = {}

    local function createTab(name)
        local btn = Instance.new("TextButton")
        btn.Size = UDim2.new(0.24, 0, 1, -6)
        btn.BackgroundColor3 = Color3.fromRGB(34, 38, 52)
        btn.BackgroundTransparency = 1
        btn.Font = Enum.Font.GothamMedium
        btn.Text = name
        btn.TextColor3 = Color3.fromRGB(165, 172, 190)
        btn.TextSize = 12
        btn.Parent = tabBar
        makeCorner(btn, 6)

        local page = Instance.new("ScrollingFrame")
        page.Size = UDim2.fromScale(1, 1)
        page.BackgroundTransparency = 1
        page.BorderSizePixel = 0
        page.ScrollBarThickness = 4
        page.ScrollBarImageColor3 = Color3.fromRGB(80, 90, 120)
        page.CanvasSize = UDim2.fromOffset(0, 0)
        page.AutomaticCanvasSize = Enum.AutomaticSize.Y
        page.Visible = false
        page.Parent = contentHolder

        local layout = Instance.new("UIListLayout")
        layout.Padding = UDim.new(0, 8)
        layout.SortOrder = Enum.SortOrder.LayoutOrder
        layout.Parent = page

        local pad = Instance.new("UIPadding")
        pad.PaddingRight = UDim.new(0, 6)
        pad.PaddingBottom = UDim.new(0, 8)
        pad.Parent = page

        tabs[name] = page
        tabButtons[name] = btn

        btn.MouseButton1Click:Connect(function()
            for tName, tPage in pairs(tabs) do
                local active = (tName == name)
                tPage.Visible = active
                tabButtons[tName].BackgroundTransparency = active and 0.15 or 1
                tabButtons[tName].TextColor3 = active and Color3.fromRGB(245, 247, 252) or Color3.fromRGB(165, 172, 190)
            end
        end)

        return page
    end

    local function createSectionLabel(parent, text)
        local lbl = Instance.new("TextLabel")
        lbl.Size = UDim2.new(1, 0, 0, 18)
        lbl.BackgroundTransparency = 1
        lbl.Font = Enum.Font.GothamBold
        lbl.Text = text
        lbl.TextColor3 = Color3.fromRGB(190, 198, 220)
        lbl.TextSize = 12
        lbl.TextXAlignment = Enum.TextXAlignment.Left
        lbl.Parent = parent
        return lbl
    end

    local function createInputBox(parent, placeholder, defaultText, height, multiline)
        local box = Instance.new("TextBox")
        box.Size = UDim2.new(1, 0, 0, height or 32)
        box.BackgroundColor3 = Color3.fromRGB(24, 27, 36)
        box.BackgroundTransparency = 0.1
        box.ClearTextOnFocus = false
        box.Font = Enum.Font.Gotham
        box.PlaceholderText = placeholder
        box.PlaceholderColor3 = Color3.fromRGB(110, 118, 138)
        box.Text = defaultText or ""
        box.TextColor3 = Color3.fromRGB(235, 238, 245)
        box.TextSize = 12
        box.TextXAlignment = Enum.TextXAlignment.Left
        box.MultiLine = multiline == true
        box.TextWrapped = multiline == true
        box.TextYAlignment = multiline and Enum.TextYAlignment.Top or Enum.TextYAlignment.Center
        box.Parent = parent
        makeCorner(box, 7)
        makeStroke(box, Color3.fromRGB(54, 60, 80), 1, 0.4)

        local pad = Instance.new("UIPadding")
        pad.PaddingLeft = UDim.new(0, 10)
        pad.PaddingRight = UDim.new(0, 10)
        pad.PaddingTop = UDim.new(0, multiline and 8 or 0)
        pad.Parent = box

        return box
    end

    -- Criar Abas
    local pageGeral = createTab("Geral")
    local pageIA = createTab("IA & Persona")
    local pageFiltros = createTab("Filtros")
    local pageHistorico = createTab("Histórico")

    -- Ativar primeira aba
    pageGeral.Visible = true
    tabButtons["Geral"].BackgroundTransparency = 0.15
    tabButtons["Geral"].TextColor3 = Color3.fromRGB(245, 247, 252)

    -- ---------------------------------------------------------------------
    -- ABA 1: GERAL
    -- ---------------------------------------------------------------------
    local toggleBtn = Instance.new("TextButton")
    toggleBtn.Size = UDim2.new(1, 0, 0, 40)
    toggleBtn.BackgroundColor3 = Color3.fromRGB(168, 55, 62)
    toggleBtn.Font = Enum.Font.GothamBold
    toggleBtn.Text = "IA: DESLIGADA (Clique para ligar)"
    toggleBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
    toggleBtn.TextSize = 13
    toggleBtn.Parent = pageGeral
    makeCorner(toggleBtn, 8)

    local function refreshToggleVisual()
        if Config.Enabled then
            toggleBtn.BackgroundColor3 = Color3.fromRGB(46, 148, 88)
            toggleBtn.Text = "IA: LIGADA (Respondendo no chat)"
        else
            toggleBtn.BackgroundColor3 = Color3.fromRGB(168, 55, 62)
            toggleBtn.Text = "IA: DESLIGADA (Clique para ligar)"
        end
    end

    toggleBtn.MouseButton1Click:Connect(function()
        Config.Enabled = not Config.Enabled
        refreshToggleVisual()
        addLog("Sistema", Config.Enabled and "IA ativada." or "IA desativada.", Color3.fromRGB(140, 200, 255))
    end)

    -- Modo de resposta
    createSectionLabel(pageGeral, "Modo de Resposta")
    local modeRow = Instance.new("Frame")
    modeRow.Size = UDim2.new(1, 0, 0, 32)
    modeRow.BackgroundTransparency = 1
    modeRow.Parent = pageGeral

    local modeLayout = Instance.new("UIListLayout")
    modeLayout.FillDirection = Enum.FillDirection.Horizontal
    modeLayout.Padding = UDim.new(0, 6)
    modeLayout.Parent = modeRow

    local modeButtons = {}
    local modeList = {
        { id = "MentionOnly", label = "Quando Mencionado" },
        { id = "DirectOnly", label = "Falando Comigo" },
        { id = "All", label = "Responder Todos" },
    }

    local function refreshModeButtons()
        for id, btn in pairs(modeButtons) do
            local active = (Config.ResponseMode == id)
            btn.BackgroundColor3 = active and Color3.fromRGB(65, 105, 225) or Color3.fromRGB(30, 34, 46)
            btn.TextColor3 = active and Color3.fromRGB(255, 255, 255) or Color3.fromRGB(185, 192, 210)
        end
    end

    for _, item in ipairs(modeList) do
        local btn = Instance.new("TextButton")
        btn.Size = UDim2.new(0.323, 0, 1, 0)
        btn.Font = Enum.Font.GothamMedium
        btn.Text = item.label
        btn.TextSize = 11
        btn.Parent = modeRow
        makeCorner(btn, 7)
        modeButtons[item.id] = btn
        btn.MouseButton1Click:Connect(function()
            Config.ResponseMode = item.id
            refreshModeButtons()
        end)
    end
    refreshModeButtons()

    -- Campo API Key (mascarado visualmente quando oculto)
    createSectionLabel(pageGeral, "Pollinations API Key (enter.pollinations.ai)")
    local keyRow = Instance.new("Frame")
    keyRow.Size = UDim2.new(1, 0, 0, 32)
    keyRow.BackgroundTransparency = 1
    keyRow.Parent = pageGeral

    local keyBox = Instance.new("TextBox")
    keyBox.Size = UDim2.new(1, -84, 1, 0)
    keyBox.BackgroundColor3 = Color3.fromRGB(24, 27, 36)
    keyBox.ClearTextOnFocus = false
    keyBox.Font = Enum.Font.Gotham
    keyBox.PlaceholderText = "Cole sua chave pk_ ou sk_ aqui..."
    keyBox.PlaceholderColor3 = Color3.fromRGB(110, 118, 138)
    keyBox.Text = ""
    keyBox.TextColor3 = Color3.fromRGB(235, 238, 245)
    keyBox.TextSize = 12
    keyBox.TextXAlignment = Enum.TextXAlignment.Left
    keyBox.Parent = keyRow
    makeCorner(keyBox, 7)
    makeStroke(keyBox, Color3.fromRGB(54, 60, 80), 1, 0.4)
    local kPad = Instance.new("UIPadding", keyBox)
    kPad.PaddingLeft = UDim.new(0, 10)
    kPad.PaddingRight = UDim.new(0, 10)

    local hideKey = true
    local keyMaskBtn = Instance.new("TextButton")
    keyMaskBtn.Size = UDim2.fromOffset(78, 32)
    keyMaskBtn.Position = UDim2.new(1, -78, 0, 0)
    keyMaskBtn.BackgroundColor3 = Color3.fromRGB(36, 40, 54)
    keyMaskBtn.Font = Enum.Font.GothamMedium
    keyMaskBtn.Text = "Mostrar"
    keyMaskBtn.TextColor3 = Color3.fromRGB(220, 224, 235)
    keyMaskBtn.TextSize = 11
    keyMaskBtn.Parent = keyRow
    makeCorner(keyMaskBtn, 7)

    keyBox.Focused:Connect(function()
        keyBox.Text = Config.ApiKey
    end)
    keyBox.FocusLost:Connect(function()
        Config.ApiKey = Security.trim(keyBox.Text)
        if hideKey and Config.ApiKey ~= "" then
            keyBox.Text = string.rep("*", math.min(#Config.ApiKey, 24))
        end
    end)
    keyMaskBtn.MouseButton1Click:Connect(function()
        hideKey = not hideKey
        keyMaskBtn.Text = hideKey and "Mostrar" or "Ocultar"
        if Config.ApiKey ~= "" then
            keyBox.Text = hideKey and string.rep("*", math.min(#Config.ApiKey, 24)) or Config.ApiKey
        end
    end)

    -- Botão de Teste da IA
    local testBtn = Instance.new("TextButton")
    testBtn.Size = UDim2.new(1, 0, 0, 34)
    testBtn.BackgroundColor3 = Color3.fromRGB(55, 92, 195)
    testBtn.Font = Enum.Font.GothamBold
    testBtn.Text = "Testar Conexão com a IA"
    testBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
    testBtn.TextSize = 12
    testBtn.Parent = pageGeral
    makeCorner(testBtn, 8)

    local testOutputLabel = Instance.new("TextLabel")
    testOutputLabel.Size = UDim2.new(1, 0, 0, 48)
    testOutputLabel.BackgroundColor3 = Color3.fromRGB(22, 25, 34)
    testOutputLabel.BackgroundTransparency = 0.2
    testOutputLabel.Font = Enum.Font.Gotham
    testOutputLabel.Text = string.format("Ambiente: Chat=%s | HTTP=%s", Environment.getChatSystemType(), Environment.getHttpRequestFunction() and "OK" or "Indisponível")
    testOutputLabel.TextColor3 = Color3.fromRGB(185, 192, 212)
    testOutputLabel.TextSize = 11
    testOutputLabel.TextWrapped = true
    testOutputLabel.Parent = pageGeral
    makeCorner(testOutputLabel, 7)

    testBtn.MouseButton1Click:Connect(function()
        testBtn.Text = "Testando API..."
        task.spawn(function()
            local ok, reply = callbacks.onTestAI()
            if ok then
                testOutputLabel.Text = "Teste OK: " .. reply
                testOutputLabel.TextColor3 = Color3.fromRGB(120, 230, 155)
            else
                testOutputLabel.Text = "Falha no teste: " .. tostring(reply)
                testOutputLabel.TextColor3 = Color3.fromRGB(245, 120, 120)
            end
            testBtn.Text = "Testar Conexão com a IA"
        end)
    end)

    -- ---------------------------------------------------------------------
    -- ABA 2: IA & PERSONA
    -- ---------------------------------------------------------------------
    createSectionLabel(pageIA, "Endpoint da API (Compatível OpenAI)")
    local urlBox = createInputBox(pageIA, "URL da API", Config.ApiUrl, 30)
    urlBox.FocusLost:Connect(function()
        if Security.trim(urlBox.Text) ~= "" then
            Config.ApiUrl = Security.trim(urlBox.Text)
        end
    end)

    createSectionLabel(pageIA, "Modelo de IA (Toque para selecionar ou digite)")
    local modelBox = createInputBox(pageIA, "Ex: openai/gpt-5.4-nano", Config.Model, 30)
    modelBox.FocusLost:Connect(function()
        if Security.trim(modelBox.Text) ~= "" then
            Config.Model = Security.trim(modelBox.Text)
        end
    end)

    local quickModels = {
        "openai/gpt-5.4-nano",
        "openai",
        "deepseek/deepseek-v4.1-flash",
        "google/gemini-2.5-flash-lite",
        "mistralai/mistral-small-4",
    }
    local modelGrid = Instance.new("Frame")
    modelGrid.Size = UDim2.new(1, 0, 0, 56)
    modelGrid.BackgroundTransparency = 1
    modelGrid.Parent = pageIA

    local mGridLayout = Instance.new("UIGridLayout")
    mGridLayout.CellSize = UDim2.new(0.485, 0, 0, 24)
    mGridLayout.CellPadding = UDim2.fromOffset(6, 5)
    mGridLayout.Parent = modelGrid

    for _, mName in ipairs(quickModels) do
        local mBtn = Instance.new("TextButton")
        mBtn.BackgroundColor3 = Color3.fromRGB(30, 34, 46)
        mBtn.Font = Enum.Font.Gotham
        mBtn.Text = mName
        mBtn.TextColor3 = Color3.fromRGB(205, 212, 230)
        mBtn.TextSize = 10
        mBtn.TextTruncate = Enum.TextTruncate.AtEnd
        mBtn.Parent = modelGrid
        makeCorner(mBtn, 6)
        mBtn.MouseButton1Click:Connect(function()
            Config.Model = mName
            modelBox.Text = mName
        end)
    end
    modelGrid.Size = UDim2.new(1, 0, 0, 86)

    -- Temperatura / Limite de Caracteres / Timeout
    createSectionLabel(pageIA, "Temperatura (0-2) | Máx. Caracteres (20-200) | Timeout (s)")
    local paramsRow = Instance.new("Frame")
    paramsRow.Size = UDim2.new(1, 0, 0, 30)
    paramsRow.BackgroundTransparency = 1
    paramsRow.Parent = pageIA

    local tempBox = createInputBox(paramsRow, "Temp", tostring(Config.Temperature), 30)
    tempBox.Size = UDim2.new(0.31, 0, 1, 0)
    local charsBox = createInputBox(paramsRow, "Chars", tostring(Config.MaxChars), 30)
    charsBox.Size = UDim2.new(0.31, 0, 1, 0)
    charsBox.Position = UDim2.new(0.345, 0, 0, 0)
    local timeBox = createInputBox(paramsRow, "Timeout", tostring(Config.Timeout), 30)
    timeBox.Size = UDim2.new(0.31, 0, 1, 0)
    timeBox.Position = UDim2.new(0.69, 0, 0, 0)

    tempBox.FocusLost:Connect(function()
        Config.Temperature = math.clamp(tonumber(tempBox.Text) or Config.Temperature, 0, 2)
        tempBox.Text = tostring(Config.Temperature)
    end)
    charsBox.FocusLost:Connect(function()
        Config.MaxChars = math.clamp(math.floor(tonumber(charsBox.Text) or Config.MaxChars), 20, 200)
        charsBox.Text = tostring(Config.MaxChars)
    end)
    timeBox.FocusLost:Connect(function()
        Config.Timeout = math.clamp(math.floor(tonumber(timeBox.Text) or Config.Timeout), 3, 60)
        timeBox.Text = tostring(Config.Timeout)
    end)

    -- Presets de Personalidade
    createSectionLabel(pageIA, "Personalidade Predefinida")
    local personaGrid = Instance.new("Frame")
    personaGrid.Size = UDim2.new(1, 0, 0, 56)
    personaGrid.BackgroundTransparency = 1
    personaGrid.Parent = pageIA
    local pLayout = Instance.new("UIGridLayout")
    pLayout.CellSize = UDim2.new(0.238, 0, 0, 25)
    pLayout.CellPadding = UDim2.fromOffset(5, 5)
    pLayout.Parent = personaGrid

    local personaNames = { "Amigável", "Engraçada", "Séria", "Sarcástica", "Inteligente", "Extrovertida", "Misteriosa", "Personalizada" }
    local personaButtons = {}

    local function refreshPersonaButtons()
        for name, btn in pairs(personaButtons) do
            local active = (Config.PersonalityPreset == name)
            btn.BackgroundColor3 = active and Color3.fromRGB(65, 105, 225) or Color3.fromRGB(30, 34, 46)
            btn.TextColor3 = active and Color3.fromRGB(255, 255, 255) or Color3.fromRGB(190, 196, 214)
        end
    end

    for _, pName in ipairs(personaNames) do
        local pBtn = Instance.new("TextButton")
        pBtn.Font = Enum.Font.GothamMedium
        pBtn.Text = pName
        pBtn.TextSize = 10
        pBtn.Parent = personaGrid
        makeCorner(pBtn, 6)
        personaButtons[pName] = pBtn
        pBtn.MouseButton1Click:Connect(function()
            Config.PersonalityPreset = pName
            refreshPersonaButtons()
        end)
    end
    refreshPersonaButtons()

    createSectionLabel(pageIA, "Personalidade Personalizada (Opcional - sobrescreve o preset)")
    local customPersonaBox = createInputBox(pageIA, "Descreva como você quer que a IA aja...", Config.CustomPersonality, 64, true)
    customPersonaBox.FocusLost:Connect(function()
        Config.CustomPersonality = customPersonaBox.Text
        if Security.trim(customPersonaBox.Text) ~= "" then
            Config.PersonalityPreset = "Personalizada"
            refreshPersonaButtons()
        end
    end)

    -- ---------------------------------------------------------------------
    -- ABA 3: FILTROS E CONTROLE
    -- ---------------------------------------------------------------------
    createSectionLabel(pageFiltros, "Intervalo entre respostas (segundos) | Chance aleatória (%)")
    local ctrlRow = Instance.new("Frame")
    ctrlRow.Size = UDim2.new(1, 0, 0, 30)
    ctrlRow.BackgroundTransparency = 1
    ctrlRow.Parent = pageFiltros

    local cdBox = createInputBox(ctrlRow, "Intervalo (s)", tostring(Config.CooldownSeconds), 30)
    cdBox.Size = UDim2.new(0.48, 0, 1, 0)
    local chanceBox = createInputBox(ctrlRow, "Chance (%)", tostring(Config.RandomReplyChance), 30)
    chanceBox.Size = UDim2.new(0.48, 0, 1, 0)
    chanceBox.Position = UDim2.new(0.52, 0, 0, 0)

    cdBox.FocusLost:Connect(function()
        Config.CooldownSeconds = math.clamp(tonumber(cdBox.Text) or Config.CooldownSeconds, 1, 120)
        cdBox.Text = tostring(Config.CooldownSeconds)
    end)
    chanceBox.FocusLost:Connect(function()
        Config.RandomReplyChance = math.clamp(math.floor(tonumber(chanceBox.Text) or Config.RandomReplyChance), 0, 100)
        chanceBox.Text = tostring(Config.RandomReplyChance)
    end)

    createSectionLabel(pageFiltros, "Jogadores Ignorados (separados por vírgula)")
    local ignoredBox = createInputBox(pageFiltros, "Ex: Jogador1, Fulano2", "", 34)
    ignoredBox.FocusLost:Connect(function()
        Config.IgnoredPlayers = Security.parseCommaList(ignoredBox.Text)
    end)

    createSectionLabel(pageFiltros, "Palavras Proibidas (separadas por vírgula)")
    local forbiddenBox = createInputBox(pageFiltros, "Ex: palavra1, palavra2", "", 34)
    forbiddenBox.FocusLost:Connect(function()
        Config.ForbiddenWords = Security.parseCommaList(forbiddenBox.Text)
    end)

    local clearHistBtn = Instance.new("TextButton")
    clearHistBtn.Size = UDim2.new(1, 0, 0, 34)
    clearHistBtn.BackgroundColor3 = Color3.fromRGB(130, 62, 68)
    clearHistBtn.Font = Enum.Font.GothamBold
    clearHistBtn.Text = "Limpar Histórico de Conversa"
    clearHistBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
    clearHistBtn.TextSize = 12
    clearHistBtn.Parent = pageFiltros
    makeCorner(clearHistBtn, 8)
    clearHistBtn.MouseButton1Click:Connect(function()
        callbacks.onClearHistory()
    end)

    local cmdHint = Instance.new("TextLabel")
    cmdHint.Size = UDim2.new(1, 0, 0, 38)
    cmdHint.BackgroundTransparency = 1
    cmdHint.Font = Enum.Font.Gotham
    cmdHint.Text = "Comandos rápidos (se digitados por você): !ia on | !ia off | !ia clear"
    cmdHint.TextColor3 = Color3.fromRGB(150, 158, 180)
    cmdHint.TextSize = 11
    cmdHint.TextWrapped = true
    cmdHint.TextXAlignment = Enum.TextXAlignment.Left
    cmdHint.Parent = pageFiltros

    -- ---------------------------------------------------------------------
    -- ABA 4: HISTÓRICO
    -- ---------------------------------------------------------------------
    local logScroll = Instance.new("ScrollingFrame")
    logScroll.Size = UDim2.new(1, 0, 1, -4)
    logScroll.BackgroundColor3 = Color3.fromRGB(12, 14, 19)
    logScroll.BackgroundTransparency = 0.25
    logScroll.BorderSizePixel = 0
    logScroll.ScrollBarThickness = 4
    logScroll.CanvasSize = UDim2.fromOffset(0, 0)
    logScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
    logScroll.Parent = pageHistorico
    makeCorner(logScroll, 8)

    local logLayout = Instance.new("UIListLayout")
    logLayout.Padding = UDim.new(0, 4)
    logLayout.Parent = logScroll

    local logPad = Instance.new("UIPadding")
    logPad.PaddingTop = UDim.new(0, 6)
    logPad.PaddingBottom = UDim.new(0, 6)
    logPad.PaddingLeft = UDim.new(0, 8)
    logPad.PaddingRight = UDim.new(0, 8)
    logPad.Parent = logScroll

    UI.LogCallback = function(tag, text, color)
        if not logScroll or not logScroll.Parent then
            return
        end
        local row = Instance.new("TextLabel")
        row.Size = UDim2.new(1, -6, 0, 0)
        row.AutomaticSize = Enum.AutomaticSize.Y
        row.BackgroundTransparency = 1
        row.Font = Enum.Font.Gotham
        row.Text = string.format("[%s] %s", tag, text)
        row.TextColor3 = color or Color3.fromRGB(220, 224, 236)
        row.TextSize = 11
        row.TextWrapped = true
        row.TextXAlignment = Enum.TextXAlignment.Left
        row.Parent = logScroll

        local children = logScroll:GetChildren()
        if #children > 65 then
            for _, child in ipairs(children) do
                if child:IsA("TextLabel") then
                    child:Destroy()
                    break
                end
            end
        end
    end

    -- Minimizar / Fechar
    local minimized = false
    minBtn.MouseButton1Click:Connect(function()
        minimized = not minimized
        tabBar.Visible = not minimized
        contentHolder.Visible = not minimized
        mainFrame.Size = minimized and UDim2.fromOffset(480, 42) or UDim2.fromOffset(480, 430)
        minBtn.Text = minimized and "+" or "-"
    end)

    closeBtn.MouseButton1Click:Connect(function()
        if globalEnv.__RobloxAutoAI_Cleanup then
            globalEnv.__RobloxAutoAI_Cleanup()
        end
    end)

    UI.Elements.RefreshToggle = refreshToggleVisual
    UI.Elements.StatusDot = statusDot
    UI.Elements.StatusText = statusText
end

function UI.setStatus(status, detail)
    local dot = UI.Elements.StatusDot
    local lbl = UI.Elements.StatusText
    if not dot or not lbl then
        return
    end
    lbl.Text = status
    if status == "Conectado" then
        dot.BackgroundColor3 = Color3.fromRGB(59, 165, 93)
    elseif status == "Erro" then
        dot.BackgroundColor3 = Color3.fromRGB(237, 66, 69)
    else
        dot.BackgroundColor3 = Color3.fromRGB(250, 166, 26)
    end
end

-- =========================================================================
-- MÓDULO 8: PROCESSAMENTO DE MENSAGENS E DECISÃO
-- =========================================================================
local MessageProcessor = {}

local function isMentioningMe(text)
    local lower = Security.normalize(text)
    local userLower = Security.normalize(LocalPlayer.Name)
    local dispLower = Security.normalize(LocalPlayer.DisplayName)

    if userLower ~= "" and lower:find(userLower, 1, true) then
        return true
    end
    if dispLower ~= "" and #dispLower >= 2 and lower:find(dispLower, 1, true) then
        return true
    end
    return false
end

local function isPlayerNearby(player)
    if not player or not player.Character or not LocalPlayer.Character then
        return false
    end
    local rootA = player.Character:FindFirstChild("HumanoidRootPart")
    local rootB = LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
    if rootA and rootB then
        return (rootA.Position - rootB.Position).Magnitude <= Config.MaxProximityStuds
    end
    return false
end

local function shouldReplyToMessage(player, playerName, displayName, text)
    local mentioned = isMentioningMe(text)

    if Config.ResponseMode == "MentionOnly" then
        return mentioned
    elseif Config.ResponseMode == "DirectOnly" then
        if mentioned then
            return true
        end
        local inActiveWindow = (Runtime.LastDirectTalker == playerName) and ((os.clock() - Runtime.LastDirectTime) <= Config.ConversationActiveWindow)
        if inActiveWindow then
            return true
        end
        -- Se o jogador estiver bem próximo e fez uma pergunta ou saudação direta
        if player and isPlayerNearby(player) then
            local lower = Security.normalize(text)
            if lower:find("%?") or lower:match("^oi") or lower:match("^ola") or lower:match("^ei") or lower:match("^mano") or lower:match("^cara") then
                return true
            end
        end
        return false
    elseif Config.ResponseMode == "All" then
        if mentioned then
            return true
        end
        local roll = math.random(1, 100)
        return roll <= Config.RandomReplyChance
    end

    return false
end

function MessageProcessor.handleOwnerCommand(rawText)
    local lower = Security.normalize(rawText)
    local prefix = Security.normalize(Config.CommandPrefix)
    if lower:sub(1, #prefix) ~= prefix then
        return false
    end

    local arg = Security.trim(lower:sub(#prefix + 1))
    if arg == "on" then
        Config.Enabled = true
        if UI.Elements.RefreshToggle then
            UI.Elements.RefreshToggle()
        end
        addLog("Comando", "IA ativada via comando.", Color3.fromRGB(140, 200, 255))
        return true
    elseif arg == "off" then
        Config.Enabled = false
        if UI.Elements.RefreshToggle then
            UI.Elements.RefreshToggle()
        end
        addLog("Comando", "IA desativada via comando.", Color3.fromRGB(140, 200, 255))
        return true
    elseif arg == "clear" then
        ContextManager.clear()
        addLog("Comando", "Histórico limpo via comando.", Color3.fromRGB(140, 200, 255))
        return true
    end
    return false
end

function MessageProcessor.onIncomingChat(data)
    -- data = { UniqueId, Player, UserId, Name, DisplayName, Text }
    if not data or type(data.Text) ~= "string" then
        return
    end

    local cleanInput = Security.trim(data.Text)
    if cleanInput == "" then
        return
    end

    -- Ignora as próprias mensagens (mas processa comandos locais caso tenham passado aqui)
    if data.UserId == LocalPlayer.UserId or data.Name == LocalPlayer.Name then
        MessageProcessor.handleOwnerCommand(cleanInput)
        return
    end

    -- Deduplicação
    local dedupKey = tostring(data.UniqueId or (tostring(data.Name) .. "|" .. cleanInput .. "|" .. tostring(math.floor(os.clock() / 2))))
    if not Security.markMessageProcessed(dedupKey) then
        return
    end

    local speakerLabel = data.DisplayName or data.Name or "Jogador"

    -- Ignora jogadores bloqueados ou palavras proibidas na entrada
    if Security.isPlayerIgnored(data.Name, data.DisplayName) then
        return
    end
    if Security.containsForbiddenWord(cleanInput) then
        return
    end

    -- Salva sempre o contexto do chat recente
    ContextManager.addMessage("user", speakerLabel, cleanInput)
    addLog(speakerLabel, cleanInput, Color3.fromRGB(205, 212, 230))

    if not Config.Enabled then
        return
    end

    -- Rate limit e proteção contra concorrência / loop
    if Runtime.IsGenerating then
        return
    end
    if (os.clock() - Runtime.LastReplyTick) < Config.CooldownSeconds then
        return
    end

    if not shouldReplyToMessage(data.Player, data.Name, data.DisplayName, cleanInput) then
        return
    end

    Runtime.IsGenerating = true

    task.spawn(function()
        local okDone, errRun = pcall(function()
            local apiMessages = ContextManager.buildApiPayloadMessages(nil, nil)
            local ok, rawReply = AIClient.requestCompletion(apiMessages)
            if not ok then
                addLog("Erro API", tostring(rawReply), Color3.fromRGB(245, 115, 115))
                return
            end

            local safeReply, blockReason = Security.sanitizeOutgoingMessage(rawReply)
            if not safeReply then
                addLog("Segurança", tostring(blockReason), Color3.fromRGB(250, 185, 95))
                return
            end

            local sentOk, sendErr = ChatSender.send(safeReply)
            if sentOk then
                Security.recordOutput(safeReply)
                ContextManager.addMessage("assistant", LocalPlayer.DisplayName or LocalPlayer.Name, safeReply)
                Runtime.LastReplyTick = os.clock()
                Runtime.LastDirectTalker = data.Name
                Runtime.LastDirectTime = os.clock()
                addLog("Você (IA)", safeReply, Color3.fromRGB(120, 230, 155))
            else
                addLog("Erro Chat", "Falha ao enviar: " .. tostring(sendErr), Color3.fromRGB(245, 115, 115))
            end
        end)

        if not okDone then
            addLog("Erro Interno", tostring(errRun), Color3.fromRGB(245, 115, 115))
        end

        Runtime.IsGenerating = false
    end)
end

-- =========================================================================
-- MÓDULO 9: CAPTURA DE MENSAGENS DO CHAT
-- =========================================================================
local ChatListener = {}

function ChatListener.start()
    local chatType = Environment.getChatSystemType()

    -- Comandos locais garantidos pelo evento Chatted do dono
    trackConnection(LocalPlayer.Chatted:Connect(function(msg)
        MessageProcessor.handleOwnerCommand(msg)
    end))

    if chatType == "TextChatService" then
        trackConnection(TextChatService.MessageReceived:Connect(function(textChatMessage)
            -- Ignora mensagens de sistema (TextSource nil)
            local source = textChatMessage.TextSource
            if not source then
                return
            end

            local player = Players:GetPlayerByUserId(source.UserId)
            MessageProcessor.onIncomingChat({
                UniqueId = "tcs_" .. tostring(textChatMessage.MessageId),
                Player = player,
                UserId = source.UserId,
                Name = player and player.Name or tostring(source.Name),
                DisplayName = player and player.DisplayName or tostring(source.Name),
                Text = textChatMessage.Text,
            })
        end))
        return
    end

    if chatType == "LegacyChat" then
        local legacyEvents = ReplicatedStorage:FindFirstChild("DefaultChatSystemChatEvents")
        local onDoneFiltering = legacyEvents and legacyEvents:FindFirstChild("OnMessageDoneFiltering")
        if onDoneFiltering and onDoneFiltering:IsA("RemoteEvent") then
            trackConnection(onDoneFiltering.OnClientEvent:Connect(function(messageData)
                if type(messageData) ~= "table" then
                    return
                end
                local speakerName = messageData.FromSpeaker
                if not speakerName or speakerName == "System" then
                    return
                end
                local player = Players:FindFirstChild(speakerName)
                if not player then
                    return
                end

                MessageProcessor.onIncomingChat({
                    UniqueId = "leg_" .. tostring(messageData.ID or (speakerName .. "_" .. tostring(messageData.Time))),
                    Player = player,
                    UserId = player.UserId,
                    Name = player.Name,
                    DisplayName = player.DisplayName,
                    Text = messageData.Message,
                })
            end))
            return
        end
    end

    -- Fallback universal via Player.Chatted
    local function hookPlayer(plr)
        if plr == LocalPlayer then
            return
        end
        trackConnection(plr.Chatted:Connect(function(msg)
            MessageProcessor.onIncomingChat({
                UniqueId = nil,
                Player = plr,
                UserId = plr.UserId,
                Name = plr.Name,
                DisplayName = plr.DisplayName,
                Text = msg,
            })
        end))
    end

    for _, plr in ipairs(Players:GetPlayers()) do
        hookPlayer(plr)
    end
    trackConnection(Players.PlayerAdded:Connect(hookPlayer))
end

-- =========================================================================
-- MÓDULO 10: INICIALIZAÇÃO E ENCERRAMENTO
-- =========================================================================
AIClient.setStatusCallback(function(status, detail)
    UI.setStatus(status, detail)
end)

UI.build({
    onTestAI = function()
        local testMessages = ContextManager.buildApiPayloadMessages("JogadorTeste", "oi, tudo bem por ai?")
        local ok, reply = AIClient.requestCompletion(testMessages)
        if not ok then
            return false, reply
        end
        local cleaned = Security.stripEmojis(reply)
        cleaned = Security.truncateSafely(cleaned, Config.MaxChars)
        addLog("Teste IA", cleaned, Color3.fromRGB(165, 225, 255))
        return true, cleaned
    end,
    onClearHistory = function()
        ContextManager.clear()
        addLog("Sistema", "Histórico de contexto limpo.", Color3.fromRGB(140, 200, 255))
    end,
})

ChatListener.start()
addLog("Sistema", "Inicializado (" .. Environment.getChatSystemType() .. ").", Color3.fromRGB(140, 200, 255))

globalEnv.__RobloxAutoAI_Cleanup = function()
    Config.Enabled = false
    for _, conn in ipairs(Connections) do
        pcall(function()
            conn:Disconnect()
        end)
    end
    table.clear(Connections)
    if UI.Root then
        pcall(function()
            UI.Root:Destroy()
        end)
        UI.Root = nil
    end
end