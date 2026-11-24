--[[
    =========================================================================
    ROBLOX AUTO-CHAT AI (TOKENHARBOR + POLLINATIONS + FISH AUDIO FREE TTS)
    UI Responsiva (Mobile & PC) • Arquitetura Modular
    =========================================================================
]]

-- Limpeza automática caso o script seja executado novamente
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
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
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
-- MÓDULO 1: CONFIGURAÇÕES E PROVEDORES SALVOS INTERNAMENTE
-- =========================================================================
local Config = {
    Enabled = false,
    SendTextInChat = true,

    -- Registro interno de modelos e suas respectivas APIs (oculto da UI)
    ModelList = {
        {
            Id = "mimo-v2.6-flash:free",
            Provider = "TokenHarbor",
            Tag = "TOKENHARBOR • FREE",
            Url = "https://tokenharbor.ai/v1/chat/completions",
            ApiKey = "thk_live_34mgJWfbFIVxLtuqGkyXAMDPtY_7qr_8VYP2UKsINMlvzn6wwZemz5s9fhnFrrmx",
        },
        {
            Id = "community/scriptsnsenses-sys/gpt-6-luna:free",
            Provider = "Pollinations",
            Tag = "POLLINATIONS • FREE",
            Url = "https://gen.pollinations.ai/v1/chat/completions",
            ApiKey = "sk_wFTJzeMtd6JRNKagK4C68tEOo6BcBgrx",
        },
        {
            Id = "community/chirag-gamer/gpt-oss-120b",
            Provider = "Pollinations",
            Tag = "POLLINATIONS • LLM",
            Url = "https://gen.pollinations.ai/v1/chat/completions",
            ApiKey = "sk_wFTJzeMtd6JRNKagK4C68tEOo6BcBgrx",
        },
    },
    Model = "mimo-v2.6-flash:free",
    Temperature = 0.85,
    MaxChars = 160,
    Timeout = 15,

    -- Integração Fish Audio TTS (modo FREE como padrão)
    FishAudio = {
        Enabled = false,
        ApiUrl = "https://api.fish.audio/v1/tts",
        ApiKey = "sk-fish-pJb1Y4LlmEYpAGz0m8ALTOP3zwQy4wfUMhJBzJBf-QU",
        VoiceId = "4e8e6f7ce2b4444bacdc8b9f47922657",
        Model = "s2.1-pro-free", -- Padrão gratuito do Fish Audio
        Format = "mp3",
        Speed = 1.0,
        PlaybackVolume = 2.0,
        Timeout = 20,
        OutputMode = "SoundService", -- "SoundService" | "AudioAPI"
        VoiceBoostEQ = true, -- Realça frequências de voz no alto-falante do celular
        AutoToggleVC = true, -- Tenta desmutar VC durante a fala e remutar após terminar
    },

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
    RandomReplyChance = 35,
    MaxProximityStuds = 45,
    ContextWindow = 12,
    ConversationActiveWindow = 25,

    -- Filtros
    IgnoredPlayers = {},
    ForbiddenWords = {},

    CommandPrefix = "!ia",
}

local function getActiveModelConfig()
    for _, entry in ipairs(Config.ModelList) do
        if entry.Id == Config.Model then
            return entry
        end
    end
    return Config.ModelList[1]
end

-- Estado em runtime
local Runtime = {
    IsGenerating = false,
    IsSpeaking = false,
    ActiveAudioCleanup = nil,
    LastReplyTick = 0,
    LastDirectTalker = nil,
    LastDirectTime = 0,
    ApiStatus = "Aguardando",
    VoiceStatus = "Desativado",
    SentHistory = {},
    ProcessedMessages = {},
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

function Environment.getAudioAssetCapabilities()
    local env = (type(getgenv) == "function" and getgenv()) or _G
    local wf = writefile or (env and env.writefile)
    local gca = getcustomasset or getsynasset or (env and (env.getcustomasset or env.getsynasset))
    local df = delfile or (env and env.delfile)
    return {
        Supported = (type(wf) == "function" and type(gca) == "function"),
        WriteFile = wf,
        GetCustomAsset = gca,
        DelFile = df,
    }
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

    cleaned = cleaned:gsub("[\r\n]+", " ")
    cleaned = cleaned:gsub("[%*_`~]+", "")
    cleaned = cleaned:gsub("%s+", " ")
    return Security.trim(cleaned)
end

-- Impede qualquer vazamento das chaves de API no chat público
function Security.containsSensitiveData(text)
    if type(text) ~= "string" or text == "" then
        return false
    end

    local keysToProtect = { Config.FishAudio.ApiKey }
    for _, m in ipairs(Config.ModelList) do
        table.insert(keysToProtect, m.ApiKey)
    end

    for _, rawKey in ipairs(keysToProtect) do
        local key = Security.trim(rawKey)
        if key ~= "" and #key >= 6 then
            if text:find(key, 1, true) then
                return true
            end
            local prefix = key:sub(1, math.min(10, #key))
            if #prefix >= 6 and text:find(prefix, 1, true) then
                return true
            end
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

    local cut = text:sub(1, limit)
    local lastSpace = cut:match("^(.*)%s+[^%s]*$")
    if lastSpace and #lastSpace >= math.floor(limit * 0.5) then
        cut = lastSpace
    end

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
    Messages = {},
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
-- MÓDULO 5: COMUNICAÇÃO COM A API DE TEXTO (TOKENHARBOR / POLLINATIONS)
-- =========================================================================
local AIClient = {}
local OnStatusChangedCallback = nil

local function updateApiStatus(status, detail)
    Runtime.ApiStatus = status
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
        updateApiStatus("Erro", "Executor sem função HTTP")
        return false, "Ambiente atual não fornece função HTTP no cliente."
    end

    local modelCfg = getActiveModelConfig()

    local headers = {
        ["Content-Type"] = "application/json",
        ["Accept"] = "application/json",
        ["Authorization"] = "Bearer " .. Security.trim(modelCfg.ApiKey),
    }

    local bodyTable = {
        model = modelCfg.Id,
        messages = messages,
        temperature = math.clamp(tonumber(Config.Temperature) or 0.85, 0, 2),
        max_tokens = 120,
        stream = false,
    }

    local okEncode, encodedBody = pcall(HttpService.JSONEncode, HttpService, bodyTable)
    if not okEncode then
        updateApiStatus("Erro", "Falha JSON")
        return false, "Erro ao montar JSON da requisição."
    end

    updateApiStatus("Aguardando", modelCfg.Provider .. "...")

    local done = false
    local reqSuccess = false
    local responseData = nil
    local startTick = os.clock()
    local timeoutLimit = math.clamp(tonumber(Config.Timeout) or 15, 3, 60)

    task.spawn(function()
        local ok, res = pcall(httpRequest, {
            Url = modelCfg.Url,
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
        updateApiStatus("Erro", "Timeout (" .. tostring(timeoutLimit) .. "s)")
        return false, "Tempo máximo de resposta excedido."
    end

    if not reqSuccess or type(responseData) ~= "table" then
        updateApiStatus("Erro", "Falha HTTP")
        return false, "Falha de rede ao chamar " .. modelCfg.Provider .. "."
    end

    local statusCode = tonumber(responseData.StatusCode or responseData.status) or 0
    local rawBody = tostring(responseData.Body or responseData.body or "")

    if statusCode == 401 or statusCode == 403 then
        updateApiStatus("Erro", "HTTP " .. statusCode)
        return false, "Acesso negado em " .. modelCfg.Provider .. " (HTTP " .. statusCode .. ")."
    elseif statusCode == 429 then
        updateApiStatus("Erro", "HTTP 429")
        return false, "Limite de requisições atingido (HTTP 429)."
    elseif statusCode < 200 or statusCode >= 300 then
        updateApiStatus("Erro", "HTTP " .. tostring(statusCode))
        return false, "Erro em " .. modelCfg.Provider .. " (HTTP " .. tostring(statusCode) .. ")."
    end

    local okDecode, decoded = pcall(HttpService.JSONDecode, HttpService, rawBody)
    if okDecode and type(decoded) == "table" then
        if type(decoded.choices) == "table" and decoded.choices[1] then
            local choice = decoded.choices[1]
            local content = (type(choice.message) == "table" and choice.message.content) or choice.text
            if type(content) == "string" and Security.trim(content) ~= "" then
                updateApiStatus("Conectado", modelCfg.Provider)
                return true, content
            end
        elseif type(decoded.content) == "string" and Security.trim(decoded.content) ~= "" then
            updateApiStatus("Conectado", modelCfg.Provider)
            return true, decoded.content
        elseif type(decoded.error) == "table" and decoded.error.message then
            updateApiStatus("Erro", "Erro da API")
            return false, tostring(decoded.error.message)
        end
    elseif Security.trim(rawBody) ~= "" and not rawBody:match("^%s*<") then
        updateApiStatus("Conectado", modelCfg.Provider)
        return true, rawBody
    end

    updateApiStatus("Erro", "Formato inválido")
    return false, "Não foi possível interpretar a resposta da API."
end

-- =========================================================================
-- MÓDULO 6: DIAGNÓSTICO DE VOICE CHAT & FISH AUDIO FREE TTS
-- =========================================================================
local VoiceTTS = {}
local OnVoiceStatusChanged = nil

local function updateVoiceStatus(text, color)
    Runtime.VoiceStatus = text
    if OnVoiceStatusChanged then
        pcall(OnVoiceStatusChanged, text, color)
    end
end

function VoiceTTS.setStatusCallback(cb)
    OnVoiceStatusChanged = cb
end

-- Coleta informações reais do sistema de voz da experiência atual
function VoiceTTS.inspectVoiceEnvironment()
    local isMobile = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
    local deviceTag = isMobile and "Celular" or (UserInputService.TouchEnabled and "Touch/Híbrido" or "PC")

    local hasVCS, vcs = pcall(function()
        return game:GetService("VoiceChatService")
    end)
    local useAudioApi = false
    if hasVCS and vcs then
        pcall(function()
            useAudioApi = vcs.UseAudioApi == Enum.AudioApiRollout.Enabled
        end)
    end

    local adi = LocalPlayer:FindFirstChildOfClass("AudioDeviceInput")
    local adiInfo = adi and (adi.Active and "Ativo" or "Inativo") or "Não encontrado"

    local char = LocalPlayer.Character
    local emitter = char and char:FindFirstChildOfClass("AudioEmitter")
    local emitterInfo = emitter and "Sim" or "Não"

    local vciAccess = "Bloqueado"
    local vciMuted = "?"
    local okVCI, vci = pcall(function()
        return game:GetService("VoiceChatInternal")
    end)
    if okVCI and vci then
        local okRead, paused = pcall(function()
            return vci:IsPublishPaused()
        end)
        if okRead then
            vciAccess = "Liberado"
            vciMuted = paused and "Mutado" or "Aberto"
        end
    end

    local caps = Environment.getAudioAssetCapabilities()
    return {
        Device = deviceTag,
        UseAudioApi = useAudioApi,
        AudioDeviceInput = adiInfo,
        CharacterEmitter = emitterInfo,
        VoiceChatInternal = vciAccess .. " (" .. vciMuted .. ")",
        AssetSupport = caps.Supported and "OK" or "Sem suporte",
        Summary = string.format(
            "Disp: %s | AudioAPI: %s | MicInput: %s | VCI: %s | Emitter: %s | Asset: %s",
            deviceTag,
            useAudioApi and "Sim" or "Não",
            adiInfo,
            vciAccess,
            emitterInfo,
            caps.Supported and "OK" or "Não"
        ),
    }
end

local function setMicrophoneState(unmute)
    if not Config.FishAudio.AutoToggleVC then
        return
    end

    -- 1. Tenta via AudioDeviceInput do jogador local
    local adi = LocalPlayer:FindFirstChildOfClass("AudioDeviceInput")
    if adi then
        pcall(function()
            adi.Muted = not unmute
        end)
    end

    -- 2. Tenta via VoiceChatInternal (quando o executor permite)
    local okVCI, vci = pcall(function()
        return game:GetService("VoiceChatInternal")
    end)
    if okVCI and vci then
        pcall(function()
            vci:PublishPause(not unmute)
        end)
    end
end

function VoiceTTS.stopCurrent()
    if type(Runtime.ActiveAudioCleanup) == "function" then
        pcall(Runtime.ActiveAudioCleanup)
        Runtime.ActiveAudioCleanup = nil
    end
    Runtime.IsSpeaking = false
end

local function playViaSoundService(assetId, onFinished)
    local sound = Instance.new("Sound")
    sound.Name = "FishAudio_TTS_Sound"
    sound.SoundId = assetId
    sound.Volume = math.clamp(tonumber(Config.FishAudio.PlaybackVolume) or 2.0, 0, 5)
    sound.Parent = SoundService

    if Config.FishAudio.VoiceBoostEQ then
        local eq = Instance.new("EqualizerSoundEffect")
        eq.LowGain = -2
        eq.MidGain = 4
        eq.HighGain = 2
        eq.Parent = sound
    end

    local loadStart = os.clock()
    while not sound.IsLoaded and (os.clock() - loadStart) < 3 do
        task.wait(0.05)
    end

    local done = false
    local function cleanup()
        if done then
            return
        end
        done = true
        pcall(function()
            sound:Stop()
            sound:Destroy()
        end)
        onFinished()
    end

    Runtime.ActiveAudioCleanup = cleanup
    sound.Ended:Connect(cleanup)
    sound.Stopped:Connect(cleanup)
    task.delay(25, cleanup)

    sound:Play()
    return true
end

local function playViaAudioAPI(assetId, onFinished)
    local created = {}
    local okSetup = pcall(function()
        local player = Instance.new("AudioPlayer")
        player.AutoLoad = true
        player.Volume = math.clamp(tonumber(Config.FishAudio.PlaybackVolume) or 2.0, 0, 5)
        player.Asset = assetId
        player.Parent = SoundService
        table.insert(created, player)

        local output = Instance.new("AudioDeviceOutput")
        output.Parent = SoundService
        table.insert(created, output)

        local wireOut = Instance.new("Wire")
        wireOut.SourceInstance = player
        wireOut.TargetInstance = output
        wireOut.Parent = player
        table.insert(created, wireOut)

        -- Conecta também no AudioEmitter local do personagem se existir (retorno espacial local)
        local char = LocalPlayer.Character
        local emitter = char and char:FindFirstChildOfClass("AudioEmitter")
        if emitter then
            local wireEm = Instance.new("Wire")
            wireEm.SourceInstance = player
            wireEm.TargetInstance = emitter
            wireEm.Parent = emitter
            table.insert(created, wireEm)
        end

        local loadStart = os.clock()
        while not player.IsReady and (os.clock() - loadStart) < 2.5 do
            task.wait(0.05)
        end

        if not player.IsReady then
            error("AudioPlayer não carregou asset customizado")
        end

        local done = false
        local function cleanup()
            if done then
                return
            end
            done = true
            pcall(function()
                player:Stop()
            end)
            for _, inst in ipairs(created) do
                pcall(function()
                    inst:Destroy()
                end)
            end
            onFinished()
        end

        Runtime.ActiveAudioCleanup = cleanup
        if typeof(player.Ended) == "RBXScriptSignal" then
            player.Ended:Connect(cleanup)
        end

        player:Play()

        -- Watcher de segurança baseado no TimeLength / IsPlaying
        task.spawn(function()
            local waitLimit = math.clamp((player.TimeLength > 0 and player.TimeLength + 1) or 15, 2, 25)
            local startP = os.clock()
            task.wait(0.35)
            while not done and (os.clock() - startP) < waitLimit do
                if not player.IsPlaying then
                    break
                end
                task.wait(0.15)
            end
            cleanup()
        end)
    end)

    if not okSetup then
        for _, inst in ipairs(created) do
            pcall(function()
                inst:Destroy()
            end)
        end
        return false
    end

    return true
end

function VoiceTTS.synthesizeAndSpeak(text)
    local cleanText = Security.stripEmojis(text)
    if cleanText == "" then
        return false, "Texto vazio para síntese"
    end

    local httpRequest = Environment.getHttpRequestFunction()
    if not httpRequest then
        updateVoiceStatus("Erro: Executor sem HTTP", Color3.fromRGB(245, 115, 115))
        return false, "Executor sem função HTTP (request)"
    end

    local audioCaps = Environment.getAudioAssetCapabilities()
    if not audioCaps.Supported then
        updateVoiceStatus("Erro: Falta writefile/getcustomasset", Color3.fromRGB(245, 115, 115))
        return false, "Ambiente sem writefile ou getcustomasset/getsynasset"
    end

    local format = (Config.FishAudio.Format == "wav") and "wav" or "mp3"
    local payloadTable = {
        text = cleanText,
        reference_id = Config.FishAudio.VoiceId,
        format = format,
        normalize = true,
        latency = "balanced",
        prosody = {
            speed = math.clamp(tonumber(Config.FishAudio.Speed) or 1.0, 0.5, 2.0),
            volume = 0,
        },
    }
    if format == "mp3" then
        payloadTable.mp3_bitrate = 128
    else
        payloadTable.sample_rate = 44100
    end

    local okEncode, bodyJson = pcall(HttpService.JSONEncode, HttpService, payloadTable)
    if not okEncode then
        updateVoiceStatus("Erro JSON Fish Audio", Color3.fromRGB(245, 115, 115))
        return false, "Falha ao codificar payload Fish Audio"
    end

    updateVoiceStatus("Gerando voz (" .. Config.FishAudio.Model .. ")...", Color3.fromRGB(245, 166, 35))

    local done = false
    local reqOk = false
    local resData = nil
    local startTick = os.clock()
    local timeoutLimit = math.clamp(tonumber(Config.FishAudio.Timeout) or 20, 5, 60)

    task.spawn(function()
        local ok, res = pcall(httpRequest, {
            Url = Config.FishAudio.ApiUrl,
            Method = "POST",
            Headers = {
                ["Authorization"] = "Bearer " .. Config.FishAudio.ApiKey,
                ["Content-Type"] = "application/json",
                ["model"] = Config.FishAudio.Model,
            },
            Body = bodyJson,
        })
        if not done then
            done = true
            reqOk = ok
            resData = res
        end
    end)

    while not done and (os.clock() - startTick) < timeoutLimit do
        task.wait(0.05)
    end

    if not done then
        done = true
        updateVoiceStatus("Timeout no Fish Audio", Color3.fromRGB(245, 115, 115))
        return false, "Tempo esgotado no Fish Audio"
    end

    if not reqOk or type(resData) ~= "table" then
        updateVoiceStatus("Erro de rede Fish Audio", Color3.fromRGB(245, 115, 115))
        return false, "Falha HTTP ao conectar com Fish Audio"
    end

    local code = tonumber(resData.StatusCode or resData.status) or 0
    local audioBytes = resData.Body or resData.body or ""

    if code == 401 or code == 403 then
        updateVoiceStatus("Fish Audio: Chave recusada (" .. code .. ")", Color3.fromRGB(245, 115, 115))
        return false, "Chave Fish Audio recusada (HTTP " .. code .. ")"
    elseif code == 402 then
        updateVoiceStatus("Fish Audio: Sem créditos (402)", Color3.fromRGB(245, 115, 115))
        return false, "Saldo insuficiente no Fish Audio (tente s2.1-pro-free)"
    elseif code < 200 or code >= 300 then
        updateVoiceStatus("Fish Audio HTTP " .. tostring(code), Color3.fromRGB(245, 115, 115))
        return false, "Erro HTTP " .. tostring(code) .. " no Fish Audio"
    end

    if type(audioBytes) ~= "string" or #audioBytes < 128 then
        updateVoiceStatus("Áudio vazio retornado", Color3.fromRGB(245, 115, 115))
        return false, "Resposta de áudio vazia ou inválida"
    end

    local fileName = string.format("fish_tts_%d.%s", math.floor(os.clock() * 1000) % 100000, format)
    local okWrite, errWrite = pcall(audioCaps.WriteFile, fileName, audioBytes)
    if not okWrite then
        updateVoiceStatus("Erro ao gravar arquivo local", Color3.fromRGB(245, 115, 115))
        return false, "Falha em writefile: " .. tostring(errWrite)
    end

    local okAsset, assetId = pcall(audioCaps.GetCustomAsset, fileName)
    if not okAsset or type(assetId) ~= "string" or assetId == "" then
        if audioCaps.DelFile then
            pcall(audioCaps.DelFile, fileName)
        end
        updateVoiceStatus("Erro em getcustomasset", Color3.fromRGB(245, 115, 115))
        return false, "Falha ao converter arquivo em asset de áudio"
    end

    VoiceTTS.stopCurrent()
    Runtime.IsSpeaking = true
    setMicrophoneState(true)
    updateVoiceStatus("Falando agora...", Color3.fromRGB(46, 204, 113))

    local function onPlaybackDone()
        setMicrophoneState(false)
        Runtime.IsSpeaking = false
        Runtime.ActiveAudioCleanup = nil
        if audioCaps.DelFile then
            task.delay(0.25, function()
                pcall(audioCaps.DelFile, fileName)
            end)
        end
        updateVoiceStatus(Config.FishAudio.Enabled and "Pronto (Áudio Ativo)" or "Desativado", Color3.fromRGB(154, 163, 189))
    end

    local started = false
    if Config.FishAudio.OutputMode == "AudioAPI" then
        started = playViaAudioAPI(assetId, onPlaybackDone)
    end
    if not started then
        -- Fallback automático para SoundService caso AudioPlayer não aceite asset customizado
        playViaSoundService(assetId, onPlaybackDone)
    end

    return true, "Áudio reproduzido"
end

-- =========================================================================
-- MÓDULO 7: ENVIO DE RESPOSTAS NO CHAT DE TEXTO
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
-- MÓDULO 8: INTERFACE GRÁFICA MODERNA E RESPONSIVA (MOBILE & PC)
-- =========================================================================
local UI = {
    Root = nil,
    LogCallback = nil,
    Elements = {},
}

local Theme = {
    BgDark = Color3.fromRGB(13, 15, 22),
    BgGradEnd = Color3.fromRGB(21, 25, 38),
    Card = Color3.fromRGB(23, 27, 39),
    CardHover = Color3.fromRGB(30, 35, 50),
    Input = Color3.fromRGB(16, 19, 28),
    Stroke = Color3.fromRGB(64, 75, 105),
    Accent = Color3.fromRGB(92, 124, 250),
    Success = Color3.fromRGB(46, 204, 113),
    Danger = Color3.fromRGB(224, 79, 95),
    Warning = Color3.fromRGB(245, 166, 35),
    TextMain = Color3.fromRGB(241, 243, 249),
    TextMuted = Color3.fromRGB(154, 163, 189),
}

local function addLog(tag, text, color)
    if UI.LogCallback then
        pcall(UI.LogCallback, tag, text, color)
    end
end

local function tweenProp(inst, props, duration)
    local info = TweenInfo.new(duration or 0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
    TweenService:Create(inst, info, props):Play()
end

local function makeCorner(parent, radius)
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, radius or 10)
    c.Parent = parent
    return c
end

local function makeStroke(parent, color, thickness, transparency)
    local s = Instance.new("UIStroke")
    s.Color = color or Theme.Stroke
    s.Thickness = thickness or 1
    s.Transparency = transparency or 0.45
    s.Parent = parent
    return s
end

local function createCard(parent, titleText)
    local card = Instance.new("Frame")
    card.Size = UDim2.new(1, 0, 0, 0)
    card.AutomaticSize = Enum.AutomaticSize.Y
    card.BackgroundColor3 = Theme.Card
    card.BackgroundTransparency = 0.08
    card.Parent = parent
    makeCorner(card, 10)
    makeStroke(card, Theme.Stroke, 1, 0.5)

    local pad = Instance.new("UIPadding")
    pad.PaddingTop = UDim.new(0, 10)
    pad.PaddingBottom = UDim.new(0, 10)
    pad.PaddingLeft = UDim.new(0, 12)
    pad.PaddingRight = UDim.new(0, 12)
    pad.Parent = card

    local layout = Instance.new("UIListLayout")
    layout.Padding = UDim.new(0, 8)
    layout.SortOrder = Enum.SortOrder.LayoutOrder
    layout.Parent = card

    if titleText and titleText ~= "" then
        local title = Instance.new("TextLabel")
        title.Size = UDim2.new(1, 0, 0, 16)
        title.BackgroundTransparency = 1
        title.Font = Enum.Font.GothamBold
        title.Text = string.upper(titleText)
        title.TextColor3 = Theme.TextMuted
        title.TextSize = 10
        title.TextXAlignment = Enum.TextXAlignment.Left
        title.Parent = card
    end

    return card
end

local function createSwitchRow(parent, labelText, subText, initialState, onToggle)
    local row = Instance.new("TextButton")
    row.Size = UDim2.new(1, 0, 0, subText and 42 or 34)
    row.BackgroundTransparency = 1
    row.Text = ""
    row.AutoButtonColor = false
    row.Parent = parent

    local lbl = Instance.new("TextLabel")
    lbl.Size = UDim2.new(1, -56, 0, 18)
    lbl.Position = UDim2.fromOffset(0, subText and 3 or 8)
    lbl.BackgroundTransparency = 1
    lbl.Font = Enum.Font.GothamBold
    lbl.Text = labelText
    lbl.TextColor3 = Theme.TextMain
    lbl.TextSize = 12
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    lbl.Parent = row

    if subText then
        local sub = Instance.new("TextLabel")
        sub.Size = UDim2.new(1, -56, 0, 14)
        sub.Position = UDim2.fromOffset(0, 22)
        sub.BackgroundTransparency = 1
        sub.Font = Enum.Font.Gotham
        sub.Text = subText
        sub.TextColor3 = Theme.TextMuted
        sub.TextSize = 10
        sub.TextXAlignment = Enum.TextXAlignment.Left
        sub.TextTruncate = Enum.TextTruncate.AtEnd
        sub.Parent = row
    end

    local track = Instance.new("Frame")
    track.Size = UDim2.fromOffset(44, 24)
    track.Position = UDim2.new(1, -44, 0.5, -12)
    track.BackgroundColor3 = initialState and Theme.Success or Color3.fromRGB(48, 54, 72)
    track.Parent = row
    makeCorner(track, 12)

    local knob = Instance.new("Frame")
    knob.Size = UDim2.fromOffset(18, 18)
    knob.Position = initialState and UDim2.fromOffset(23, 3) or UDim2.fromOffset(3, 3)
    knob.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    knob.Parent = track
    makeCorner(knob, 9)

    local state = initialState == true
    local function setStateVisual(newState)
        state = newState == true
        tweenProp(track, { BackgroundColor3 = state and Theme.Success or Color3.fromRGB(48, 54, 72) }, 0.16)
        tweenProp(knob, { Position = state and UDim2.fromOffset(23, 3) or UDim2.fromOffset(3, 3) }, 0.16)
    end

    row.MouseButton1Click:Connect(function()
        setStateVisual(not state)
        onToggle(state)
    end)

    return { SetVisual = setStateVisual }
end

local function createInputBox(parent, placeholder, defaultText, height, multiline)
    local box = Instance.new("TextBox")
    box.Size = UDim2.new(1, 0, 0, height or 32)
    box.BackgroundColor3 = Theme.Input
    box.ClearTextOnFocus = false
    box.Font = Enum.Font.Gotham
    box.PlaceholderText = placeholder
    box.PlaceholderColor3 = Color3.fromRGB(100, 108, 130)
    box.Text = defaultText or ""
    box.TextColor3 = Theme.TextMain
    box.TextSize = 12
    box.TextXAlignment = Enum.TextXAlignment.Left
    box.MultiLine = multiline == true
    box.TextWrapped = multiline == true
    box.TextYAlignment = multiline and Enum.TextYAlignment.Top or Enum.TextYAlignment.Center
    box.Parent = parent
    makeCorner(box, 8)
    makeStroke(box, Color3.fromRGB(48, 55, 76), 1, 0.4)

    local pad = Instance.new("UIPadding")
    pad.PaddingLeft = UDim.new(0, 10)
    pad.PaddingRight = UDim.new(0, 10)
    pad.PaddingTop = UDim.new(0, multiline and 8 or 0)
    pad.Parent = box

    return box
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

    -- Cálculo responsivo para caber bem no celular e no PC
    local function getWindowSize()
        local cam = workspace.CurrentCamera
        local vp = cam and cam.ViewportSize or Vector2.new(800, 600)
        local w = math.clamp(vp.X - 24, 315, 480)
        local h = math.clamp(vp.Y - 36, 320, 455)
        return w, h
    end

    local winW, winH = getWindowSize()

    local mainFrame = Instance.new("Frame")
    mainFrame.Name = "MainFrame"
    mainFrame.Size = UDim2.fromOffset(winW, winH)
    mainFrame.Position = UDim2.new(0.5, -math.floor(winW / 2), 0.5, -math.floor(winH / 2))
    mainFrame.BackgroundColor3 = Theme.BgDark
    mainFrame.BackgroundTransparency = 0.06
    mainFrame.ClipsDescendants = true
    mainFrame.Parent = screenGui
    makeCorner(mainFrame, 14)
    makeStroke(mainFrame, Color3.fromRGB(82, 96, 136), 1.2, 0.35)

    local bgGrad = Instance.new("UIGradient")
    bgGrad.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Theme.BgDark),
        ColorSequenceKeypoint.new(1, Theme.BgGradEnd),
    })
    bgGrad.Rotation = 135
    bgGrad.Parent = mainFrame

    -- Cabeçalho
    local topBar = Instance.new("Frame")
    topBar.Name = "TopBar"
    topBar.Size = UDim2.new(1, 0, 0, 46)
    topBar.BackgroundColor3 = Color3.fromRGB(20, 23, 34)
    topBar.BackgroundTransparency = 0.12
    topBar.BorderSizePixel = 0
    topBar.Parent = mainFrame

    local accentLine = Instance.new("Frame")
    accentLine.Size = UDim2.new(1, 0, 0, 2)
    accentLine.Position = UDim2.new(0, 0, 1, -2)
    accentLine.BorderSizePixel = 0
    accentLine.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    accentLine.Parent = topBar
    local lineGrad = Instance.new("UIGradient")
    lineGrad.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Theme.Accent),
        ColorSequenceKeypoint.new(1, Theme.Success),
    })
    lineGrad.Parent = accentLine

    local titleLabel = Instance.new("TextLabel")
    titleLabel.Size = UDim2.new(1, -180, 0, 20)
    titleLabel.Position = UDim2.fromOffset(14, 6)
    titleLabel.BackgroundTransparency = 1
    titleLabel.Font = Enum.Font.GothamBold
    titleLabel.Text = "Assistente IA"
    titleLabel.TextColor3 = Theme.TextMain
    titleLabel.TextSize = 14
    titleLabel.TextXAlignment = Enum.TextXAlignment.Left
    titleLabel.Parent = topBar

    local subTitleLabel = Instance.new("TextLabel")
    subTitleLabel.Size = UDim2.new(1, -180, 0, 14)
    subTitleLabel.Position = UDim2.fromOffset(14, 24)
    subTitleLabel.BackgroundTransparency = 1
    subTitleLabel.Font = Enum.Font.Gotham
    subTitleLabel.Text = "TokenHarbor • Pollinations • Fish TTS"
    subTitleLabel.TextColor3 = Theme.TextMuted
    subTitleLabel.TextSize = 10
    subTitleLabel.TextXAlignment = Enum.TextXAlignment.Left
    subTitleLabel.TextTruncate = Enum.TextTruncate.AtEnd
    subTitleLabel.Parent = topBar

    -- Pílula de status da API
    local statusBadge = Instance.new("Frame")
    statusBadge.Size = UDim2.fromOffset(102, 24)
    statusBadge.Position = UDim2.new(1, -172, 0.5, -12)
    statusBadge.BackgroundColor3 = Color3.fromRGB(28, 33, 48)
    statusBadge.Parent = topBar
    makeCorner(statusBadge, 12)
    makeStroke(statusBadge, Theme.Stroke, 1, 0.5)

    local statusDot = Instance.new("Frame")
    statusDot.Size = UDim2.fromOffset(8, 8)
    statusDot.Position = UDim2.new(0, 9, 0.5, -4)
    statusDot.BackgroundColor3 = Theme.Warning
    statusDot.BorderSizePixel = 0
    statusDot.Parent = statusBadge
    makeCorner(statusDot, 4)

    local statusText = Instance.new("TextLabel")
    statusText.Size = UDim2.new(1, -24, 1, 0)
    statusText.Position = UDim2.fromOffset(22, 0)
    statusText.BackgroundTransparency = 1
    statusText.Font = Enum.Font.GothamMedium
    statusText.Text = "Aguardando"
    statusText.TextColor3 = Theme.TextMain
    statusText.TextSize = 10
    statusText.TextXAlignment = Enum.TextXAlignment.Left
    statusText.TextTruncate = Enum.TextTruncate.AtEnd
    statusText.Parent = statusBadge

    -- Botão rápido de energia (útil principalmente quando minimizado no celular)
    local miniPowerBtn = Instance.new("TextButton")
    miniPowerBtn.Size = UDim2.fromOffset(58, 24)
    miniPowerBtn.Position = UDim2.new(1, -130, 0.5, -12)
    miniPowerBtn.BackgroundColor3 = Theme.Danger
    miniPowerBtn.Font = Enum.Font.GothamBold
    miniPowerBtn.Text = "OFF"
    miniPowerBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
    miniPowerBtn.TextSize = 10
    miniPowerBtn.Visible = false
    miniPowerBtn.Parent = topBar
    makeCorner(miniPowerBtn, 12)

    local minBtn = Instance.new("TextButton")
    minBtn.Size = UDim2.fromOffset(28, 26)
    minBtn.Position = UDim2.new(1, -66, 0.5, -13)
    minBtn.BackgroundColor3 = Color3.fromRGB(36, 42, 58)
    minBtn.Font = Enum.Font.GothamBold
    minBtn.Text = "—"
    minBtn.TextColor3 = Theme.TextMain
    minBtn.TextSize = 13
    minBtn.Parent = topBar
    makeCorner(minBtn, 8)

    local closeBtn = Instance.new("TextButton")
    closeBtn.Size = UDim2.fromOffset(28, 26)
    closeBtn.Position = UDim2.new(1, -34, 0.5, -13)
    closeBtn.BackgroundColor3 = Theme.Danger
    closeBtn.Font = Enum.Font.GothamBold
    closeBtn.Text = "×"
    closeBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
    closeBtn.TextSize = 16
    closeBtn.Parent = topBar
    makeCorner(closeBtn, 8)

    -- Sistema de arrastar seguro para Toque (Mobile) e Mouse (PC)
    local dragging = false
    local dragInput = nil
    local dragStart, startPos
    trackConnection(topBar.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            dragInput = input
            dragStart = input.Position
            startPos = mainFrame.Position
        end
    end))
    trackConnection(UserInputService.InputChanged:Connect(function(input)
        if dragging and (input == dragInput or input.UserInputType == Enum.UserInputType.MouseMovement) then
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
        if input == dragInput or input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = false
            dragInput = nil
        end
    end))

    -- Barra de Abas moderna
    local tabBar = Instance.new("Frame")
    tabBar.Size = UDim2.new(1, -20, 0, 34)
    tabBar.Position = UDim2.fromOffset(10, 52)
    tabBar.BackgroundColor3 = Color3.fromRGB(19, 22, 32)
    tabBar.Parent = mainFrame
    makeCorner(tabBar, 10)
    makeStroke(tabBar, Theme.Stroke, 1, 0.55)

    local tabLayout = Instance.new("UIListLayout")
    tabLayout.FillDirection = Enum.FillDirection.Horizontal
    tabLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
    tabLayout.VerticalAlignment = Enum.VerticalAlignment.Center
    tabLayout.Padding = UDim.new(0, 4)
    tabLayout.Parent = tabBar

    local contentHolder = Instance.new("Frame")
    contentHolder.Size = UDim2.new(1, -20, 1, -98)
    contentHolder.Position = UDim2.fromOffset(10, 92)
    contentHolder.BackgroundTransparency = 1
    contentHolder.Parent = mainFrame

    local tabs = {}
    local tabButtons = {}

    local function createTab(name)
        local btn = Instance.new("TextButton")
        btn.Size = UDim2.new(0.188, 0, 1, -6)
        btn.BackgroundColor3 = Theme.Accent
        btn.BackgroundTransparency = 1
        btn.Font = Enum.Font.GothamBold
        btn.Text = name
        btn.TextColor3 = Theme.TextMuted
        btn.TextSize = 10
        btn.TextTruncate = Enum.TextTruncate.AtEnd
        btn.Parent = tabBar
        makeCorner(btn, 7)

        local page = Instance.new("ScrollingFrame")
        page.Size = UDim2.fromScale(1, 1)
        page.BackgroundTransparency = 1
        page.BorderSizePixel = 0
        page.ScrollBarThickness = 3
        page.ScrollBarImageColor3 = Theme.Accent
        page.CanvasSize = UDim2.fromOffset(0, 0)
        page.AutomaticCanvasSize = Enum.AutomaticSize.Y
        page.Visible = false
        page.Parent = contentHolder

        local layout = Instance.new("UIListLayout")
        layout.Padding = UDim.new(0, 10)
        layout.SortOrder = Enum.SortOrder.LayoutOrder
        layout.Parent = page

        local pad = Instance.new("UIPadding")
        pad.PaddingRight = UDim.new(0, 5)
        pad.PaddingBottom = UDim.new(0, 10)
        pad.Parent = page

        tabs[name] = page
        tabButtons[name] = btn

        btn.MouseButton1Click:Connect(function()
            for tName, tPage in pairs(tabs) do
                local active = (tName == name)
                tPage.Visible = active
                tweenProp(tabButtons[tName], {
                    BackgroundTransparency = active and 0.1 or 1,
                    TextColor3 = active and Color3.fromRGB(255, 255, 255) or Theme.TextMuted,
                }, 0.16)
            end
        end)

        return page
    end

    local pageGeral = createTab("Geral")
    local pageIA = createTab("Persona")
    local pageVoz = createTab("Áudio / Voz")
    local pageFiltros = createTab("Filtros")
    local pageHistorico = createTab("Histórico")

    pageGeral.Visible = true
    tabButtons["Geral"].BackgroundTransparency = 0.1
    tabButtons["Geral"].TextColor3 = Color3.fromRGB(255, 255, 255)

    -- ---------------------------------------------------------------------
    -- ABA 1: GERAL
    -- ---------------------------------------------------------------------
    local cardMainCtrl = createCard(pageGeral, "Controle Principal")
    local mainSwitch
    local function syncPowerState()
        if mainSwitch then
            mainSwitch.SetVisual(Config.Enabled)
        end
        miniPowerBtn.BackgroundColor3 = Config.Enabled and Theme.Success or Theme.Danger
        miniPowerBtn.Text = Config.Enabled and "ON" or "OFF"
    end

    mainSwitch = createSwitchRow(
        cardMainCtrl,
        "Ativar IA no Chat",
        "Lê mensagens e responde naturalmente sem emojis",
        Config.Enabled,
        function(val)
            Config.Enabled = val
            syncPowerState()
            addLog("Sistema", Config.Enabled and "IA ativada." or "IA desativada.", Color3.fromRGB(140, 200, 255))
        end
    )

    miniPowerBtn.MouseButton1Click:Connect(function()
        Config.Enabled = not Config.Enabled
        syncPowerState()
        addLog("Sistema", Config.Enabled and "IA ativada." or "IA desativada.", Color3.fromRGB(140, 200, 255))
    end)

    -- Cards de Modelos (sem campos de API/URL)
    local cardModels = createCard(pageGeral, "Selecionar Modelo de IA")
    local modelCards = {}

    local function refreshModelCards()
        for id, item in pairs(modelCards) do
            local active = (Config.Model == id)
            tweenProp(item.Frame, {
                BackgroundColor3 = active and Color3.fromRGB(36, 48, 86) or Theme.Input,
            }, 0.16)
            item.Stroke.Color = active and Theme.Accent or Color3.fromRGB(48, 55, 76)
            item.Stroke.Transparency = active and 0.1 or 0.5
            item.Badge.BackgroundColor3 = active and Theme.Accent or Color3.fromRGB(40, 46, 65)
        end
    end

    for _, mInfo in ipairs(Config.ModelList) do
        local mBtn = Instance.new("TextButton")
        mBtn.Size = UDim2.new(1, 0, 0, 38)
        mBtn.BackgroundColor3 = Theme.Input
        mBtn.Text = ""
        mBtn.AutoButtonColor = false
        mBtn.Parent = cardModels
        makeCorner(mBtn, 8)
        local mStroke = makeStroke(mBtn, Color3.fromRGB(48, 55, 76), 1, 0.5)

        local mTitle = Instance.new("TextLabel")
        mTitle.Size = UDim2.new(1, -132, 1, 0)
        mTitle.Position = UDim2.fromOffset(10, 0)
        mTitle.BackgroundTransparency = 1
        mTitle.Font = Enum.Font.GothamBold
        mTitle.Text = mInfo.Id
        mTitle.TextColor3 = Theme.TextMain
        mTitle.TextSize = 11
        mTitle.TextXAlignment = Enum.TextXAlignment.Left
        mTitle.TextTruncate = Enum.TextTruncate.AtEnd
        mTitle.Parent = mBtn

        local mBadge = Instance.new("TextLabel")
        mBadge.Size = UDim2.fromOffset(116, 20)
        mBadge.Position = UDim2.new(1, -124, 0.5, -10)
        mBadge.BackgroundColor3 = Color3.fromRGB(40, 46, 65)
        mBadge.Font = Enum.Font.GothamBold
        mBadge.Text = mInfo.Tag
        mBadge.TextColor3 = Color3.fromRGB(245, 247, 255)
        mBadge.TextSize = 9
        mBadge.Parent = mBtn
        makeCorner(mBadge, 6)

        modelCards[mInfo.Id] = { Frame = mBtn, Stroke = mStroke, Badge = mBadge }
        mBtn.MouseButton1Click:Connect(function()
            Config.Model = mInfo.Id
            refreshModelCards()
            addLog("Modelo", "Selecionado: " .. mInfo.Id .. " (" .. mInfo.Provider .. ")", Color3.fromRGB(165, 210, 255))
        end)
    end
    refreshModelCards()

    -- Modo de Resposta
    local cardMode = createCard(pageGeral, "Modo de Resposta")
    local modeRow = Instance.new("Frame")
    modeRow.Size = UDim2.new(1, 0, 0, 32)
    modeRow.BackgroundTransparency = 1
    modeRow.Parent = cardMode

    local modeLayout = Instance.new("UIListLayout")
    modeLayout.FillDirection = Enum.FillDirection.Horizontal
    modeLayout.Padding = UDim.new(0, 6)
    modeLayout.Parent = modeRow

    local modeButtons = {}
    local modeList = {
        { id = "MentionOnly", label = "Mencionado" },
        { id = "DirectOnly", label = "Falando Comigo" },
        { id = "All", label = "Todos" },
    }

    local function refreshModeButtons()
        for id, btn in pairs(modeButtons) do
            local active = (Config.ResponseMode == id)
            tweenProp(btn, {
                BackgroundColor3 = active and Theme.Accent or Theme.Input,
                TextColor3 = active and Color3.fromRGB(255, 255, 255) or Theme.TextMuted,
            }, 0.15)
        end
    end

    for _, item in ipairs(modeList) do
        local btn = Instance.new("TextButton")
        btn.Size = UDim2.new(0.32, 0, 1, 0)
        btn.Font = Enum.Font.GothamBold
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

    -- Teste rápido
    local cardTest = createCard(pageGeral, "Teste Rápido")
    local testBtn = Instance.new("TextButton")
    testBtn.Size = UDim2.new(1, 0, 0, 34)
    testBtn.BackgroundColor3 = Theme.Accent
    testBtn.Font = Enum.Font.GothamBold
    testBtn.Text = "Testar Resposta da IA"
    testBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
    testBtn.TextSize = 12
    testBtn.Parent = cardTest
    makeCorner(testBtn, 8)

    local testOutputLabel = Instance.new("TextLabel")
    testOutputLabel.Size = UDim2.new(1, 0, 0, 38)
    testOutputLabel.BackgroundColor3 = Theme.Input
    testOutputLabel.Font = Enum.Font.Gotham
    testOutputLabel.Text = string.format(
        "Chat: %s | HTTP: %s",
        Environment.getChatSystemType(),
        Environment.getHttpRequestFunction() and "OK" or "Indisponível"
    )
    testOutputLabel.TextColor3 = Theme.TextMuted
    testOutputLabel.TextSize = 11
    testOutputLabel.TextWrapped = true
    testOutputLabel.Parent = cardTest
    makeCorner(testOutputLabel, 8)

    testBtn.MouseButton1Click:Connect(function()
        testBtn.Text = "Consultando modelo..."
        task.spawn(function()
            local ok, reply = callbacks.onTestAI()
            if ok then
                testOutputLabel.Text = "OK: " .. reply
                testOutputLabel.TextColor3 = Theme.Success
            else
                testOutputLabel.Text = "Falha: " .. tostring(reply)
                testOutputLabel.TextColor3 = Theme.Danger
            end
            testBtn.Text = "Testar Resposta da IA"
        end)
    end)

    -- ---------------------------------------------------------------------
    -- ABA 2: PERSONA & PARÂMETROS
    -- ---------------------------------------------------------------------
    local cardParams = createCard(pageIA, "Parâmetros da Resposta")
    local paramLabels = Instance.new("TextLabel")
    paramLabels.Size = UDim2.new(1, 0, 0, 14)
    paramLabels.BackgroundTransparency = 1
    paramLabels.Font = Enum.Font.Gotham
    paramLabels.Text = "Temperatura (0-2)        Máx. Caracteres        Timeout (s)"
    paramLabels.TextColor3 = Theme.TextMuted
    paramLabels.TextSize = 10
    paramLabels.TextXAlignment = Enum.TextXAlignment.Left
    paramLabels.Parent = cardParams

    local paramsRow = Instance.new("Frame")
    paramsRow.Size = UDim2.new(1, 0, 0, 32)
    paramsRow.BackgroundTransparency = 1
    paramsRow.Parent = cardParams

    local tempBox = createInputBox(paramsRow, "Temp", tostring(Config.Temperature), 32)
    tempBox.Size = UDim2.new(0.31, 0, 1, 0)
    local charsBox = createInputBox(paramsRow, "Chars", tostring(Config.MaxChars), 32)
    charsBox.Size = UDim2.new(0.31, 0, 1, 0)
    charsBox.Position = UDim2.new(0.345, 0, 0, 0)
    local timeBox = createInputBox(paramsRow, "Timeout", tostring(Config.Timeout), 32)
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

    local cardPersona = createCard(pageIA, "Personalidade")
    local personaGrid = Instance.new("Frame")
    personaGrid.Size = UDim2.new(1, 0, 0, 58)
    personaGrid.BackgroundTransparency = 1
    personaGrid.Parent = cardPersona

    local pLayout = Instance.new("UIGridLayout")
    pLayout.CellSize = UDim2.new(0.238, 0, 0, 26)
    pLayout.CellPadding = UDim2.fromOffset(5, 5)
    pLayout.Parent = personaGrid

    local personaNames = { "Amigável", "Engraçada", "Séria", "Sarcástica", "Inteligente", "Extrovertida", "Misteriosa", "Personalizada" }
    local personaButtons = {}

    local function refreshPersonaButtons()
        for name, btn in pairs(personaButtons) do
            local active = (Config.PersonalityPreset == name)
            tweenProp(btn, {
                BackgroundColor3 = active and Theme.Accent or Theme.Input,
                TextColor3 = active and Color3.fromRGB(255, 255, 255) or Theme.TextMuted,
            }, 0.15)
        end
    end

    for _, pName in ipairs(personaNames) do
        local pBtn = Instance.new("TextButton")
        pBtn.Font = Enum.Font.GothamBold
        pBtn.Text = pName
        pBtn.TextSize = 10
        pBtn.Parent = personaGrid
        makeCorner(pBtn, 7)
        personaButtons[pName] = pBtn
        pBtn.MouseButton1Click:Connect(function()
            Config.PersonalityPreset = pName
            refreshPersonaButtons()
        end)
    end
    refreshPersonaButtons()

    local customPersonaBox = createInputBox(cardPersona, "Personalidade personalizada (opcional)...", Config.CustomPersonality, 72, true)
    customPersonaBox.FocusLost:Connect(function()
        Config.CustomPersonality = customPersonaBox.Text
        if Security.trim(customPersonaBox.Text) ~= "" then
            Config.PersonalityPreset = "Personalizada"
            refreshPersonaButtons()
        end
    end)

    -- ---------------------------------------------------------------------
    -- ABA 3: ÁUDIO / VOZ (FISH AUDIO FREE + DIAGNÓSTICO VC)
    -- ---------------------------------------------------------------------
    local cardVoiceMain = createCard(pageVoz, "Resposta por Áudio (Fish Audio Free)")

    createSwitchRow(
        cardVoiceMain,
        "Ativar Resposta por Áudio",
        "Gera voz via Fish Audio (s2.1-pro-free) quando a IA responder",
        Config.FishAudio.Enabled,
        function(val)
            Config.FishAudio.Enabled = val
            updateVoiceStatus(val and "Pronto (Áudio Ativo)" or "Desativado", val and Theme.Success or Theme.TextMuted)
        end
    )

    createSwitchRow(
        cardVoiceMain,
        "Enviar texto no chat também",
        "Desative se quiser tentar responder apenas pelo áudio",
        Config.SendTextInChat,
        function(val)
            Config.SendTextInChat = val
        end
    )

    local voiceStatusLbl = Instance.new("TextLabel")
    voiceStatusLbl.Size = UDim2.new(1, 0, 0, 24)
    voiceStatusLbl.BackgroundColor3 = Theme.Input
    voiceStatusLbl.Font = Enum.Font.GothamMedium
    voiceStatusLbl.Text = "Status Áudio: Desativado"
    voiceStatusLbl.TextColor3 = Theme.TextMuted
    voiceStatusLbl.TextSize = 11
    voiceStatusLbl.Parent = cardVoiceMain
    makeCorner(voiceStatusLbl, 7)

    -- Card Motor & Saída de Áudio
    local cardVoiceEngine = createCard(pageVoz, "Saída & Ajustes de Voz")

    -- Modo de saída: SoundService vs AudioAPI
    local outModeRow = Instance.new("Frame")
    outModeRow.Size = UDim2.new(1, 0, 0, 30)
    outModeRow.BackgroundTransparency = 1
    outModeRow.Parent = cardVoiceEngine

    local outLayout = Instance.new("UIListLayout")
    outLayout.FillDirection = Enum.FillDirection.Horizontal
    outLayout.Padding = UDim.new(0, 6)
    outLayout.Parent = outModeRow

    local outButtons = {}
    local outOptions = {
        { id = "SoundService", label = "Alto-falante (Celular)" },
        { id = "AudioAPI", label = "Audio API (AudioPlayer)" },
    }
    local function refreshOutMode()
        for id, b in pairs(outButtons) do
            local active = (Config.FishAudio.OutputMode == id)
            tweenProp(b, {
                BackgroundColor3 = active and Theme.Accent or Theme.Input,
                TextColor3 = active and Color3.fromRGB(255, 255, 255) or Theme.TextMuted,
            }, 0.15)
        end
    end
    for _, opt in ipairs(outOptions) do
        local b = Instance.new("TextButton")
        b.Size = UDim2.new(0.49, 0, 1, 0)
        b.Font = Enum.Font.GothamBold
        b.Text = opt.label
        b.TextSize = 10
        b.Parent = outModeRow
        makeCorner(b, 7)
        outButtons[opt.id] = b
        b.MouseButton1Click:Connect(function()
            Config.FishAudio.OutputMode = opt.id
            refreshOutMode()
