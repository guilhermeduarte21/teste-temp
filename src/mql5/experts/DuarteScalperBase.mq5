//+------------------------------------------------------------------+
//|                                     DuarteScalperBase.mq5         |
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
#include <Trade\HistoryOrderInfo.mqh>
#include <Trade\DealInfo.mqh>

//+------------------------------------------------------------------+
//| Input parameters                                                 |
//+------------------------------------------------------------------+
input group "=== CONFIGURAÇÕES PRINCIPAIS ==="
input string InpSymbolsPrefix = "WIN*,WDO*";             // Prefixos dos símbolos (suporta wildcards)
input double InpLotSize = 1.0;                           // Tamanho do lote
input int    InpMagicNumber = 778899;                    // Magic Number

input group "=== RISK MANAGEMENT ==="
input double InpMaxRiskPerTrade = 0.01;                  // Risco máximo por trade (%)
input double InpMaxDailyLoss = 0.03;                     // Perda máxima diária (%)
input int    InpMaxConsecutiveLosses = 5;                // Máximo de perdas consecutivas
input int    InpMaxPositionTimeMin = 10;                 // Tempo máximo de posição (minutos)

input group "=== CONFIGURAÇÕES DE IA ==="
input double InpMinConfidence = 0.7;                     // Confiança mínima da IA
input int    InpSignalTimeoutSec = 5;                    // Timeout do sinal da IA (segundos)
input bool   InpEnableAI = true;                         // Habilitar processamento de IA

input group "=== CONFIGURAÇÕES DE COMUNICAÇÃO ==="
input string InpCommName = "DuarteScalper_Comm";         // Nome da comunicação
input bool   InpDebugMode = false;                       // Modo debug

input group "=== CONFIGURAÇÕES DO PAINEL ==="
input bool   InpShowPanel = true;                        // Mostrar painel gráfico
input int    InpPanelPosX = 10;                         // Posição X do painel
input int    InpPanelPosY = 30;                         // Posição Y do painel

//+------------------------------------------------------------------+
//| Global variables                                                 |
//+------------------------------------------------------------------+
CDuarteCommunication* g_comm = NULL;                     // Comunicação com Python
CTrade g_trade;                                          // Objeto de negociação
CSymbolInfo g_symbolInfo;                                // Informações do símbolo
CPositionInfo g_positionInfo;                            // Informações de posição
CAccountInfo g_accountInfo;                              // Informações da conta

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
    Print("Prefixos de símbolos: ", InpSymbolsPrefix);
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
    
    // Buscar símbolos automaticamente
    if (!FindSymbolsByPattern())
    {
        Print("ERRO: Falha ao encontrar símbolos");
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
        Print("✅ Símbolo encontrado: ", g_symbols[i]);
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
//| Buscar símbolos por padrão (suporta wildcards)                  |
//+------------------------------------------------------------------+
bool FindSymbolsByPattern()
{
    string patterns[];
    
    // Parse padrões de entrada
    string patterns_str = InpSymbolsPrefix;
    int patterns_count = 1;
    
    // Contar padrões
    for (int i = 0; i < StringLen(patterns_str); i++)
    {
        if (StringGetCharacter(patterns_str, i) == ',')
            patterns_count++;
    }
    
    ArrayResize(patterns, patterns_count);
    
    // Extrair padrões
    string current_pattern = "";
    int pattern_index = 0;
    
    for (int i = 0; i <= StringLen(patterns_str); i++)
    {
        ushort char_code = StringGetCharacter(patterns_str, i);
        
        if (char_code == ',' || i == StringLen(patterns_str))
        {
            StringTrimLeft(current_pattern);
            StringTrimRight(current_pattern);
            
            if (StringLen(current_pattern) > 0)
            {
                patterns[pattern_index] = current_pattern;
                pattern_index++;
            }
            
            current_pattern = "";
        }
        else
        {
            current_pattern += CharToString((char)char_code);
        }
    }
    
    // Buscar símbolos que matching os padrões
    string found_symbols[];
    int found_count = 0;
    
    Print("Buscando símbolos que correspondem aos padrões...");
    
    for (int i = 0; i < SymbolsTotal(true); i++)
    {
        string symbol = SymbolName(i, true);
        
        // Verificar contra cada padrão
        for (int j = 0; j < ArraySize(patterns); j++)
        {
            if (MatchesPattern(symbol, patterns[j]))
            {
                ArrayResize(found_symbols, found_count + 1);
                found_symbols[found_count] = symbol;
                found_count++;
                Print("   ✅ Encontrado: ", symbol, " (padrão: ", patterns[j], ")");
                break;
            }
        }
    }
    
    // Atualizar array global
    g_symbolsCount = found_count;
    ArrayResize(g_symbols, g_symbolsCount);
    
    for (int i = 0; i < g_symbolsCount; i++)
    {
        g_symbols[i] = found_symbols[i];
    }
    
    if (g_symbolsCount == 0)
    {
        Print("❌ Nenhum símbolo encontrado para os padrões: ", InpSymbolsPrefix);
        return false;
    }
    
    Print("Total de símbolos encontrados: ", g_symbolsCount);
    return true;
}

//+------------------------------------------------------------------+
//| Verificar se símbolo corresponde ao padrão                       |
//+------------------------------------------------------------------+
bool MatchesPattern(const string symbol, const string pattern)
{
    // Suporte simples a wildcards
    if (StringFind(pattern, "*") >= 0)
    {
        // Remover * do final/início para matching
        string clean_pattern = pattern;
        StringReplace(clean_pattern, "*", "");
        
        // Se padrão termina com *, verificar se símbolo começa com padrão
        if (StringFind(pattern, "*") == StringLen(pattern) - 1)
        {
            string prefix = StringSubstr(pattern, 0, StringLen(pattern) - 1);
            return StringFind(symbol, prefix) == 0;
        }
        
        // Se padrão começa com *, verificar se símbolo termina com padrão
        if (StringFind(pattern, "*") == 0)
        {
            string suffix = StringSubstr(pattern, 1);
            return StringFind(symbol, suffix) == StringLen(symbol) - StringLen(suffix);
        }
        
        // Wildcard no meio
        return StringFind(symbol, clean_pattern) >= 0;
    }
    else
    {
        // Matching exato
        return symbol == pattern;
    }
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
//| Calcular P&L diário - CORRIGIDO                                 |
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
    
    // Selecionar histórico de hoje
    if (HistorySelect(todayStart, TimeCurrent()))
    {
        // Verificar deals fechados hoje
        CDealInfo deal;
        for (int i = 0; i < HistoryDealsTotal(); i++)
        {
            if (deal.SelectByIndex(i))
            {
                if (deal.Magic() == InpMagicNumber && 
                    deal.DealType() != DEAL_TYPE_BALANCE)
                {
                    g_dailyPnL += deal.Profit();
                }
            }
        }
    }
    
    // Somar P&L das posições abertas
    for (int i = 0; i < PositionsTotal(); i++)
    {
        if (g_positionInfo.SelectByIndex(i))
        {
            if (g_positionInfo.Magic() == InpMagicNumber)
            {
                g_dailyPnL += g_positionInfo.Profit();
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
#define PANEL_WIDTH 350
#define PANEL_HEIGHT 450
#define PANEL_BORDER 5
#define LINE_HEIGHT 22

// Cores do painel - Tema moderno
#define COLOR_PANEL_BG      C'25,25,30'        // Cinza escuro moderno
#define COLOR_PANEL_BORDER  C'75,75,85'        // Borda sutil
#define COLOR_HEADER_BG     C'45,45,55'        // Header background
#define COLOR_TEXT_WHITE    C'240,240,245'     // Branco suave
#define COLOR_TEXT_GREEN    C'76,175,80'       // Verde moderno
#define COLOR_TEXT_RED      C'244,67,54'       // Vermelho moderno
#define COLOR_TEXT_YELLOW   C'255,193,7'       // Amarelo/dourado
#define COLOR_TEXT_CYAN     C'0,188,212'       // Azul ciano
#define COLOR_TEXT_GRAY     C'158,158,158'     // Cinza médio
#define COLOR_BUTTON_BG     C'55,55,65'        // Background botão
#define COLOR_BUTTON_HOVER  C'65,65,75'        // Hover botão

// Objetos do painel
string g_panelObjects[];

//+------------------------------------------------------------------+
//| Criar painel gráfico moderno                                    |
//+------------------------------------------------------------------+
void CreatePanel()
{
    // Limpar objetos anteriores
    DestroyPanel();
    
    long chartId = ChartID();
    int x = InpPanelPosX;
    int y = InpPanelPosY;
    
    // Fundo principal do painel com bordas arredondadas (simuladas)
    CreatePanelRect("DuartePanel_Background", x, y, PANEL_WIDTH, PANEL_HEIGHT, 
                    COLOR_PANEL_BG, COLOR_PANEL_BORDER, 2);
    
    // Header do painel
    CreatePanelRect("DuartePanel_Header", x, y, PANEL_WIDTH, 45, 
                    COLOR_HEADER_BG, COLOR_PANEL_BORDER, 1);
    
    // Logo/Título principal
    CreatePanelLabel("DuartePanel_Title", "🚀 DUARTE-SCALPER", 
                     x + 15, y + 12, COLOR_TEXT_CYAN, 14, true);
    
    CreatePanelLabel("DuartePanel_Version", "v1.0 Pro", 
                     x + 220, y + 15, COLOR_TEXT_GRAY, 9);
    
    // Status geral
    CreatePanelLabel("DuartePanel_StatusTitle", "STATUS DO SISTEMA", 
                     x + 15, y + 60, COLOR_TEXT_YELLOW, 11, true);
    
    CreatePanelLabel("DuartePanel_Status", "Sistema: ", 
                     x + 20, y + 85, COLOR_TEXT_WHITE, 10);
    
    CreatePanelLabel("DuartePanel_AIStatus", "IA: ", 
                     x + 20, y + 105, COLOR_TEXT_WHITE, 10);
    
    // Linha divisória
    CreatePanelLine("DuartePanel_Line1", x + 15, y + 130, x + PANEL_WIDTH - 15, y + 130);
    
    // Seção da conta
    CreatePanelLabel("DuartePanel_AccountTitle", "INFORMAÇÕES DA CONTA", 
                     x + 15, y + 145, COLOR_TEXT_YELLOW, 11, true);
                     
    CreatePanelLabel("DuartePanel_Account", "Conta: ", 
                     x + 20, y + 170, COLOR_TEXT_WHITE, 10);
                     
    CreatePanelLabel("DuartePanel_Balance", "Saldo: ", 
                     x + 20, y + 190, COLOR_TEXT_WHITE, 10);
    
    CreatePanelLabel("DuartePanel_Equity", "Patrimônio: ", 
                     x + 20, y + 210, COLOR_TEXT_WHITE, 10);
    
    // Linha divisória
    CreatePanelLine("DuartePanel_Line2", x + 15, y + 235, x + PANEL_WIDTH - 15, y + 235);
    
    // Seção de performance
    CreatePanelLabel("DuartePanel_PerformanceTitle", "PERFORMANCE", 
                     x + 15, y + 250, COLOR_TEXT_YELLOW, 11, true);
    
    CreatePanelLabel("DuartePanel_TotalTrades", "Total de Trades: ", 
                     x + 20, y + 275, COLOR_TEXT_WHITE, 10);
                     
    CreatePanelLabel("DuartePanel_WinRate", "Taxa de Acerto: ", 
                     x + 180, y + 275, COLOR_TEXT_WHITE, 10);
                     
    CreatePanelLabel("DuartePanel_ProfitToday", "Profit Hoje: ", 
                     x + 20, y + 295, COLOR_TEXT_WHITE, 10);
                     
    CreatePanelLabel("DuartePanel_DrawdownCurrent", "Drawdown: ", 
                     x + 180, y + 295, COLOR_TEXT_WHITE, 10);
    
    // Linha divisória
    CreatePanelLine("DuartePanel_Line3", x + 15, y + 320, x + PANEL_WIDTH - 15, y + 320);
    
    // Seção de posições
    CreatePanelLabel("DuartePanel_PositionsTitle", "POSIÇÕES ATIVAS", 
                     x + 15, y + 335, COLOR_TEXT_YELLOW, 11, true);
                     
    CreatePanelLabel("DuartePanel_Positions", "Nenhuma posição aberta", 
                     x + 20, y + 360, COLOR_TEXT_GRAY, 10);
    
    CreatePanelLabel("DuartePanel_PositionsProfit", "P&L Total: --", 
                     x + 20, y + 380, COLOR_TEXT_WHITE, 10);
    
    // Controles modernos
    CreateModernButton("DuartePanel_BtnStartStop", "⏸️ PAUSAR", 
                       x + 15, y + 410, 100, 30, COLOR_TEXT_RED);
                      
    CreateModernButton("DuartePanel_BtnCloseAll", "❌ FECHAR", 
                       x + 125, y + 410, 100, 30, COLOR_TEXT_YELLOW);
                       
    CreateModernButton("DuartePanel_BtnRefresh", "🔄 ATUALIZAR", 
                       x + 235, y + 410, 100, 30, COLOR_TEXT_CYAN);
    
    Print("✅ Painel gráfico moderno criado");
}

//+------------------------------------------------------------------+
//| Criar retângulo do painel                                       |
//+------------------------------------------------------------------+
void CreatePanelRect(string name, int x, int y, int width, int height, 
                     color bgColor, color borderColor, int borderWidth)
{
    long chartId = ChartID();
    
    ObjectCreate(chartId, name, OBJ_RECTANGLE_LABEL, 0, 0, 0);
    ObjectSetInteger(chartId, name, OBJPROP_XDISTANCE, x);
    ObjectSetInteger(chartId, name, OBJPROP_YDISTANCE, y);
    ObjectSetInteger(chartId, name, OBJPROP_XSIZE, width);
    ObjectSetInteger(chartId, name, OBJPROP_YSIZE, height);
    ObjectSetInteger(chartId, name, OBJPROP_BGCOLOR, bgColor);
    ObjectSetInteger(chartId, name, OBJPROP_BORDER_TYPE, BORDER_FLAT);
    ObjectSetInteger(chartId, name, OBJPROP_COLOR, borderColor);
    ObjectSetInteger(chartId, name, OBJPROP_WIDTH, borderWidth);
    ObjectSetInteger(chartId, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
    ObjectSetInteger(chartId, name, OBJPROP_SELECTABLE, false);
    ObjectSetInteger(chartId, name, OBJPROP_HIDDEN, true);
    
    AddObjectToPanel(name);
}

//+------------------------------------------------------------------+
//| Criar label moderno do painel                                   |
//+------------------------------------------------------------------+
void CreatePanelLabel(string name, string text, int x, int y, 
                     color textColor, int fontSize = 10, bool bold = false)
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
    
    AddObjectToPanel(name);
}

//+------------------------------------------------------------------+
//| Criar linha moderna do painel                                   |
//+------------------------------------------------------------------+
void CreatePanelLine(string name, int x1, int y1, int x2, int y2)
{
    long chartId = ChartID();
    
    // Criar como rectângulo para ter melhor controle
    ObjectCreate(chartId, name, OBJ_RECTANGLE_LABEL, 0, 0, 0);
    ObjectSetInteger(chartId, name, OBJPROP_XDISTANCE, x1);
    ObjectSetInteger(chartId, name, OBJPROP_YDISTANCE, y1);
    ObjectSetInteger(chartId, name, OBJPROP_XSIZE, x2 - x1);
    ObjectSetInteger(chartId, name, OBJPROP_YSIZE, 1);
    ObjectSetInteger(chartId, name, OBJPROP_BGCOLOR, COLOR_PANEL_BORDER);
    ObjectSetInteger(chartId, name, OBJPROP_BORDER_TYPE, BORDER_FLAT);
    ObjectSetInteger(chartId, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
    ObjectSetInteger(chartId, name, OBJPROP_SELECTABLE, false);
    ObjectSetInteger(chartId, name, OBJPROP_HIDDEN, true);
    
    AddObjectToPanel(name);
}

//+------------------------------------------------------------------+
//| Criar botão moderno                                             |
//+------------------------------------------------------------------+
void CreateModernButton(string name, string text, int x, int y, 
                        int width, int height, color textColor)
{
    long chartId = ChartID();
    
    // Background do botão com gradiente simulado
    ObjectCreate(chartId, name + "_BG", OBJ_RECTANGLE_LABEL, 0, 0, 0);
    ObjectSetInteger(chartId, name + "_BG", OBJPROP_XDISTANCE, x);
    ObjectSetInteger(chartId, name + "_BG", OBJPROP_YDISTANCE, y);
    ObjectSetInteger(chartId, name + "_BG", OBJPROP_XSIZE, width);
    ObjectSetInteger(chartId, name + "_BG", OBJPROP_YSIZE, height);
    ObjectSetInteger(chartId, name + "_BG", OBJPROP_BGCOLOR, COLOR_BUTTON_BG);
    ObjectSetInteger(chartId, name + "_BG", OBJPROP_BORDER_TYPE, BORDER_FLAT);
    ObjectSetInteger(chartId, name + "_BG", OBJPROP_COLOR, COLOR_PANEL_BORDER);
    ObjectSetInteger(chartId, name + "_BG", OBJPROP_WIDTH, 1);
    ObjectSetInteger(chartId, name + "_BG", OBJPROP_CORNER, CORNER_LEFT_UPPER);
    ObjectSetInteger(chartId, name + "_BG", OBJPROP_SELECTABLE, true);
    ObjectSetInteger(chartId, name + "_BG", OBJPROP_HIDDEN, true);
    
    // Texto do botão centralizado
    ObjectCreate(chartId, name, OBJ_LABEL, 0, 0, 0);
    ObjectSetString(chartId, name, OBJPROP_TEXT, text);
    // Centralizar text
    int textLen = StringLen(text);
    int textX = x + (width - textLen * 6) / 2;
    int textY = y + (height - 12) / 2;
    ObjectSetInteger(chartId, name, OBJPROP_XDISTANCE, textX);
    ObjectSetInteger(chartId, name, OBJPROP_YDISTANCE, textY);
    ObjectSetInteger(chartId, name, OBJPROP_COLOR, textColor);
    ObjectSetInteger(chartId, name, OBJPROP_FONTSIZE, 10);
    ObjectSetString(chartId, name, OBJPROP_FONT, "Arial Bold");
    ObjectSetInteger(chartId, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
    ObjectSetInteger(chartId, name, OBJPROP_SELECTABLE, false);
    ObjectSetInteger(chartId, name, OBJPROP_HIDDEN, true);
    
    AddObjectToPanel(name + "_BG");
    AddObjectToPanel(name);
}

//+------------------------------------------------------------------+
//| Adicionar objeto ao panel                                       |
//+------------------------------------------------------------------+
void AddObjectToPanel(string objectName)
{
    ArrayResize(g_panelObjects, ArraySize(g_panelObjects) + 1);
    g_panelObjects[ArraySize(g_panelObjects) - 1] = objectName;
}

//+------------------------------------------------------------------+
//| Atualizar painel com dados dinâmicos                           |
//+------------------------------------------------------------------+
void UpdatePanel()
{
    if (!InpShowPanel)
        return;
    
    long chartId = ChartID();
    
    // Atualizar status do sistema
    string systemStatus = g_isRunning ? "🟢 ATIVO" : "🔴 PARADO";
    string aiStatus = g_aiConnected ? "🟢 CONECTADA" : "🔴 OFFLINE";
    
    ObjectSetString(chartId, "DuartePanel_Status", OBJPROP_TEXT, 
                    "Sistema: " + systemStatus);
    
    ObjectSetString(chartId, "DuartePanel_AIStatus", OBJPROP_TEXT, 
                    "IA: " + aiStatus);
    
    // Atualizar informações da conta
    ObjectSetString(chartId, "DuartePanel_Account", OBJPROP_TEXT, 
                    "Conta: " + IntegerToString(g_accountInfo.Login()));
    
    ObjectSetString(chartId, "DuartePanel_Balance", OBJPROP_TEXT, 
                    StringFormat("Saldo: %.2f", g_accountInfo.Balance()));
    
    ObjectSetString(chartId, "DuartePanel_Equity", OBJPROP_TEXT, 
                    StringFormat("Patrimônio: %.2f", g_accountInfo.Equity()));
    
    // Atualizar performance
    ObjectSetString(chartId, "DuartePanel_TotalTrades", OBJPROP_TEXT, 
                    "Trades: " + IntegerToString(g_stats.totalTrades));
    
    double winRate = g_stats.totalTrades > 0 ? 
                    (double)g_stats.winTrades / g_stats.totalTrades * 100 : 0;
    ObjectSetString(chartId, "DuartePanel_WinRate", OBJPROP_TEXT, 
                    StringFormat("Win: %.1f%%", winRate));
    
    // Profit de hoje com cores
    color profitColor = g_dailyPnL >= 0 ? COLOR_TEXT_GREEN : COLOR_TEXT_RED;
    string profitSymbol = g_dailyPnL >= 0 ? "💰" : "📉";
    ObjectSetString(chartId, "DuartePanel_ProfitToday", OBJPROP_TEXT, 
                    StringFormat("%s %.2f", profitSymbol, g_dailyPnL));
    ObjectSetInteger(chartId, "DuartePanel_ProfitToday", OBJPROP_COLOR, profitColor);
    
    // Drawdown
    double drawdownPercent = g_accountInfo.Balance() > 0 ? 
                            (g_stats.currentDrawdown / g_accountInfo.Balance()) * 100 : 0;
    color drawdownColor = drawdownPercent > 2.0 ? COLOR_TEXT_RED : COLOR_TEXT_WHITE;
    ObjectSetString(chartId, "DuartePanel_DrawdownCurrent", OBJPROP_TEXT, 
                    StringFormat("DD: %.2f%%", drawdownPercent));
    ObjectSetInteger(chartId, "DuartePanel_DrawdownCurrent", OBJPROP_COLOR, drawdownColor);
    
    // Atualizar posições
    UpdatePositionsDisplay();
    
    // Atualizar botões
    string buttonText = g_isRunning ? "⏸️ PAUSAR" : "▶️ INICIAR";
    color buttonColor = g_isRunning ? COLOR_TEXT_RED : COLOR_TEXT_GREEN;
    ObjectSetString(chartId, "DuartePanel_BtnStartStop", OBJPROP_TEXT, buttonText);
    ObjectSetInteger(chartId, "DuartePanel_BtnStartStop", OBJPROP_COLOR, buttonColor);
    
    ChartRedraw();
}

//+------------------------------------------------------------------+
//| Atualizar display de posições melhorado                         |
//+------------------------------------------------------------------+
void UpdatePositionsDisplay()
{
    long chartId = ChartID();
    string positionsText = "";
    double totalProfit = 0.0;
    int positionsCount = 0;
    
    // Contar e sumarizar posições
    for (int i = 0; i < PositionsTotal(); i++)
    {
        if (g_positionInfo.SelectByIndex(i))
        {
            if (g_positionInfo.Magic() == InpMagicNumber)
            {
                positionsCount++;
                string symbol = g_positionInfo.Symbol();
                double profit = g_positionInfo.Profit();
                totalProfit += profit;
                string type = g_positionInfo.PositionType() == POSITION_TYPE_BUY ? "📈" : "📉";
                
                if (positionsText != "")
                    positionsText += " | ";
                    
                positionsText += StringFormat("%s %s", symbol, type);
            }
        }
    }
    
    if (positionsCount == 0)
    {
        positionsText = "Nenhuma posição aberta";
        ObjectSetInteger(chartId, "DuartePanel_Positions", OBJPROP_COLOR, COLOR_TEXT_GRAY);
    }
    else
    {
        positionsText = StringFormat("%d posições: %s", positionsCount, positionsText);
        ObjectSetInteger(chartId, "DuartePanel_Positions", OBJPROP_COLOR, COLOR_TEXT_WHITE);
    }
    
    ObjectSetString(chartId, "DuartePanel_Positions", OBJPROP_TEXT, positionsText);
    
    // Atualizar profit total das posições
    color profitColor = totalProfit >= 0 ? COLOR_TEXT_GREEN : COLOR_TEXT_RED;
    string profitSymbol = totalProfit >= 0 ? "💰" : "📉";
    ObjectSetString(chartId, "DuartePanel_PositionsProfit", OBJPROP_TEXT, 
                    StringFormat("P&L Total: %s %.2f", profitSymbol, totalProfit));
    ObjectSetInteger(chartId, "DuartePanel_PositionsProfit", OBJPROP_COLOR, profitColor);
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
//| Processar eventos do painel com efeitos visuais                 |
//+------------------------------------------------------------------+
void ProcessPanelEvents(const int id, const long& lparam, 
                       const double& dparam, const string& sparam)
{
    if (id == CHARTEVENT_OBJECT_CLICK)
    {
        long chartId = ChartID();
        
        // Botão Start/Stop
        if (sparam == "DuartePanel_BtnStartStop_BG")
        {
            g_isRunning = !g_isRunning;
            string status = g_isRunning ? "retomado" : "pausado";
            
            // Efeito visual - mudar cor temporariamente
            ObjectSetInteger(chartId, sparam, OBJPROP_BGCOLOR, COLOR_BUTTON_HOVER);
            ChartRedraw();
            Sleep(150);
            ObjectSetInteger(chartId, sparam, OBJPROP_BGCOLOR, COLOR_BUTTON_BG);
            
            Print("🔄 Trading " + status + " pelo usuário");
            
            if (g_comm != NULL)
                g_comm.SendStatusUpdate("USER_" + (g_isRunning ? "START" : "STOP"), 
                                       "Trading " + status + " pelo usuário");
        }
        
        // Botão Fechar Todas
        if (sparam == "DuartePanel_BtnCloseAll_BG")
        {
            // Efeito visual
            ObjectSetInteger(chartId, sparam, OBJPROP_BGCOLOR, COLOR_BUTTON_HOVER);
            ChartRedraw();
            Sleep(150);
            ObjectSetInteger(chartId, sparam, OBJPROP_BGCOLOR, COLOR_BUTTON_BG);
            
            CloseAllPositions();
            Print("🔄 Todas as posições fechadas pelo usuário");
            
            if (g_comm != NULL)
                g_comm.SendStatusUpdate("USER_CLOSE_ALL", 
                                       "Todas as posições fechadas pelo usuário");
        }
        
        // Botão Refresh
        if (sparam == "DuartePanel_BtnRefresh_BG")
        {
            // Efeito visual
            ObjectSetInteger(chartId, sparam, OBJPROP_BGCOLOR, COLOR_BUTTON_HOVER);
            ChartRedraw();
            Sleep(150);
            ObjectSetInteger(chartId, sparam, OBJPROP_BGCOLOR, COLOR_BUTTON_BG);
            
            // Forçar atualização do painel
            UpdatePanel();
            Print("🔄 Painel atualizado manualmente");
        }
        
        // Remover seleção do objeto
        ObjectSetInteger(chartId, sparam, OBJPROP_STATE, false);
        ChartRedraw();
    }
}