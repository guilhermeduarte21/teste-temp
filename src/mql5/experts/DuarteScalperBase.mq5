//+------------------------------------------------------------------+
//|                                     DuarteScalerBase.mq5         |
//|                           Duarte-Scalper Base Expert Advisor     |
//|                                      https://www.duarte.com      |
//+------------------------------------------------------------------+
#property copyright "Duarte Trading Systems"
#property link      "https://www.duarte.com"
#property version   "1.00"
#property description "Duarte-Scalper - Advanced AI-Powered Scalping Robot"

//+------------------------------------------------------------------+
//| Includes necessários                                             |
//+------------------------------------------------------------------+
#include <DuarteScalper\Communication.mqh>
#include <Trade\Trade.mqh>
#include <Trade\SymbolInfo.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\AccountInfo.mqh>

//+------------------------------------------------------------------+
//| Input parameters                                                 |
//+------------------------------------------------------------------+
input group "=== CONFIGURAÇÕES PRINCIPAIS ==="
input string InpSymbols = "WINM25,WDOM25";          // Símbolos para negociar
input double InpLotSize = 1.0;                       // Tamanho do lote
input int    InpMagicNumber = 778899;                // Magic Number

input group "=== RISK MANAGEMENT ==="
input double InpMaxRiskPerTrade = 0.01;              // Risco máximo por trade (%)
input double InpMaxDailyLoss = 0.03;                 // Perda máxima diária (%)
input int    InpMaxConsecutiveLosses = 5;            // Máximo de perdas consecutivas
input int    InpMaxPositionTimeMin = 10;             // Tempo máximo de posição (minutos)

input group "=== CONFIGURAÇÕES DE IA ==="
input double InpMinConfidence = 0.7;                 // Confiança mínima da IA
input int    InpSignalTimeoutSec = 5;                // Timeout do sinal da IA (segundos)
input bool   InpEnableAI = true;                     // Habilitar processamento de IA

input group "=== CONFIGURAÇÕES DE COMUNICAÇÃO ==="
input string InpCommName = "DuarteScalper_Comm";     // Nome da comunicação
input bool   InpDebugMode = false;                   // Modo debug

input group "=== CONFIGURAÇÕES DO PAINEL ==="
input bool   InpShowPanel = true;                    // Mostrar painel gráfico
input int    InpPanelPosX = 10;                      // Posição X do painel
input int    InpPanelPosY = 30;                      // Posição Y do painel

//+------------------------------------------------------------------+
//| Global variables                                                 |
//+------------------------------------------------------------------+
CDuarteCommunication* g_comm = NULL;                 // Comunicação com Python
CTrade g_trade;                                      // Objeto de negociação
CSymbolInfo g_symbolInfo;                            // Informações do símbolo
CPositionInfo g_positionInfo;                        // Informações de posição
CAccountInfo g_accountInfo;                          // Informações da conta

// Arrays de símbolos
string g_symbols[];
int g_symbolsCount = 0;

// Estado do robô
bool g_isInitialized = false;
bool g_isRunning = false;
bool g_aiConnected = false;

// Controle de tempo
datetime g_lastTickTime = 0;
datetime g_lastHeartbeat = 0;

// Controle de risco
double g_dailyPnL = 0.0;
int g_consecutiveLosses = 0;
datetime g_lastTradeTime = 0;
datetime g_sessionStartTime = 0;

// Estatísticas
struct DuarteStats
{
    long     totalTrades;
    long     winTrades;
    long     lossTrades;
    double   totalProfit;
    double   todayProfit;
    double   maxDrawdown;
    double   currentDrawdown;
    double   sharpeRatio;
    datetime lastUpdateTime;
};

DuarteStats g_stats;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
    Print("=== INICIANDO DUARTE-SCALPER ===");
    Print("Versão: ", "1.00");
    Print("Símbolos: ", InpSymbols);
    Print("Magic Number: ", InpMagicNumber);
    
    // Verificar se já há outra instância rodando
    if (GlobalVariableCheck("DuarteScalper_Running"))
    {
        Alert("ERRO: Duarte-Scalper já está rodando em outro gráfico!");
        return INIT_FAILED;
    }
    
    // Marcar como rodando
    GlobalVariableSet("DuarteScalper_Running", 1);
    
    // Inicializar comunicação
    g_comm = new CDuarteCommunication();
    if (!g_comm.Initialize(InpCommName))
    {
        Print("ERRO: Falha ao inicializar comunicação com Python");
        delete g_comm;
        g_comm = NULL;
        return INIT_FAILED;
    }
    
    g_comm.SetDebugMode(InpDebugMode);
    Print("✅ Comunicação com Python inicializada");
    
    // Configurar trade
    g_trade.SetExpertMagicNumber(InpMagicNumber);
    g_trade.SetDeviationInPoints(10);
    g_trade.SetTypeFilling(ORDER_FILLING_FOK);
    
    // Parse símbolos
    if (!ParseSymbols())
    {
        Print("ERRO: Falha ao processar símbolos");
        return INIT_FAILED;
    }
    
    // Verificar símbolos
    for (int i = 0; i < g_symbolsCount; i++)
    {
        if (!g_symbolInfo.Name(g_symbols[i]))
        {
            Print("ERRO: Símbolo inválido: ", g_symbols[i]);
            return INIT_FAILED;
        }
        Print("✅ Símbolo verificado: ", g_symbols[i]);
    }
    
    // Inicializar estatísticas
    InitializeStats();
    
    // Inicializar sessão
    g_sessionStartTime = TimeCurrent();
    g_dailyPnL = 0.0;
    g_consecutiveLosses = 0;
    
    // Criar painel se habilitado
    if (InpShowPanel)
    {
        CreatePanel();
    }
    
    // Enviar status inicial
    g_comm.SendStatusUpdate("INITIALIZED", "Duarte-Scalper inicializado com sucesso");
    
    g_isInitialized = true;
    g_isRunning = true;
    
    Print("✅ DUARTE-SCALPER INICIALIZADO COM SUCESSO!");
    
    return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    Print("=== FINALIZANDO DUARTE-SCALPER ===");
    Print("Razão: ", GetDeintReason(reason));
    
    g_isRunning = false;
    
    // Fechar todas as posições se necessário
    if (reason == REASON_REMOVE || reason == REASON_PROGRAM)
    {
        CloseAllPositions();
    }
    
    // Salvar estatísticas finais
    SaveStatistics();
    
    // Finalizar comunicação
    if (g_comm != NULL)
    {
        g_comm.SendStatusUpdate("SHUTDOWN", "Duarte-Scalper finalizado");
        g_comm.Shutdown();
        delete g_comm;
        g_comm = NULL;
    }
    
    // Remover painel
    if (InpShowPanel)
    {
        DestroyPanel();
    }
    
    // Remover flag de execução
    GlobalVariableDel("DuarteScalper_Running");
    
    Print("✅ DUARTE-SCALPER FINALIZADO");
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
    // Verificar se inicializado
    if (!g_isInitialized || !g_isRunning)
        return;
    
    // Verificar comunicação
    if (!CheckCommunication())
        return;
    
    // Processar cada símbolo
    for (int i = 0; i < g_symbolsCount; i++)
    {
        ProcessSymbolTick(g_symbols[i]);
    }
    
    // Verificar risk management
    CheckRiskManagement();
    
    // Atualizar painel
    if (InpShowPanel)
    {
        UpdatePanel();
    }
    
    // Heartbeat a cada 30 segundos
    if (TimeCurrent() - g_lastHeartbeat >= 30)
    {
        g_comm.SendHeartbeat();
        g_lastHeartbeat = TimeCurrent();
    }
}

//+------------------------------------------------------------------+
//| Expert timer function                                            |
//+------------------------------------------------------------------+
void OnTimer()
{
    // Verificar conexão com IA
    CheckAIConnection();
    
    // Atualizar estatísticas
    UpdateStatistics();
    
    // Verificar sessão diária
    CheckDailySession();
}

//+------------------------------------------------------------------+
//| Trade function                                                   |
//+------------------------------------------------------------------+
void OnTrade()
{
    // Processar execuções de trade
    ProcessTradeEvent();
    
    // Atualizar estatísticas
    UpdateTradeStatistics();
}

//+------------------------------------------------------------------+
//| Chart event function                                            |
//+------------------------------------------------------------------+
void OnChartEvent(const int id,
                  const long& lparam,
                  const double& dparam,
                  const string& sparam)
{
    // Processar eventos do painel
    if (InpShowPanel)
    {
        ProcessPanelEvents(id, lparam, dparam, sparam);
    }
}

//+------------------------------------------------------------------+
//| Funções auxiliares                                               |
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| Parse símbolos de entrada                                        |
//+------------------------------------------------------------------+
bool ParseSymbols()
{
    string symbols_str = InpSymbols;
    
    // Contar símbolos
    g_symbolsCount = 1;
    for (int i = 0; i < StringLen(symbols_str); i++)
    {
        if (StringGetCharacter(symbols_str, i) == ',')
            g_symbolsCount++;
    }
    
    // Redimensionar array
    ArrayResize(g_symbols, g_symbolsCount);
    
    // Extrair símbolos
    string current_symbol = "";
    int symbol_index = 0;
    
    for (int i = 0; i <= StringLen(symbols_str); i++)
    {
        ushort char_code = StringGetCharacter(symbols_str, i);
        
        if (char_code == ',' || i == StringLen(symbols_str))
        {
            // Limpar espaços
            StringTrimLeft(current_symbol);
            StringTrimRight(current_symbol);
            
            if (StringLen(current_symbol) > 0)
            {
                g_symbols[symbol_index] = current_symbol;
                symbol_index++;
            }
            
            current_symbol = "";
        }
        else
        {
            current_symbol += CharToString((char)char_code);
        }
    }
    
    return g_symbolsCount > 0;
}

//+------------------------------------------------------------------+
//| Verificar comunicação                                            |
//+------------------------------------------------------------------+
bool CheckCommunication()
{
    if (g_comm == NULL)
        return false;
    
    if (!g_comm.IsConnected())
    {
        // Tentar reconectar
        Print("Tentando reconectar com Python...");
        g_comm.ResetConnection();
        return false;
    }
    
    return g_comm.CheckConnection();
}

//+------------------------------------------------------------------+
//| Processar tick do símbolo                                        |
//+------------------------------------------------------------------+
void ProcessSymbolTick(const string symbol)
{
    // Verificar se há posição aberta
    bool hasPosition = false;
    if (g_positionInfo.Select(symbol))
    {
        if (g_positionInfo.Magic() == InpMagicNumber)
        {
            hasPosition = true;
            // Gerenciar posição existente
            ManagePosition(symbol);
        }
    }
    
    // Se não há posição e IA está habilitada, buscar sinal
    if (!hasPosition && InpEnableAI)
    {
        // Enviar dados do tick
        SendTickData(symbol);
        
        // Solicitar sinal (com throttling)
        if (TimeCurrent() - g_lastTickTime >= 1) // 1 segundo de throttling
        {
            CheckForSignal(symbol);
            g_lastTickTime = TimeCurrent();
        }
    }
}

//+------------------------------------------------------------------+
//| Enviar dados do tick                                             |
//+------------------------------------------------------------------+
void SendTickData(const string symbol)
{
    if (g_comm == NULL || !g_comm.IsConnected())
        return;
    
    MqlTick tick;
    if (!SymbolInfoTick(symbol, tick))
        return;
    
    DuarteTickData tickData;
    tickData.symbol = symbol;
    tickData.time = tick.time;
    tickData.bid = tick.bid;
    tickData.ask = tick.ask;
    tickData.last = tick.last;
    tickData.volume = tick.volume;
    tickData.spread = tick.ask - tick.bid;
    
    // Calcular direção simples
    static double lastPrice = 0;
    if (lastPrice > 0)
    {
        if (tick.last > lastPrice)
            tickData.direction = 1;
        else if (tick.last < lastPrice)
            tickData.direction = -1;
        else
            tickData.direction = 0;
    }
    lastPrice = tick.last;
    
    g_comm.SendTickData(tickData);
}

//+------------------------------------------------------------------+
//| Verificar sinais da IA                                          |
//+------------------------------------------------------------------+
void CheckForSignal(const string symbol)
{
    if (g_comm == NULL || !g_comm.IsConnected())
        return;
    
    DuarteSignalData signal;
    if (g_comm.RequestSignal(symbol, signal))
    {
        // Verificar se sinal é válido
        if (signal.confidence >= InpMinConfidence && signal.direction != 0)
        {
            // Executar trade baseado no sinal
            ExecuteSignal(symbol, signal);
        }
    }
}

//+------------------------------------------------------------------+
//| Executar sinal da IA                                             |
//+------------------------------------------------------------------+
void ExecuteSignal(const string symbol, const DuarteSignalData& signal)
{
    if (!CanOpenPosition(symbol))
        return;
    
    // Preparar dados do símbolo
    if (!g_symbolInfo.Name(symbol))
        return;
    
    // Calcular volume baseado no risco
    double volume = CalculateVolume(symbol, signal.confidence);
    if (volume <= 0)
        return;
    
    // Obter preços
    double price, sl, tp;
    if (!CalculatePrices(symbol, signal, price, sl, tp))
        return;
    
    // Criar ordem
    DuarteOrderData order;
    order.symbol = symbol;
    order.operation = (signal.direction > 0) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
    order.volume = volume;
    order.price = price;
    order.sl = sl;
    order.tp = tp;
    order.comment = StringFormat("Duarte-AI Conf:%.2f", signal.confidence);
    order.magic = InpMagicNumber;
    
    // Executar ordem
    bool result = false;
    if (signal.direction > 0)
    {
        result = g_trade.Buy(volume, symbol, price, sl, tp, order.comment);
    }
    else
    {
        result = g_trade.Sell(volume, symbol, price, sl, tp, order.comment);
    }
    
    if (result)
    {
        Print("✅ Trade executado: ", symbol, " ", 
              (signal.direction > 0 ? "BUY" : "SELL"), 
              " Volume: ", volume, 
              " Confiança: ", signal.confidence);
              
        g_lastTradeTime = TimeCurrent();
        g_stats.totalTrades++;
    }
    else
    {
        Print("❌ Falha no trade: ", symbol, " Error: ", GetLastError());
    }
}

//+------------------------------------------------------------------+
//| Gerenciar posição existente                                     |
//+------------------------------------------------------------------+
void ManagePosition(const string symbol)
{
    if (!g_positionInfo.Select(symbol))
        return;
    
    // Verificar timeout de posição
    if (InpMaxPositionTimeMin > 0)
    {
        datetime positionTime = g_positionInfo.Time();
        if (TimeCurrent() - positionTime >= InpMaxPositionTimeMin * 60)
        {
            ClosePosition(symbol, "Timeout");
            return;
        }
    }
    
    // Implementar trailing stop ou outras estratégias de saída
    // (será implementado na próxima parte)
}

//+------------------------------------------------------------------+
//| Verificar se pode abrir posição                                 |
//+------------------------------------------------------------------+
bool CanOpenPosition(const string symbol)
{
    // Verificar limite de perdas consecutivas
    if (g_consecutiveLosses >= InpMaxConsecutiveLosses)
    {
        Print("❌ Máximo de perdas consecutivas atingido: ", g_consecutiveLosses);
        return false;
    }
    
    // Verificar perda diária
    if (g_dailyPnL <= -InpMaxDailyLoss * g_accountInfo.Balance())
    {
        Print("❌ Limite de perda diária atingido: ", g_dailyPnL);
        return false;
    }
    
    // Verificar se já há posição no símbolo
    if (g_positionInfo.Select(symbol))
    {
        if (g_positionInfo.Magic() == InpMagicNumber)
            return false;
    }
    
    return true;
}

//+------------------------------------------------------------------+
//| Calcular volume baseado no risco                                |
//+------------------------------------------------------------------+
double CalculateVolume(const string symbol, double confidence)
{
    if (!g_symbolInfo.Name(symbol))
        return 0;
    
    double balance = g_accountInfo.Balance();
    double riskAmount = balance * InpMaxRiskPerTrade;
    
    // Ajustar baseado na confiança
    double confidenceMultiplier = MathMin(confidence * 1.5, 1.0);
    riskAmount *= confidenceMultiplier;
    
    // Calcular volume baseado no risco
    double tickValue = g_symbolInfo.TickValue();
    double tickSize = g_symbolInfo.TickSize();
    double spread = g_symbolInfo.Spread() * g_symbolInfo.Point();
    
    if (tickValue == 0 || tickSize == 0)
        return InpLotSize;
    
    // Assumir stop loss de 100 pontos como base
    double stopLossPoints = 100 * g_symbolInfo.Point();
    double stopLossValue = stopLossPoints / tickSize * tickValue;
    
    if (stopLossValue > 0)
    {
        double volume = riskAmount / stopLossValue;
        volume = MathMax(volume, g_symbolInfo.LotsMin());
        volume = MathMin(volume, g_symbolInfo.LotsMax());
        return NormalizeDouble(volume, 2);
    }
    
    return InpLotSize;
}

//+------------------------------------------------------------------+
//| Calcular preços para entrada                                    |
//+------------------------------------------------------------------+
bool CalculatePrices(const string symbol, const DuarteSignalData& signal,
                     double& price, double& sl, double& tp)
{
    if (!g_symbolInfo.Name(symbol))
        return false;
    
    MqlTick tick;
    if (!SymbolInfoTick(symbol, tick))
        return false;
    
    double point = g_symbolInfo.Point();
    double spread = g_symbolInfo.Spread() * point;
    
    if (signal.direction > 0) // BUY
    {
        price = tick.ask;
        sl = price - 100 * point; // 100 points stop loss
        tp = price + 200 * point; // 2:1 risk/reward
    }
    else // SELL
    {
        price = tick.bid;
        sl = price + 100 * point;
        tp = price - 200 * point;
    }
    
    // Normalizar preços
    int digits = g_symbolInfo.Digits();
    price = NormalizeDouble(price, digits);
    sl = NormalizeDouble(sl, digits);
    tp = NormalizeDouble(tp, digits);
    
    return true;
}

//+------------------------------------------------------------------+
//| Fechar posição                                                   |
//+------------------------------------------------------------------+
bool ClosePosition(const string symbol, const string reason = "Manual")
{
    if (!g_positionInfo.Select(symbol))
        return false;
    
    if (g_positionInfo.Magic() != InpMagicNumber)
        return false;
    
    string comment = "Duarte-Close: " + reason;
    bool result = g_trade.PositionClose(symbol, 3);
    
    if (result)
    {
        Print("✅ Posição fechada: ", symbol, " Motivo: ", reason);
    }
    else
    {
        Print("❌ Falha ao fechar posição: ", symbol, " Error: ", GetLastError());
    }
    
    return result;
}

//+------------------------------------------------------------------+
//| Fechar todas as posições                                         |
//+------------------------------------------------------------------+
void CloseAllPositions()
{
    for (int i = 0; i < g_symbolsCount; i++)
    {
        ClosePosition(g_symbols[i], "Shutdown");
    }
}

//+------------------------------------------------------------------+
//| Verificar risk management                                        |
//+------------------------------------------------------------------+
void CheckRiskManagement()
{
    // Calcular P&L diário
    CalculateDailyPnL();
    
    // Verificar limite de perda diária
    if (g_dailyPnL <= -InpMaxDailyLoss * g_accountInfo.Balance())
    {
        Print("⚠️ LIMITE DE PERDA DIÁRIA ATINGIDO!");
        CloseAllPositions();
        g_isRunning = false;
    }
}

//+------------------------------------------------------------------+
//| Calcular P&L diário                                             |
//+------------------------------------------------------------------+
void CalculateDailyPnL()
{
    g_dailyPnL = 0.0;
    
    datetime today = TimeCurrent();
    MqlDateTime dt;
    TimeToStruct(today, dt);
    dt.hour = 0;
    dt.min = 0;
    dt.sec = 0;
    datetime todayStart = StructToTime(dt);
    
    // Calcular P&L das posições fechadas hoje
    for (int i = PositionsHistoryTotal() - 1; i >= 0; i--)
    {
        ulong ticket = PositionGetTicket(i);
        if (ticket > 0)
        {
            if (PositionGetInteger(POSITION_TIME) >= todayStart &&
                PositionGetInteger(POSITION_MAGIC) == InpMagicNumber)
            {
                g_dailyPnL += PositionGetDouble(POSITION_PROFIT);
            }
        }
    }
    
    // Somar P&L das posições abertas
    for (int i = 0; i < PositionsTotal(); i++)
    {
        ulong ticket = PositionGetTicket(i);
        if (ticket > 0)
        {
            if (PositionGetInteger(POSITION_MAGIC) == InpMagicNumber)
            {
                g_dailyPnL += PositionGetDouble(POSITION_PROFIT);
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Inicializar estatísticas                                         |
//+------------------------------------------------------------------+
void InitializeStats()
{
    ZeroMemory(g_stats);
    g_stats.lastUpdateTime = TimeCurrent();
}

//+------------------------------------------------------------------+
//| Salvar estatísticas                                              |
//+------------------------------------------------------------------+
void SaveStatistics()
{
    // Implementar salvamento das estatísticas
    Print("📊 Estatísticas da sessão:");
    Print("   Total de trades: ", g_stats.totalTrades);
    Print("   Profit total: ", g_stats.totalProfit);
    Print("   P&L hoje: ", g_stats.todayProfit);
}

//+------------------------------------------------------------------+
//| Obter razão da desinicialização                                  |
//+------------------------------------------------------------------+
string GetDeintReason(int reason)
{
    switch(reason)
    {
        case REASON_ACCOUNT: return "Mudança de conta";
        case REASON_CHARTCHANGE: return "Mudança de símbolo/timeframe";
        case REASON_CHARTCLOSE: return "Fechamento do gráfico";
        case REASON_PARAMETERS: return "Mudança de parâmetros";
        case REASON_RECOMPILE: return "Recompilação";
        case REASON_REMOVE: return "Remoção do EA";
        case REASON_TEMPLATE: return "Novo template";
        case REASON_INITFAILED: return "Falha na inicialização";
        case REASON_CLOSE: return "Fechamento do terminal";
        default: return "Razão desconhecida";
    }
}

//+------------------------------------------------------------------+
//| Processar eventos de trade                                       |
//+------------------------------------------------------------------+
void ProcessTradeEvent()
{
    // Implementar lógica de processamento de eventos de trade
}

//+------------------------------------------------------------------+
//| Atualizar estatísticas de trade                                  |
//+------------------------------------------------------------------+
void UpdateTradeStatistics()
{
    // Implementar atualização de estatísticas quando trades são executados
}

//+------------------------------------------------------------------+
//| Verificar conexão com IA                                         |
//+------------------------------------------------------------------+
void CheckAIConnection()
{
    if (g_comm != NULL && g_comm.IsConnected())
    {
        g_aiConnected = true;
    }
    else
    {
        g_aiConnected = false;
    }
}

//+------------------------------------------------------------------+
//| Atualizar estatísticas                                           |
//+------------------------------------------------------------------+
void UpdateStatistics()
{
    g_stats.lastUpdateTime = TimeCurrent();
    
    // Calcular estatísticas
    g_stats.todayProfit = g_dailyPnL;
    
    if (g_stats.totalTrades > 0)
    {
        // Calcular outras métricas
    }
}

//+------------------------------------------------------------------+
//| Verificar sessão diária                                          |
//+------------------------------------------------------------------+
void CheckDailySession()
{
    // Reset diário às 00:00
    datetime current = TimeCurrent();
    MqlDateTime dt;
    TimeToStruct(current, dt);
    
    if (dt.hour == 0 && dt.min == 0 && current - g_sessionStartTime >= 86400)
    {
        // Reset diário
        g_dailyPnL = 0.0;
        g_consecutiveLosses = 0;
        g_sessionStartTime = current;
        
        Print("🔄 Reset diário executado");
        g_comm.SendStatusUpdate("DAILY_RESET", "Reset diário executado - nova sessão iniciada");
    }
}

//+------------------------------------------------------------------+
//| Funções do Painel Gráfico                                       |
//+------------------------------------------------------------------+

// Definições do painel
#define PANEL_WIDTH 300
#define PANEL_HEIGHT 400
#define PANEL_BORDER 5
#define LINE_HEIGHT 20

// Cores do painel
#define COLOR_PANEL_BG      C'30,30,30'
#define COLOR_PANEL_BORDER  C'70,70,70'
#define COLOR_TEXT_WHITE    clrWhite
#define COLOR_TEXT_GREEN    clrLime
#define COLOR_TEXT_RED      clrRed
#define COLOR_TEXT_YELLOW   clrYellow
#define COLOR_TEXT_CYAN     clrCyan

// Objetos do painel
string g_panelObjects[];

//+------------------------------------------------------------------+
//| Criar painel gráfico                                            |
//+------------------------------------------------------------------+
void CreatePanel()
{
    // Limpar objetos anteriores
    DestroyPanel();
    
    long chartId = ChartID();
    int x = InpPanelPosX;
    int y = InpPanelPosY;
    
    // Fundo do painel
    string objName = "DuartePanel_Background";
    ObjectCreate(chartId, objName, OBJ_RECTANGLE_LABEL, 0, 0, 0);
    ObjectSetInteger(chartId, objName, OBJPROP_XDISTANCE, x);
    ObjectSetInteger(chartId, objName, OBJPROP_YDISTANCE, y);
    ObjectSetInteger(chartId, objName, OBJPROP_XSIZE, PANEL_WIDTH);
    ObjectSetInteger(chartId, objName, OBJPROP_YSIZE, PANEL_HEIGHT);
    ObjectSetInteger(chartId, objName, OBJPROP_BGCOLOR, COLOR_PANEL_BG);
    ObjectSetInteger(chartId, objName, OBJPROP_BORDER_TYPE, BORDER_FLAT);
    ObjectSetInteger(chartId, objName, OBJPROP_CORNER, CORNER_LEFT_UPPER);
    ObjectSetInteger(chartId, objName, OBJPROP_COLOR, COLOR_PANEL_BORDER);
    ObjectSetInteger(chartId, objName, OBJPROP_STYLE, STYLE_SOLID);
    ObjectSetInteger(chartId, objName, OBJPROP_WIDTH, 2);
    ObjectSetInteger(chartId, objName, OBJPROP_SELECTABLE, false);
    ObjectSetInteger(chartId, objName, OBJPROP_HIDDEN, true);
    
    ArrayResize(g_panelObjects, ArraySize(g_panelObjects) + 1);
    g_panelObjects[ArraySize(g_panelObjects) - 1] = objName;
    
    // Título do painel
    CreatePanelLabel("DuartePanel_Title", "DUARTE-SCALPER v1.0", 
                     x + 10, y + 10, COLOR_TEXT_CYAN, 12, true);
    
    // Status da conexão
    CreatePanelLabel("DuartePanel_Status", "Status: ", 
                     x + 10, y + 35, COLOR_TEXT_WHITE, 9);
    
    // Informações da conta
    CreatePanelLabel("DuartePanel_Account", "Conta: ", 
                     x + 10, y + 60, COLOR_TEXT_WHITE, 9);
                     
    CreatePanelLabel("DuartePanel_Balance", "Saldo: ", 
                     x + 10, y + 80, COLOR_TEXT_WHITE, 9);
    
    CreatePanelLabel("DuartePanel_Equity", "Patrimônio: ", 
                     x + 10, y + 100, COLOR_TEXT_WHITE, 9);
    
    // Linha divisória
    CreatePanelLine("DuartePanel_Line1", x + 10, y + 120, x + PANEL_WIDTH - 20, y + 120);
    
    // Estatísticas de trading
    CreatePanelLabel("DuartePanel_StatsTitle", "ESTATÍSTICAS", 
                     x + 10, y + 130, COLOR_TEXT_YELLOW, 10, true);
    
    CreatePanelLabel("DuartePanel_TotalTrades", "Total de Trades: ", 
                     x + 10, y + 155, COLOR_TEXT_WHITE, 9);
                     
    CreatePanelLabel("DuartePanel_WinRate", "Taxa de Acerto: ", 
                     x + 10, y + 175, COLOR_TEXT_WHITE, 9);
                     
    CreatePanelLabel("DuartePanel_ProfitToday", "Profit Hoje: ", 
                     x + 10, y + 195, COLOR_TEXT_WHITE, 9);
                     
    CreatePanelLabel("DuartePanel_DrawdownCurrent", "Drawdown: ", 
                     x + 10, y + 215, COLOR_TEXT_WHITE, 9);
    
    // Linha divisória
    CreatePanelLine("DuartePanel_Line2", x + 10, y + 235, x + PANEL_WIDTH - 20, y + 235);
    
    // Status da IA
    CreatePanelLabel("DuartePanel_AITitle", "INTELIGÊNCIA ARTIFICIAL", 
                     x + 10, y + 245, COLOR_TEXT_YELLOW, 10, true);
                     
    CreatePanelLabel("DuartePanel_AIStatus", "IA Status: ", 
                     x + 10, y + 270, COLOR_TEXT_WHITE, 9);
                     
    CreatePanelLabel("DuartePanel_LastSignal", "Último Sinal: ", 
                     x + 10, y + 290, COLOR_TEXT_WHITE, 9);
    
    // Posições abertas
    CreatePanelLabel("DuartePanel_PositionsTitle", "POSIÇÕES ABERTAS", 
                     x + 10, y + 315, COLOR_TEXT_YELLOW, 10, true);
                     
    CreatePanelLabel("DuartePanel_Positions", "Nenhuma posição", 
                     x + 10, y + 340, COLOR_TEXT_WHITE, 9);
    
    // Controles
    CreatePanelButton("DuartePanel_BtnStartStop", "PARAR", 
                      x + 10, y + 365, 80, 25, COLOR_TEXT_RED);
                      
    CreatePanelButton("DuartePanel_BtnCloseAll", "FECHAR TODAS", 
                      x + 100, y + 365, 100, 25, COLOR_TEXT_YELLOW);
    
    Print("✅ Painel gráfico criado");
}

//+------------------------------------------------------------------+
//| Criar label do painel                                           |
//+------------------------------------------------------------------+
void CreatePanelLabel(string name, string text, int x, int y, 
                     color textColor, int fontSize = 9, bool bold = false)
{
    long chartId = ChartID();
    
    ObjectCreate(chartId, name, OBJ_LABEL, 0, 0, 0);
    ObjectSetString(chartId, name, OBJPROP_TEXT, text);
    ObjectSetInteger(chartId, name, OBJPROP_XDISTANCE, x);
    ObjectSetInteger(chartId, name, OBJPROP_YDISTANCE, y);
    ObjectSetInteger(chartId, name, OBJPROP_COLOR, textColor);
    ObjectSetInteger(chartId, name, OBJPROP_FONTSIZE, fontSize);
    ObjectSetString(chartId, name, OBJPROP_FONT, bold ? "Arial Bold" : "Arial");
    ObjectSetInteger(chartId, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
    ObjectSetInteger(chartId, name, OBJPROP_SELECTABLE, false);
    ObjectSetInteger(chartId, name, OBJPROP_HIDDEN, true);
    
    ArrayResize(g_panelObjects, ArraySize(g_panelObjects) + 1);
    g_panelObjects[ArraySize(g_panelObjects) - 1] = name;
}

//+------------------------------------------------------------------+
//| Criar linha do painel                                           |
//+------------------------------------------------------------------+
void CreatePanelLine(string name, int x1, int y1, int x2, int y2)
{
    long chartId = ChartID();
    
    ObjectCreate(chartId, name, OBJ_HLINE, 0, 0, 0);
    ObjectSetInteger(chartId, name, OBJPROP_COLOR, COLOR_PANEL_BORDER);
    ObjectSetInteger(chartId, name, OBJPROP_STYLE, STYLE_SOLID);
    ObjectSetInteger(chartId, name, OBJPROP_WIDTH, 1);
    ObjectSetInteger(chartId, name, OBJPROP_SELECTABLE, false);
    ObjectSetInteger(chartId, name, OBJPROP_HIDDEN, true);
    
    ArrayResize(g_panelObjects, ArraySize(g_panelObjects) + 1);
    g_panelObjects[ArraySize(g_panelObjects) - 1] = name;
}

//+------------------------------------------------------------------+
//| Criar botão do painel                                           |
//+------------------------------------------------------------------+
void CreatePanelButton(string name, string text, int x, int y, 
                      int width, int height, color textColor)
{
    long chartId = ChartID();
    
    // Fundo do botão
    ObjectCreate(chartId, name + "_BG", OBJ_RECTANGLE_LABEL, 0, 0, 0);
    ObjectSetInteger(chartId, name + "_BG", OBJPROP_XDISTANCE, x);
    ObjectSetInteger(chartId, name + "_BG", OBJPROP_YDISTANCE, y);
    ObjectSetInteger(chartId, name + "_BG", OBJPROP_XSIZE, width);
    ObjectSetInteger(chartId, name + "_BG", OBJPROP_YSIZE, height);
    ObjectSetInteger(chartId, name + "_BG", OBJPROP_BGCOLOR, C'50,50,50');
    ObjectSetInteger(chartId, name + "_BG", OBJPROP_BORDER_TYPE, BORDER_FLAT);
    ObjectSetInteger(chartId, name + "_BG", OBJPROP_CORNER, CORNER_LEFT_UPPER);
    ObjectSetInteger(chartId, name + "_BG", OBJPROP_COLOR, COLOR_PANEL_BORDER);
    ObjectSetInteger(chartId, name + "_BG", OBJPROP_STYLE, STYLE_SOLID);
    ObjectSetInteger(chartId, name + "_BG", OBJPROP_WIDTH, 1);
    ObjectSetInteger(chartId, name + "_BG", OBJPROP_SELECTABLE, true);
    ObjectSetInteger(chartId, name + "_BG", OBJPROP_HIDDEN, true);
    
    // Texto do botão
    ObjectCreate(chartId, name, OBJ_LABEL, 0, 0, 0);
    ObjectSetString(chartId, name, OBJPROP_TEXT, text);
    ObjectSetInteger(chartId, name, OBJPROP_XDISTANCE, x + width/2 - StringLen(text)*3);
    ObjectSetInteger(chartId, name, OBJPROP_YDISTANCE, y + height/2 - 7);
    ObjectSetInteger(chartId, name, OBJPROP_COLOR, textColor);
    ObjectSetInteger(chartId, name, OBJPROP_FONTSIZE, 9);
    ObjectSetString(chartId, name, OBJPROP_FONT, "Arial Bold");
    ObjectSetInteger(chartId, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
    ObjectSetInteger(chartId, name, OBJPROP_SELECTABLE, false);
    ObjectSetInteger(chartId, name, OBJPROP_HIDDEN, true);
    
    ArrayResize(g_panelObjects, ArraySize(g_panelObjects) + 1);
    g_panelObjects[ArraySize(g_panelObjects) - 1] = name + "_BG";
    ArrayResize(g_panelObjects, ArraySize(g_panelObjects) + 1);
    g_panelObjects[ArraySize(g_panelObjects) - 1] = name;
}

//+------------------------------------------------------------------+
//| Atualizar painel                                                |
//+------------------------------------------------------------------+
void UpdatePanel()
{
    if (!InpShowPanel)
        return;
    
    long chartId = ChartID();
    
    // Atualizar status
    string status = g_isRunning ? "🟢 ATIVO" : "🔴 PARADO";
    if (g_aiConnected)
        status += " | IA: 🟢";
    else
        status += " | IA: 🔴";
    
    ObjectSetString(chartId, "DuartePanel_Status", OBJPROP_TEXT, "Status: " + status);
    
    // Atualizar informações da conta
    ObjectSetString(chartId, "DuartePanel_Account", OBJPROP_TEXT, 
                    "Conta: " + IntegerToString(g_accountInfo.Login()));
    
    ObjectSetString(chartId, "DuartePanel_Balance", OBJPROP_TEXT, 
                    StringFormat("Saldo: %.2f %s", g_accountInfo.Balance(), g_accountInfo.Currency()));
    
    ObjectSetString(chartId, "DuartePanel_Equity", OBJPROP_TEXT, 
                    StringFormat("Patrimônio: %.2f %s", g_accountInfo.Equity(), g_accountInfo.Currency()));
    
    // Atualizar estatísticas
    ObjectSetString(chartId, "DuartePanel_TotalTrades", OBJPROP_TEXT, 
                    "Total de Trades: " + IntegerToString(g_stats.totalTrades));
    
    double winRate = g_stats.totalTrades > 0 ? (double)g_stats.winTrades / g_stats.totalTrades * 100 : 0;
    ObjectSetString(chartId, "DuartePanel_WinRate", OBJPROP_TEXT, 
                    StringFormat("Taxa de Acerto: %.1f%%", winRate));
    
    // Colorir profit de acordo com valor
    color profitColor = g_dailyPnL >= 0 ? COLOR_TEXT_GREEN : COLOR_TEXT_RED;
    ObjectSetString(chartId, "DuartePanel_ProfitToday", OBJPROP_TEXT, 
                    StringFormat("Profit Hoje: %.2f", g_dailyPnL));
    ObjectSetInteger(chartId, "DuartePanel_ProfitToday", OBJPROP_COLOR, profitColor);
    
    // Atualizar drawdown
    double drawdownPercent = g_accountInfo.Balance() > 0 ? 
                            (g_stats.currentDrawdown / g_accountInfo.Balance()) * 100 : 0;
    ObjectSetString(chartId, "DuartePanel_DrawdownCurrent", OBJPROP_TEXT, 
                    StringFormat("Drawdown: %.2f%%", drawdownPercent));
    
    // Atualizar status da IA
    string aiStatus = g_aiConnected ? "🟢 CONECTADA" : "🔴 DESCONECTADA";
    ObjectSetString(chartId, "DuartePanel_AIStatus", OBJPROP_TEXT, "IA Status: " + aiStatus);
    
    // Atualizar posições
    UpdatePositionsDisplay();
    
    // Atualizar texto do botão Start/Stop
    string buttonText = g_isRunning ? "PARAR" : "INICIAR";
    color buttonColor = g_isRunning ? COLOR_TEXT_RED : COLOR_TEXT_GREEN;
    ObjectSetString(chartId, "DuartePanel_BtnStartStop", OBJPROP_TEXT, buttonText);
    ObjectSetInteger(chartId, "DuartePanel_BtnStartStop", OBJPROP_COLOR, buttonColor);
    
    ChartRedraw();
}

//+------------------------------------------------------------------+
//| Atualizar display de posições                                   |
//+------------------------------------------------------------------+
void UpdatePositionsDisplay()
{
    long chartId = ChartID();
    string positionsText = "";
    int positionsCount = 0;
    
    // Contar posições do robô
    for (int i = 0; i < PositionsTotal(); i++)
    {
        if (PositionGetTicket(i) > 0)
        {
            if (PositionGetInteger(POSITION_MAGIC) == InpMagicNumber)
            {
                positionsCount++;
                string symbol = PositionGetString(POSITION_SYMBOL);
                double profit = PositionGetDouble(POSITION_PROFIT);
                string type = PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY ? "BUY" : "SELL";
                
                if (positionsText != "")
                    positionsText += "\n";
                    
                color profitColor = profit >= 0 ? COLOR_TEXT_GREEN : COLOR_TEXT_RED;
                positionsText += StringFormat("%s %s: %.2f", symbol, type, profit);
            }
        }
    }
    
    if (positionsCount == 0)
    {
        positionsText = "Nenhuma posição";
    }
    
    ObjectSetString(chartId, "DuartePanel_Positions", OBJPROP_TEXT, positionsText);
}

//+------------------------------------------------------------------+
//| Destruir painel                                                 |
//+------------------------------------------------------------------+
void DestroyPanel()
{
    long chartId = ChartID();
    
    for (int i = 0; i < ArraySize(g_panelObjects); i++)
    {
        ObjectDelete(chartId, g_panelObjects[i]);
    }
    
    ArrayResize(g_panelObjects, 0);
    ChartRedraw();
}

//+------------------------------------------------------------------+
//| Processar eventos do painel                                     |
//+------------------------------------------------------------------+
void ProcessPanelEvents(const int id, const long& lparam, 
                       const double& dparam, const string& sparam)
{
    if (id == CHARTEVENT_OBJECT_CLICK)
    {
        // Botão Start/Stop
        if (sparam == "DuartePanel_BtnStartStop_BG")
        {
            g_isRunning = !g_isRunning;
            string status = g_isRunning ? "retomado" : "pausado";
            Print("🔄 Trading " + status + " pelo usuário");
            
            if (g_comm != NULL)
                g_comm.SendStatusUpdate("USER_" + (g_isRunning ? "START" : "STOP"), 
                                       "Trading " + status + " pelo usuário");
        }
        
        // Botão Fechar Todas
        if (sparam == "DuartePanel_BtnCloseAll_BG")
        {
            CloseAllPositions();
            Print("🔄 Todas as posições fechadas pelo usuário");
            
            if (g_comm != NULL)
                g_comm.SendStatusUpdate("USER_CLOSE_ALL", "Todas as posições fechadas pelo usuário");
        }
        
        // Remover seleção do objeto
        ObjectSetInteger(ChartID(), sparam, OBJPROP_STATE, false);
        ChartRedraw();
    }
}