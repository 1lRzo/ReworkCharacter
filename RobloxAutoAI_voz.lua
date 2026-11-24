local globalEnv = (type(getgenv) == "function" and getgenv()) or _G
if type(globalEnv.__RobloxAutoAI_Cleanup) == "function" then
    pcall(globalEnv.__RobloxAutoAI_Cleanup)
end

local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local TextChatService = game:GetService("TextChatService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local CoreGui = game:GetService("CoreGui")

local LocalPlayer = Players.LocalPlayer or Players.PlayerAdded:Wait()

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
    SendTextInChat = true,
    AutoFallbackModel = true,

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
    Temperature = 0.78,
    MaxChars = 150,
    Timeout = 10,

    FishAudio = {
        Enabled = true,
        ApiUrl = "https://api.fish.audio/v1/tts",
        ApiKey = "sk-fish-pJb1Y4LlmEYpAGz0m8ALTOP3zwQy4wfUMhJBzJBf-QU",
        VoiceId = "4e8e6f7ce2b4444bacdc8b9f47922657",
        Model = "s2.1-pro-free",
        FallbackModels = { "s2.1-pro", "s2-pro" },
        Format = "mp3",
        Speed = 0.90,
        PlaybackVolume = 4.5,
        Timeout = 18,
        OutputMode = "SoundService",
        VoiceBoostEQ = true,
        AutoToggleVC = true,
        PreSpeakDelay = 0.45,
        PostSpeakDelay = 0.7,
        Provider = "Fish",
        FallbackProvider = true,
        GoogleLang = "pt-BR",
        DuckGameAudio = true,
        SaveLastFile = true,
        RouteMode = nil,
    },

    PersonalityPreset = "Amigável",
    CustomPersonality = "",
    PreventUnnecessaryLaugh = true,
    Presets = {
        ["Amigável"] = "Você é gente boa, tranquilo e conversa de forma leve e simpática como um amigo jogando junto.",
        ["Engraçada"] = "Você tem senso de humor leve, faz comentários espertos e entra nas brincadeiras de forma natural.",
        ["Séria"] = "Você é direto, calmo, objetivo e responde sem enrolação, mantendo um tom natural.",
        ["Sarcástica"] = "Você tem humor ácido sutil e dá respostas irônicas de vez em quando, mas sem ser tóxico.",
        ["Inteligente"] = "Você observa bem o que falam, dá respostas espertas e curiosas, mas sem falar como professor.",
        ["Extrovertida"] = "Você é animado, puxa assunto fácil, faz perguntas e gosta de interagir com todo mundo.",
        ["Misteriosa"] = "Você fala pouco, de um jeito enigmático e tranquilo, deixando respostas curtas e curiosas.",
    },

    ResponseMode = "DirectOnly",
    TargetOnly = false,
    ReplyAllFromTargets = true,
    TargetPlayers = {},
    CooldownSeconds = 1.5,
    RandomReplyChance = 35,
    MaxProximityStuds = 45,
    ContextWindow = 10,
    ConversationActiveWindow = 28,

    IgnoredPlayers = {},
    ForbiddenWords = {},
    CommandPrefix = "!ia",
}

local function getActiveModelConfig()
    for idx, entry in ipairs(Config.ModelList) do
        if entry.Id == Config.Model then
            return entry, idx
        end
    end
    return Config.ModelList[1], 1
end

local Runtime = {
    IsGenerating = false,
    IsSpeaking = false,
    VoiceRequestId = 0,
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
-- MÓDULO 2: AMBIENTE E COMPATIBILIDADE
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
-- MÓDULO 3: PROTEÇÃO, SEGURANÇA E ANTI-RISADA
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
        for _, cp in utf8.codes(text) do
            local isEmoji =
                (cp >= 0x1F000 and cp <= 0x1FAFF) or
                (cp >= 0x2600 and cp <= 0x27BF) or
                (cp >= 0x2300 and cp <= 0x23FF) or
                (cp >= 0x2B00 and cp <= 0x2BFF) or
                (cp >= 0xFE00 and cp <= 0xFE0F) or
                (cp == 0x200D) or
                (cp >= 0xE0020 and cp <= 0xE007F)
            if not isEmoji then
                table.insert(buffer, utf8.char(cp))
            end
        end
    end)
    local cleaned = ok and table.concat(buffer) or text:gsub("[\240-\244][\128-\191]*", "")
    cleaned = cleaned:gsub("[\r\n]+", " "):gsub("[%*_`~]+", ""):gsub("%s+", " ")
    return Security.trim(cleaned)
end

function Security.hasHumorCue(text)
    local lower = Security.normalize(text)
    if lower == "" then
        return false
    end
    for _, cue in ipairs({ "kk", "haha", "hehe", "rsrs", "piada", "engraçad", "engracad", "zoeira", "zueira", "lol", "lmao" }) do
        if lower:find(cue, 1, true) then
            return true
        end
    end
    return false
end

function Security.stripUnnecessaryLaugh(text, incomingText)
    if not Config.PreventUnnecessaryLaugh or type(text) ~= "string" then
        return text
    end
    local cleaned = text:gsub("%f[%a][kK][kK][kK][kK]+%f[%A]", "kk")
    if not Security.hasHumorCue(incomingText or "") then
        cleaned = cleaned:gsub("%f[%a][kK][kK]+%f[%A]", "")
        cleaned = cleaned:gsub("%f[%a][hH][aA][hH][aA]+[hH]?[aA]?%f[%A]", "")
        cleaned = cleaned:gsub("%f[%a][rR][sS][rR][sS]+%f[%A]", "")
    end
    cleaned = cleaned:gsub("%s+([,%.!?])", "%1"):gsub(",%s*,+", ","):gsub("^[,%.!%s]+", ""):gsub("[,]+%s*$", ""):gsub("%s+", " ")
    return Security.trim(cleaned)
end

function Security.containsSensitiveData(text)
    if type(text) ~= "string" or text == "" then
        return false
    end
    local keys = { Config.FishAudio.ApiKey }
    for _, m in ipairs(Config.ModelList) do
        table.insert(keys, m.ApiKey)
    end
    for _, rawKey in ipairs(keys) do
        local key = Security.trim(rawKey)
        if #key >= 6 then
            local prefix = key:sub(1, math.min(10, #key))
            if text:find(key, 1, true) or (#prefix >= 6 and text:find(prefix, 1, true)) then
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
    local n1, n2 = Security.normalize(playerName or ""), Security.normalize(displayName or "")
    for _, blocked in ipairs(Config.IgnoredPlayers) do
        if blocked ~= "" and (blocked == n1 or blocked == n2) then
            return true
        end
    end
    return false
end

function Security.isPlayerTargeted(playerName, displayName)
    local n1, n2 = Security.normalize(playerName or ""), Security.normalize(displayName or "")
    return (n1 ~= "" and Config.TargetPlayers[n1] == true) or (n2 ~= "" and Config.TargetPlayers[n2] == true)
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
    local limit = math.clamp(tonumber(maxChars) or 150, 20, 200)
    if #text <= limit then
        return text
    end
    local cut = text:sub(1, limit)
    local lastSpace = cut:match("^(.*)%s+[^%s]*$")
    if lastSpace and #lastSpace >= math.floor(limit * 0.5) then
        cut = lastSpace
    end
    while #cut > 0 do
        if pcall(utf8.len, cut) then
            break
        end
        cut = cut:sub(1, #cut - 1)
    end
    return Security.trim(cut)
end

function Security.sanitizeOutgoingMessage(rawText, incomingText)
    if Security.containsSensitiveData(rawText) then
        return nil, "Bloqueado por conter dados sensíveis"
    end
    local cleaned = Security.stripEmojis(rawText):gsub("^%[?[%w%s_-]+%]?:%s*", "")
    cleaned = Security.stripUnnecessaryLaugh(cleaned, incomingText)
    cleaned = Security.trim(cleaned)
    if cleaned == "" then
        return nil, "Resposta vazia após limpeza"
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
-- MÓDULO 4: CONTEXTO
-- =========================================================================
local ContextManager = { Messages = {} }

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

    local laughRule = Config.PreventUnnecessaryLaugh
        and "5. NUNCA coloque 'kk', 'kkk', 'kkkk', 'haha' ou risadas sem motivo. Responda sem rir, a menos que seja uma piada clara."
        or "5. Use risadas com moderação apenas quando fizer sentido."

    return table.concat({
        "Você é uma pessoa real jogando Roblox e conversando no chat.",
        string.format("Seu nome de exibição é '%s' e seu usuário é '@%s'.", myDisplay, myUser),
        "Personalidade: " .. personalityText,
        "Regras obrigatórias:",
        "1. Aja 100% como jogador humano comum, nunca como IA ou bot.",
        "2. Se perguntarem se você é IA ou bot, reaja de forma natural e casual.",
        "3. NUNCA use emojis ou símbolos gráficos.",
        "4. Responda de forma curta, calma, direta e natural (ex: 'blz', 'entendi', 'to aqui', 'serio?').",
        laughRule,
        "6. Entenda gírias, abreviações e erros sem corrigir ninguém.",
        "7. Não use listas, markdown ou textos longos e não invente coisas sobre o jogo.",
        string.format("8. Máximo de %d caracteres. Retorne apenas a fala exata, sem seu nome antes.", Config.MaxChars),
    }, "\n")
end

function ContextManager.buildApiPayloadMessages(latestSpeaker, latestText)
    local payload = { { role = "system", content = ContextManager.buildSystemPrompt() } }
    for _, entry in ipairs(ContextManager.Messages) do
        if entry.role == "assistant" then
            table.insert(payload, { role = "assistant", content = entry.content })
        else
            table.insert(payload, { role = "user", content = string.format("[%s]: %s", entry.author, entry.content) })
        end
    end
    if latestSpeaker and latestText then
        table.insert(payload, { role = "user", content = string.format("[%s]: %s", latestSpeaker, latestText) })
    end
    return payload
end

-- =========================================================================
-- MÓDULO 5: API DE TEXTO (COM AUTO-FALLBACK RÁPIDO)
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

local function callSingleModel(httpRequest, modelCfg, messages)
    local headers = {
        ["Content-Type"] = "application/json",
        ["Accept"] = "application/json",
        ["Authorization"] = "Bearer " .. Security.trim(modelCfg.ApiKey),
    }
    local bodyTable = {
        model = modelCfg.Id,
        messages = messages,
        temperature = math.clamp(tonumber(Config.Temperature) or 0.78, 0, 2),
        max_tokens = 95,
        stream = false,
    }
    local okEncode, encodedBody = pcall(HttpService.JSONEncode, HttpService, bodyTable)
    if not okEncode then
        return false, "Erro ao montar JSON."
    end

    updateApiStatus("Aguardando", modelCfg.Provider .. "...")
    local done, reqSuccess, responseData = false, false, nil
    local startTick = os.clock()
    local timeoutLimit = math.clamp(tonumber(Config.Timeout) or 10, 3, 60)

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
        task.wait()
    end

    if not done then
        done = true
        return false, "Timeout em " .. modelCfg.Provider
    end
    if not reqSuccess or type(responseData) ~= "table" then
        return false, "Falha HTTP em " .. modelCfg.Provider
    end

    local statusCode = tonumber(responseData.StatusCode or responseData.status) or 0
    local rawBody = tostring(responseData.Body or responseData.body or "")
    if statusCode < 200 or statusCode >= 300 then
        return false, modelCfg.Provider .. " HTTP " .. tostring(statusCode)
    end

    local okDecode, decoded = pcall(HttpService.JSONDecode, HttpService, rawBody)
    if okDecode and type(decoded) == "table" then
        if type(decoded.choices) == "table" and decoded.choices[1] then
            local choice = decoded.choices[1]
            local content = (type(choice.message) == "table" and choice.message.content) or choice.text
            if type(content) == "string" and Security.trim(content) ~= "" then
                return true, content
            end
        elseif type(decoded.content) == "string" and Security.trim(decoded.content) ~= "" then
            return true, decoded.content
        elseif type(decoded.error) == "table" and decoded.error.message then
            return false, tostring(decoded.error.message)
        end
    elseif Security.trim(rawBody) ~= "" and not rawBody:match("^%s*<") then
        return true, rawBody
    end
    return false, "Resposta inválida de " .. modelCfg.Provider
end

function AIClient.requestCompletion(messages)
    local httpRequest = Environment.getHttpRequestFunction()
    if not httpRequest then
        updateApiStatus("Erro", "Executor sem HTTP")
        return false, "Executor sem função HTTP."
    end

    local activeCfg, activeIdx = getActiveModelConfig()
    local ok, result = callSingleModel(httpRequest, activeCfg, messages)
    if ok then
        updateApiStatus("Conectado", activeCfg.Provider)
        return true, result
    end

    if Config.AutoFallbackModel then
        for idx, entry in ipairs(Config.ModelList) do
            if idx ~= activeIdx then
                local fbOk, fbResult = callSingleModel(httpRequest, entry, messages)
                if fbOk then
                    updateApiStatus("Conectado", entry.Provider .. " (Backup)")
                    return true, fbResult
                end
            end
        end
    end

    updateApiStatus("Erro", result)
    return false, result
end

-- =========================================================================
-- MÓDULO 6: VOICE CHAT & TTS (Fish Audio + Google como reserva)
-- =========================================================================
-- IMPORTANTE: o Roblox NÃO tem nenhuma API para enviar áudio direto para o
-- seu chat de voz (AudioDeviceInput só lê o microfone físico). O que este
-- módulo faz é: gerar a fala, abrir o mic, tocar o áudio localmente e deixar
-- o som chegar ao microfone pela "rota" (cabo virtual no PC / alto-falante
-- no celular). Use o Diagnóstico da aba Voz para ver onde está falhando.
-- =========================================================================
local VoiceTTS = {}
local OnVoiceStatusChanged = nil
local TTS_NAME = "AutoAI_TTS"

local VCOLOR = {
    Ok = Color3.fromRGB(46, 204, 113),
    Warn = Color3.fromRGB(245, 166, 35),
    Err = Color3.fromRGB(245, 115, 115),
    Muted = Color3.fromRGB(154, 163, 189),
}

local function updateVoiceStatus(text, color)
    Runtime.VoiceStatus = text
    if OnVoiceStatusChanged then
        pcall(OnVoiceStatusChanged, text, color)
    end
end

function VoiceTTS.setStatusCallback(cb)
    OnVoiceStatusChanged = cb
end

local function idleStatus()
    return Config.FishAudio.Enabled and "Pronto (Áudio Ativo)" or "Desativado"
end

-- -------------------------------------------------------------------------
-- Microfone do Roblox
-- -------------------------------------------------------------------------
local function findMicInput()
    local direct = LocalPlayer:FindFirstChildOfClass("AudioDeviceInput")
    if direct then
        return direct
    end
    for _, d in ipairs(LocalPlayer:GetDescendants()) do
        if d:IsA("AudioDeviceInput") then
            return d
        end
    end
    return nil
end

local function getVoiceChatInternal()
    local okGet, vci = pcall(function()
        return game:GetService("VoiceChatInternal")
    end)
    if not okGet or not vci then
        return nil
    end
    local okRead = pcall(function()
        return vci:IsPublishPaused()
    end)
    if okRead then
        return vci
    end
    return nil
end

function VoiceTTS.getMicState()
    local adi = findMicInput()
    local vci = getVoiceChatInternal()
    local state = { HasInput = adi ~= nil, HasVCI = vci ~= nil, Muted = nil, Active = nil, Paused = nil }
    if adi then
        pcall(function() state.Muted = adi.Muted end)
        pcall(function() state.Active = adi.Active end)
    end
    if vci then
        pcall(function() state.Paused = vci:IsPublishPaused() end)
    end
    if not state.HasInput and not state.HasVCI then
        state.Label = "Sem acesso"
        state.Kind = "fail"
    elseif state.Muted == true or state.Paused == true then
        state.Label = "Mutado"
        state.Kind = "warn"
    else
        state.Label = "Aberto"
        state.Kind = "ok"
    end
    return state
end

function VoiceTTS.inspectVoiceEnvironment()
    local isMobile = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
    local deviceTag = isMobile and "Celular" or (UserInputService.TouchEnabled and "Touch/Híbrido" or "PC")

    local useAudioApi = false
    local hasVCS, vcs = pcall(function()
        return game:GetService("VoiceChatService")
    end)
    if hasVCS and vcs then
        pcall(function()
            useAudioApi = vcs.UseAudioApi == Enum.AudioApiRollout.Enabled
        end)
    end

    local mic = VoiceTTS.getMicState()
    local caps = Environment.getAudioAssetCapabilities()
    return {
        Summary = string.format(
            "Disp: %s | AudioAPI: %s | Mic: %s | VCI: %s | Arquivos: %s | HTTP: %s",
            deviceTag,
            useAudioApi and "Sim" or "Não",
            mic.HasInput and mic.Label or "Não achado",
            mic.HasVCI and "Liberado" or "Bloqueado",
            caps.Supported and "OK" or "Não",
            Environment.getHttpRequestFunction() and "OK" or "Não"
        ),
    }
end

local MicState = { Original = nil, Token = 0 }

local function captureMicSnapshot()
    local snap = {
        adi = findMicInput(),
        adiMuted = nil,
        vci = getVoiceChatInternal(),
        vciPaused = nil,
        changedAdi = false,
        changedVci = false,
    }
    if snap.adi then
        pcall(function() snap.adiMuted = snap.adi.Muted end)
    end
    if snap.vci then
        pcall(function() snap.vciPaused = snap.vci:IsPublishPaused() end)
    end
    return snap
end

local function openMicForSpeech(snap)
    if not Config.FishAudio.AutoToggleVC then
        return false
    end
    local changed = false
    if snap.adi and snap.adiMuted == true and not snap.changedAdi then
        local ok = pcall(function() snap.adi.Muted = false end)
        if ok then
            snap.changedAdi = true
            changed = true
        end
    end
    if snap.vci and snap.vciPaused == true and not snap.changedVci then
        local ok = pcall(function() snap.vci:PublishPause(false) end)
        if ok then
            snap.changedVci = true
            changed = true
        end
    end
    return changed
end

local function restoreMicSnapshot(snap)
    if not snap then
        return
    end
    if snap.changedAdi and snap.adi then
        pcall(function() snap.adi.Muted = true end)
    end
    if snap.changedVci and snap.vci then
        pcall(function() snap.vci:PublishPause(true) end)
    end
end

-- Abre o mic (guardando o estado original só uma vez, mesmo com falas seguidas)
local function acquireMic()
    MicState.Token = MicState.Token + 1
    if not MicState.Original then
        MicState.Original = captureMicSnapshot()
    end
    return openMicForSpeech(MicState.Original)
end

-- Fecha o mic depois de um tempo (cancelado se outra fala começar nesse meio tempo)
local function releaseMic(delaySeconds)
    local token = MicState.Token
    task.delay(delaySeconds or 0.7, function()
        if token ~= MicState.Token then
            return
        end
        if MicState.Original then
            restoreMicSnapshot(MicState.Original)
            MicState.Original = nil
        end
    end)
end

-- -------------------------------------------------------------------------
-- Abaixar o áudio do jogo enquanto a IA fala (só a voz vai pro mic)
-- -------------------------------------------------------------------------
local Duck = { Saved = {}, Conns = {} }

local function duckInstance(inst)
    if inst.Name == TTS_NAME or Duck.Saved[inst] ~= nil then
        return
    end
    if inst:IsA("Sound") or inst:IsA("AudioPlayer") then
        local ok, vol = pcall(function() return inst.Volume end)
        if ok and type(vol) == "number" and vol > 0 then
            Duck.Saved[inst] = vol
            pcall(function() inst.Volume = 0 end)
        end
    end
end

local function stopDucking()
    for _, c in ipairs(Duck.Conns) do
        pcall(function() c:Disconnect() end)
    end
    Duck.Conns = {}
    for inst, vol in pairs(Duck.Saved) do
        pcall(function()
            if inst.Parent then
                inst.Volume = vol
            end
        end)
    end
    Duck.Saved = {}
end

local function startDucking()
    stopDucking()
    if not Config.FishAudio.DuckGameAudio then
        return
    end
    local roots = { workspace, SoundService }
    local pg = LocalPlayer:FindFirstChildOfClass("PlayerGui")
    if pg then
        table.insert(roots, pg)
    end
    for _, root in ipairs(roots) do
        for _, d in ipairs(root:GetDescendants()) do
            duckInstance(d)
        end
        local okConn, conn = pcall(function()
            return root.DescendantAdded:Connect(duckInstance)
        end)
        if okConn and conn then
            table.insert(Duck.Conns, conn)
        end
    end
end

function VoiceTTS.stopCurrent()
    if type(Runtime.ActiveAudioCleanup) == "function" then
        pcall(Runtime.ActiveAudioCleanup)
        Runtime.ActiveAudioCleanup = nil
    end
    Runtime.IsSpeaking = false
end

-- -------------------------------------------------------------------------
-- Reprodução local
-- -------------------------------------------------------------------------
local function playViaSoundService(assetId, onFinished)
    local sound = Instance.new("Sound")
    sound.Name = TTS_NAME
    sound.SoundId = assetId
    sound.Volume = math.clamp(tonumber(Config.FishAudio.PlaybackVolume) or 4.5, 0, 10)
    sound.PlaybackSpeed = 1
    sound.Looped = false
    sound.Parent = SoundService

    if Config.FishAudio.VoiceBoostEQ then
        local eq = Instance.new("EqualizerSoundEffect")
        eq.LowGain = -3
        eq.MidGain = 5
        eq.HighGain = 2.5
        eq.Parent = sound
    end

    local loadStart = os.clock()
    while not sound.IsLoaded and (os.clock() - loadStart) < 4 do
        task.wait()
    end
    if not sound.IsLoaded then
        pcall(function() sound:Destroy() end)
        return false
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
    local maxLen = (sound.TimeLength > 0) and (sound.TimeLength + 2) or 25
    task.delay(math.clamp(maxLen, 3, 40), cleanup)
    sound:Play()
    return true
end

local function playViaAudioAPI(assetId, onFinished)
    local created = {}
    local okSetup = pcall(function()
        local player = Instance.new("AudioPlayer")
        player.Name = TTS_NAME
        player.AutoLoad = true
        player.Volume = math.clamp(tonumber(Config.FishAudio.PlaybackVolume) or 4.5, 0, 10)
        pcall(function() player.Asset = assetId end)
        pcall(function() player.AssetId = assetId end)
        player.Parent = SoundService
        table.insert(created, player)

        local output = Instance.new("AudioDeviceOutput")
        output.Name = TTS_NAME
        output.Parent = SoundService
        table.insert(created, output)

        local wireOut = Instance.new("Wire")
        wireOut.SourceInstance = player
        wireOut.TargetInstance = output
        wireOut.Parent = player
        table.insert(created, wireOut)

        local loadStart = os.clock()
        while not player.IsReady and (os.clock() - loadStart) < 3 do
            task.wait()
        end
        if not player.IsReady then
            error("AudioPlayer não carregou asset")
        end

        local done = false
        local function cleanup()
            if done then
                return
            end
            done = true
            pcall(function() player:Stop() end)
            for _, inst in ipairs(created) do
                pcall(function() inst:Destroy() end)
            end
            onFinished()
        end

        Runtime.ActiveAudioCleanup = cleanup
        if typeof(player.Ended) == "RBXScriptSignal" then
            player.Ended:Connect(cleanup)
        end
        player:Play()

        task.spawn(function()
            local waitLimit = math.clamp((player.TimeLength > 0 and player.TimeLength + 1) or 15, 2, 40)
            local startP = os.clock()
            task.wait(0.35)
            while not done and (os.clock() - startP) < waitLimit do
                if not player.IsPlaying then
                    break
                end
                task.wait(0.1)
            end
            cleanup()
        end)
    end)

    if not okSetup then
        for _, inst in ipairs(created) do
            pcall(function() inst:Destroy() end)
        end
        return false
    end
    return true
end

-- -------------------------------------------------------------------------
-- Tom de teste (WAV gerado em Lua, não depende de nenhuma API)
-- -------------------------------------------------------------------------
local function buildToneWav(segments, sampleRate)
    sampleRate = sampleRate or 16000
    local chunks = {}
    for _, seg in ipairs(segments) do
        local freq, seconds = seg[1], seg[2]
        local n = math.floor(sampleRate * seconds)
        local fade = math.floor(sampleRate * 0.03)
        local samples = table.create(n)
        for i = 0, n - 1 do
            local env = 1
            if i < fade then
                env = i / fade
            elseif i > n - fade then
                env = (n - i) / fade
            end
            local v = 0
            if freq > 0 then
                v = math.sin(2 * math.pi * freq * i / sampleRate) * 0.6 * env
            end
            samples[i + 1] = string.pack("<i2", math.floor(v * 32767))
        end
        table.insert(chunks, table.concat(samples))
    end
    local data = table.concat(chunks)
    local header = "RIFF" .. string.pack("<I4", 36 + #data) .. "WAVE"
        .. "fmt " .. string.pack("<I4I2I2I4I4I2I2", 16, 1, 1, sampleRate, sampleRate * 2, 2, 16)
        .. "data" .. string.pack("<I4", #data)
    return header .. data
end

-- -------------------------------------------------------------------------
-- Provedores de TTS
-- -------------------------------------------------------------------------
local function httpWithTimeout(httpRequest, requestTable, timeoutSeconds)
    local done, reqOk, resData = false, false, nil
    local startTick = os.clock()

    task.spawn(function()
        local ok, res = pcall(httpRequest, requestTable)
        if not done then
            done = true
            reqOk = ok
            resData = res
        end
    end)

    while not done and (os.clock() - startTick) < timeoutSeconds do
        task.wait()
    end
    if not done then
        done = true
        return false, 0, "Tempo esgotado"
    end
    if not reqOk or type(resData) ~= "table" then
        return false, 0, "Falha HTTP: " .. tostring(resData)
    end
    local code = tonumber(resData.StatusCode or resData.status or resData.Status) or 0
    local body = resData.Body or resData.body or ""
    return (code >= 200 and code < 300), code, body
end

local function describeHttpError(code, body)
    if code == 401 or code == 403 then
        return "Chave recusada (HTTP " .. code .. ")"
    elseif code == 402 then
        return "Sem créditos (HTTP 402)"
    elseif code == 429 then
        return "Limite de uso (HTTP 429)"
    elseif code == 0 then
        return tostring(body)
    end
    return "HTTP " .. tostring(code) .. ": " .. tostring(body):sub(1, 80)
end

local function fetchFishAudio(httpRequest, text)
    local cfg = Config.FishAudio
    if type(cfg.ApiKey) ~= "string" or cfg.ApiKey == "" then
        return nil, nil, "Sem chave do Fish Audio"
    end

    local format = (cfg.Format == "wav") and "wav" or "mp3"
    local payload = {
        text = text,
        format = format,
        normalize = true,
        latency = "balanced",
        prosody = {
            speed = math.clamp(tonumber(cfg.Speed) or 0.90, 0.5, 2.0),
            volume = 0,
        },
    }
    if type(cfg.VoiceId) == "string" and cfg.VoiceId ~= "" then
        payload.reference_id = cfg.VoiceId
    end
    if format == "mp3" then
        payload.mp3_bitrate = 128
    else
        payload.sample_rate = 44100
    end

    local okEncode, bodyJson = pcall(HttpService.JSONEncode, HttpService, payload)
    if not okEncode then
        return nil, nil, "Erro JSON Fish Audio"
    end

    local models = { cfg.Model }
    for _, fb in ipairs(cfg.FallbackModels) do
        if fb ~= cfg.Model then
            table.insert(models, fb)
        end
    end

    local timeoutLimit = math.clamp(tonumber(cfg.Timeout) or 18, 5, 60)
    local lastErr = "Erro desconhecido"
    for _, modelName in ipairs(models) do
        updateVoiceStatus("Fish Audio (" .. modelName .. ")...", VCOLOR.Warn)
        local ok, code, body = httpWithTimeout(httpRequest, {
            Url = cfg.ApiUrl,
            Method = "POST",
            Headers = {
                ["Authorization"] = "Bearer " .. cfg.ApiKey,
                ["Content-Type"] = "application/json",
                ["model"] = modelName,
            },
            Body = bodyJson,
        }, timeoutLimit)

        if ok and type(body) == "string" and #body >= 128 then
            return body, format, nil
        end
        lastErr = describeHttpError(code, body)
        if code == 401 or code == 402 or code == 403 then
            break
        end
    end
    return nil, nil, lastErr
end

local function fetchGoogleAudio(httpRequest, text)
    -- Endpoint não oficial do Google Tradutor (sem chave, limite ~180 caracteres)
    local cut = text
    local okCut, pos = pcall(utf8.offset, text, 181)
    if okCut and pos then
        cut = text:sub(1, pos - 1)
    end
    local url = string.format(
        "https://translate.google.com/translate_tts?ie=UTF-8&client=tw-ob&tl=%s&q=%s",
        tostring(Config.FishAudio.GoogleLang or "pt-BR"),
        HttpService:UrlEncode(cut)
    )
    updateVoiceStatus("Google TTS...", VCOLOR.Warn)
    local ok, code, body = httpWithTimeout(httpRequest, {
        Url = url,
        Method = "GET",
        Headers = {
            ["User-Agent"] = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36",
            ["Referer"] = "https://translate.google.com/",
        },
    }, 12)

    if ok and type(body) == "string" and #body >= 128 and (body:sub(1, 3) == "ID3" or body:byte(1) == 0xFF) then
        return body, "mp3", nil
    end
    if ok then
        return nil, nil, "Google não devolveu áudio (bloqueado?)"
    end
    return nil, nil, describeHttpError(code, body)
end

local function fetchSpeechAudio(httpRequest, cleanText, myReqId)
    local order = { "Fish", "Google" }
    if Config.FishAudio.Provider == "Google" then
        order = { "Google", "Fish" }
    end
    if not Config.FishAudio.FallbackProvider then
        order = { order[1] }
    end

    local errors = {}
    for _, provider in ipairs(order) do
        if Runtime.VoiceRequestId ~= myReqId then
            return nil, nil, nil, "Substituído por fala nova"
        end
        local bytes, ext, err
        if provider == "Fish" then
            bytes, ext, err = fetchFishAudio(httpRequest, cleanText)
        else
            bytes, ext, err = fetchGoogleAudio(httpRequest, cleanText)
        end
        if bytes then
            return bytes, ext, (provider == "Fish") and "Fish Audio" or "Google TTS", nil
        end
        table.insert(errors, provider .. ": " .. tostring(err))
    end
    return nil, nil, nil, table.concat(errors, " | ")
end

-- -------------------------------------------------------------------------
-- Falar
-- -------------------------------------------------------------------------
local function speakAudioBytes(audioBytes, ext, myReqId, providerLabel)
    local audioCaps = Environment.getAudioAssetCapabilities()
    if not audioCaps.Supported then
        updateVoiceStatus("Erro: Falta writefile/getcustomasset", VCOLOR.Err)
        return false, "Falta writefile ou getcustomasset"
    end

    local fileName = string.format("autoai_tts_%d.%s", math.floor(os.clock() * 1000) % 1000000, ext)
    local okWrite, errWrite = pcall(audioCaps.WriteFile, fileName, audioBytes)
    if not okWrite then
        updateVoiceStatus("Erro writefile", VCOLOR.Err)
        return false, tostring(errWrite)
    end
    if Config.FishAudio.SaveLastFile and providerLabel ~= "Tom de teste" then
        pcall(audioCaps.WriteFile, "AutoAI_ultima_fala." .. ext, audioBytes)
    end

    local okAsset, assetId = pcall(audioCaps.GetCustomAsset, fileName)
    if not okAsset or type(assetId) ~= "string" or assetId == "" then
        if audioCaps.DelFile then pcall(audioCaps.DelFile, fileName) end
        updateVoiceStatus("Erro getcustomasset", VCOLOR.Err)
        return false, "Falha ao carregar asset local"
    end

    VoiceTTS.stopCurrent()
    local opened = acquireMic()
    if opened then
        task.wait(tonumber(Config.FishAudio.PreSpeakDelay) or 0.45)
    end

    if Runtime.VoiceRequestId ~= myReqId then
        releaseMic(0.1)
        if audioCaps.DelFile then pcall(audioCaps.DelFile, fileName) end
        return false, "Substituído por fala nova"
    end

    Runtime.IsSpeaking = true
    updateVoiceStatus("Falando (" .. tostring(providerLabel or "TTS") .. ")...", VCOLOR.Ok)
    startDucking()

    local finished = false
    local function onPlaybackDone()
        if finished then
            return
        end
        finished = true
        Runtime.IsSpeaking = false
        Runtime.ActiveAudioCleanup = nil
        stopDucking()
        releaseMic(tonumber(Config.FishAudio.PostSpeakDelay) or 0.7)
        if audioCaps.DelFile then
            task.delay(1.5, function() pcall(audioCaps.DelFile, fileName) end)
        end
        updateVoiceStatus(idleStatus(), VCOLOR.Muted)
    end

    local started = false
    if Config.FishAudio.OutputMode == "AudioAPI" then
        started = playViaAudioAPI(assetId, onPlaybackDone)
    end
    if not started then
        local okPlay, playResult = pcall(playViaSoundService, assetId, onPlaybackDone)
        if not okPlay or playResult ~= true then
            onPlaybackDone()
            updateVoiceStatus("Erro ao tocar o áudio", VCOLOR.Err)
            return false, "Falha ao tocar o áudio (" .. (okPlay and "asset não carregou" or tostring(playResult)) .. ")"
        end
    end
    return true, "OK"
end

function VoiceTTS.synthesizeAndSpeak(text)
    local cleanText = Security.stripEmojis(text)
    if cleanText == "" then
        return false, "Texto vazio"
    end
    local httpRequest = Environment.getHttpRequestFunction()
    if not httpRequest then
        updateVoiceStatus("Erro: Executor sem HTTP", VCOLOR.Err)
        return false, "Executor sem HTTP"
    end
    local audioCaps = Environment.getAudioAssetCapabilities()
    if not audioCaps.Supported then
        updateVoiceStatus("Erro: Falta writefile/getcustomasset", VCOLOR.Err)
        return false, "Falta writefile ou getcustomasset"
    end

    Runtime.VoiceRequestId = Runtime.VoiceRequestId + 1
    local myReqId = Runtime.VoiceRequestId

    local bytes, ext, providerLabel, err = fetchSpeechAudio(httpRequest, cleanText, myReqId)
    if not bytes then
        updateVoiceStatus("Falha TTS: " .. tostring(err):sub(1, 40), VCOLOR.Err)
        return false, tostring(err)
    end
    if Runtime.VoiceRequestId ~= myReqId then
        return false, "Substituído por fala nova"
    end
    return speakAudioBytes(bytes, ext, myReqId, providerLabel)
end

function VoiceTTS.playTestTone()
    local caps = Environment.getAudioAssetCapabilities()
    if not caps.Supported then
        updateVoiceStatus("Erro: Falta writefile/getcustomasset", VCOLOR.Err)
        return false, "Falta writefile ou getcustomasset"
    end
    Runtime.VoiceRequestId = Runtime.VoiceRequestId + 1
    local okWav, wav = pcall(buildToneWav, { { 440, 0.4 }, { 0, 0.1 }, { 660, 0.4 }, { 0, 0.1 }, { 880, 0.6 } }, 16000)
    if not okWav or type(wav) ~= "string" then
        updateVoiceStatus("Erro ao gerar o tom", VCOLOR.Err)
        return false, "Não consegui gerar o WAV (string.pack indisponível?): " .. tostring(wav)
    end
    return speakAudioBytes(wav, "wav", Runtime.VoiceRequestId, "Tom de teste")
end

-- -------------------------------------------------------------------------
-- Diagnóstico por etapas
-- -------------------------------------------------------------------------
function VoiceTTS.runDiagnostics(report)
    local results = {}
    local function add(label, kind, detail)
        table.insert(results, { Label = label, Kind = kind, Detail = detail })
        if report then
            pcall(report, label, kind, detail)
        end
    end

    local httpRequest = Environment.getHttpRequestFunction()
    if httpRequest then
        add("HTTP do executor", "ok", "request disponível")
    else
        add("HTTP do executor", "fail", "Seu executor não tem request/http_request. Sem isso não existe TTS.")
    end

    local caps = Environment.getAudioAssetCapabilities()
    if caps.Supported then
        add("Arquivos de áudio", "ok", "writefile + getcustomasset disponíveis")
    else
        add("Arquivos de áudio", "fail", "Faltam writefile/getcustomasset. Sem isso o áudio não toca.")
    end

    local mic = VoiceTTS.getMicState()
    if mic.Kind == "fail" then
        add("Mic do Roblox", "fail", "Não achei AudioDeviceInput nem VoiceChatInternal. Ative o chat de voz na conta e entre em um jogo com voz ligada.")
    elseif mic.Kind == "warn" then
        add("Mic do Roblox", "warn", "Mutado agora. Com 'Auto-Abrir Mic' ligado o script abre sozinho ao falar.")
    else
        add("Mic do Roblox", "ok", "Aberto")
    end
    if mic.HasVCI then
        add("VoiceChatInternal", "ok", "Liberado neste executor")
    else
        add("VoiceChatInternal", "warn", "Bloqueado. O mic só abre via AudioDeviceInput.")
    end

    if httpRequest then
        local fb, _, ferr = fetchFishAudio(httpRequest, "Oi.")
        add("Fish Audio", fb and "ok" or "fail", fb and (tostring(#fb) .. " bytes de áudio") or tostring(ferr))
        local gb, _, gerr = fetchGoogleAudio(httpRequest, "Oi.")
        add("Google TTS (reserva)", gb and "ok" or "fail", gb and (tostring(#gb) .. " bytes de áudio") or tostring(gerr))
    end

    add("Rota até o mic", "warn", "O Roblox não permite verificar isso por script. Use 'Tom de Teste' e peça pra alguém no VC confirmar se ouviu.")
    updateVoiceStatus(idleStatus(), VCOLOR.Muted)
    return results
end

-- =========================================================================
-- MÓDULO 7: ENVIO DE CHAT
-- =========================================================================
local ChatSender = {}

function ChatSender.send(messageText)
    local chatType = Environment.getChatSystemType()
    if chatType == "TextChatService" then
        local channels = TextChatService:FindFirstChild("TextChannels")
        local general = channels and (channels:FindFirstChild("RBXGeneral") or channels:FindFirstChildOfClass("TextChannel"))
        if general then
            local ok, err = pcall(function() general:SendAsync(messageText) end)
            return ok, err and tostring(err)
        end
        return false, "Canal RBXGeneral não encontrado"
    end

    local legacyEvents = ReplicatedStorage:FindFirstChild("DefaultChatSystemChatEvents")
    local sayRequest = legacyEvents and legacyEvents:FindFirstChild("SayMessageRequest")
    if sayRequest and sayRequest:IsA("RemoteEvent") then
        local ok, err = pcall(function() sayRequest:FireServer(messageText, "All") end)
        return ok, err and tostring(err)
    end
    return false, "Canal de chat não suportado"
end

-- =========================================================================
-- MÓDULO 8: INTERFACE GRÁFICA (MOBILE & PC)
-- =========================================================================
local UI = { Root = nil, LogCallback = nil, Elements = {} }

local Theme = {
    BgDark = Color3.fromRGB(13, 15, 22),
    BgGradEnd = Color3.fromRGB(21, 25, 38),
    Card = Color3.fromRGB(23, 27, 39),
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
    TweenService:Create(inst, TweenInfo.new(duration or 0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), props):Play()
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
        title.TextColor3 = Color3.fromRGB(128, 152, 255)
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

    local function getWindowSize()
        local cam = workspace.CurrentCamera
        local vp = cam and cam.ViewportSize or Vector2.new(800, 600)
        return math.clamp(vp.X - 24, 315, 480), math.clamp(vp.Y - 36, 330, 465)
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

    local openScale = Instance.new("UIScale")
    openScale.Scale = 0.92
    openScale.Parent = mainFrame
    tweenProp(openScale, { Scale = 1 }, 0.28)

    trackConnection(UserInputService.InputBegan:Connect(function(input, processed)
        if processed then return end
        if input.KeyCode == Enum.KeyCode.RightShift then
            mainFrame.Visible = not mainFrame.Visible
        end
    end))

    local bgGrad = Instance.new("UIGradient")
    bgGrad.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Theme.BgDark),
        ColorSequenceKeypoint.new(1, Theme.BgGradEnd),
    })
    bgGrad.Rotation = 135
    bgGrad.Parent = mainFrame

    local topBar = Instance.new("Frame")
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
    lineGrad.Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, Theme.Accent), ColorSequenceKeypoint.new(1, Theme.Success) })
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
    subTitleLabel.Text = "Chat • Voz • Alvos   |   RightShift oculta"
    subTitleLabel.TextColor3 = Theme.TextMuted
    subTitleLabel.TextSize = 10
    subTitleLabel.TextXAlignment = Enum.TextXAlignment.Left
    subTitleLabel.Parent = topBar

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

    do
        local dragging, dragInput, dragStart, startPos = false, nil, nil, nil
        trackConnection(topBar.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                dragging, dragInput, dragStart, startPos = true, input, input.Position, mainFrame.Position
            end
        end))
        trackConnection(UserInputService.InputChanged:Connect(function(input)
            if dragging and (input == dragInput or input.UserInputType == Enum.UserInputType.MouseMovement) then
                local delta = input.Position - dragStart
                mainFrame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
            end
        end))
        trackConnection(UserInputService.InputEnded:Connect(function(input)
            if input == dragInput or input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                dragging, dragInput = false, nil
            end
        end))
    end

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

    local tabs, tabButtons = {}, {}
    local function createTab(name)
        local btn = Instance.new("TextButton")
        btn.Name = "TabBtn"
        btn.Size = UDim2.new(0.188, 0, 1, -6)
        btn.BackgroundColor3 = Theme.Accent
        btn.BackgroundTransparency = 1
        btn.Font = Enum.Font.GothamBold
        btn.Text = name
        btn.TextColor3 = Theme.TextMuted
        btn.TextSize = 11
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

        tabs[name], tabButtons[name] = page, btn
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
    local pageAlvos = createTab("Alvos")
    local pageIA = createTab("Persona")
    local pageVoz = createTab("Voz")
    local pageHistorico = createTab("Log")

    pageGeral.Visible = true
    tabButtons["Geral"].BackgroundTransparency = 0.1
    tabButtons["Geral"].TextColor3 = Color3.fromRGB(255, 255, 255)

    local mainSwitch
    local function syncPowerState()
        if mainSwitch then
            mainSwitch.SetVisual(Config.Enabled)
        end
        miniPowerBtn.BackgroundColor3 = Config.Enabled and Theme.Success or Theme.Danger
        miniPowerBtn.Text = Config.Enabled and "ON" or "OFF"
    end

    -- ABA 1: GERAL
    do
        local cardMainCtrl = createCard(pageGeral, "Controle Principal")
        mainSwitch = createSwitchRow(cardMainCtrl, "Ativar IA no Chat", "Responde rápido, natural e sem emojis", Config.Enabled, function(val)
            Config.Enabled = val
            syncPowerState()
            addLog("Sistema", Config.Enabled and "IA ativada." or "IA desativada.", Color3.fromRGB(140, 200, 255))
        end)
        createSwitchRow(cardMainCtrl, "Auto-Fallback de Modelo", "Troca automaticamente se o modelo falhar", Config.AutoFallbackModel, function(val)
            Config.AutoFallbackModel = val
        end)
        miniPowerBtn.MouseButton1Click:Connect(function()
            Config.Enabled = not Config.Enabled
            syncPowerState()
            addLog("Sistema", Config.Enabled and "IA ativada." or "IA desativada.", Color3.fromRGB(140, 200, 255))
        end)

        local cardModels = createCard(pageGeral, "Selecionar Modelo de IA")
        local modelCards = {}
        local function refreshModelCards()
            for id, item in pairs(modelCards) do
                local active = (Config.Model == id)
                tweenProp(item.Frame, { BackgroundColor3 = active and Color3.fromRGB(36, 48, 86) or Theme.Input }, 0.16)
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
                addLog("Modelo", "Selecionado: " .. mInfo.Id, Color3.fromRGB(165, 210, 255))
            end)
        end
        refreshModelCards()

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
        local function refreshModeButtons()
            for id, btn in pairs(modeButtons) do
                local active = (Config.ResponseMode == id)
                tweenProp(btn, {
                    BackgroundColor3 = active and Theme.Accent or Theme.Input,
                    TextColor3 = active and Color3.fromRGB(255, 255, 255) or Theme.TextMuted,
                }, 0.15)
            end
        end
        for _, item in ipairs({
            { id = "MentionOnly", label = "Mencionado" },
            { id = "DirectOnly", label = "Falando Comigo" },
            { id = "All", label = "Todos" },
        }) do
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

        local testOut = Instance.new("TextLabel")
        testOut.Size = UDim2.new(1, 0, 0, 38)
        testOut.BackgroundColor3 = Theme.Input
        testOut.Font = Enum.Font.Gotham
        testOut.Text = string.format("Chat: %s | HTTP: %s", Environment.getChatSystemType(), Environment.getHttpRequestFunction() and "OK" or "Indisponível")
        testOut.TextColor3 = Theme.TextMuted
        testOut.TextSize = 11
        testOut.TextWrapped = true
        testOut.Parent = cardTest
        makeCorner(testOut, 8)

        testBtn.MouseButton1Click:Connect(function()
            testBtn.Text = "Consultando..."
            task.spawn(function()
                local ok, reply = callbacks.onTestAI()
                testOut.Text = (ok and "OK: " or "Falha: ") .. tostring(reply)
                testOut.TextColor3 = ok and Theme.Success or Theme.Danger
                testBtn.Text = "Testar Resposta da IA"
            end)
        end)
    end

    -- ABA 2: ALVOS & FILTROS
    do
        local cardTargetMode = createCard(pageAlvos, "Escolher Quem Responder")
        createSwitchRow(cardTargetMode, "Responder Apenas Selecionados", "Ignora todos que não estiverem marcados abaixo", Config.TargetOnly, function(val)
            Config.TargetOnly = val
            addLog("Alvos", val and "Modo Alvos ativado." or "Modo Alvos desativado.", Color3.fromRGB(165, 210, 255))
        end)
        createSwitchRow(cardTargetMode, "Responder Tudo dos Selecionados", "Responde qualquer msg deles mesmo sem te citar", Config.ReplyAllFromTargets, function(val)
            Config.ReplyAllFromTargets = val
        end)

        local cardPicker = createCard(pageAlvos, "Jogadores no Servidor (Toque para Marcar)")
        local actionsRow = Instance.new("Frame")
        actionsRow.Size = UDim2.new(1, 0, 0, 28)
        actionsRow.BackgroundTransparency = 1
        actionsRow.Parent = cardPicker

        local refreshBtn = Instance.new("TextButton")
        refreshBtn.Size = UDim2.new(0.48, 0, 1, 0)
        refreshBtn.BackgroundColor3 = Color3.fromRGB(45, 52, 74)
        refreshBtn.Font = Enum.Font.GothamBold
        refreshBtn.Text = "Atualizar Lista"
        refreshBtn.TextColor3 = Theme.TextMain
        refreshBtn.TextSize = 11
        refreshBtn.Parent = actionsRow
        makeCorner(refreshBtn, 7)

        local clearBtn = Instance.new("TextButton")
        clearBtn.Size = UDim2.new(0.48, 0, 1, 0)
        clearBtn.Position = UDim2.new(0.52, 0, 0, 0)
        clearBtn.BackgroundColor3 = Color3.fromRGB(70, 42, 50)
        clearBtn.Font = Enum.Font.GothamBold
        clearBtn.Text = "Desmarcar Todos"
        clearBtn.TextColor3 = Color3.fromRGB(255, 220, 225)
        clearBtn.TextSize = 11
        clearBtn.Parent = actionsRow
        makeCorner(clearBtn, 7)

        local listHolder = Instance.new("Frame")
        listHolder.Size = UDim2.new(1, 0, 0, 0)
        listHolder.AutomaticSize = Enum.AutomaticSize.Y
        listHolder.BackgroundTransparency = 1
        listHolder.Parent = cardPicker
        local listLayout = Instance.new("UIListLayout")
        listLayout.Padding = UDim.new(0, 5)
        listLayout.Parent = listHolder

        local function rebuildPlayerList()
            for _, child in ipairs(listHolder:GetChildren()) do
                if child:IsA("GuiObject") then
                    child:Destroy()
                end
            end
            local others = {}
            for _, plr in ipairs(Players:GetPlayers()) do
                if plr ~= LocalPlayer then
                    table.insert(others, plr)
                end
            end
            table.sort(others, function(a, b) return a.DisplayName:lower() < b.DisplayName:lower() end)

            if #others == 0 then
                local empty = Instance.new("TextLabel")
                empty.Size = UDim2.new(1, 0, 0, 26)
                empty.BackgroundColor3 = Theme.Input
                empty.Font = Enum.Font.Gotham
                empty.Text = "Nenhum outro jogador no servidor."
                empty.TextColor3 = Theme.TextMuted
                empty.TextSize = 11
                empty.Parent = listHolder
                makeCorner(empty, 7)
                return
            end

            for _, plr in ipairs(others) do
                local key = Security.normalize(plr.Name)
                local selected = Config.TargetPlayers[key] == true

                local pBtn = Instance.new("TextButton")
                pBtn.Size = UDim2.new(1, 0, 0, 34)
                pBtn.BackgroundColor3 = selected and Color3.fromRGB(34, 62, 50) or Theme.Input
                pBtn.Text = ""
                pBtn.AutoButtonColor = false
                pBtn.Parent = listHolder
                makeCorner(pBtn, 8)
                local pStroke = makeStroke(pBtn, selected and Theme.Success or Color3.fromRGB(48, 55, 76), 1, selected and 0.15 or 0.5)

                local nameLbl = Instance.new("TextLabel")
                nameLbl.Size = UDim2.new(1, -78, 1, 0)
                nameLbl.Position = UDim2.fromOffset(10, 0)
                nameLbl.BackgroundTransparency = 1
                nameLbl.Font = Enum.Font.GothamMedium
                nameLbl.Text = (plr.DisplayName ~= plr.Name) and string.format("%s (@%s)", plr.DisplayName, plr.Name) or ("@" .. plr.Name)
                nameLbl.TextColor3 = Theme.TextMain
                nameLbl.TextSize = 11
                nameLbl.TextXAlignment = Enum.TextXAlignment.Left
                nameLbl.TextTruncate = Enum.TextTruncate.AtEnd
                nameLbl.Parent = pBtn

                local tagLbl = Instance.new("TextLabel")
                tagLbl.Size = UDim2.fromOffset(62, 20)
                tagLbl.Position = UDim2.new(1, -68, 0.5, -10)
                tagLbl.BackgroundColor3 = selected and Theme.Success or Color3.fromRGB(42, 47, 65)
                tagLbl.Font = Enum.Font.GothamBold
                tagLbl.Text = selected and "ATIVO" or "OFF"
                tagLbl.TextColor3 = Color3.fromRGB(255, 255, 255)
                tagLbl.TextSize = 9
                tagLbl.Parent = pBtn
                makeCorner(tagLbl, 6)

                pBtn.MouseButton1Click:Connect(function()
                    local newState = not (Config.TargetPlayers[key] == true)
                    Config.TargetPlayers[key] = newState or nil
                    tweenProp(pBtn, { BackgroundColor3 = newState and Color3.fromRGB(34, 62, 50) or Theme.Input }, 0.12)
                    pStroke.Color = newState and Theme.Success or Color3.fromRGB(48, 55, 76)
                    pStroke.Transparency = newState and 0.15 or 0.5
                    tagLbl.BackgroundColor3 = newState and Theme.Success or Color3.fromRGB(42, 47, 65)
                    tagLbl.Text = newState and "ATIVO" or "OFF"
                end)
            end
        end

        refreshBtn.MouseButton1Click:Connect(rebuildPlayerList)
        clearBtn.MouseButton1Click:Connect(function()
            table.clear(Config.TargetPlayers)
            rebuildPlayerList()
            addLog("Alvos", "Selecionados limpos.", Color3.fromRGB(165, 210, 255))
        end)
        trackConnection(Players.PlayerAdded:Connect(function() task.defer(rebuildPlayerList) end))
        trackConnection(Players.PlayerRemoving:Connect(function() task.defer(rebuildPlayerList) end))
        rebuildPlayerList()

        local cardTiming = createCard(pageAlvos, "Agilidade e Bloqueios")
        local tHint = Instance.new("TextLabel")
        tHint.Size = UDim2.new(1, 0, 0, 14)
        tHint.BackgroundTransparency = 1
        tHint.Font = Enum.Font.Gotham
        tHint.Text = "Intervalo entre falas (s)                    Chance aleatória (%)"
        tHint.TextColor3 = Theme.TextMuted
        tHint.TextSize = 10
        tHint.TextXAlignment = Enum.TextXAlignment.Left
        tHint.Parent = cardTiming

        local ctrlRow = Instance.new("Frame")
        ctrlRow.Size = UDim2.new(1, 0, 0, 32)
        ctrlRow.BackgroundTransparency = 1
        ctrlRow.Parent = cardTiming

        local cdBox = createInputBox(ctrlRow, "Intervalo", tostring(Config.CooldownSeconds), 32)
        cdBox.Size = UDim2.new(0.48, 0, 1, 0)
        local chanceBox = createInputBox(ctrlRow, "Chance %", tostring(Config.RandomReplyChance), 32)
        chanceBox.Size = UDim2.new(0.48, 0, 1, 0)
        chanceBox.Position = UDim2.new(0.52, 0, 0, 0)

        cdBox.FocusLost:Connect(function()
            Config.CooldownSeconds = math.clamp(tonumber(cdBox.Text) or Config.CooldownSeconds, 0.3, 120)
            cdBox.Text = tostring(Config.CooldownSeconds)
        end)
        chanceBox.FocusLost:Connect(function()
            Config.RandomReplyChance = math.clamp(math.floor(tonumber(chanceBox.Text) or Config.RandomReplyChance), 0, 100)
            chanceBox.Text = tostring(Config.RandomReplyChance)
        end)

        local ignoredBox = createInputBox(cardTiming, "Jogadores ignorados (Ex: Fulano, Ciclano)", "", 32)
        ignoredBox.FocusLost:Connect(function() Config.IgnoredPlayers = Security.parseCommaList(ignoredBox.Text) end)

        local forbiddenBox = createInputBox(cardTiming, "Palavras proibidas (separadas por vírgula)", "", 32)
        forbiddenBox.FocusLost:Connect(function() Config.ForbiddenWords = Security.parseCommaList(forbiddenBox.Text) end)
    end

    -- ABA 3: PERSONA
    do
        local cardParams = createCard(pageIA, "Parâmetros da Resposta")
        local pHint = Instance.new("TextLabel")
        pHint.Size = UDim2.new(1, 0, 0, 14)
        pHint.BackgroundTransparency = 1
        pHint.Font = Enum.Font.Gotham
        pHint.Text = "Temperatura (0-2)        Máx. Caracteres        Timeout (s)"
        pHint.TextColor3 = Theme.TextMuted
        pHint.TextSize = 10
        pHint.TextXAlignment = Enum.TextXAlignment.Left
        pHint.Parent = cardParams

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

        createSwitchRow(cardParams, "Evitar risadas (kkk / haha)", "Impede a IA de usar 'kk' ou 'kkkk' sem motivo", Config.PreventUnnecessaryLaugh, function(val)
            Config.PreventUnnecessaryLaugh = val
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
        for _, pName in ipairs({ "Amigável", "Engraçada", "Séria", "Sarcástica", "Inteligente", "Extrovertida", "Misteriosa", "Personalizada" }) do
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

        local customBox = createInputBox(cardPersona, "Personalidade personalizada (opcional)...", Config.CustomPersonality, 72, true)
        customBox.FocusLost:Connect(function()
            Config.CustomPersonality = customBox.Text
            if Security.trim(customBox.Text) ~= "" then
                Config.PersonalityPreset = "Personalizada"
                refreshPersonaButtons()
            end
        end)
    end

    -- ABA 4: VOZ
    do
        local function kindColor(kind)
            if kind == "ok" then
                return Theme.Success
            elseif kind == "warn" then
                return Theme.Warning
            end
            return Theme.Danger
        end

        local function makeRow(parent, height)
            local row = Instance.new("Frame")
            row.Size = UDim2.new(1, 0, 0, height)
            row.BackgroundTransparency = 1
            row.Parent = parent
            local layout = Instance.new("UIListLayout")
            layout.FillDirection = Enum.FillDirection.Horizontal
            layout.Padding = UDim.new(0, 6)
            layout.Parent = row
            return row
        end

        local function makeBtn(parent, text, color, widthScale, textColor)
            local b = Instance.new("TextButton")
            local n = math.max(1, math.floor(1 / widthScale + 0.5))
            b.Size = UDim2.new(widthScale, -math.floor(6 * (n - 1) / n + 0.5), 1, 0)
            b.BackgroundColor3 = color
            b.Font = Enum.Font.GothamBold
            b.Text = text
            b.TextColor3 = textColor or Color3.fromRGB(255, 255, 255)
            b.TextSize = 11
            b.Parent = parent
            makeCorner(b, 8)
            return b
        end

        local duckSwitch, eqSwitch, volBox

        -- ===== Card 1: liga/desliga + status ao vivo =====
        local cardVoiceMain = createCard(pageVoz, "Resposta por Áudio")
        createSwitchRow(cardVoiceMain, "Ativar Resposta por Áudio", "A IA fala as respostas no chat de voz", Config.FishAudio.Enabled, function(val)
            Config.FishAudio.Enabled = val
            updateVoiceStatus(val and "Pronto (Áudio Ativo)" or "Desativado", val and Theme.Success or Theme.TextMuted)
        end)
        createSwitchRow(cardVoiceMain, "Enviar texto no chat também", "Mantém o texto no chat além do áudio", Config.SendTextInChat, function(val)
            Config.SendTextInChat = val
        end)

        local statusRow = Instance.new("Frame")
        statusRow.Size = UDim2.new(1, 0, 0, 32)
        statusRow.BackgroundColor3 = Theme.Input
        statusRow.Parent = cardVoiceMain
        makeCorner(statusRow, 8)

        local voiceStatusLbl = Instance.new("TextLabel")
        voiceStatusLbl.Size = UDim2.new(1, -66, 1, 0)
        voiceStatusLbl.Position = UDim2.fromOffset(10, 0)
        voiceStatusLbl.BackgroundTransparency = 1
        voiceStatusLbl.Font = Enum.Font.GothamMedium
        voiceStatusLbl.Text = "Status Áudio: " .. idleStatus()
        voiceStatusLbl.TextColor3 = Theme.TextMuted
        voiceStatusLbl.TextSize = 11
        voiceStatusLbl.TextXAlignment = Enum.TextXAlignment.Left
        voiceStatusLbl.TextTruncate = Enum.TextTruncate.AtEnd
        voiceStatusLbl.Parent = statusRow
        UI.Elements.VoiceStatusLabel = voiceStatusLbl

        local waveHolder = Instance.new("Frame")
        waveHolder.Size = UDim2.fromOffset(44, 24)
        waveHolder.Position = UDim2.new(1, -52, 0.5, -12)
        waveHolder.BackgroundTransparency = 1
        waveHolder.Parent = statusRow
        local waveLayout = Instance.new("UIListLayout")
        waveLayout.FillDirection = Enum.FillDirection.Horizontal
        waveLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
        waveLayout.VerticalAlignment = Enum.VerticalAlignment.Center
        waveLayout.Padding = UDim.new(0, 3)
        waveLayout.SortOrder = Enum.SortOrder.LayoutOrder
        waveLayout.Parent = waveHolder
        local bars = {}
        for i = 1, 6 do
            local bar = Instance.new("Frame")
            bar.Size = UDim2.fromOffset(4, 3)
            bar.BackgroundColor3 = Theme.Success
            bar.BorderSizePixel = 0
            bar.LayoutOrder = i
            bar.Parent = waveHolder
            makeCorner(bar, 2)
            bars[i] = bar
        end

        local micRow = Instance.new("Frame")
        micRow.Size = UDim2.new(1, 0, 0, 24)
        micRow.BackgroundTransparency = 1
        micRow.Parent = cardVoiceMain

        local micLbl = Instance.new("TextLabel")
        micLbl.Size = UDim2.new(1, -100, 1, 0)
        micLbl.BackgroundTransparency = 1
        micLbl.Font = Enum.Font.Gotham
        micLbl.Text = "Microfone do Roblox (ao vivo)"
        micLbl.TextColor3 = Theme.TextMuted
        micLbl.TextSize = 11
        micLbl.TextXAlignment = Enum.TextXAlignment.Left
        micLbl.Parent = micRow

        local micPill = Instance.new("TextLabel")
        micPill.Size = UDim2.fromOffset(92, 20)
        micPill.Position = UDim2.new(1, -92, 0.5, -10)
        micPill.BackgroundColor3 = Theme.Warning
        micPill.Font = Enum.Font.GothamBold
        micPill.Text = "..."
        micPill.TextColor3 = Color3.fromRGB(255, 255, 255)
        micPill.TextSize = 10
        micPill.Parent = micRow
        makeCorner(micPill, 10)

        -- ===== Card 2: rota do áudio =====
        local cardRoute = createCard(pageVoz, "Rota do Áudio até o Microfone")
        local isMobileDevice = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
        if Config.FishAudio.RouteMode == nil then
            Config.FishAudio.RouteMode = isMobileDevice and "Mobile" or "PC"
        end

        local ROUTES = {
            PC = {
                label = "PC (Cabo Virtual)",
                text = "O Roblox não deixa o script mandar áudio direto pro VC; o som precisa entrar no microfone.\n\n1) Instale o VB-Cable (gratuito).\n2) Windows > Som > Mixer de volume: saída do Roblox = CABLE Input.\n3) No Roblox (Esc > Configurações), dispositivo de entrada (mic) = CABLE Output.\n4) Pra você ouvir: Painel de Som > Gravação > CABLE Output > Propriedades > Ouvir > 'Ouvir este dispositivo'.",
                duck = true, eq = false, volume = 5,
            },
            Mobile = {
                label = "Celular (Alto-falante)",
                text = "O Roblox não deixa o script mandar áudio direto pro VC; no celular o som sai no alto-falante e o mic capta pelo ar.\n\nSem fone de ouvido, volume do celular no máximo, permissão de microfone liberada pro Roblox e ambiente silencioso. Fica um pouco abafado e o cancelamento de eco do aparelho pode cortar a voz.",
                duck = true, eq = true, volume = 8,
            },
        }

        local routeRow = makeRow(cardRoute, 30)
        local routeButtons = {}
        local routeInfo = Instance.new("TextLabel")
        routeInfo.Size = UDim2.new(1, 0, 0, 0)
        routeInfo.AutomaticSize = Enum.AutomaticSize.Y
        routeInfo.BackgroundColor3 = Color3.fromRGB(28, 33, 48)
        routeInfo.Font = Enum.Font.Gotham
        routeInfo.TextColor3 = Color3.fromRGB(185, 198, 230)
        routeInfo.TextSize = 10
        routeInfo.TextWrapped = true
        routeInfo.TextXAlignment = Enum.TextXAlignment.Left
        routeInfo.TextYAlignment = Enum.TextYAlignment.Top
        routeInfo.Parent = cardRoute
        makeCorner(routeInfo, 8)
        local routePad = Instance.new("UIPadding")
        routePad.PaddingTop = UDim.new(0, 8)
        routePad.PaddingBottom = UDim.new(0, 8)
        routePad.PaddingLeft = UDim.new(0, 10)
        routePad.PaddingRight = UDim.new(0, 10)
        routePad.Parent = routeInfo

        local function refreshRoute(applyPreset)
            local mode = Config.FishAudio.RouteMode
            for id, btn in pairs(routeButtons) do
                local active = (id == mode)
                tweenProp(btn, {
                    BackgroundColor3 = active and Theme.Accent or Theme.Input,
                    TextColor3 = active and Color3.fromRGB(255, 255, 255) or Theme.TextMuted,
                }, 0.15)
            end
            local route = ROUTES[mode]
            routeInfo.Text = route.text
            if applyPreset then
                Config.FishAudio.DuckGameAudio = route.duck
                Config.FishAudio.VoiceBoostEQ = route.eq
                Config.FishAudio.PlaybackVolume = route.volume
                if duckSwitch then duckSwitch.SetVisual(route.duck) end
                if eqSwitch then eqSwitch.SetVisual(route.eq) end
                if volBox then volBox.Text = tostring(route.volume) end
            end
        end
        for _, id in ipairs({ "PC", "Mobile" }) do
            local b = makeBtn(routeRow, ROUTES[id].label, Theme.Input, 0.5, Theme.TextMuted)
            b.TextSize = 10
            routeButtons[id] = b
            b.MouseButton1Click:Connect(function()
                Config.FishAudio.RouteMode = id
                refreshRoute(true)
            end)
        end

        -- ===== Card 3: provedor =====
        local cardProv = createCard(pageVoz, "Provedor de Voz")
        local provRow = makeRow(cardProv, 30)
        local provButtons = {}
        local function refreshProv()
            for id, btn in pairs(provButtons) do
                local active = (Config.FishAudio.Provider == id)
                tweenProp(btn, {
                    BackgroundColor3 = active and Theme.Accent or Theme.Input,
                    TextColor3 = active and Color3.fromRGB(255, 255, 255) or Theme.TextMuted,
                }, 0.15)
            end
        end
        for _, opt in ipairs({
            { id = "Fish", label = "Fish Audio (chave)" },
            { id = "Google", label = "Google (sem chave)" },
        }) do
            local b = makeBtn(provRow, opt.label, Theme.Input, 0.5, Theme.TextMuted)
            b.TextSize = 10
            provButtons[opt.id] = b
            b.MouseButton1Click:Connect(function()
                Config.FishAudio.Provider = opt.id
                refreshProv()
            end)
        end
        refreshProv()
        createSwitchRow(cardProv, "Trocar sozinho se falhar", "Se um provedor cair, tenta o outro", Config.FishAudio.FallbackProvider, function(val)
            Config.FishAudio.FallbackProvider = val
        end)
        createSwitchRow(cardProv, "Salvar última fala em arquivo", "AutoAI_ultima_fala na pasta do executor", Config.FishAudio.SaveLastFile, function(val)
            Config.FishAudio.SaveLastFile = val
        end)

        -- ===== Card 4: ritmo e saída =====
        local cardEngine = createCard(pageVoz, "Ritmo da Voz e Saída")
        local speedPresetRow = makeRow(cardEngine, 28)

        local speedBox
        for _, sp in ipairs({
            { label = "Bem Calma (0.85)", val = 0.85 },
            { label = "Calma (0.90)", val = 0.90 },
            { label = "Normal (1.0)", val = 1.00 },
        }) do
            local b = makeBtn(speedPresetRow, sp.label, (math.abs(Config.FishAudio.Speed - sp.val) < 0.02) and Theme.Accent or Theme.Input, 0.3333, Theme.TextMain)
            b.TextSize = 10
            b.MouseButton1Click:Connect(function()
                Config.FishAudio.Speed = sp.val
                if speedBox then speedBox.Text = tostring(sp.val) end
                for _, sib in ipairs(speedPresetRow:GetChildren()) do
                    if sib:IsA("TextButton") then sib.BackgroundColor3 = Theme.Input end
                end
                b.BackgroundColor3 = Theme.Accent
            end)
        end

        local outModeRow = makeRow(cardEngine, 30)
        local outButtons = {}
        local function refreshOutMode()
            for id, b in pairs(outButtons) do
                local active = (Config.FishAudio.OutputMode == id)
                tweenProp(b, {
                    BackgroundColor3 = active and Theme.Accent or Theme.Input,
                    TextColor3 = active and Color3.fromRGB(255, 255, 255) or Theme.TextMuted,
                }, 0.15)
            end
        end
        for _, opt in ipairs({
            { id = "SoundService", label = "Alto-falante (Sound)" },
            { id = "AudioAPI", label = "Audio API (Player)" },
        }) do
            local b = makeBtn(outModeRow, opt.label, Theme.Input, 0.5, Theme.TextMuted)
            b.TextSize = 10
            outButtons[opt.id] = b
            b.MouseButton1Click:Connect(function()
                Config.FishAudio.OutputMode = opt.id
                refreshOutMode()
            end)
        end
        refreshOutMode()

        createSwitchRow(cardEngine, "Auto-Abrir Mic VC ao falar", "Abre o mic antes da fala e fecha depois", Config.FishAudio.AutoToggleVC, function(val)
            Config.FishAudio.AutoToggleVC = val
        end)
        duckSwitch = createSwitchRow(cardEngine, "Abaixar áudio do jogo ao falar", "Só a voz da IA vai pro mic (sem música/efeitos)", Config.FishAudio.DuckGameAudio, function(val)
            Config.FishAudio.DuckGameAudio = val
        end)
        eqSwitch = createSwitchRow(cardEngine, "Realce de Voz (EQ)", "Voz mais nítida no alto-falante do celular", Config.FishAudio.VoiceBoostEQ, function(val)
            Config.FishAudio.VoiceBoostEQ = val
        end)

        local audioRow = Instance.new("Frame")
        audioRow.Size = UDim2.new(1, 0, 0, 48)
        audioRow.BackgroundTransparency = 1
        audioRow.Parent = cardEngine

        local function labeledColumn(xScale, labelText)
            local col = Instance.new("Frame")
            col.Size = UDim2.new(0.31, 0, 1, 0)
            col.Position = UDim2.new(xScale, 0, 0, 0)
            col.BackgroundTransparency = 1
            col.Parent = audioRow
            local lbl = Instance.new("TextLabel")
            lbl.Size = UDim2.new(1, 0, 0, 14)
            lbl.BackgroundTransparency = 1
            lbl.Font = Enum.Font.Gotham
            lbl.Text = labelText
            lbl.TextColor3 = Theme.TextMuted
            lbl.TextSize = 10
            lbl.TextXAlignment = Enum.TextXAlignment.Left
            lbl.Parent = col
            return col
        end

        local colSpeed = labeledColumn(0, "Velocidade (0.5-2)")
        speedBox = createInputBox(colSpeed, "Speed", tostring(Config.FishAudio.Speed), 30)
        speedBox.Position = UDim2.fromOffset(0, 17)

        local colVol = labeledColumn(0.345, "Volume (0-10)")
        volBox = createInputBox(colVol, "Vol", tostring(Config.FishAudio.PlaybackVolume), 30)
        volBox.Position = UDim2.fromOffset(0, 17)

        local colFmt = labeledColumn(0.69, "Formato (Fish)")
        local fmtBtn = Instance.new("TextButton")
        fmtBtn.Size = UDim2.new(1, 0, 0, 30)
        fmtBtn.Position = UDim2.fromOffset(0, 17)
        fmtBtn.BackgroundColor3 = Theme.Input
        fmtBtn.Font = Enum.Font.GothamBold
        fmtBtn.Text = string.upper(Config.FishAudio.Format)
        fmtBtn.TextColor3 = Theme.TextMain
        fmtBtn.TextSize = 11
        fmtBtn.Parent = colFmt
        makeCorner(fmtBtn, 8)
        makeStroke(fmtBtn, Color3.fromRGB(48, 55, 76), 1, 0.4)

        speedBox.FocusLost:Connect(function()
            Config.FishAudio.Speed = math.clamp(tonumber(speedBox.Text) or Config.FishAudio.Speed, 0.5, 2.0)
            speedBox.Text = tostring(Config.FishAudio.Speed)
        end)
        volBox.FocusLost:Connect(function()
            Config.FishAudio.PlaybackVolume = math.clamp(tonumber(volBox.Text) or Config.FishAudio.PlaybackVolume, 0, 10)
            volBox.Text = tostring(Config.FishAudio.PlaybackVolume)
        end)
        fmtBtn.MouseButton1Click:Connect(function()
            Config.FishAudio.Format = (Config.FishAudio.Format == "mp3") and "wav" or "mp3"
            fmtBtn.Text = string.upper(Config.FishAudio.Format)
        end)

        refreshRoute(false)

        -- ===== Card 5: diagnóstico e testes =====
        local cardDiag = createCard(pageVoz, "Diagnóstico e Testes")
        local diagLabel = Instance.new("TextLabel")
        diagLabel.Size = UDim2.new(1, 0, 0, 42)
        diagLabel.BackgroundColor3 = Theme.Input
        diagLabel.Font = Enum.Font.Gotham
        diagLabel.Text = VoiceTTS.inspectVoiceEnvironment().Summary
        diagLabel.TextColor3 = Theme.TextMuted
        diagLabel.TextSize = 10
        diagLabel.TextWrapped = true
        diagLabel.Parent = cardDiag
        makeCorner(diagLabel, 8)

        local btnRow1 = makeRow(cardDiag, 34)
        local diagBtn = makeBtn(btnRow1, "Diagnóstico Completo", Theme.Accent, 0.5)
        local toneBtn = makeBtn(btnRow1, "Tom de Teste", Color3.fromRGB(45, 52, 74), 0.5, Theme.TextMain)
        local btnRow2 = makeRow(cardDiag, 34)
        local testVBtn = makeBtn(btnRow2, "Testar Voz (TTS)", Theme.Accent, 0.5)
        local stopVBtn = makeBtn(btnRow2, "Parar", Theme.Danger, 0.5)

        local diagResults = Instance.new("Frame")
        diagResults.Size = UDim2.new(1, 0, 0, 0)
        diagResults.AutomaticSize = Enum.AutomaticSize.Y
        diagResults.BackgroundTransparency = 1
        diagResults.Parent = cardDiag
        local diagLayout = Instance.new("UIListLayout")
        diagLayout.Padding = UDim.new(0, 4)
        diagLayout.SortOrder = Enum.SortOrder.LayoutOrder
        diagLayout.Parent = diagResults

        local diagCount = 0
        local function clearResults()
            diagCount = 0
            for _, child in ipairs(diagResults:GetChildren()) do
                if child:IsA("GuiObject") then
                    child:Destroy()
                end
            end
        end
        local function addResultRow(label, kind, detail)
            diagCount = diagCount + 1
            local row = Instance.new("Frame")
            row.Size = UDim2.new(1, 0, 0, 0)
            row.AutomaticSize = Enum.AutomaticSize.Y
            row.BackgroundColor3 = Theme.Input
            row.LayoutOrder = diagCount
            row.Parent = diagResults
            makeCorner(row, 7)
            local rowPad = Instance.new("UIPadding")
            rowPad.PaddingTop = UDim.new(0, 5)
            rowPad.PaddingBottom = UDim.new(0, 5)
            rowPad.PaddingLeft = UDim.new(0, 6)
            rowPad.PaddingRight = UDim.new(0, 6)
            rowPad.Parent = row

            local tag = Instance.new("TextLabel")
            tag.Size = UDim2.fromOffset(44, 16)
            tag.BackgroundColor3 = kindColor(kind)
            tag.Font = Enum.Font.GothamBold
            tag.Text = (kind == "ok") and "OK" or ((kind == "warn") and "AVISO" or "ERRO")
            tag.TextColor3 = Color3.fromRGB(255, 255, 255)
            tag.TextSize = 9
            tag.Parent = row
            makeCorner(tag, 5)

            local txt = Instance.new("TextLabel")
            txt.Size = UDim2.new(1, -52, 0, 16)
            txt.Position = UDim2.fromOffset(52, 0)
            txt.AutomaticSize = Enum.AutomaticSize.Y
            txt.BackgroundTransparency = 1
            txt.Font = Enum.Font.Gotham
            txt.Text = label .. ": " .. tostring(detail)
            txt.TextColor3 = Theme.TextMain
            txt.TextSize = 10
            txt.TextWrapped = true
            txt.TextXAlignment = Enum.TextXAlignment.Left
            txt.TextYAlignment = Enum.TextYAlignment.Top
            txt.Parent = row
        end

        local busyDiag = false
        diagBtn.MouseButton1Click:Connect(function()
            if busyDiag then return end
            busyDiag = true
            diagBtn.Text = "Verificando..."
            clearResults()
            task.spawn(function()
                local okRun, errRun = pcall(function()
                    VoiceTTS.runDiagnostics(function(label, kind, detail)
                        addResultRow(label, kind, detail)
                        addLog("Diag Voz", label .. ": " .. tostring(detail), kindColor(kind))
                    end)
                end)
                if not okRun then
                    addResultRow("Erro interno", "fail", tostring(errRun))
                end
                diagLabel.Text = VoiceTTS.inspectVoiceEnvironment().Summary
                diagBtn.Text = "Diagnóstico Completo"
                busyDiag = false
            end)
        end)

        toneBtn.MouseButton1Click:Connect(function()
            toneBtn.Text = "Tocando..."
            task.spawn(function()
                local ok, msg = VoiceTTS.playTestTone()
                if ok then
                    addLog("Tom Teste", "Tom tocando. Confirme com alguém no VC se chegou.", Theme.Success)
                else
                    addLog("Erro Tom", tostring(msg), Theme.Danger)
                    clearResults()
                    addResultRow("Tom de teste", "fail", tostring(msg))
                end
                toneBtn.Text = "Tom de Teste"
            end)
        end)

        testVBtn.MouseButton1Click:Connect(function()
            testVBtn.Text = "Gerando..."
            task.spawn(function()
                local ok, msg = callbacks.onTestVoice()
                addLog(ok and "Teste Voz" or "Erro Voz", ok and "Áudio reproduzido." or tostring(msg), ok and Theme.Success or Theme.Danger)
                if not ok then
                    clearResults()
                    addResultRow("Testar Voz", "fail", tostring(msg))
                end
                testVBtn.Text = "Testar Voz (TTS)"
            end)
        end)

        stopVBtn.MouseButton1Click:Connect(function()
            VoiceTTS.stopCurrent()
            updateVoiceStatus("Som interrompido", Theme.Warning)
        end)

        -- ===== Animação da onda + mic ao vivo =====
        task.spawn(function()
            local t = 0
            local tick = 0
            while UI.Root and UI.Root.Parent do
                t = t + 0.08
                tick = tick + 1
                local speaking = Runtime.IsSpeaking
                for i, bar in ipairs(bars) do
                    local h = speaking and (4 + math.abs(math.sin(t * 3 + i * 0.9)) * 18) or 3
                    bar.Size = UDim2.fromOffset(4, math.floor(h))
                end
                if tick % 12 == 1 then
                    local okMic, mic = pcall(VoiceTTS.getMicState)
                    if okMic and mic then
                        micPill.Text = string.upper(mic.Label)
                        micPill.BackgroundColor3 = kindColor(mic.Kind)
                    end
                end
                task.wait(0.08)
            end
        end)
    end

    -- ABA 5: LOG
    do
        local cardHist = createCard(pageHistorico, "Memória e Comandos")
        local clearHistBtn = Instance.new("TextButton")
        clearHistBtn.Size = UDim2.new(1, 0, 0, 32)
        clearHistBtn.BackgroundColor3 = Theme.Danger
        clearHistBtn.Font = Enum.Font.GothamBold
        clearHistBtn.Text = "Limpar Memória de Conversa"
        clearHistBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
        clearHistBtn.TextSize = 12
        clearHistBtn.Parent = cardHist
        makeCorner(clearHistBtn, 8)
        clearHistBtn.MouseButton1Click:Connect(callbacks.onClearHistory)

        local cmdHint = Instance.new("TextLabel")
        cmdHint.Size = UDim2.new(1, 0, 0, 14)
        cmdHint.BackgroundTransparency = 1
        cmdHint.Font = Enum.Font.Gotham
        cmdHint.Text = "Chat: !ia on | !ia off | !ia clear"
        cmdHint.TextColor3 = Theme.TextMuted
        cmdHint.TextSize = 10
        cmdHint.TextXAlignment = Enum.TextXAlignment.Left
        cmdHint.Parent = cardHist

        local logScroll = Instance.new("ScrollingFrame")
        logScroll.Size = UDim2.new(1, 0, 0, 210)
        logScroll.BackgroundColor3 = Theme.Card
        logScroll.BackgroundTransparency = 0.08
        logScroll.BorderSizePixel = 0
        logScroll.ScrollBarThickness = 3
        logScroll.ScrollBarImageColor3 = Theme.Accent
        logScroll.CanvasSize = UDim2.fromOffset(0, 0)
        logScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
        logScroll.Parent = pageHistorico
        makeCorner(logScroll, 10)
        makeStroke(logScroll, Theme.Stroke, 1, 0.5)

        local logLayout = Instance.new("UIListLayout")
        logLayout.Padding = UDim.new(0, 5)
        logLayout.Parent = logScroll

        local logPad = Instance.new("UIPadding")
        logPad.PaddingTop = UDim.new(0, 8)
        logPad.PaddingBottom = UDim.new(0, 8)
        logPad.PaddingLeft = UDim.new(0, 10)
        logPad.PaddingRight = UDim.new(0, 10)
        logPad.Parent = logScroll

        UI.LogCallback = function(tag, text, color)
            if not logScroll or not logScroll.Parent then
                return
            end
            local row = Instance.new("TextLabel")
            row.Size = UDim2.new(1, -4, 0, 0)
            row.AutomaticSize = Enum.AutomaticSize.Y
            row.BackgroundTransparency = 1
            row.Font = Enum.Font.Gotham
            row.Text = string.format("[%s] %s", tag, text)
            row.TextColor3 = color or Theme.TextMain
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
    end

    local minimized = false
    minBtn.MouseButton1Click:Connect(function()
        minimized = not minimized
        local curW, curH = getWindowSize()
        if minimized then
            tabBar.Visible = false
            contentHolder.Visible = false
            statusBadge.Visible = false
            subTitleLabel.Visible = false
            titleLabel.Position = UDim2.fromOffset(14, 13)
            miniPowerBtn.Visible = true
            tweenProp(mainFrame, { Size = UDim2.fromOffset(275, 46) }, 0.22)
            minBtn.Text = "+"
        else
            miniPowerBtn.Visible = false
            statusBadge.Visible = true
            subTitleLabel.Visible = true
            titleLabel.Position = UDim2.fromOffset(14, 6)
            tweenProp(mainFrame, { Size = UDim2.fromOffset(curW, curH) }, 0.22)
            task.delay(0.14, function()
                if not minimized and tabBar and contentHolder then
                    tabBar.Visible = true
                    contentHolder.Visible = true
                end
            end)
            minBtn.Text = "—"
        end
    end)

    closeBtn.MouseButton1Click:Connect(function()
        if globalEnv.__RobloxAutoAI_Cleanup then
            globalEnv.__RobloxAutoAI_Cleanup()
        end
    end)

    -- Hover nos botões (PC)
    for _, d in ipairs(mainFrame:GetDescendants()) do
        if d:IsA("TextButton") and d.Name ~= "TabBtn" and d.Text ~= "" and d.BackgroundTransparency < 1 then
            local base = d.BackgroundTransparency
            trackConnection(d.MouseEnter:Connect(function()
                tweenProp(d, { BackgroundTransparency = math.min(base + 0.2, 0.9) }, 0.12)
            end))
            trackConnection(d.MouseLeave:Connect(function()
                tweenProp(d, { BackgroundTransparency = base }, 0.12)
            end))
        end
    end

    UI.Elements.SyncPower = syncPowerState
    UI.Elements.StatusDot = statusDot
    UI.Elements.StatusText = statusText
end

function UI.setStatus(status)
    local dot, lbl = UI.Elements.StatusDot, UI.Elements.StatusText
    if not dot or not lbl then
        return
    end
    lbl.Text = status
    if status == "Conectado" then
        tweenProp(dot, { BackgroundColor3 = Theme.Success }, 0.15)
    elseif status == "Erro" then
        tweenProp(dot, { BackgroundColor3 = Theme.Danger }, 0.15)
    else
        tweenProp(dot, { BackgroundColor3 = Theme.Warning }, 0.15)
    end
end

-- =========================================================================
-- MÓDULO 9: PROCESSAMENTO DE MENSAGENS
-- =========================================================================
local MessageProcessor = {}

local function isMentioningMe(text)
    local lower = Security.normalize(text)
    local userLower = Security.normalize(LocalPlayer.Name)
    local dispLower = Security.normalize(LocalPlayer.DisplayName)
    return (userLower ~= "" and lower:find(userLower, 1, true) ~= nil)
        or (dispLower ~= "" and #dispLower >= 2 and lower:find(dispLower, 1, true) ~= nil)
end

local function isPlayerNearby(player)
    if not player or not player.Character or not LocalPlayer.Character then
        return false
    end
    local rootA = player.Character:FindFirstChild("HumanoidRootPart")
    local rootB = LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
    return (rootA and rootB) and ((rootA.Position - rootB.Position).Magnitude <= Config.MaxProximityStuds) or false
end

local function shouldReplyToMessage(player, playerName, displayName, text)
    local isTargeted = Security.isPlayerTargeted(playerName, displayName)
    if Config.TargetOnly then
        if not isTargeted then
            return false
        end
        if Config.ReplyAllFromTargets then
            return true
        end
    elseif isTargeted and Config.ReplyAllFromTargets then
        return true
    end

    local mentioned = isMentioningMe(text)
    if Config.ResponseMode == "MentionOnly" then
        return mentioned
    elseif Config.ResponseMode == "DirectOnly" then
        if mentioned then
            return true
        end
        if (Runtime.LastDirectTalker == playerName) and ((os.clock() - Runtime.LastDirectTime) <= Config.ConversationActiveWindow) then
            return true
        end
        if player and isPlayerNearby(player) then
            local lower = Security.normalize(text)
            if lower:find("%?") or lower:match("^oi") or lower:match("^ola") or lower:match("^ei") or lower:match("^mano") or lower:match("^cara") then
                return true
            end
        end
        return false
    elseif Config.ResponseMode == "All" then
        return mentioned or (math.random(1, 100) <= Config.RandomReplyChance)
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
        if UI.Elements.SyncPower then UI.Elements.SyncPower() end
        addLog("Comando", "IA ativada.", Color3.fromRGB(140, 200, 255))
        return true
    elseif arg == "off" then
        Config.Enabled = false
        if UI.Elements.SyncPower then UI.Elements.SyncPower() end
        addLog("Comando", "IA desativada.", Color3.fromRGB(140, 200, 255))
        return true
    elseif arg == "clear" then
        ContextManager.clear()
        addLog("Comando", "Histórico limpo.", Color3.fromRGB(140, 200, 255))
        return true
    end
    return false
end

function MessageProcessor.onIncomingChat(data)
    if not data or type(data.Text) ~= "string" then
        return
    end
    local cleanInput = Security.trim(data.Text)
    if cleanInput == "" then
        return
    end
    if data.UserId == LocalPlayer.UserId or data.Name == LocalPlayer.Name then
        MessageProcessor.handleOwnerCommand(cleanInput)
        return
    end

    local dedupKey = tostring(data.UniqueId or (tostring(data.Name) .. "|" .. cleanInput .. "|" .. tostring(math.floor(os.clock() / 2))))
    if not Security.markMessageProcessed(dedupKey) then
        return
    end
    if Security.isPlayerIgnored(data.Name, data.DisplayName) or Security.containsForbiddenWord(cleanInput) then
        return
    end

    local speakerLabel = data.DisplayName or data.Name or "Jogador"
    if not Config.TargetOnly or Security.isPlayerTargeted(data.Name, data.DisplayName) then
        ContextManager.addMessage("user", speakerLabel, cleanInput)
        addLog(speakerLabel, cleanInput, Theme.TextMain)
    end

    if not Config.Enabled or Runtime.IsGenerating or (os.clock() - Runtime.LastReplyTick) < Config.CooldownSeconds then
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
                addLog("Erro API", tostring(rawReply), Theme.Danger)
                return
            end

            local safeReply, blockReason = Security.sanitizeOutgoingMessage(rawReply, cleanInput)
            if not safeReply then
                addLog("Segurança", tostring(blockReason), Theme.Warning)
                return
            end

            local sentSomething = false
            if Config.SendTextInChat or not Config.FishAudio.Enabled then
                local sentOk, sendErr = ChatSender.send(safeReply)
                if sentOk then
                    sentSomething = true
                    addLog("Você (Texto)", safeReply, Theme.Success)
                else
                    addLog("Erro Chat", tostring(sendErr), Theme.Danger)
                end
            end

            if Config.FishAudio.Enabled then
                sentSomething = true
                task.spawn(function()
                    local voiceOk, voiceMsg = VoiceTTS.synthesizeAndSpeak(safeReply)
                    addLog(voiceOk and "Você (Áudio)" or "Erro Áudio", voiceOk and safeReply or tostring(voiceMsg), voiceOk and Color3.fromRGB(130, 215, 255) or Theme.Danger)
                end)
            end

            if sentSomething then
                Security.recordOutput(safeReply)
                ContextManager.addMessage("assistant", LocalPlayer.DisplayName or LocalPlayer.Name, safeReply)
                Runtime.LastReplyTick = os.clock()
                Runtime.LastDirectTalker = data.Name
                Runtime.LastDirectTime = os.clock()
            end
        end)

        if not okDone then
            addLog("Erro Interno", tostring(errRun), Theme.Danger)
        end
        Runtime.IsGenerating = false
    end)
end

-- =========================================================================
-- MÓDULO 10: ESCUTA DO CHAT E INICIALIZAÇÃO
-- =========================================================================
local ChatListener = {}

function ChatListener.start()
    local chatType = Environment.getChatSystemType()
    trackConnection(LocalPlayer.Chatted:Connect(MessageProcessor.handleOwnerCommand))

    if chatType == "TextChatService" then
        trackConnection(TextChatService.MessageReceived:Connect(function(tcm)
            local src = tcm.TextSource
            if not src then return end
            local plr = Players:GetPlayerByUserId(src.UserId)
            MessageProcessor.onIncomingChat({
                UniqueId = "tcs_" .. tostring(tcm.MessageId),
                Player = plr,
                UserId = src.UserId,
                Name = plr and plr.Name or tostring(src.Name),
                DisplayName = plr and plr.DisplayName or tostring(src.Name),
                Text = tcm.Text,
            })
        end))
        return
    end

    if chatType == "LegacyChat" then
        local events = ReplicatedStorage:FindFirstChild("DefaultChatSystemChatEvents")
        local onDone = events and events:FindFirstChild("OnMessageDoneFiltering")
        if onDone and onDone:IsA("RemoteEvent") then
            trackConnection(onDone.OnClientEvent:Connect(function(msgData)
                if type(msgData) ~= "table" then return end
                local speaker = msgData.FromSpeaker
                if not speaker or speaker == "System" then return end
                local plr = Players:FindFirstChild(speaker)
                if not plr then return end
                MessageProcessor.onIncomingChat({
                    UniqueId = "leg_" .. tostring(msgData.ID or (speaker .. "_" .. tostring(msgData.Time))),
                    Player = plr,
                    UserId = plr.UserId,
                    Name = plr.Name,
                    DisplayName = plr.DisplayName,
                    Text = msgData.Message,
                })
            end))
            return
        end
    end

    local function hookPlayer(plr)
        if plr == LocalPlayer then return end
        trackConnection(plr.Chatted:Connect(function(msg)
            MessageProcessor.onIncomingChat({
                Player = plr,
                UserId = plr.UserId,
                Name = plr.Name,
                DisplayName = plr.DisplayName,
                Text = msg,
            })
        end))
    end
    for _, plr in ipairs(Players:GetPlayers()) do hookPlayer(plr) end
    trackConnection(Players.PlayerAdded:Connect(hookPlayer))
end

AIClient.setStatusCallback(function(status)
    UI.setStatus(status)
end)

VoiceTTS.setStatusCallback(function(text, color)
    local lbl = UI.Elements.VoiceStatusLabel
    if lbl then
        lbl.Text = "Status Áudio: " .. text
        if color then lbl.TextColor3 = color end
    end
end)

UI.build({
    onTestAI = function()
        local testMessages = ContextManager.buildApiPayloadMessages("JogadorTeste", "oi, tudo bem por ai?")
        local ok, reply = AIClient.requestCompletion(testMessages)
        if not ok then
            return false, reply
        end
        local cleaned = Security.stripUnnecessaryLaugh(Security.stripEmojis(reply), "oi, tudo bem por ai?")
        cleaned = Security.truncateSafely(cleaned, Config.MaxChars)
        addLog("Teste IA", cleaned, Color3.fromRGB(165, 225, 255))
        return true, cleaned
    end,
    onTestVoice = function()
        return VoiceTTS.synthesizeAndSpeak("Oi, tudo bem por aqui? Falando com calma pra testar a voz.")
    end,
    onClearHistory = function()
        ContextManager.clear()
        addLog("Sistema", "Histórico limpo.", Color3.fromRGB(140, 200, 255))
    end,
})

ChatListener.start()
addLog("Sistema", "Inicializado (" .. Environment.getChatSystemType() .. ").", Color3.fromRGB(140, 200, 255))

globalEnv.__RobloxAutoAI_Cleanup = function()
    Config.Enabled = false
    VoiceTTS.stopCurrent()
    for _, conn in ipairs(Connections) do
        pcall(function() conn:Disconnect() end)
    end
    table.clear(Connections)
    if UI.Root then
        pcall(function() UI.Root:Destroy() end)
        UI.Root = nil
    end
end