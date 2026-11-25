--[[
    ════════════════════════════════════════════════════════════════════════
    ⚡ AI SCRIPT STUDIO PRO (LUA)
    • API: https://coarena.ai/api/v1/chat/completions
    • Modelos: gpt-6-luna | deepseek-v4-1-flash-1017 | gemini-3-8-flash
    • Recursos: Seletor de Modelo, Copiar Script, Drag Suave, UI Fluida
    ════════════════════════════════════════════════════════════════════════
]]

-- ====================================================================
--                      CONFIGURAÇÃO PRINCIPAL
-- ====================================================================
local API_CONFIG = {
    Url = "https://coarena.ai/api/v1/chat/completions",
    Key = "coa_16caada09c8414e36108d6530602d8bb",
    AvailableModels = {
        "gpt-6-luna",
        "deepseek-v4-1-flash-1017",
        "gemini-3-8-flash"
    },
    CurrentModel = "gpt-6-luna" -- Modelo padrão ao iniciar
}

-- Serviços
local TweenService = game:GetService("TweenService")
local HttpService = game:GetService("HttpService")
local UserInputService = game:GetService("UserInputService")
local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer

-- Identificação do CoreGui compatível
local CoreGui = game:GetService("CoreGui")
local ParentGui = (gethui and gethui()) or CoreGui:FindFirstChild("RobloxGui") or CoreGui or LocalPlayer:WaitForChild("PlayerGui")

-- Função universal para requisições HTTP
local httpRequest = (syn and syn.request) or (http and http.request) or http_request or request
-- Função universal para copiar para a área de transferência
local copyClipboard = setclipboard or toclipboard or function(text) 
    print("[Clipboard]:", text) 
end

-- Limpa UI anterior se existir
if ParentGui:FindFirstChild("AIStudioProGui") then
    ParentGui.AIStudioProGui:Destroy()
end

-- ====================================================================
--                      CONSTRUÇÃO DA INTERFACE (UI)
-- ====================================================================
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "AIStudioProGui"
ScreenGui.ResetOnSpawn = false
ScreenGui.Parent = ParentGui

-- Notificação Flutuante (Toast)
local function ShowToast(text, color)
    local Toast = Instance.new("Frame")
    Toast.Size = UDim2.new(0, 220, 0, 36)
    Toast.Position = UDim2.new(0.5, -110, 0.1, 0)
    Toast.BackgroundColor3 = color or Color3.fromRGB(30, 160, 90)
    Toast.BackgroundTransparency = 0.1
    Toast.BorderSizePixel = 0
    Toast.ZIndex = 100
    Toast.Parent = ScreenGui

    local Corner = Instance.new("UICorner")
    Corner.CornerRadius = UDim.new(0, 8)
    Corner.Parent = Toast

    local Label = Instance.new("TextLabel")
    Label.Size = UDim2.new(1, 0, 1, 0)
    Label.BackgroundTransparency = 1
    Label.Text = text
    Label.TextColor3 = Color3.fromRGB(255, 255, 255)
    Label.Font = Enum.Font.GothamBold
    Label.TextSize = 12
    Label.ZIndex = 101
    Label.Parent = Toast

    Toast.Position = UDim2.new(0.5, -110, 0.05, 0)
    TweenService:Create(Toast, TweenInfo.new(0.3, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {Position = UDim2.new(0.5, -110, 0.1, 0)}):Play()

    task.delay(2, function()
        local tw = TweenService:Create(Toast, TweenInfo.new(0.3, Enum.EasingStyle.Quart, Enum.EasingDirection.In), {Position = UDim2.new(0.5, -110, 0.05, 0), BackgroundTransparency = 1})
        tw:Play()
        tw.Completed:Connect(function() Toast:Destroy() end)
    end)
end

-- Frame Principal
local Main = Instance.new("Frame")
Main.Name = "MainFrame"
Main.Size = UDim2.new(0, 520, 0, 480)
Main.Position = UDim2.new(0.5, -260, 0.5, -240)
Main.BackgroundColor3 = Color3.fromRGB(15, 17, 23)
Main.BorderSizePixel = 0
Main.Active = true
Main.Parent = ScreenGui

local MainCorner = Instance.new("UICorner")
MainCorner.CornerRadius = UDim.new(0, 12)
MainCorner.Parent = Main

local MainStroke = Instance.new("UIStroke")
MainStroke.Color = Color3.fromRGB(35, 40, 55)
MainStroke.Thickness = 1.2
MainStroke.Parent = Main

-- Top Bar
local TopBar = Instance.new("Frame")
TopBar.Size = UDim2.new(1, 0, 0, 48)
TopBar.BackgroundColor3 = Color3.fromRGB(20, 24, 33)
TopBar.BorderSizePixel = 0
TopBar.Parent = Main

local TopCorner = Instance.new("UICorner")
TopCorner.CornerRadius = UDim.new(0, 12)
TopCorner.Parent = TopBar

local Title = Instance.new("TextLabel")
Title.Size = UDim2.new(0, 200, 1, 0)
Title.Position = UDim2.new(0, 16, 0, 0)
Title.BackgroundTransparency = 1
Title.Text = "✨ AI Script Studio"
Title.Font = Enum.Font.GothamBold
Title.TextSize = 15
Title.TextColor3 = Color3.fromRGB(245, 245, 250)
Title.TextXAlignment = Enum.TextXAlignment.Left
Title.Parent = TopBar

-- Botões do Top Bar (Fechar, Minimizar, Limpar)
local Controls = Instance.new("Frame")
Controls.Size = UDim2.new(0, 110, 1, 0)
Controls.Position = UDim2.new(1, -118, 0, 0)
Controls.BackgroundTransparency = 1
Controls.Parent = TopBar

local CtrlLayout = Instance.new("UIListLayout")
CtrlLayout.FillDirection = Enum.FillDirection.Horizontal
CtrlLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
CtrlLayout.VerticalAlignment = Enum.VerticalAlignment.Center
CtrlLayout.Padding = UDim.new(0, 6)
CtrlLayout.Parent = Controls

local function CreateHeaderBtn(txt, color, hoverColor)
    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(0, 30, 0, 30)
    btn.BackgroundColor3 = color
    btn.Text = txt
    btn.Font = Enum.Font.GothamBold
    btn.TextColor3 = Color3.fromRGB(240, 240, 240)
    btn.TextSize = 12
    btn.Parent = Controls

    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, 6)
    c.Parent = btn

    btn.MouseEnter:Connect(function()
        TweenService:Create(btn, TweenInfo.new(0.2), {BackgroundColor3 = hoverColor}):Play()
    end)
    btn.MouseLeave:Connect(function()
        TweenService:Create(btn, TweenInfo.new(0.2), {BackgroundColor3 = color}):Play()
    end)
    return btn
end

local ClearBtn = CreateHeaderBtn("🗑", Color3.fromRGB(32, 36, 48), Color3.fromRGB(48, 54, 72))
local MinBtn   = CreateHeaderBtn("—", Color3.fromRGB(32, 36, 48), Color3.fromRGB(48, 54, 72))
local CloseBtn = CreateHeaderBtn("✕", Color3.fromRGB(60, 30, 35), Color3.fromRGB(95, 35, 42))

-- Barra de Seleção de Modelo
local ModelBar = Instance.new("Frame")
ModelBar.Size = UDim2.new(1, -24, 0, 32)
ModelBar.Position = UDim2.new(0, 12, 0, 54)
ModelBar.BackgroundColor3 = Color3.fromRGB(20, 23, 31)
ModelBar.Parent = Main

local ModelCorner = Instance.new("UICorner")
ModelCorner.CornerRadius = UDim.new(0, 8)
ModelCorner.Parent = ModelBar

local ModelLayout = Instance.new("UIListLayout")
ModelLayout.FillDirection = Enum.FillDirection.Horizontal
ModelLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
ModelLayout.VerticalAlignment = Enum.VerticalAlignment.Center
ModelLayout.Padding = UDim.new(0, 6)
ModelLayout.Parent = ModelBar

local ModelButtons = {}

local function UpdateModelSelection(chosenModel)
    API_CONFIG.CurrentModel = chosenModel
    for modelName, btn in pairs(ModelButtons) do
        local isSelected = (modelName == chosenModel)
        TweenService:Create(btn, TweenInfo.new(0.2), {
            BackgroundColor3 = isSelected and Color3.fromRGB(55, 90, 240) or Color3.fromRGB(28, 32, 44),
            TextColor3 = isSelected and Color3.fromRGB(255, 255, 255) or Color3.fromRGB(150, 155, 175)
        }):Play()
    end
    ShowToast("Modelo selecionado: " .. chosenModel, Color3.fromRGB(55, 90, 240))
end

for _, modelName in ipairs(API_CONFIG.AvailableModels) do
    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(0, 155, 0, 24)
    btn.BackgroundColor3 = Color3.fromRGB(28, 32, 44)
    btn.Text = modelName
    btn.Font = Enum.Font.GothamMedium
    btn.TextSize = 10
    btn.TextColor3 = Color3.fromRGB(150, 155, 175)
    btn.Parent = ModelBar

    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, 6)
    c.Parent = btn

    btn.MouseButton1Click:Connect(function()
        UpdateModelSelection(modelName)
    end)
    ModelButtons[modelName] = btn
end
UpdateModelSelection(API_CONFIG.CurrentModel)

-- Painel de Rolagem das Mensagens
local ChatScroll = Instance.new("ScrollingFrame")
ChatScroll.Size = UDim2.new(1, -24, 1, -150)
ChatScroll.Position = UDim2.new(0, 12, 0, 92)
ChatScroll.BackgroundTransparency = 1
ChatScroll.BorderSizePixel = 0
ChatScroll.ScrollBarThickness = 4
ChatScroll.ScrollBarImageColor3 = Color3.fromRGB(55, 65, 85)
ChatScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
ChatScroll.Parent = Main

local ChatListLayout = Instance.new("UIListLayout")
ChatListLayout.SortOrder = Enum.SortOrder.LayoutOrder
ChatListLayout.Padding = UDim.new(0, 12)
ChatListLayout.Parent = ChatScroll

-- Barra Inferior de Entrada
local InputContainer = Instance.new("Frame")
InputContainer.Size = UDim2.new(1, -24, 0, 44)
InputContainer.Position = UDim2.new(0, 12, 1, -52)
InputContainer.BackgroundColor3 = Color3.fromRGB(20, 23, 31)
InputContainer.Parent = Main

local InputCorner = Instance.new("UICorner")
InputCorner.CornerRadius = UDim.new(0, 8)
InputCorner.Parent = InputContainer

local InputStroke = Instance.new("UIStroke")
InputStroke.Color = Color3.fromRGB(35, 42, 58)
InputStroke.Parent = InputContainer

local TextBox = Instance.new("TextBox")
TextBox.Size = UDim2.new(1, -100, 1, 0)
TextBox.Position = UDim2.new(0, 12, 0, 0)
TextBox.BackgroundTransparency = 1
TextBox.Font = Enum.Font.Gotham
TextBox.PlaceholderText = "Descreva detalhadamente o script que você deseja..."
TextBox.PlaceholderColor3 = Color3.fromRGB(100, 105, 125)
TextBox.Text = ""
TextBox.TextColor3 = Color3.fromRGB(255, 255, 255)
TextBox.TextSize = 13
TextBox.ClearTextOnFocus = false
TextBox.TextXAlignment = Enum.TextXAlignment.Left
TextBox.Parent = InputContainer

local SendBtn = Instance.new("TextButton")
SendBtn.Size = UDim2.new(0, 85, 0, 32)
SendBtn.Position = UDim2.new(1, -90, 0, 6)
SendBtn.BackgroundColor3 = Color3.fromRGB(55, 90, 240)
SendBtn.Text = "Gerar"
SendBtn.Font = Enum.Font.GothamBold
SendBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
SendBtn.TextSize = 12
SendBtn.Parent = InputContainer

local SendCorner = Instance.new("UICorner")
SendCorner.CornerRadius = UDim.new(0, 6)
SendCorner.Parent = SendBtn

-- ====================================================================
--                  SISTEMA DE ARRASTE & JANELA
-- ====================================================================
local dragging, dragInput, dragStart, startPos
TopBar.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        dragging = true
        dragStart = input.Position
        startPos = Main.Position
        input.Changed:Connect(function()
            if input.UserInputState == Enum.UserInputState.End then
                dragging = false
            end
        end)
    end
end)

TopBar.InputChanged:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
        dragInput = input
    end
end)

UserInputService.InputChanged:Connect(function(input)
    if input == dragInput and dragging then
        local delta = input.Position - dragStart
        Main.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
    end
end)

-- Fechar Janela
CloseBtn.MouseButton1Click:Connect(function()
    ScreenGui:Destroy()
end)

-- Minimizar
local isMinimized = false
MinBtn.MouseButton1Click:Connect(function()
    isMinimized = not isMinimized
    local targetHeight = isMinimized and 48 or 480
    ChatScroll.Visible = not isMinimized
    ModelBar.Visible = not isMinimized
    InputContainer.Visible = not isMinimized
    TweenService:Create(Main, TweenInfo.new(0.25, Enum.EasingStyle.Quart), {Size = UDim2.new(0, 520, 0, targetHeight)}):Play()
end)

-- Limpar Histórico
ClearBtn.MouseButton1Click:Connect(function()
    for _, child in ipairs(ChatScroll:GetChildren()) do
        if child:IsA("Frame") then
            child:Destroy()
        end
    end
    ShowToast("Histórico limpo com sucesso!", Color3.fromRGB(40, 45, 60))
end)

-- ====================================================================
--                  CRIADOR DE CARDS DE MENSAGENS
-- ====================================================================
local function AddChatMessage(sender, text, rawCode)
    local Card = Instance.new("Frame")
    Card.Size = UDim2.new(1, 0, 0, 0)
    Card.BackgroundColor3 = (sender == "Você") and Color3.fromRGB(22, 26, 36) or Color3.fromRGB(18, 21, 29)
    Card.AutomaticSize = Enum.AutomaticSize.Y
    Card.BorderSizePixel = 0
    Card.Parent = ChatScroll

    local CardCorner = Instance.new("UICorner")
    CardCorner.CornerRadius = UDim.new(0, 10)
    CardCorner.Parent = Card

    local CardStroke = Instance.new("UIStroke")
    CardStroke.Color = Color3.fromRGB(30, 36, 48)
    CardStroke.Parent = Card

    local Padding = Instance.new("UIPadding")
    Padding.PaddingTop = UDim.new(0, 10)
    Padding.PaddingBottom = UDim.new(0, 10)
    Padding.PaddingLeft = UDim.new(0, 12)
    Padding.PaddingRight = UDim.new(0, 12)
    Padding.Parent = Card

    local CardLayout = Instance.new("UIListLayout")
    CardLayout.SortOrder = Enum.SortOrder.LayoutOrder
    CardLayout.Padding = UDim.new(0, 8)
    CardLayout.Parent = Card

    -- Remetente + Modelo Badge
    local HeaderFrame = Instance.new("Frame")
    HeaderFrame.Size = UDim2.new(1, 0, 0, 18)
    HeaderFrame.BackgroundTransparency = 1
    HeaderFrame.Parent = Card

    local SenderLabel = Instance.new("TextLabel")
    SenderLabel.Size = UDim2.new(0, 100, 1, 0)
    SenderLabel.BackgroundTransparency = 1
    SenderLabel.Font = Enum.Font.GothamBold
    SenderLabel.Text = (sender == "Você") and "👤 Você" or "🤖 IA (" .. API_CONFIG.CurrentModel .. ")"
    SenderLabel.TextColor3 = (sender == "Você") and Color3.fromRGB(110, 150, 255) or Color3.fromRGB(120, 240, 180)
    SenderLabel.TextSize = 12
    SenderLabel.TextXAlignment = Enum.TextXAlignment.Left
    SenderLabel.Parent = HeaderFrame

    -- Texto explicativo
    if text and text:gsub("%s+", "") ~= "" then
        local Content = Instance.new("TextLabel")
        Content.Size = UDim2.new(1, 0, 0, 0)
        Content.BackgroundTransparency = 1
        Content.Font = Enum.Font.Gotham
        Content.Text = text
        Content.TextColor3 = Color3.fromRGB(220, 225, 235)
        Content.TextSize = 13
        Content.TextWrapped = true
        Content.AutomaticSize = Enum.AutomaticSize.Y
        Content.TextXAlignment = Enum.TextXAlignment.Left
        Content.Parent = Card
    end

    -- Se houver código gerado, monta o Card de Código Avançado
    if rawCode then
        local CodeContainer = Instance.new("Frame")
        CodeContainer.Size = UDim2.new(1, 0, 0, 0)
        CodeContainer.BackgroundColor3 = Color3.fromRGB(11, 13, 18)
        CodeContainer.AutomaticSize = Enum.AutomaticSize.Y
        CodeContainer.Parent = Card

        local CodeCorner = Instance.new("UICorner")
        CodeCorner.CornerRadius = UDim.new(0, 8)
        CodeCorner.Parent = CodeContainer

        local CodeStroke = Instance.new("UIStroke")
        CodeStroke.Color = Color3.fromRGB(40, 50, 70)
        CodeStroke.Parent = CodeContainer

        local CodePad = Instance.new("UIPadding")
        CodePad.PaddingTop = UDim.new(0, 8)
        CodePad.PaddingBottom = UDim.new(0, 8)
        CodePad.PaddingLeft = UDim.new(0, 10)
        CodePad.PaddingRight = UDim.new(0, 10)
        CodePad.Parent = CodeContainer

        local CodeLayout = Instance.new("UIListLayout")
        CodeLayout.SortOrder = Enum.SortOrder.LayoutOrder
        CodeLayout.Padding = UDim.new(0, 8)
        CodeLayout.Parent = CodeContainer

        -- Cabeçalho do Bloco de Código com Botão Copiar
        local CodeTop = Instance.new("Frame")
        CodeTop.Size = UDim2.new(1, 0, 0, 32)
        CodeTop.BackgroundTransparency = 1
        CodeTop.Parent = CodeContainer

        local LangLabel = Instance.new("TextLabel")
        LangLabel.Size = UDim2.new(0, 100, 1, 0)
        LangLabel.BackgroundTransparency = 1
        LangLabel.Text = "LUA SCRIPT"
        LangLabel.Font = Enum.Font.Code
        LangLabel.TextColor3 = Color3.fromRGB(120, 130, 160)
        LangLabel.TextSize = 11
        LangLabel.TextXAlignment = Enum.TextXAlignment.Left
        LangLabel.Parent = CodeTop

        -- Botão: Copiar Todo o Script
        local CopyAllBtn = Instance.new("TextButton")
        CopyAllBtn.Size = UDim2.new(0, 140, 0, 28)
        CopyAllBtn.Position = UDim2.new(1, -140, 0, 2)
        CopyAllBtn.BackgroundColor3 = Color3.fromRGB(45, 80, 220)
        CopyAllBtn.Text = "📋 Copiar Script"
        CopyAllBtn.Font = Enum.Font.GothamBold
        CopyAllBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
        CopyAllBtn.TextSize = 11
        CopyAllBtn.Parent = CodeTop

        local CopyCorner = Instance.new("UICorner")
        CopyCorner.CornerRadius = UDim.new(0, 6)
        CopyCorner.Parent = CopyAllBtn

        CopyAllBtn.MouseButton1Click:Connect(function()
            copyClipboard(rawCode)
            CopyAllBtn.Text = "✔ Copiado!"
            CopyAllBtn.BackgroundColor3 = Color3.fromRGB(30, 160, 90)
            ShowToast("Script copiado para a Área de Transferência!", Color3.fromRGB(30, 160, 90))
            task.wait(2)
            CopyAllBtn.Text = "📋 Copiar Script"
            CopyAllBtn.BackgroundColor3 = Color3.fromRGB(45, 80, 220)
        end)

        -- Preview do Código
        local CodePreview = Instance.new("TextLabel")
        CodePreview.Size = UDim2.new(1, 0, 0, 0)
        CodePreview.BackgroundTransparency = 1
        CodePreview.Font = Enum.Font.Code
        CodePreview.Text = rawCode
        CodePreview.TextColor3 = Color3.fromRGB(160, 215, 255)
        CodePreview.TextSize = 11
        CodePreview.TextWrapped = true
        CodePreview.AutomaticSize = Enum.AutomaticSize.Y
        CodePreview.TextXAlignment = Enum.TextXAlignment.Left
        CodePreview.Parent = CodeContainer
    end

    -- Rola para o fim
    task.defer(function()
        ChatScroll.CanvasPosition = Vector2.new(0, 999999)
    end)
end

-- ====================================================================
--                  REQUISIÇÃO PARA A API
-- ====================================================================
local isSending = false

local function RequestScriptAI(userPrompt)
    if isSending then return end
    if not httpRequest then
        AddChatMessage("Sistema", "Seu executor não possui a função 'request'/'httpRequest' habilitada.", nil)
        return
    end

    isSending = true
    SendBtn.Text = "..."
    SendBtn.BackgroundColor3 = Color3.fromRGB(90, 95, 115)

    AddChatMessage("Você", userPrompt, nil)

    -- Prompt de Engenharia do Sistema: Força a IA a gerar scripts avançados, seguros e prontos
    local systemPrompt = "Você é um Engenheiro de Software sênior especialista em Lua e Roblox Luau. " ..
        "Quando o usuário solicitar um recurso ou script, crie códigos completos, modernos, modulares e altamente avançados. " ..
        "Utilize boas práticas: Services (game:GetService), pcall para proteções, TweenService para animações fluidas e UserInputService. " ..
        "OBRIGATÓRIO: Sempre coloque o código final Lua completo dentro de um bloco de marcação ```lua ... ``` para que o usuário possa copiá-lo facilmente. " ..
        "Seja direto e conciso na explicação."

    local payload = {
        model = API_CONFIG.CurrentModel,
        messages = {
            { role = "system", content = systemPrompt },
            { role = "user", content = userPrompt }
        },
        temperature = 0.5
    }

    task.spawn(function()
        local success, response = pcall(function()
            return httpRequest({
                Url = API_CONFIG.Url,
                Method = "POST",
                Headers = {
                    ["Content-Type"] = "application/json",
                    ["Authorization"] = "Bearer " .. API_CONFIG.Key
                },
                Body = HttpService:JSONEncode(payload)
            })
        end)

        isSending = false
        SendBtn.Text = "Gerar"
        SendBtn.BackgroundColor3 = Color3.fromRGB(55, 90, 240)

        if success and response and (response.StatusCode == 200 or response.Status == 200) then
            local decoded = HttpService:JSONDecode(response.Body)
            local reply = decoded.choices and decoded.choices[1] and decoded.choices[1].message.content or "Nenhuma resposta gerada."

            -- Extração do código Lua
            local code = reply:match("```lua%s*(.-)%s*```") or reply:match("```%s*(.-)%s*```")
            local cleanText = reply:gsub("```lua.-```", ""):gsub("```.-```", "")

            AddChatMessage("IA", cleanText, code)
        else
            local err = response and response.Body or "Falha de conexão com a API."
            AddChatMessage("Sistema", "Erro na resposta da API (" .. API_CONFIG.CurrentModel .. "): " .. tostring(err), nil)
        end
    end)
end

-- ====================================================================
--                  EVENTOS DE ENVIO
-- ====================================================================
SendBtn.MouseButton1Click:Connect(function()
    if TextBox.Text ~= "" then
        local msg = TextBox.Text
        TextBox.Text = ""
        RequestScriptAI(msg)
    end
end)

TextBox.FocusLost:Connect(function(enterPressed)
    if enterPressed and TextBox.Text ~= "" then
        local msg = TextBox.Text
        TextBox.Text = ""
        RequestScriptAI(msg)
    end
end)

AddChatMessage("Sistema", "Bem-vindo ao AI Script Studio! Escolha o modelo acima e faça seu pedido.", nil)