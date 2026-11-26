--[[
    ════════════════════════════════════════════════════════════════════════
    📱 AI SCRIPT STUDIO PRO (COMPACT MOBILE + EXPLORER SCANNER)
    • API: https://coarena.ai/api/v1/chat/completions
    • Modelos: gpt-6-luna | deepseek-v4-1-flash-1017 | gemini-3-8-flash
    • Scanner: Mapeia Remotes, Modules, Scripts e Pastas do jogo
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
--              SCANNER DO EXPLORER (SCRIPTS & REMOTES)
-- ====================================================================
local ScannedExplorerData = {}
local ScannedSummaryText = ""

local function ScanGameExplorer()
    local found = {}
    local targetClasses = {
        ["RemoteEvent"] = true,
        ["RemoteFunction"] = true,
        ["ModuleScript"] = true,
        ["LocalScript"] = true,
        ["Script"] = true,
        ["BindableEvent"] = true
    }

    local targetServices = {
        game:GetService("ReplicatedStorage"),
        game:GetService("ReplicatedFirst"),
        LocalPlayer and LocalPlayer:FindFirstChildOfClass("PlayerScripts"),
        LocalPlayer and LocalPlayer:FindFirstChildOfClass("PlayerGui"),
        LocalPlayer and LocalPlayer:FindFirstChildOfClass("Backpack"),
        workspace
    }

    local count = 0
    local maxItems = 160 -- Limite equilibrado para não estourar o limite de tokens da API

    for _, srv in ipairs(targetServices) do
        if srv then
            pcall(function()
                for _, inst in ipairs(srv:GetDescendants()) do
                    if count >= maxItems then break end
                    if targetClasses[inst.ClassName] then
                        count = count + 1
                        table.insert(found, string.format("[%s] %s", inst.ClassName, inst:GetFullName()))
                    end
                end
            end)
        end
        if count >= maxItems then break end
    end

    ScannedExplorerData = found
    ScannedSummaryText = table.concat(found, "\n")
    return count
end

-- Executa o scan inicial
local initialCount = ScanGameExplorer()

-- ====================================================================
--                      HISTÓRICO & SESSÕES
-- ====================================================================
local ChatSessions = {}
local CurrentSessionId = 1
local SessionCounter = 1

local function CreateNewSessionData()
    local newSession = {
        id = SessionCounter,
        title = "Chat " .. SessionCounter,
        messages = {}
    }
    table.insert(ChatSessions, newSession)
    SessionCounter = SessionCounter + 1
    return newSession
end

CreateNewSessionData()

-- ====================================================================
--                  INTERFACE COMPACTA (MOBILE)
-- ====================================================================
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "AIStudioMobileGui"
ScreenGui.ResetOnSpawn = false
ScreenGui.Parent = ParentGui

-- Notificação Toast
local function ShowToast(text, color)
    local Toast = Instance.new("Frame")
    Toast.Size = UDim2.new(0, 220, 0, 30)
    Toast.Position = UDim2.new(0.5, -110, 0.03, 0)
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
    Label.TextSize = 11
    Label.ZIndex = 201
    Label.Parent = Toast

    Toast.Position = UDim2.new(0.5, -110, 0.01, 0)
    TweenService:Create(Toast, TweenInfo.new(0.25, Enum.EasingStyle.Quart), {Position = UDim2.new(0.5, -110, 0.04, 0)}):Play()

    task.delay(1.8, function()
        local tw = TweenService:Create(Toast, TweenInfo.new(0.25, Enum.EasingStyle.Quart), {Position = UDim2.new(0.5, -110, 0.01, 0), BackgroundTransparency = 1})
        tw:Play()
        tw.Completed:Connect(function() Toast:Destroy() end)
    end)
end

-- Janela Principal Reduzida
local Main = Instance.new("Frame")
Main.Name = "MainFrame"
Main.AnchorPoint = Vector2.new(0.5, 0.5)
Main.Size = UDim2.new(0.85, 0, 0.72, 0) -- Tamanho menor e mais compacto
Main.Position = UDim2.new(0.5, 0, 0.5, 0)
Main.BackgroundColor3 = Color3.fromRGB(15, 17, 24)
Main.BorderSizePixel = 0
Main.ClipsDescendants = true
Main.Active = true
Main.Parent = ScreenGui

-- Limites proporcionais para dispositivos mobile e tablets
local SizeConstraint = Instance.new("UISizeConstraint")
SizeConstraint.MinSize = Vector2.new(280, 260)
SizeConstraint.MaxSize = Vector2.new(460, 390)
SizeConstraint.Parent = Main

local MainCorner = Instance.new("UICorner")
MainCorner.CornerRadius = UDim.new(0, 10)
MainCorner.Parent = Main

local MainStroke = Instance.new("UIStroke")
MainStroke.Color = Color3.fromRGB(36, 42, 58)
MainStroke.Thickness = 1.2
MainStroke.Parent = Main

-- TopBar Compacta (38px)
local TopBar = Instance.new("Frame")
TopBar.Size = UDim2.new(1, 0, 0, 38)
TopBar.BackgroundColor3 = Color3.fromRGB(21, 25, 35)
TopBar.BorderSizePixel = 0
TopBar.ZIndex = 10
TopBar.Parent = Main

local TopCorner = Instance.new("UICorner")
TopCorner.CornerRadius = UDim.new(0, 10)
TopCorner.Parent = TopBar

-- Botão Menu Hambúrguer (Sidebar)
local MenuBtn = Instance.new("TextButton")
MenuBtn.Size = UDim2.new(0, 28, 0, 28)
MenuBtn.Position = UDim2.new(0, 6, 0.5, -14)
MenuBtn.BackgroundColor3 = Color3.fromRGB(30, 35, 48)
MenuBtn.Text = "☰"
MenuBtn.Font = Enum.Font.GothamBold
MenuBtn.TextColor3 = Color3.fromRGB(230, 230, 240)
MenuBtn.TextSize = 14
MenuBtn.ZIndex = 11
MenuBtn.Parent = TopBar

local MenuCorner = Instance.new("UICorner")
MenuCorner.CornerRadius = UDim.new(0, 6)
MenuCorner.Parent = MenuBtn

local Title = Instance.new("TextLabel")
Title.Size = UDim2.new(1, -140, 1, 0)
Title.Position = UDim2.new(0, 40, 0, 0)
Title.BackgroundTransparency = 1
Title.Text = "⚡ AI Studio (" .. initialCount .. " remotes/mods)"
Title.Font = Enum.Font.GothamBold
Title.TextSize = 11
Title.TextColor3 = Color3.fromRGB(240, 245, 255)
Title.TextXAlignment = Enum.TextXAlignment.Left
Title.ZIndex = 11
Title.Parent = TopBar

-- Controles Direita (Reescanear + Fechar)
local TopRightFrame = Instance.new("Frame")
TopRightFrame.Size = UDim2.new(0, 65, 1, 0)
TopRightFrame.Position = UDim2.new(1, -70, 0, 0)
TopRightFrame.BackgroundTransparency = 1
TopRightFrame.ZIndex = 11
TopRightFrame.Parent = TopBar

local TopRightLayout = Instance.new("UIListLayout")
TopRightLayout.FillDirection = Enum.FillDirection.Horizontal
TopRightLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
TopRightLayout.VerticalAlignment = Enum.VerticalAlignment.Center
TopRightLayout.Padding = UDim.new(0, 5)
TopRightLayout.Parent = TopRightFrame

-- Botão de Re-Scanear Explorer
local RescanBtn = Instance.new("TextButton")
RescanBtn.Size = UDim2.new(0, 28, 0, 28)
RescanBtn.BackgroundColor3 = Color3.fromRGB(30, 42, 60)
RescanBtn.Text = "🔄"
RescanBtn.Font = Enum.Font.GothamBold
RescanBtn.TextColor3 = Color3.fromRGB(200, 220, 255)
RescanBtn.TextSize = 11
RescanBtn.Parent = TopRightFrame

local RescanCorner = Instance.new("UICorner")
RescanCorner.CornerRadius = UDim.new(0, 6)
RescanCorner.Parent = RescanBtn

RescanBtn.MouseButton1Click:Connect(function()
    local c = ScanGameExplorer()
    Title.Text = "⚡ AI Studio (" .. c .. " remotes/mods)"
    ShowToast("Explorer atualizado: " .. c .. " itens!", Color3.fromRGB(50, 95, 230))
end)

local CloseBtn = Instance.new("TextButton")
CloseBtn.Size = UDim2.new(0, 28, 0, 28)
CloseBtn.BackgroundColor3 = Color3.fromRGB(60, 28, 35)
CloseBtn.Text = "✕"
CloseBtn.Font = Enum.Font.GothamBold
CloseBtn.TextColor3 = Color3.fromRGB(255, 120, 120)
CloseBtn.TextSize = 11
CloseBtn.Parent = TopRightFrame

local CloseCorner = Instance.new("UICorner")
CloseCorner.CornerRadius = UDim.new(0, 6)
CloseCorner.Parent = CloseBtn

CloseBtn.MouseButton1Click:Connect(function()
    ScreenGui:Destroy()
end)

-- Barra de Modelos (Rolagem Horizontal Compacta)
local ModelScroll = Instance.new("ScrollingFrame")
ModelScroll.Size = UDim2.new(1, -12, 0, 26)
ModelScroll.Position = UDim2.new(0, 6, 0, 42)
ModelScroll.BackgroundTransparency = 1
ModelScroll.BorderSizePixel = 0
ModelScroll.ScrollBarThickness = 0
ModelScroll.CanvasSize = UDim2.new(0, 390, 0, 0)
ModelScroll.Parent = Main

local ModelList = Instance.new("UIListLayout")
ModelList.FillDirection = Enum.FillDirection.Horizontal
ModelList.Padding = UDim.new(0, 5)
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
    mBtn.Size = UDim2.new(0, 122, 0, 24)
    mBtn.BackgroundColor3 = Color3.fromRGB(25, 30, 42)
    mBtn.Text = m
    mBtn.Font = Enum.Font.GothamMedium
    mBtn.TextSize = 9
    mBtn.TextColor3 = Color3.fromRGB(140, 145, 165)
    mBtn.Parent = ModelScroll

    local mc = Instance.new("UICorner")
    mc.CornerRadius = UDim.new(0, 5)
    mc.Parent = mBtn

    mBtn.MouseButton1Click:Connect(function()
        SelectModel(m)
    end)
    ModelButtons[m] = mBtn
end
SelectModel(API_CONFIG.CurrentModel)

-- Painel de Chat
local ChatScroll = Instance.new("ScrollingFrame")
ChatScroll.Size = UDim2.new(1, -12, 1, -116)
ModelScroll.Position = UDim2.new(0, 6, 0, 40)
ChatScroll.Position = UDim2.new(0, 6, 0, 70)
ChatScroll.BackgroundTransparency = 1
ChatScroll.BorderSizePixel = 0
ChatScroll.ScrollBarThickness = 3
ChatScroll.ScrollBarImageColor3 = Color3.fromRGB(50, 60, 80)
ChatScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
ChatScroll.Parent = Main

local ChatListLayout = Instance.new("UIListLayout")
ChatListLayout.SortOrder = Enum.SortOrder.LayoutOrder
ChatListLayout.Padding = UDim.new(0, 8)
ChatListLayout.Parent = ChatScroll

-- Barra Inferior de Input Compacta (38px)
local InputFrame = Instance.new("Frame")
InputFrame.Size = UDim2.new(1, -12, 0, 38)
InputFrame.Position = UDim2.new(0, 6, 1, -42)
InputFrame.BackgroundColor3 = Color3.fromRGB(21, 25, 35)
InputFrame.Parent = Main

local InputCorner = Instance.new("UICorner")
InputCorner.CornerRadius = UDim.new(0, 7)
InputCorner.Parent = InputFrame

local InputStroke = Instance.new("UIStroke")
InputStroke.Color = Color3.fromRGB(36, 42, 58)
InputStroke.Parent = InputFrame

local TextBox = Instance.new("TextBox")
TextBox.Size = UDim2.new(1, -75, 1, 0)
TextBox.Position = UDim2.new(0, 8, 0, 0)
TextBox.BackgroundTransparency = 1
TextBox.Font = Enum.Font.Gotham
TextBox.PlaceholderText = "Peça um script com base no jogo..."
TextBox.PlaceholderColor3 = Color3.fromRGB(100, 105, 125)
TextBox.Text = ""
TextBox.TextColor3 = Color3.fromRGB(255, 255, 255)
TextBox.TextSize = 11
TextBox.ClearTextOnFocus = false
TextBox.TextXAlignment = Enum.TextXAlignment.Left
TextBox.Parent = InputFrame

local SendBtn = Instance.new("TextButton")
SendBtn.Size = UDim2.new(0, 62, 0, 28)
SendBtn.Position = UDim2.new(1, -66, 0.5, -14)
SendBtn.BackgroundColor3 = Color3.fromRGB(50, 85, 230)
SendBtn.Text = "Gerar"
SendBtn.Font = Enum.Font.GothamBold
SendBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
SendBtn.TextSize = 11
SendBtn.Parent = InputFrame

local SendCorner = Instance.new("UICorner")
SendCorner.CornerRadius = UDim.new(0, 5)
SendCorner.Parent = SendBtn

-- ====================================================================
--                  SIDEBAR COMPACTA (HISTÓRICO)
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
SideCorner.CornerRadius = UDim.new(0, 10)
SideCorner.Parent = Sidebar

local SideHeader = Instance.new("Frame")
SideHeader.Size = UDim2.new(1, 0, 0, 38)
SideHeader.BackgroundTransparency = 1
SideHeader.ZIndex = 52
SideHeader.Parent = Sidebar

local SideTitle = Instance.new("TextLabel")
SideTitle.Size = UDim2.new(1, -36, 1, 0)
SideTitle.Position = UDim2.new(0, 10, 0, 0)
SideTitle.BackgroundTransparency = 1
SideTitle.Text = "Histórico"
SideTitle.Font = Enum.Font.GothamBold
SideTitle.TextColor3 = Color3.fromRGB(240, 245, 255)
SideTitle.TextSize = 13
SideTitle.TextXAlignment = Enum.TextXAlignment.Left
SideTitle.ZIndex = 53
SideTitle.Parent = SideHeader

local CloseSideBtn = Instance.new("TextButton")
CloseSideBtn.Size = UDim2.new(0, 26, 0, 26)
CloseSideBtn.Position = UDim2.new(1, -30, 0.5, -13)
CloseSideBtn.BackgroundColor3 = Color3.fromRGB(30, 35, 48)
CloseSideBtn.Text = "←"
CloseSideBtn.Font = Enum.Font.GothamBold
CloseSideBtn.TextColor3 = Color3.fromRGB(200, 205, 225)
CloseSideBtn.TextSize = 12
CloseSideBtn.ZIndex = 53
CloseSideBtn.Parent = SideHeader

local CloseSideCorner = Instance.new("UICorner")
CloseSideCorner.CornerRadius = UDim.new(0, 5)
CloseSideCorner.Parent = CloseSideBtn

local NewChatBtn = Instance.new("TextButton")
NewChatBtn.Size = UDim2.new(1, -16, 0, 32)
NewChatBtn.Position = UDim2.new(0, 8, 0, 42)
NewChatBtn.BackgroundColor3 = Color3.fromRGB(38, 140, 75)
NewChatBtn.Text = "➕ Nova Conversa"
NewChatBtn.Font = Enum.Font.GothamBold
NewChatBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
NewChatBtn.TextSize = 11
NewChatBtn.ZIndex = 52
NewChatBtn.Parent = Sidebar

local NewChatCorner = Instance.new("UICorner")
NewChatCorner.CornerRadius = UDim.new(0, 6)
NewChatCorner.Parent = NewChatBtn

local HistoryScroll = Instance.new("ScrollingFrame")
HistoryScroll.Size = UDim2.new(1, -16, 1, -85)
HistoryScroll.Position = UDim2.new(0, 8, 0, 80)
HistoryScroll.BackgroundTransparency = 1
HistoryScroll.BorderSizePixel = 0
HistoryScroll.ScrollBarThickness = 2
HistoryScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
HistoryScroll.ZIndex = 52
HistoryScroll.Parent = Sidebar

local HistoryLayout = Instance.new("UIListLayout")
HistoryLayout.SortOrder = Enum.SortOrder.LayoutOrder
HistoryLayout.Padding = UDim.new(0, 5)
HistoryLayout.Parent = HistoryScroll

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
--                  SISTEMA DE MENSAGENS E CARDS
-- ====================================================================
local function RenderCard(sender, text, rawCode)
    local Card = Instance.new("Frame")
    Card.Size = UDim2.new(1, 0, 0, 0)
    Card.BackgroundColor3 = (sender == "Você") and Color3.fromRGB(22, 26, 38) or Color3.fromRGB(18, 20, 28)
    Card.AutomaticSize = Enum.AutomaticSize.Y
    Card.BorderSizePixel = 0
    Card.Parent = ChatScroll

    local CardCorner = Instance.new("UICorner")
    CardCorner.CornerRadius = UDim.new(0, 7)
    CardCorner.Parent = Card

    local Padding = Instance.new("UIPadding")
    Padding.PaddingTop = UDim.new(0, 6)
    Padding.PaddingBottom = UDim.new(0, 6)
    Padding.PaddingLeft = UDim.new(0, 8)
    Padding.PaddingRight = UDim.new(0, 8)
    Padding.Parent = Card

    local CardLayout = Instance.new("UIListLayout")
    CardLayout.SortOrder = Enum.SortOrder.LayoutOrder
    CardLayout.Padding = UDim.new(0, 5)
    CardLayout.Parent = Card

    local SenderLabel = Instance.new("TextLabel")
    SenderLabel.Size = UDim2.new(1, 0, 0, 13)
    SenderLabel.BackgroundTransparency = 1
    SenderLabel.Font = Enum.Font.GothamBold
    SenderLabel.Text = (sender == "Você") and "👤 Você" or "🤖 IA (" .. API_CONFIG.CurrentModel .. ")"
    SenderLabel.TextColor3 = (sender == "Você") and Color3.fromRGB(110, 160, 255) or Color3.fromRGB(110, 235, 160)
    SenderLabel.TextSize = 10
    SenderLabel.TextXAlignment = Enum.TextXAlignment.Left
    SenderLabel.Parent = Card

    if text and text:gsub("%s+", "") ~= "" then
        local Content = Instance.new("TextLabel")
        Content.Size = UDim2.new(1, 0, 0, 0)
        Content.BackgroundTransparency = 1
        Content.Font = Enum.Font.Gotham
        Content.Text = text
        Content.TextColor3 = Color3.fromRGB(220, 225, 235)
        Content.TextSize = 11
        Content.TextWrapped = true
        Content.AutomaticSize = Enum.AutomaticSize.Y
        Content.TextXAlignment = Enum.TextXAlignment.Left
        Content.Parent = Card
    end

    if rawCode then
        local CodeBox = Instance.new("Frame")
        CodeBox.Size = UDim2.new(1, 0, 0, 0)
        CodeBox.BackgroundColor3 = Color3.fromRGB(12, 14, 20)
        CodeBox.AutomaticSize = Enum.AutomaticSize.Y
        CodeBox.Parent = Card

        local CodeCorner = Instance.new("UICorner")
        CodeCorner.CornerRadius = UDim.new(0, 6)
        CodeCorner.Parent = CodeBox

        local CodePad = Instance.new("UIPadding")
        CodePad.PaddingTop = UDim.new(0, 5)
        CodePad.PaddingBottom = UDim.new(0, 5)
        CodePad.PaddingLeft = UDim.new(0, 6)
        CodePad.PaddingRight = UDim.new(0, 6)
        CodePad.Parent = CodeBox

        local CodeList = Instance.new("UIListLayout")
        CodeList.SortOrder = Enum.SortOrder.LayoutOrder
        CodeList.Padding = UDim.new(0, 5)
        CodeList.Parent = CodeBox

        local CopyBtn = Instance.new("TextButton")
        CopyBtn.Size = UDim2.new(1, 0, 0, 28)
        CopyBtn.BackgroundColor3 = Color3.fromRGB(45, 80, 220)
        CopyBtn.Text = "📋 COPIAR TODO O SCRIPT"
        CopyBtn.Font = Enum.Font.GothamBold
        CopyBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
        CopyBtn.TextSize = 10
        CopyBtn.Parent = CodeBox

        local CopyCorner = Instance.new("UICorner")
        CopyCorner.CornerRadius = UDim.new(0, 5)
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

        local CodeLabel = Instance.new("TextLabel")
        CodeLabel.Size = UDim2.new(1, 0, 0, 0)
        CodeLabel.BackgroundTransparency = 1
        CodeLabel.Font = Enum.Font.Code
        CodeLabel.Text = rawCode
        CodeLabel.TextColor3 = Color3.fromRGB(160, 220, 255)
        CodeLabel.TextSize = 9
        CodeLabel.TextWrapped = true
        CodeLabel.AutomaticSize = Enum.AutomaticSize.Y
        CodeLabel.TextXAlignment = Enum.TextXAlignment.Left
        CodeLabel.Parent = CodeBox
    end

    task.defer(function()
        ChatScroll.CanvasPosition = Vector2.new(0, 999999)
    end)
end

local function LoadSessionMessages(session)
    for _, child in ipairs(ChatScroll:GetChildren()) do
        if child:IsA("Frame") then child:Destroy() end
    end
    for _, msg in ipairs(session.messages) do
        RenderCard(msg.sender, msg.text, msg.rawCode)
    end
    if #session.messages == 0 then
        RenderCard("Sistema", "Scanner carregou " .. #ScannedExplorerData .. " instâncias do jogo. Peça seu script!", nil)
    end
end

local function RefreshSidebarHistory()
    for _, child in ipairs(HistoryScroll:GetChildren()) do
        if child:IsA("Frame") then child:Destroy() end
    end

    for _, session in ipairs(ChatSessions) do
        local Item = Instance.new("Frame")
        Item.Size = UDim2.new(1, 0, 0, 32)
        Item.BackgroundColor3 = (session.id == CurrentSessionId) and Color3.fromRGB(35, 42, 60) or Color3.fromRGB(24, 28, 38)
        Item.BorderSizePixel = 0
        Item.ZIndex = 53
        Item.Parent = HistoryScroll

        local ItemCorner = Instance.new("UICorner")
        ItemCorner.CornerRadius = UDim.new(0, 5)
        ItemCorner.Parent = Item

        local Btn = Instance.new("TextButton")
        Btn.Size = UDim2.new(1, -26, 1, 0)
        Btn.Position = UDim2.new(0, 6, 0, 0)
        Btn.BackgroundTransparency = 1
        Btn.Text = session.title
        Btn.Font = Enum.Font.GothamMedium
        Btn.TextSize = 10
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

        local DelBtn = Instance.new("TextButton")
        DelBtn.Size = UDim2.new(0, 20, 0, 20)
        DelBtn.Position = UDim2.new(1, -22, 0.5, -10)
        DelBtn.BackgroundTransparency = 1
        DelBtn.Text = "✕"
        DelBtn.Font = Enum.Font.GothamBold
        DelBtn.TextColor3 = Color3.fromRGB(150, 70, 80)
        DelBtn.TextSize = 9
        DelBtn.ZIndex = 54
        DelBtn.Parent = Item

        DelBtn.MouseButton1Click:Connect(function()
            if #ChatSessions > 1 then
                for idx, s in ipairs(ChatSessions) do
                    if s.id == session.id then
                        table.remove(ChatSessions, idx)
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

NewChatBtn.MouseButton1Click:Connect(function()
    local newSess = CreateNewSessionData()
    CurrentSessionId = newSess.id
    LoadSessionMessages(newSess)
    RefreshSidebarHistory()
    ToggleSidebar(false)
    ShowToast("Nova conversa iniciada!", Color3.fromRGB(38, 140, 75))
end)

-- ====================================================================
--                  REQUISIÇÃO DA IA COM CONTEXTO REAL
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

    if #currentSession.messages == 0 then
        local preview = promptText:sub(1, 14)
        if #promptText > 14 then preview = preview .. "..." end
        currentSession.title = preview
        RefreshSidebarHistory()
    end

    table.insert(currentSession.messages, {sender = "Você", text = promptText, rawCode = nil})
    RenderCard("Você", promptText, nil)

    isSending = true
    SendBtn.Text = "..."
    SendBtn.BackgroundColor3 = Color3.fromRGB(80, 85, 105)

    -- Injeta os scripts, módulos e remotes capturados do jogo no System Prompt
    local systemPrompt = "Você é um engenheiro sênior de Luau no Roblox. " ..
        "Você tem acesso total à estrutura real do Explorer deste jogo atual:\n" ..
        "=== HIERARQUIA CAPTURADA DO JOGO (SCRIPTS, MODULES, REMOTES) ===\n" ..
        ScannedSummaryText .. "\n" ..
        "================================================================\n" ..
        "INSTRUÇÕES OBRIGATÓRIAS:\n" ..
        "1. Analise os caminhos dos RemoteEvents, RemoteFunctions e ModuleScripts listados acima e use os caminhos exatos no script gerado.\n" ..
        "2. Sempre devolva o script completo dentro de um bloco formatado com ```lua [codigo] ```.\n" ..
        "3. O código deve ser avançado, seguro (usando pcall), modular e pronto para execução."

    local payload = {
        model = API_CONFIG.CurrentModel,
        messages = {
            { role = "system", content = systemPrompt },
            { role = "user", content = promptText }
        },
        temperature = 0.4
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