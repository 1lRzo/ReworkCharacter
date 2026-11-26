--[[
    ════════════════════════════════════════════════════════════════════════
    📱 AI SCRIPT STUDIO PRO (MOBILE READY)
    • API: https://coarena.ai/api/v1/chat/completions
    • Modelos: gpt-6-luna | deepseek-v4-1-flash-1017 | gemini-3-8-flash
    • Recursos: Sidebar Lateral, Histórico de Sessões, UI Adaptativa
    ════════════════════════════════════════════════════════════════════════
]]

-- ====================================================================
--                      CONFIGURAÇÕES DA API
-- ====================================================================
local API_CONFIG = {
    Url = "https://coarena.ai/api/v1/chat/completions",
    Key = "coa_16caada09c8414e36108d6530602d8bb",
    AvailableModels = {
        "gpt-6-luna",
        "deepseek-v4-1-flash-1017",
        "gemini-3-8-flash"
    },
    CurrentModel = "gpt-6-luna"
}

-- Serviços
local TweenService = game:GetService("TweenService")
local HttpService = game:GetService("HttpService")
local UserInputService = game:GetService("UserInputService")
local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer

local CoreGui = game:GetService("CoreGui")
local ParentGui = (gethui and gethui()) or CoreGui:FindFirstChild("RobloxGui") or CoreGui or LocalPlayer:WaitForChild("PlayerGui")

local httpRequest = (syn and syn.request) or (http and http.request) or http_request or request
local copyClipboard = setclipboard or toclipboard or function(text) print("[Clipboard]:", text) end

-- Remove instância anterior
if ParentGui:FindFirstChild("AIStudioMobileGui") then
    ParentGui.AIStudioMobileGui:Destroy()
end

-- ====================================================================
--                      GERENCIAMENTO DE HISTÓRICO
-- ====================================================================
local ChatSessions = {}
local CurrentSessionId = 1
local SessionCounter = 1

local function CreateNewSessionData()
    local newSession = {
        id = SessionCounter,
        title = "Conversa " .. SessionCounter,
        messages = {}
    }
    table.insert(ChatSessions, newSession)
    SessionCounter = SessionCounter + 1
    return newSession
end

-- Cria primeira sessão por padrão
CreateNewSessionData()

-- ====================================================================
--                      INTERFACE PRINCIPAL (MOBILE)
-- ====================================================================
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "AIStudioMobileGui"
ScreenGui.ResetOnSpawn = false
ScreenGui.Parent = ParentGui

-- Notificação Flutuante (Toast)
local function ShowToast(text, color)
    local Toast = Instance.new("Frame")
    Toast.Size = UDim2.new(0, 240, 0, 34)
    Toast.Position = UDim2.new(0.5, -120, 0.04, 0)
    Toast.BackgroundColor3 = color or Color3.fromRGB(35, 170, 95)
    Toast.BorderSizePixel = 0
    Toast.ZIndex = 200
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
    Label.ZIndex = 201
    Label.Parent = Toast

    Toast.Position = UDim2.new(0.5, -120, 0.01, 0)
    TweenService:Create(Toast, TweenInfo.new(0.25, Enum.EasingStyle.Quart), {Position = UDim2.new(0.5, -120, 0.05, 0)}):Play()

    task.delay(1.8, function()
        local tw = TweenService:Create(Toast, TweenInfo.new(0.25, Enum.EasingStyle.Quart), {Position = UDim2.new(0.5, -120, 0.01, 0), BackgroundTransparency = 1})
        tw:Play()
        tw.Completed:Connect(function() Toast:Destroy() end)
    end)
end

-- Janela Principal (Tamanho Responsivo para Celular)
local Main = Instance.new("Frame")
Main.Name = "MainFrame"
Main.AnchorPoint = Vector2.new(0.5, 0.5)
Main.Size = UDim2.new(0.92, 0, 0.82, 0)
Main.Position = UDim2.new(0.5, 0, 0.5, 0)
Main.BackgroundColor3 = Color3.fromRGB(15, 17, 24)
Main.BorderSizePixel = 0
Main.ClipsDescendants = true
Main.Active = true
Main.Parent = ScreenGui

-- Limites de tamanho para não quebrar em tablets ou celulares muito pequenos
local SizeConstraint = Instance.new("UISizeConstraint")
SizeConstraint.MinSize = Vector2.new(300, 320)
SizeConstraint.MaxSize = Vector2.new(580, 520)
SizeConstraint.Parent = Main

local MainCorner = Instance.new("UICorner")
MainCorner.CornerRadius = UDim.new(0, 12)
MainCorner.Parent = Main

local MainStroke = Instance.new("UIStroke")
MainStroke.Color = Color3.fromRGB(36, 42, 58)
MainStroke.Thickness = 1.2
MainStroke.Parent = Main

-- Barra Superior
local TopBar = Instance.new("Frame")
TopBar.Size = UDim2.new(1, 0, 0, 44)
TopBar.BackgroundColor3 = Color3.fromRGB(21, 25, 35)
TopBar.BorderSizePixel = 0
TopBar.ZIndex = 10
TopBar.Parent = Main

local TopCorner = Instance.new("UICorner")
TopCorner.CornerRadius = UDim.new(0, 12)
TopCorner.Parent = TopBar

-- Botão Menu Hambúrguer (Abre Sidebar)
local MenuBtn = Instance.new("TextButton")
MenuBtn.Size = UDim2.new(0, 34, 0, 34)
MenuBtn.Position = UDim2.new(0, 6, 0.5, -17)
MenuBtn.BackgroundColor3 = Color3.fromRGB(30, 35, 48)
MenuBtn.Text = "☰"
MenuBtn.Font = Enum.Font.GothamBold
MenuBtn.TextColor3 = Color3.fromRGB(230, 230, 240)
MenuBtn.TextSize = 16
MenuBtn.ZIndex = 11
MenuBtn.Parent = TopBar

local MenuCorner = Instance.new("UICorner")
MenuCorner.CornerRadius = UDim.new(0, 6)
MenuCorner.Parent = MenuBtn

local Title = Instance.new("TextLabel")
Title.Size = UDim2.new(1, -130, 1, 0)
Title.Position = UDim2.new(0, 46, 0, 0)
Title.BackgroundTransparency = 1
Title.Text = "⚡ AI Studio Mobile"
Title.Font = Enum.Font.GothamBold
Title.TextSize = 14
Title.TextColor3 = Color3.fromRGB(240, 245, 255)
Title.TextXAlignment = Enum.TextXAlignment.Left
Title.ZIndex = 11
Title.Parent = TopBar

-- Botão Fechar
local CloseBtn = Instance.new("TextButton")
CloseBtn.Size = UDim2.new(0, 32, 0, 32)
CloseBtn.Position = UDim2.new(1, -38, 0.5, -16)
CloseBtn.BackgroundColor3 = Color3.fromRGB(60, 28, 35)
CloseBtn.Text = "✕"
CloseBtn.Font = Enum.Font.GothamBold
CloseBtn.TextColor3 = Color3.fromRGB(255, 120, 120)
CloseBtn.TextSize = 12
CloseBtn.ZIndex = 11
CloseBtn.Parent = TopBar

local CloseCorner = Instance.new("UICorner")
CloseCorner.CornerRadius = UDim.new(0, 6)
CloseCorner.Parent = CloseBtn

CloseBtn.MouseButton1Click:Connect(function()
    ScreenGui:Destroy()
end)

-- Barra de Seleção de Modelos (Scroll horizontal perfeito para celular)
local ModelScroll = Instance.new("ScrollingFrame")
ModelScroll.Size = UDim2.new(1, -16, 0, 30)
ModelScroll.Position = UDim2.new(0, 8, 0, 48)
ModelScroll.BackgroundTransparency = 1
ModelScroll.BorderSizePixel = 0
ModelScroll.ScrollBarThickness = 0
ModelScroll.CanvasSize = UDim2.new(0, 420, 0, 0)
ModelScroll.Parent = Main

local ModelList = Instance.new("UIListLayout")
ModelList.FillDirection = Enum.FillDirection.Horizontal
ModelList.Padding = UDim.new(0, 6)
ModelList.Parent = ModelScroll

local ModelButtons = {}

local function SelectModel(modelName)
    API_CONFIG.CurrentModel = modelName
    for name, btn in pairs(ModelButtons) do
        local active = (name == modelName)
        TweenService:Create(btn, TweenInfo.new(0.2), {
            BackgroundColor3 = active and Color3.fromRGB(50, 85, 230) or Color3.fromRGB(25, 30, 42),
            TextColor3 = active and Color3.fromRGB(255, 255, 255) or Color3.fromRGB(140, 145, 165)
        }):Play()
    end
    ShowToast("Modelo: " .. modelName, Color3.fromRGB(50, 85, 230))
end

for _, m in ipairs(API_CONFIG.AvailableModels) do
    local mBtn = Instance.new("TextButton")
    mBtn.Size = UDim2.new(0, 130, 0, 28)
    mBtn.BackgroundColor3 = Color3.fromRGB(25, 30, 42)
    mBtn.Text = m
    mBtn.Font = Enum.Font.GothamMedium
    mBtn.TextSize = 10
    mBtn.TextColor3 = Color3.fromRGB(140, 145, 165)
    mBtn.Parent = ModelScroll

    local mc = Instance.new("UICorner")
    mc.CornerRadius = UDim.new(0, 6)
    mc.Parent = mBtn

    mBtn.MouseButton1Click:Connect(function()
        SelectModel(m)
    end)
    ModelButtons[m] = mBtn
end
SelectModel(API_CONFIG.CurrentModel)

-- Painel de Rolagem das Mensagens
local ChatScroll = Instance.new("ScrollingFrame")
ChatScroll.Size = UDim2.new(1, -16, 1, -135)
ChatScroll.Position = UDim2.new(0, 8, 0, 82)
ChatScroll.BackgroundTransparency = 1
ChatScroll.BorderSizePixel = 0
ChatScroll.ScrollBarThickness = 3
ChatScroll.ScrollBarImageColor3 = Color3.fromRGB(50, 60, 80)
ChatScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
ChatScroll.Parent = Main

local ChatListLayout = Instance.new("UIListLayout")
ChatListLayout.SortOrder = Enum.SortOrder.LayoutOrder
ChatListLayout.Padding = UDim.new(0, 10)
ChatListLayout.Parent = ChatScroll

-- Entrada Inferior
local InputFrame = Instance.new("Frame")
InputFrame.Size = UDim2.new(1, -16, 0, 42)
InputFrame.Position = UDim2.new(0, 8, 1, -48)
InputFrame.BackgroundColor3 = Color3.fromRGB(21, 25, 35)
InputFrame.Parent = Main

local InputCorner = Instance.new("UICorner")
InputCorner.CornerRadius = UDim.new(0, 8)
InputCorner.Parent = InputFrame

local InputStroke = Instance.new("UIStroke")
InputStroke.Color = Color3.fromRGB(36, 42, 58)
InputStroke.Parent = InputFrame

local TextBox = Instance.new("TextBox")
TextBox.Size = UDim2.new(1, -85, 1, 0)
TextBox.Position = UDim2.new(0, 10, 0, 0)
TextBox.BackgroundTransparency = 1
TextBox.Font = Enum.Font.Gotham
TextBox.PlaceholderText = "Peça o script que deseja..."
TextBox.PlaceholderColor3 = Color3.fromRGB(100, 105, 125)
TextBox.Text = ""
TextBox.TextColor3 = Color3.fromRGB(255, 255, 255)
TextBox.TextSize = 12
TextBox.ClearTextOnFocus = false
TextBox.TextXAlignment = Enum.TextXAlignment.Left
TextBox.Parent = InputFrame

local SendBtn = Instance.new("TextButton")
SendBtn.Size = UDim2.new(0, 70, 0, 32)
SendBtn.Position = UDim2.new(1, -75, 0.5, -16)
SendBtn.BackgroundColor3 = Color3.fromRGB(50, 85, 230)
SendBtn.Text = "Gerar"
SendBtn.Font = Enum.Font.GothamBold
SendBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
SendBtn.TextSize = 12
SendBtn.Parent = InputFrame

local SendCorner = Instance.new("UICorner")
SendCorner.CornerRadius = UDim.new(0, 6)
SendCorner.Parent = SendBtn

-- ====================================================================
--                      SIDEBAR (GAVETA DE HISTÓRICO)
-- ====================================================================
local SidebarOverlay = Instance.new("TextButton")
SidebarOverlay.Size = UDim2.new(1, 0, 1, 0)
SidebarOverlay.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
SidebarOverlay.BackgroundTransparency = 1
SidebarOverlay.Text = ""
SidebarOverlay.Visible = false
SidebarOverlay.ZIndex = 50
SidebarOverlay.Parent = Main

local Sidebar = Instance.new("Frame")
Sidebar.Size = UDim2.new(0.75, 0, 1, 0)
Sidebar.Position = UDim2.new(-0.75, 0, 0, 0)
Sidebar.BackgroundColor3 = Color3.fromRGB(18, 21, 30)
Sidebar.BorderSizePixel = 0
Sidebar.ZIndex = 51
Sidebar.Parent = Main

local SideCorner = Instance.new("UICorner")
SideCorner.CornerRadius = UDim.new(0, 12)
SideCorner.Parent = Sidebar

local SideStroke = Instance.new("UIStroke")
SideStroke.Color = Color3.fromRGB(36, 42, 58)
SideStroke.Parent = Sidebar

-- Topo da Sidebar
local SideHeader = Instance.new("Frame")
SideHeader.Size = UDim2.new(1, 0, 0, 44)
SideHeader.BackgroundTransparency = 1
SideHeader.ZIndex = 52
SideHeader.Parent = Sidebar

local SideTitle = Instance.new("TextLabel")
SideTitle.Size = UDim2.new(1, -40, 1, 0)
SideTitle.Position = UDim2.new(0, 12, 0, 0)
SideTitle.BackgroundTransparency = 1
SideTitle.Text = "Conversas"
SideTitle.Font = Enum.Font.GothamBold
SideTitle.TextColor3 = Color3.fromRGB(240, 245, 255)
SideTitle.TextSize = 14
SideTitle.TextXAlignment = Enum.TextXAlignment.Left
SideTitle.ZIndex = 53
SideTitle.Parent = SideHeader

local CloseSideBtn = Instance.new("TextButton")
CloseSideBtn.Size = UDim2.new(0, 30, 0, 30)
CloseSideBtn.Position = UDim2.new(1, -36, 0.5, -15)
CloseSideBtn.BackgroundColor3 = Color3.fromRGB(30, 35, 48)
CloseSideBtn.Text = "←"
CloseSideBtn.Font = Enum.Font.GothamBold
CloseSideBtn.TextColor3 = Color3.fromRGB(200, 205, 225)
CloseSideBtn.TextSize = 14
CloseSideBtn.ZIndex = 53
CloseSideBtn.Parent = SideHeader

local CloseSideCorner = Instance.new("UICorner")
CloseSideCorner.CornerRadius = UDim.new(0, 6)
CloseSideCorner.Parent = CloseSideBtn

-- Botão "+ Nova Conversa"
local NewChatBtn = Instance.new("TextButton")
NewChatBtn.Size = UDim2.new(1, -20, 0, 36)
NewChatBtn.Position = UDim2.new(0, 10, 0, 48)
NewChatBtn.BackgroundColor3 = Color3.fromRGB(38, 140, 75)
NewChatBtn.Text = "➕ Nova Conversa"
NewChatBtn.Font = Enum.Font.GothamBold
NewChatBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
NewChatBtn.TextSize = 12
NewChatBtn.ZIndex = 52
NewChatBtn.Parent = Sidebar

local NewChatCorner = Instance.new("UICorner")
NewChatCorner.CornerRadius = UDim.new(0, 6)
NewChatCorner.Parent = NewChatBtn

-- Lista de Sessões (Histórico)
local HistoryScroll = Instance.new("ScrollingFrame")
HistoryScroll.Size = UDim2.new(1, -20, 1, -95)
HistoryScroll.Position = UDim2.new(0, 10, 0, 90)
HistoryScroll.BackgroundTransparency = 1
HistoryScroll.BorderSizePixel = 0
HistoryScroll.ScrollBarThickness = 2
HistoryScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
HistoryScroll.ZIndex = 52
HistoryScroll.Parent = Sidebar

local HistoryLayout = Instance.new("UIListLayout")
HistoryLayout.SortOrder = Enum.SortOrder.LayoutOrder
HistoryLayout.Padding = UDim.new(0, 6)
HistoryLayout.Parent = HistoryScroll

-- Animação de Abrir e Fechar Sidebar
local isSidebarOpen = false
local function ToggleSidebar(state)
    isSidebarOpen = state
    if state then
        SidebarOverlay.Visible = true
        TweenService:Create(SidebarOverlay, TweenInfo.new(0.2), {BackgroundTransparency = 0.5}):Play()
        TweenService:Create(Sidebar, TweenInfo.new(0.25, Enum.EasingStyle.Quart), {Position = UDim2.new(0, 0, 0, 0)}):Play()
    else
        local tw = TweenService:Create(SidebarOverlay, TweenInfo.new(0.2), {BackgroundTransparency = 1})
        tw:Play()
        tw.Completed:Connect(function()
            if not isSidebarOpen then SidebarOverlay.Visible = false end
        end)
        TweenService:Create(Sidebar, TweenInfo.new(0.25, Enum.EasingStyle.Quart), {Position = UDim2.new(-0.75, 0, 0, 0)}):Play()
    end
end

MenuBtn.MouseButton1Click:Connect(function() ToggleSidebar(true) end)
CloseSideBtn.MouseButton1Click:Connect(function() ToggleSidebar(false) end)
SidebarOverlay.MouseButton1Click:Connect(function() ToggleSidebar(false) end)

-- ====================================================================
--                  RENDERIZAÇÃO DO CHAT E MENSAGENS
-- ====================================================================
local function RenderCard(sender, text, rawCode)
    local Card = Instance.new("Frame")
    Card.Size = UDim2.new(1, 0, 0, 0)
    Card.BackgroundColor3 = (sender == "Você") and Color3.fromRGB(22, 26, 38) or Color3.fromRGB(18, 20, 28)
    Card.AutomaticSize = Enum.AutomaticSize.Y
    Card.BorderSizePixel = 0
    Card.Parent = ChatScroll

    local CardCorner = Instance.new("UICorner")
    CardCorner.CornerRadius = UDim.new(0, 8)
    CardCorner.Parent = Card

    local CardStroke = Instance.new("UIStroke")
    CardStroke.Color = Color3.fromRGB(28, 34, 46)
    CardStroke.Parent = Card

    local Padding = Instance.new("UIPadding")
    Padding.PaddingTop = UDim.new(0, 8)
    Padding.PaddingBottom = UDim.new(0, 8)
    Padding.PaddingLeft = UDim.new(0, 10)
    Padding.PaddingRight = UDim.new(0, 10)
    Padding.Parent = Card

    local CardLayout = Instance.new("UIListLayout")
    CardLayout.SortOrder = Enum.SortOrder.LayoutOrder
    CardLayout.Padding = UDim.new(0, 6)
    CardLayout.Parent = Card

    -- Remetente
    local SenderLabel = Instance.new("TextLabel")
    SenderLabel.Size = UDim2.new(1, 0, 0, 14)
    SenderLabel.BackgroundTransparency = 1
    SenderLabel.Font = Enum.Font.GothamBold
    SenderLabel.Text = (sender == "Você") and "👤 Você" or "🤖 IA Assistant"
    SenderLabel.TextColor3 = (sender == "Você") and Color3.fromRGB(110, 160, 255) or Color3.fromRGB(110, 235, 160)
    SenderLabel.TextSize = 11
    SenderLabel.TextXAlignment = Enum.TextXAlignment.Left
    SenderLabel.Parent = Card

    -- Texto Normal
    if text and text:gsub("%s+", "") ~= "" then
        local Content = Instance.new("TextLabel")
        Content.Size = UDim2.new(1, 0, 0, 0)
        Content.BackgroundTransparency = 1
        Content.Font = Enum.Font.Gotham
        Content.Text = text
        Content.TextColor3 = Color3.fromRGB(220, 225, 235)
        Content.TextSize = 12
        Content.TextWrapped = true
        Content.AutomaticSize = Enum.AutomaticSize.Y
        Content.TextXAlignment = Enum.TextXAlignment.Left
        Content.Parent = Card
    end

    -- Bloco de Código com Botão Copiar
    if rawCode then
        local CodeBox = Instance.new("Frame")
        CodeBox.Size = UDim2.new(1, 0, 0, 0)
        CodeBox.BackgroundColor3 = Color3.fromRGB(12, 14, 20)
        CodeBox.AutomaticSize = Enum.AutomaticSize.Y
        CodeBox.Parent = Card

        local CodeCorner = Instance.new("UICorner")
        CodeCorner.CornerRadius = UDim.new(0, 6)
        CodeCorner.Parent = CodeBox

        local CodeStroke = Instance.new("UIStroke")
        CodeStroke.Color = Color3.fromRGB(35, 45, 65)
        CodeStroke.Parent = CodeBox

        local CodePad = Instance.new("UIPadding")
        CodePad.PaddingTop = UDim.new(0, 6)
        CodePad.PaddingBottom = UDim.new(0, 6)
        CodePad.PaddingLeft = UDim.new(0, 8)
        CodePad.PaddingRight = UDim.new(0, 8)
        CodePad.Parent = CodeBox

        local CodeList = Instance.new("UIListLayout")
        CodeList.SortOrder = Enum.SortOrder.LayoutOrder
        CodeList.Padding = UDim.new(0, 6)
        CodeList.Parent = CodeBox

        -- Botão de Copiar Gigante/Amigável para Celular
        local CopyBtn = Instance.new("TextButton")
        CopyBtn.Size = UDim2.new(1, 0, 0, 32)
        CopyBtn.BackgroundColor3 = Color3.fromRGB(45, 80, 220)
        CopyBtn.Text = "📋 COPIAR TODO O SCRIPT"
        CopyBtn.Font = Enum.Font.GothamBold
        CopyBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
        CopyBtn.TextSize = 11
        CopyBtn.Parent = CodeBox

        local CopyCorner = Instance.new("UICorner")
        CopyCorner.CornerRadius = UDim.new(0, 6)
        CopyCorner.Parent = CopyBtn

        CopyBtn.MouseButton1Click:Connect(function()
            copyClipboard(rawCode)
            CopyBtn.Text = "✔ COPIADO COM SUCESSO!"
            CopyBtn.BackgroundColor3 = Color3.fromRGB(35, 170, 95)
            ShowToast("Script copiado para o Clipboard!", Color3.fromRGB(35, 170, 95))
            task.wait(1.5)
            CopyBtn.Text = "📋 COPIAR TODO O SCRIPT"
            CopyBtn.BackgroundColor3 = Color3.fromRGB(45, 80, 220)
        end)

        -- Texto do Código
        local CodeLabel = Instance.new("TextLabel")
        CodeLabel.Size = UDim2.new(1, 0, 0, 0)
        CodeLabel.BackgroundTransparency = 1
        CodeLabel.Font = Enum.Font.Code
        CodeLabel.Text = rawCode
        CodeLabel.TextColor3 = Color3.fromRGB(160, 220, 255)
        CodeLabel.TextSize = 10
        CodeLabel.TextWrapped = true
        CodeLabel.AutomaticSize = Enum.AutomaticSize.Y
        CodeLabel.TextXAlignment = Enum.TextXAlignment.Left
        CodeLabel.Parent = CodeBox
    end

    task.defer(function()
        ChatScroll.CanvasPosition = Vector2.new(0, 999999)
    end)
end

-- Renderiza as mensagens da sessão atual
local function LoadSessionMessages(session)
    for _, child in ipairs(ChatScroll:GetChildren()) do
        if child:IsA("Frame") then child:Destroy() end
    end
    for _, msg in ipairs(session.messages) do
        RenderCard(msg.sender, msg.text, msg.rawCode)
    end
    if #session.messages == 0 then
        RenderCard("Sistema", "Início de uma nova conversa. Digite seu pedido abaixo!", nil)
    end
end

-- Atualiza a listagem visual do Histórico na Sidebar
local function RefreshSidebarHistory()
    for _, child in ipairs(HistoryScroll:GetChildren()) do
        if child:IsA("Frame") then child:Destroy() end
    end

    for _, session in ipairs(ChatSessions) do
        local Item = Instance.new("Frame")
        Item.Size = UDim2.new(1, 0, 0, 36)
        Item.BackgroundColor3 = (session.id == CurrentSessionId) and Color3.fromRGB(35, 42, 60) or Color3.fromRGB(24, 28, 38)
        Item.BorderSizePixel = 0
        Item.ZIndex = 53
        Item.Parent = HistoryScroll

        local ItemCorner = Instance.new("UICorner")
        ItemCorner.CornerRadius = UDim.new(0, 6)
        ItemCorner.Parent = Item

        local Btn = Instance.new("TextButton")
        Btn.Size = UDim2.new(1, -30, 1, 0)
        Btn.Position = UDim2.new(0, 8, 0, 0)
        Btn.BackgroundTransparency = 1
        Btn.Text = session.title
        Btn.Font = Enum.Font.GothamMedium
        Btn.TextSize = 11
        Btn.TextColor3 = (session.id == CurrentSessionId) and Color3.fromRGB(255, 255, 255) or Color3.fromRGB(170, 175, 195)
        Btn.TextXAlignment = Enum.TextXAlignment.Left
        Btn.TextTruncate = Enum.TextTruncate.AtEnd
        Btn.ZIndex = 54
        Btn.Parent = Item

        Btn.MouseButton1Click:Connect(function()
            CurrentSessionId = session.id
            LoadSessionMessages(session)
            RefreshSidebarHistory()
            ToggleSidebar(false)
        end)

        -- Botão Apagar Sessão
        local DelBtn = Instance.new("TextButton")
        DelBtn.Size = UDim2.new(0, 24, 0, 24)
        DelBtn.Position = UDim2.new(1, -26, 0.5, -12)
        DelBtn.BackgroundTransparency = 1
        DelBtn.Text = "✕"
        DelBtn.Font = Enum.Font.GothamBold
        DelBtn.TextColor3 = Color3.fromRGB(150, 70, 80)
        DelBtn.TextSize = 10
        DelBtn.ZIndex = 54
        DelBtn.Parent = Item

        DelBtn.MouseButton1Click:Connect(function()
            if #ChatSessions > 1 then
                for index, s in ipairs(ChatSessions) do
                    if s.id == session.id then
                        table.remove(ChatSessions, index)
                        break
                    end
                end
                if CurrentSessionId == session.id then
                    CurrentSessionId = ChatSessions[1].id
                    LoadSessionMessages(ChatSessions[1])
                end
                RefreshSidebarHistory()
            else
                ShowToast("Não é possível apagar a única conversa!", Color3.fromRGB(180, 60, 60))
            end
        end)
    end
end

-- Ação do botão "+ Nova Conversa"
NewChatBtn.MouseButton1Click:Connect(function()
    local newSess = CreateNewSessionData()
    CurrentSessionId = newSess.id
    LoadSessionMessages(newSess)
    RefreshSidebarHistory()
    ToggleSidebar(false)
    ShowToast("Nova conversa iniciada!", Color3.fromRGB(38, 140, 75))
end)

-- ====================================================================
--                  REQUISIÇÃO DA API & FLUXO
-- ====================================================================
local isSending = false

local function RequestScriptAI(promptText)
    if isSending then return end
    if not httpRequest then
        ShowToast("Executor sem função request!", Color3.fromRGB(180, 50, 50))
        return
    end

    local currentSession
    for _, s in ipairs(ChatSessions) do
        if s.id == CurrentSessionId then
            currentSession = s
            break
        end
    end

    -- Se for a 1ª mensagem da conversa, renomeia o título da sessão
    if #currentSession.messages == 0 then
        local preview = promptText:sub(1, 16)
        if #promptText > 16 then preview = preview .. "..." end
        currentSession.title = preview
        RefreshSidebarHistory()
    end

    table.insert(currentSession.messages, {sender = "Você", text = promptText, rawCode = nil})
    RenderCard("Você", promptText, nil)

    isSending = true
    SendBtn.Text = "..."
    SendBtn.BackgroundColor3 = Color3.fromRGB(80, 85, 105)

    local systemPrompt = "Você é um programador especialista em Roblox Luau. " ..
        "Crie scripts Lua completos, funcionais e avançados de acordo com o pedido do usuário. " ..
        "Sempre envolva o script principal completo dentro de blocos de código com a sintaxe ```lua [script] ``` para que o usuário possa copiar. " ..
        "Seja direto e prático."

    local payload = {
        model = API_CONFIG.CurrentModel,
        messages = {
            { role = "system", content = systemPrompt },
            { role = "user", content = promptText }
        },
        temperature = 0.5
    }

    task.spawn(function()
        local success, res = pcall(function()
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
        SendBtn.BackgroundColor3 = Color3.fromRGB(50, 85, 230)

        if success and res and (res.StatusCode == 200 or res.Status == 200) then
            local data = HttpService:JSONDecode(res.Body)
            local reply = data.choices and data.choices[1] and data.choices[1].message.content or "Sem resposta."

            local code = reply:match("```lua%s*(.-)%s*```") or reply:match("```%s*(.-)%s*```")
            local clean = reply:gsub("```lua.-```", ""):gsub("```.-```", "")

            table.insert(currentSession.messages, {sender = "IA", text = clean, rawCode = code})
            RenderCard("IA", clean, code)
        else
            local err = res and res.Body or "Erro de conexão com o servidor."
            RenderCard("Sistema", "Falha na API: " .. tostring(err), nil)
        end
    end)
end

-- Gatilhos de Envio
SendBtn.MouseButton1Click:Connect(function()
    if TextBox.Text ~= "" then
        local t = TextBox.Text
        TextBox.Text = ""
        RequestScriptAI(t)
    end
end)

TextBox.FocusLost:Connect(function(enterPressed)
    if enterPressed and TextBox.Text ~= "" then
        local t = TextBox.Text
        TextBox.Text = ""
        RequestScriptAI(t)
    end
end)

-- Inicialização
RefreshSidebarHistory()
LoadSessionMessages(ChatSessions[1])