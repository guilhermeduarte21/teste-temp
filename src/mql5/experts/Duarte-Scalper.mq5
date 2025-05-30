//+------------------------------------------------------------------+
//|                                               Duarte-Scalper.mq5 |
//|                                                   Copyright 2025 |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Duarte-Scalper"
#property version   "2.21"
#property description "Robô de Scalping com Painel Gráfico Avançado"

#include <Trade\Trade.mqh>
#include <DuarteScalper\Communication.mqh>

// Instância de trading
CTrade trade;

//+------------------------------------------------------------------+
//| Parâmetros de entrada                                           |
//+------------------------------------------------------------------+
input group "=== Configurações Básicas ==="
input string   InpRobotName = "DUARTE-SCALPER";     // Nome do Robô
input int      InpMagicNumber = 778899;             // Número Mágico
input double   InpLotSize = 1.0;                    // Tamanho do Lote

input group "=== Configurações do Painel ==="
input bool     InpShowPanel = true;                 // Mostrar Painel

//+------------------------------------------------------------------+
//| Enumerações                                                     |
//+------------------------------------------------------------------+
enum ENUM_TIME_PERIOD
{
   TIME_DAILY = 0,    // Diário
   TIME_WEEKLY = 1,   // Semanal
   TIME_MONTHLY = 2,  // Mensal
   TIME_TOTAL = 3     // Total
};

//+------------------------------------------------------------------+
//| Estruturas                                                      |
//+------------------------------------------------------------------+
struct STradingStats
{
   double profit_loss;
   int total_trades;
   double win_rate;
   double profit_factor;
   double max_drawdown;
   double best_trade;
   double worst_trade;
   int winning_trades;
   int losing_trades;
   
   // Por período
   double daily_profit;
   double weekly_profit;
   double monthly_profit;
   double total_profit;
};

struct SPanelLayout
{
   int x, y;
   int width, height;
   bool minimized;
   ENUM_TIME_PERIOD selected_period;
};

//+------------------------------------------------------------------+
//| Variáveis globais                                               |
//+------------------------------------------------------------------+
string g_symbol;
bool g_robot_enabled = false;
bool g_panel_initialized = false;
bool g_updating_panel = false;

// Cores fixas do painel
color InpPanelBgColor = C'47,54,64';       // Cor do fundo do painel
color InpHeaderColor = C'34,40,49';        // Cor do cabeçalho
color InpTextColor = clrWhite;             // Cor do texto
color InpPositiveColor = C'46,213,115';    // Cor positiva (verde)
color InpNegativeColor = C'231,76,60';     // Cor negativa (vermelho)
color InpAccentColor = C'52,152,219';      // Cor de destaque (azul)
color InpWarningColor = C'241,196,15';     // Cor de aviso (amarelo)
color InpMarketClosedColor = C'156,136,255'; // Cor mercado fechado (roxo)

// Estatísticas
STradingStats g_stats = {0};
datetime g_last_update = 0;

// Layout do painel
SPanelLayout g_panel = {20, 50, 300, 500, false, TIME_DAILY};

// Cache de objetos
datetime g_last_panel_update = 0;
int g_current_positions = 0;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   g_symbol = Symbol();
   trade.SetExpertMagicNumber(InpMagicNumber);
   
   if(InpShowPanel)
   {
      InitializePanel();
   }
   
   UpdateStats();
   
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   CleanupPanel();
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{    
   static datetime last_update = 0;
   datetime current_time = TimeCurrent();
   
   // Atualizar painel a cada segundo
   if(InpShowPanel && current_time - last_update >= 1)
   {
      last_update = current_time;
      UpdatePanel();
   }
   
   // Verificar mudanças nas posições
   int current_pos = PositionsTotal();
   if(current_pos != g_current_positions)
   {
      g_current_positions = current_pos;
      UpdateStats();
   }
   
   // Lógica de trading (se habilitado)
   if(g_robot_enabled)
   {
      // TODO: Implementar lógica de trading
   }
}

//+------------------------------------------------------------------+
//| Chart events                                                     |
//+------------------------------------------------------------------+
void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
{
   if(id == CHARTEVENT_OBJECT_CLICK)
   {
      HandleButtonClick(sparam);
   }
   else if(id == CHARTEVENT_CHART_CHANGE)
   {
      if(InpShowPanel && g_panel_initialized)
      {
         Sleep(100);
         RepositionPanel();
      }
   }
}

//+------------------------------------------------------------------+
//| Verificar se o mercado está aberto                              |
//+------------------------------------------------------------------+
bool IsMarketOpen()
{
   // Verificar se é fins de semana
   MqlDateTime dt;
   TimeCurrent(dt);
   
   // Sábado = 6, Domingo = 0
   if(dt.day_of_week == 6 || dt.day_of_week == 0)
      return false;
   
   // Verificar horário de funcionamento (24/5 para Forex)
   // Para outros mercados, implementar lógica específica
   
   // Verificar se há cotações recentes (último tick)
   long last_tick = 0;
   if(!SeriesInfoInteger(g_symbol, PERIOD_CURRENT, SERIES_LASTBAR_DATE, last_tick))
      return true; // Se não conseguir obter info, assumir mercado aberto
   
   datetime current_time = TimeCurrent();
   
   // Se a última cotação é muito antiga (mais de 5 minutos), mercado pode estar fechado
   if(current_time - (datetime)last_tick > 300) // 5 minutos
      return false;
   
   return true;
}

//+------------------------------------------------------------------+
//| Inicializar painel                                              |
//+------------------------------------------------------------------+
void InitializePanel()
{
   CleanupPanel();
   CalculatePanelPosition();
   CreatePanelObjects();
   g_panel_initialized = true;
   UpdatePanel();
}

//+------------------------------------------------------------------+
//| Calcular posição do painel                                      |
//+------------------------------------------------------------------+
void CalculatePanelPosition()
{
   // Posicionar no canto superior ESQUERDO
   g_panel.x = 3;
   g_panel.y = 20;
}

//+------------------------------------------------------------------+
//| Reposicionar painel                                             |
//+------------------------------------------------------------------+
void RepositionPanel()
{
   CalculatePanelPosition();
   
   // Reposicionar todos os objetos
   string objects[] = {
      "DS_Background", "DS_Header", "DS_Title", "DS_Toggle", "DS_Minimize",
      "DS_Magic", "DS_Status", "DS_Symbol", "DS_ResAberto", "DS_ResDia",
      "DS_DateTime", "DS_MaiorLucro", "DS_BtnZero",
      "DS_EstHeader", "DS_BtnDaily", "DS_BtnWeekly", "DS_BtnMonthly", "DS_BtnTotal",
      "DS_Rentabilidade", "DS_QtdOp", "DS_PctAcerto", "DS_FatorLucro", "DS_Drawdown"
   };
   
   for(int i = 0; i < ArraySize(objects); i++)
   {
      if(ObjectFind(0, objects[i]) >= 0)
      {
         UpdateObjectPosition(objects[i]);
      }
   }
   
   ChartRedraw();
}

//+------------------------------------------------------------------+
//| Atualizar posição de objeto específico                          |
//+------------------------------------------------------------------+
void UpdateObjectPosition(string name)
{
   if(name == "DS_Background")
   {
      ObjectSetInteger(0, name, OBJPROP_XDISTANCE, g_panel.x);
      ObjectSetInteger(0, name, OBJPROP_YDISTANCE, g_panel.y);
   }
   else if(name == "DS_Header")
   {
      ObjectSetInteger(0, name, OBJPROP_XDISTANCE, g_panel.x);
      ObjectSetInteger(0, name, OBJPROP_YDISTANCE, g_panel.y);
   }
   else if(name == "DS_Title")
   {
      ObjectSetInteger(0, name, OBJPROP_XDISTANCE, g_panel.x + 10);
      ObjectSetInteger(0, name, OBJPROP_YDISTANCE, g_panel.y + 8);
   }
   else if(name == "DS_Toggle")
   {
      ObjectSetInteger(0, name, OBJPROP_XDISTANCE, g_panel.x + g_panel.width - 80);
      ObjectSetInteger(0, name, OBJPROP_YDISTANCE, g_panel.y + 5);
   }
   else if(name == "DS_Minimize")
   {
      ObjectSetInteger(0, name, OBJPROP_XDISTANCE, g_panel.x + g_panel.width - 25);
      ObjectSetInteger(0, name, OBJPROP_YDISTANCE, g_panel.y + 5);
   }
}

//+------------------------------------------------------------------+
//| Criar objetos do painel                                         |
//+------------------------------------------------------------------+
void CreatePanelObjects()
{
   // Background principal
   CreateRectangle("DS_Background", g_panel.x, g_panel.y, g_panel.width, 
                   g_panel.minimized ? 35 : g_panel.height, InpPanelBgColor);
   
   // Header
   CreateRectangle("DS_Header", g_panel.x, g_panel.y, g_panel.width, 35, InpHeaderColor);
   
   // Título
   CreateLabel("DS_Title", g_panel.x + 10, g_panel.y + 8, InpRobotName, clrWhite, 12, "Arial Bold");
   
   // Toggle ON/OFF - CORRIGIDO: usar estado atual do robô
   CreateButton("DS_Toggle", g_panel.x + g_panel.width - 80, g_panel.y + 5, 50, 25, 
                g_robot_enabled ? "ON" : "OFF", 
                g_robot_enabled ? InpPositiveColor : InpNegativeColor);
   
   // Botão minimizar
   CreateButton("DS_Minimize", g_panel.x + g_panel.width - 25, g_panel.y + 5, 20, 25, 
                g_panel.minimized ? "+" : "-", InpAccentColor);
   
   if(!g_panel.minimized)
   {
      CreateMainPanelContent();
   }
}

//+------------------------------------------------------------------+
//| Criar conteúdo principal do painel                              |
//+------------------------------------------------------------------+
void CreateMainPanelContent()
{
   int y_offset = 45;
   
   // Número Mágico
   CreateLabel("DS_Magic_Label", g_panel.x + 10, g_panel.y + y_offset, "N. Mágico:", clrSilver, 10);
   CreateLabel("DS_Magic", g_panel.x + g_panel.width - 70, g_panel.y + y_offset, 
               IntegerToString(InpMagicNumber), InpWarningColor, 10, "Arial Bold");
   y_offset += 25;
   
   // === ABA ENTRADA ===
   CreateSectionHeader("ENTRADA", y_offset);
   y_offset += 30;
   
   // Estado do robô - CORRIGIDO: usar função GetRobotStatus()
   CreateLabel("DS_Status_Label", g_panel.x + 10, g_panel.y + y_offset, "Estado:", clrSilver, 10);
   string initial_status = GetRobotStatus();
   color initial_color = GetRobotStatusColor();
   CreateLabel("DS_Status", g_panel.x + g_panel.width - 120, g_panel.y + y_offset, 
               initial_status, initial_color, 10, "Arial Bold");
   y_offset += 25;
   
   // Símbolo
   CreateLabel("DS_Symbol_Label", g_panel.x + 10, g_panel.y + y_offset, "Símbolo:", clrSilver, 10);
   CreateLabel("DS_Symbol", g_panel.x + g_panel.width - 120, g_panel.y + y_offset, 
               g_symbol, clrWhite, 10, "Arial Bold");
   y_offset += 25;
   
   // Res Aberto
   CreateLabel("DS_ResAberto_Label", g_panel.x + 10, g_panel.y + y_offset, "Res Aberto:", clrSilver, 10);
   CreateLabel("DS_ResAberto", g_panel.x + g_panel.width - 120, g_panel.y + y_offset, 
               "0,00", clrWhite, 10, "Arial Bold");
   y_offset += 25;
   
   // Res Dia
   CreateLabel("DS_ResDia_Label", g_panel.x + 10, g_panel.y + y_offset, "Res Dia:", clrSilver, 10);
   CreateLabel("DS_ResDia", g_panel.x + g_panel.width - 120, g_panel.y + y_offset, 
               "0,00", clrWhite, 10, "Arial Bold");
   y_offset += 25;
   
   // Data/Hora - CORRIGIDO para atualizar do sistema
   CreateLabel("DS_DateTime_Label", g_panel.x + 10, g_panel.y + y_offset, "Data/Hora:", clrSilver, 10);
   CreateLabel("DS_DateTime", g_panel.x + g_panel.width - 130, g_panel.y + y_offset, 
               TimeToString(TimeCurrent(), TIME_DATE|TIME_MINUTES), clrWhite, 10);
   y_offset += 25;
   
   // Maior Lucro
   CreateLabel("DS_MaiorLucro_Label", g_panel.x + 10, g_panel.y + y_offset, "Maior Lucro:", clrSilver, 10);
   CreateLabel("DS_MaiorLucro", g_panel.x + g_panel.width - 120, g_panel.y + y_offset, 
               "0,00", InpPositiveColor, 10, "Arial Bold");
   y_offset += 30;
   
   // Botão Close All ocupando quase toda a largura do painel
   int btn_width = g_panel.width - 40; // 20px margin em cada lado
   int btn_start_x = g_panel.x + 20;
   
   CreateButton("DS_BtnZero", btn_start_x, g_panel.y + y_offset, btn_width, 30, "Zerar e Desligar", InpWarningColor);
   y_offset += 50;
   
   // === ABA ESTATÍSTICAS ===
   CreateSectionHeader("ESTATÍSTICAS", y_offset);
   y_offset += 30;
   
   // Botões de período
   int period_btn_width = 60;
   int period_btn_spacing = 5;
   int period_start_x = g_panel.x + (g_panel.width - (4 * period_btn_width + 3 * period_btn_spacing)) / 2;
   
   CreateButton("DS_BtnDaily", period_start_x, g_panel.y + y_offset, period_btn_width, 25, 
                "D", g_panel.selected_period == TIME_DAILY ? InpAccentColor : C'70,70,70');
   CreateButton("DS_BtnWeekly", period_start_x + period_btn_width + period_btn_spacing, g_panel.y + y_offset, period_btn_width, 25, 
                "S", g_panel.selected_period == TIME_WEEKLY ? InpAccentColor : C'70,70,70');
   CreateButton("DS_BtnMonthly", period_start_x + 2*(period_btn_width + period_btn_spacing), g_panel.y + y_offset, period_btn_width, 25, 
                "M", g_panel.selected_period == TIME_MONTHLY ? InpAccentColor : C'70,70,70');
   CreateButton("DS_BtnTotal", period_start_x + 3*(period_btn_width + period_btn_spacing), g_panel.y + y_offset, period_btn_width, 25, 
                "T", g_panel.selected_period == TIME_TOTAL ? InpAccentColor : C'70,70,70');
   y_offset += 40;
   
   // Estatísticas
   CreateStatLine("Rentabilidade:", "DS_Rentabilidade", y_offset);
   y_offset += 25;
   CreateStatLine("Qtd Operações:", "DS_QtdOp", y_offset);
   y_offset += 25;
   CreateStatLine("% Acerto:", "DS_PctAcerto", y_offset);
   y_offset += 25;
   CreateStatLine("Fator Lucro:", "DS_FatorLucro", y_offset);
   y_offset += 25;
   CreateStatLine("Drawdown:", "DS_Drawdown", y_offset);
}

//+------------------------------------------------------------------+
//| Criar cabeçalho de seção                                        |
//+------------------------------------------------------------------+
void CreateSectionHeader(string text, int y_offset)
{
   // Linha separadora
   CreateRectangle("DS_Sep_" + text, g_panel.x + 10, g_panel.y + y_offset - 5, 
                   g_panel.width - 20, 2, InpAccentColor);
   
   // Texto do cabeçalho
   CreateLabel("DS_Header_" + text, g_panel.x + 10, g_panel.y + y_offset + 5, 
               text, InpAccentColor, 11, "Arial Bold");
}

//+------------------------------------------------------------------+
//| Criar linha de estatística                                      |
//+------------------------------------------------------------------+
void CreateStatLine(string label, string obj_name, int y_offset)
{
   CreateLabel(obj_name + "_Label", g_panel.x + 15, g_panel.y + y_offset, label, clrSilver, 10);
   CreateLabel(obj_name, g_panel.x + g_panel.width - 120, g_panel.y + y_offset, "0,00", clrWhite, 10, "Arial Bold");
}

//+------------------------------------------------------------------+
//| Criar retângulo                                                  |
//+------------------------------------------------------------------+
void CreateRectangle(string name, int x, int y, int width, int height, color bg_color)
{
   if(ObjectFind(0, name) >= 0) ObjectDelete(0, name);
   
   ObjectCreate(0, name, OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE, width);
   ObjectSetInteger(0, name, OBJPROP_YSIZE, height);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR, bg_color);
   ObjectSetInteger(0, name, OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
   ObjectSetInteger(0, name, OBJPROP_BORDER_COLOR, C'60,60,60');
}

//+------------------------------------------------------------------+
//| Criar label                                                      |
//+------------------------------------------------------------------+
void CreateLabel(string name, int x, int y, string text, color text_color, int font_size = 10, string font = "Segoe UI")
{
   if(ObjectFind(0, name) >= 0) ObjectDelete(0, name);
   
   ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_COLOR, text_color);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, font_size);
   ObjectSetString(0, name, OBJPROP_FONT, font);
}

//+------------------------------------------------------------------+
//| Criar botão                                                      |
//+------------------------------------------------------------------+
void CreateButton(string name, int x, int y, int width, int height, string text, color bg_color)
{
   if(ObjectFind(0, name) >= 0) ObjectDelete(0, name);
   
   ObjectCreate(0, name, OBJ_BUTTON, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE, width);
   ObjectSetInteger(0, name, OBJPROP_YSIZE, height);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR, bg_color);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clrWhite);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 10);
   ObjectSetString(0, name, OBJPROP_FONT, "Segoe UI");
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, true);
   ObjectSetInteger(0, name, OBJPROP_STATE, false);
}

//+------------------------------------------------------------------+
//| Manipular cliques em botões                                     |
//+------------------------------------------------------------------+
void HandleButtonClick(string name)
{
   // Reset imediato do estado do botão para todos os botões
   ObjectSetInteger(0, name, OBJPROP_STATE, false);
   
   if(name == "DS_Toggle")
   {
      g_robot_enabled = !g_robot_enabled;
      
      // Atualizar o botão toggle
      ObjectSetString(0, "DS_Toggle", OBJPROP_TEXT, g_robot_enabled ? "ON" : "OFF");
      ObjectSetInteger(0, "DS_Toggle", OBJPROP_BGCOLOR, 
                       g_robot_enabled ? InpPositiveColor : InpNegativeColor);
      
      // Atualizar IMEDIATAMENTE o status do robô
      string status_text = GetRobotStatus();
      color status_color = GetRobotStatusColor();
      ObjectSetString(0, "DS_Status", OBJPROP_TEXT, status_text);
      ObjectSetInteger(0, "DS_Status", OBJPROP_COLOR, status_color);
   }
   else if(name == "DS_Minimize")
   {
      g_panel.minimized = !g_panel.minimized;
      CleanupPanel();
      CreatePanelObjects();
      
      // CORRIGIDO: Após recriar o painel, atualizar todos os valores
      if(!g_panel.minimized)
      {
         UpdateDisplayValues();
      }
   }
   else if(name == "DS_BtnZero")
   {
      // Efeito visual de clique
      color original_color = InpWarningColor;
      color click_color = C'200,150,50'; // Amarelo mais escuro
      
      ObjectSetInteger(0, name, OBJPROP_BGCOLOR, click_color);
      ChartRedraw();
      Sleep(100); // Efeito visual
      ObjectSetInteger(0, name, OBJPROP_BGCOLOR, original_color);
      
      // Fechar todas as posições E desligar o robô
      bool result = CloseAllPositions();
      g_robot_enabled = false; // Sempre desliga, mesmo se não tiver posições
      
      // Atualizar o botão toggle
      ObjectSetString(0, "DS_Toggle", OBJPROP_TEXT, "OFF");
      ObjectSetInteger(0, "DS_Toggle", OBJPROP_BGCOLOR, InpNegativeColor);
      
      // Atualizar IMEDIATAMENTE o status do robô
      ObjectSetString(0, "DS_Status", OBJPROP_TEXT, "Desligado");
      ObjectSetInteger(0, "DS_Status", OBJPROP_COLOR, InpNegativeColor);
   }
   else if(name == "DS_BtnDaily")
   {
      g_panel.selected_period = TIME_DAILY;
      UpdatePeriodButtons();
      UpdateStats();
   }
   else if(name == "DS_BtnWeekly")
   {
      g_panel.selected_period = TIME_WEEKLY;
      UpdatePeriodButtons();
      UpdateStats();
   }
   else if(name == "DS_BtnMonthly")
   {
      g_panel.selected_period = TIME_MONTHLY;
      UpdatePeriodButtons();
      UpdateStats();
   }
   else if(name == "DS_BtnTotal")
   {
      g_panel.selected_period = TIME_TOTAL;
      UpdatePeriodButtons();
      UpdateStats();
   }
   
   ChartRedraw();
}

//+------------------------------------------------------------------+
//| Atualizar botões de período                                     |
//+------------------------------------------------------------------+
void UpdatePeriodButtons()
{
   string buttons[] = {"DS_BtnDaily", "DS_BtnWeekly", "DS_BtnMonthly", "DS_BtnTotal"};
   ENUM_TIME_PERIOD periods[] = {TIME_DAILY, TIME_WEEKLY, TIME_MONTHLY, TIME_TOTAL};
   
   for(int i = 0; i < ArraySize(buttons); i++)
   {
      color btn_color = (periods[i] == g_panel.selected_period) ? InpAccentColor : C'70,70,70';
      ObjectSetInteger(0, buttons[i], OBJPROP_BGCOLOR, btn_color);
   }
}

//+------------------------------------------------------------------+
//| Atualizar painel                                                |
//+------------------------------------------------------------------+
void UpdatePanel()
{
   if(!g_panel_initialized || g_updating_panel) return;
   
   g_updating_panel = true;
   
   // Verificar se objetos ainda existem
   if(ObjectFind(0, "DS_Background") < 0)
   {
      InitializePanel();
      g_updating_panel = false;
      return;
   }
   
   // Atualizar apenas se não minimizado
   if(!g_panel.minimized)
   {
      UpdateDisplayValues();
   }
   
   g_updating_panel = false;
   g_last_panel_update = TimeCurrent();
}

//+------------------------------------------------------------------+
//| Atualizar valores exibidos                                      |
//+------------------------------------------------------------------+
void UpdateDisplayValues()
{
   // Status do robô - SISTEMA INTELIGENTE COM MERCADO FECHADO
   string status_text = GetRobotStatus();
   color status_color = GetRobotStatusColor();
   
   ObjectSetString(0, "DS_Status", OBJPROP_TEXT, status_text);
   ObjectSetInteger(0, "DS_Status", OBJPROP_COLOR, status_color);
   
   // Atualizar toggle também
   ObjectSetString(0, "DS_Toggle", OBJPROP_TEXT, g_robot_enabled ? "ON" : "OFF");
   ObjectSetInteger(0, "DS_Toggle", OBJPROP_BGCOLOR, 
                    g_robot_enabled ? InpPositiveColor : InpNegativeColor);
   
   // Data/Hora - CORRIGIDO para atualizar em tempo real do sistema
   ObjectSetString(0, "DS_DateTime", OBJPROP_TEXT, 
                   TimeToString(TimeCurrent(), TIME_DATE|TIME_MINUTES));
   
   // Resultado em aberto - Usar nova função de cor
   double open_result = CalculateOpenProfit();
   ObjectSetString(0, "DS_ResAberto", OBJPROP_TEXT, 
                   DoubleToString(open_result, 2));
   ObjectSetInteger(0, "DS_ResAberto", OBJPROP_COLOR, GetProfitColor(open_result));
   
   // Resultado do dia - Usar nova função de cor
   double daily_result = GetDailyProfit();
   ObjectSetString(0, "DS_ResDia", OBJPROP_TEXT, 
                   DoubleToString(daily_result, 2));
   ObjectSetInteger(0, "DS_ResDia", OBJPROP_COLOR, GetProfitColor(daily_result));
   
   // Maior lucro
   ObjectSetString(0, "DS_MaiorLucro", OBJPROP_TEXT, 
                   DoubleToString(g_stats.best_trade, 2));
   
   // Estatísticas baseadas no período selecionado
   UpdateStatsDisplay();
}

//+------------------------------------------------------------------+
//| Atualizar exibição das estatísticas                             |
//+------------------------------------------------------------------+
void UpdateStatsDisplay()
{
   double profit = 0;
   
   switch(g_panel.selected_period)
   {
      case TIME_DAILY:   profit = g_stats.daily_profit; break;
      case TIME_WEEKLY:  profit = g_stats.weekly_profit; break;
      case TIME_MONTHLY: profit = g_stats.monthly_profit; break;
      case TIME_TOTAL:   profit = g_stats.total_profit; break;
   }
   
   // Rentabilidade
   ObjectSetString(0, "DS_Rentabilidade", OBJPROP_TEXT, 
                   DoubleToString(profit, 2));
   ObjectSetInteger(0, "DS_Rentabilidade", OBJPROP_COLOR, 
                    profit >= 0 ? InpPositiveColor : InpNegativeColor);
   
   // Quantidade de operações
   ObjectSetString(0, "DS_QtdOp", OBJPROP_TEXT, 
                   IntegerToString(g_stats.total_trades));
   
   // % Acerto
   ObjectSetString(0, "DS_PctAcerto", OBJPROP_TEXT, 
                   DoubleToString(g_stats.win_rate, 1) + "%");
   ObjectSetInteger(0, "DS_PctAcerto", OBJPROP_COLOR, 
                    g_stats.win_rate >= 50 ? InpPositiveColor : InpNegativeColor);
   
   // Fator de lucro
   ObjectSetString(0, "DS_FatorLucro", OBJPROP_TEXT, 
                   DoubleToString(g_stats.profit_factor, 2));
   ObjectSetInteger(0, "DS_FatorLucro", OBJPROP_COLOR, 
                    g_stats.profit_factor >= 1.0 ? InpPositiveColor : InpNegativeColor);
   
   // Drawdown
   ObjectSetString(0, "DS_Drawdown", OBJPROP_TEXT, 
                   DoubleToString(g_stats.max_drawdown, 2) + "%");
   ObjectSetInteger(0, "DS_Drawdown", OBJPROP_COLOR, InpNegativeColor);
}

//+------------------------------------------------------------------+
//| Obter status do robô                                            |
//+------------------------------------------------------------------+
string GetRobotStatus()
{
   // PRIMEIRO: Verificar se o robô está desligado
   // Esta verificação SEMPRE vem primeiro, independente do mercado
   if(!g_robot_enabled)
   {
      return "Desligado";
   }
   
   // SEGUNDO: Verificar se o mercado está fechado
   // Só verifica mercado fechado se o robô estiver ligado
   if(!IsMarketOpen())
   {
      return "Mercado Fechado";
   }
   
   // TERCEIRO: Contar posições ativas do robô
   int buy_positions = 0;
   int sell_positions = 0;
   
   for(int i = 0; i < PositionsTotal(); i++)
   {
      if(PositionSelectByTicket(PositionGetTicket(i)))
      {
         if(PositionGetString(POSITION_SYMBOL) == g_symbol && 
            PositionGetInteger(POSITION_MAGIC) == InpMagicNumber)
         {
            if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
               buy_positions++;
            else if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL)
               sell_positions++;
         }
      }
   }
   
   // QUARTO: Retornar status baseado nas posições
   if(buy_positions > 0 && sell_positions > 0)
      return "Comprado x" + IntegerToString(buy_positions) + " / Vendido x" + IntegerToString(sell_positions);
   else if(buy_positions > 0)
      return "Comprado x" + IntegerToString(buy_positions);
   else if(sell_positions > 0)
      return "Vendido x" + IntegerToString(sell_positions);
   else
      return "Analisando";
}

//+------------------------------------------------------------------+
//| Obter cor do status                                             |
//+------------------------------------------------------------------+
color GetRobotStatusColor()
{
   // PRIMEIRO: Verificar se o robô está desligado
   // Esta verificação SEMPRE vem primeiro, independente do mercado
   if(!g_robot_enabled)
   {
      return InpNegativeColor; // Vermelho para desligado
   }
   
   // SEGUNDO: Verificar se o mercado está fechado
   // Só verifica mercado fechado se o robô estiver ligado
   if(!IsMarketOpen())
   {
      return InpMarketClosedColor; // Roxo para mercado fechado
   }
   
   // TERCEIRO: Verificar se tem posições
   int buy_positions = 0;
   int sell_positions = 0;
   
   for(int i = 0; i < PositionsTotal(); i++)
   {
      if(PositionSelectByTicket(PositionGetTicket(i)))
      {
         if(PositionGetString(POSITION_SYMBOL) == g_symbol && 
            PositionGetInteger(POSITION_MAGIC) == InpMagicNumber)
         {
            if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
               buy_positions++;
            else if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL)
               sell_positions++;
         }
      }
   }
   
   // QUARTO: Cores baseadas nas posições
   if(buy_positions > 0 && sell_positions == 0)
      return InpPositiveColor; // Verde para comprado
   else if(sell_positions > 0 && buy_positions == 0)
      return InpNegativeColor; // Vermelho para vendido
   else if(buy_positions > 0 && sell_positions > 0)
   {
      // Se tem ambas, usar cor baseada no lucro
      double profit = CalculateOpenProfit();
      return profit >= 0 ? InpPositiveColor : InpNegativeColor;
   }
   
   // Se não tem posições mas está ligado (analisando)
   return InpWarningColor; // Amarelo para analisando
}

//+------------------------------------------------------------------+
//| Obter cor para resultado (baseado no valor)                     |
//+------------------------------------------------------------------+
color GetProfitColor(double value)
{
   if(value > 0) return InpPositiveColor;      // Verde para lucro
   if(value < 0) return InpNegativeColor;      // Vermelho para prejuízo
   return clrWhite;                            // Branco para zero
}

//+------------------------------------------------------------------+
//| Calcular lucro em aberto                                        |
//+------------------------------------------------------------------+
double CalculateOpenProfit()
{
   double total_profit = 0;
   
   for(int i = 0; i < PositionsTotal(); i++)
   {
      if(PositionSelectByTicket(PositionGetTicket(i)))
      {
         if(PositionGetString(POSITION_SYMBOL) == g_symbol && 
            PositionGetInteger(POSITION_MAGIC) == InpMagicNumber)
         {
            total_profit += PositionGetDouble(POSITION_PROFIT);
            total_profit += PositionGetDouble(POSITION_SWAP);
         }
      }
   }
   
   return total_profit;
}

//+------------------------------------------------------------------+
//| Obter lucro do dia                                              |
//+------------------------------------------------------------------+
double GetDailyProfit()
{
   datetime start_of_day = GetStartOfDay();
   
   if(!HistorySelect(start_of_day, TimeCurrent()))
      return 0;
   
   double daily_profit = 0;
   int total_deals = HistoryDealsTotal();
   
   for(int i = 0; i < total_deals; i++)
   {
      ulong deal_ticket = HistoryDealGetTicket(i);
      if(deal_ticket == 0) continue;
      
      if(HistoryDealGetString(deal_ticket, DEAL_SYMBOL) == g_symbol &&
         HistoryDealGetInteger(deal_ticket, DEAL_MAGIC) == InpMagicNumber)
      {
         daily_profit += HistoryDealGetDouble(deal_ticket, DEAL_PROFIT);
         daily_profit += HistoryDealGetDouble(deal_ticket, DEAL_SWAP);
         daily_profit += HistoryDealGetDouble(deal_ticket, DEAL_COMMISSION);
      }
   }
   
   // Adicionar lucro das posições abertas
   daily_profit += CalculateOpenProfit();
   
   return daily_profit;
}

//+------------------------------------------------------------------+
//| Obter início do dia                                             |
//+------------------------------------------------------------------+
datetime GetStartOfDay()
{
   MqlDateTime dt;
   TimeCurrent(dt);
   dt.hour = 0;
   dt.min = 0;
   dt.sec = 0;
   return StructToTime(dt);
}

//+------------------------------------------------------------------+
//| Obter início da semana                                          |
//+------------------------------------------------------------------+
datetime GetStartOfWeek()
{
   MqlDateTime dt;
   TimeCurrent(dt);
   dt.hour = 0;
   dt.min = 0;
   dt.sec = 0;
   
   // Calcular dias para voltar até segunda-feira
   int days_back = dt.day_of_week == 0 ? 6 : dt.day_of_week - 1;
   return StructToTime(dt) - days_back * 24 * 60 * 60;
}

//+------------------------------------------------------------------+
//| Obter início do mês                                             |
//+------------------------------------------------------------------+
datetime GetStartOfMonth()
{
   MqlDateTime dt;
   TimeCurrent(dt);
   dt.day = 1;
   dt.hour = 0;
   dt.min = 0;
   dt.sec = 0;
   return StructToTime(dt);
}

//+------------------------------------------------------------------+
//| Atualizar estatísticas                                          |
//+------------------------------------------------------------------+
void UpdateStats()
{
   // Calcular estatísticas para todos os períodos
   CalculateStatsForPeriod(TIME_DAILY);
   CalculateStatsForPeriod(TIME_WEEKLY);
   CalculateStatsForPeriod(TIME_MONTHLY);
   CalculateStatsForPeriod(TIME_TOTAL);
   
   g_last_update = TimeCurrent();
}

//+------------------------------------------------------------------+
//| Calcular estatísticas para período específico                   |
//+------------------------------------------------------------------+
void CalculateStatsForPeriod(ENUM_TIME_PERIOD period)
{
   datetime start_time = 0;
   
   switch(period)
   {
      case TIME_DAILY:   start_time = GetStartOfDay(); break;
      case TIME_WEEKLY:  start_time = GetStartOfWeek(); break;
      case TIME_MONTHLY: start_time = GetStartOfMonth(); break;
      case TIME_TOTAL:   start_time = 0; break;
   }
   
   if(!HistorySelect(start_time, TimeCurrent()))
      return;
   
   double total_profit = 0;
   double total_loss = 0;
   int winning_trades = 0;
   int losing_trades = 0;
   int total_trades = 0;
   double best_trade = 0;
   double worst_trade = 0;
   double max_dd = 0;
   double peak = 0;
   double running_profit = 0;
   
   int total_deals = HistoryDealsTotal();
   
   for(int i = 0; i < total_deals; i++)
   {
      ulong deal_ticket = HistoryDealGetTicket(i);
      if(deal_ticket == 0) continue;
      
      if(HistoryDealGetString(deal_ticket, DEAL_SYMBOL) == g_symbol &&
         HistoryDealGetInteger(deal_ticket, DEAL_MAGIC) == InpMagicNumber)
      {
         ENUM_DEAL_TYPE deal_type = (ENUM_DEAL_TYPE)HistoryDealGetInteger(deal_ticket, DEAL_TYPE);
         
         if(deal_type == DEAL_TYPE_BUY || deal_type == DEAL_TYPE_SELL)
         {
            total_trades++;
            double profit = HistoryDealGetDouble(deal_ticket, DEAL_PROFIT);
            double swap = HistoryDealGetDouble(deal_ticket, DEAL_SWAP);
            double commission = HistoryDealGetDouble(deal_ticket, DEAL_COMMISSION);
            
            double net_profit = profit + swap + commission;
            running_profit += net_profit;
            
            if(net_profit > 0)
            {
               winning_trades++;
               total_profit += net_profit;
               if(net_profit > best_trade) best_trade = net_profit;
            }
            else if(net_profit < 0)
            {
               losing_trades++;
               total_loss += MathAbs(net_profit);
               if(net_profit < worst_trade) worst_trade = net_profit;
            }
            
            // Calcular drawdown
            if(running_profit > peak) peak = running_profit;
            double dd = (peak - running_profit) / (peak == 0 ? 1 : peak) * 100;
            if(dd > max_dd) max_dd = dd;
         }
      }
   }
   
   // Calcular fator de lucro
   double profit_factor = (total_loss > 0) ? total_profit / total_loss : 0;
   
   // Taxa de acerto
   double win_rate = (total_trades > 0) ? (double)winning_trades / total_trades * 100 : 0;
   
   // Salvar estatísticas no período correto
   switch(period)
   {
      case TIME_DAILY:
         g_stats.daily_profit = running_profit;
         break;
      case TIME_WEEKLY:
         g_stats.weekly_profit = running_profit;
         break;
      case TIME_MONTHLY:
         g_stats.monthly_profit = running_profit;
         break;
      case TIME_TOTAL:
         g_stats.total_profit = running_profit;
         g_stats.total_trades = total_trades;
         g_stats.winning_trades = winning_trades;
         g_stats.losing_trades = losing_trades;
         g_stats.win_rate = win_rate;
         g_stats.profit_factor = profit_factor;
         g_stats.max_drawdown = max_dd;
         g_stats.best_trade = best_trade;
         g_stats.worst_trade = worst_trade;
         break;
   }
}

//+------------------------------------------------------------------+
//| Limpar painel                                                   |
//+------------------------------------------------------------------+
void CleanupPanel()
{
   g_updating_panel = true;
   
   // Lista de todos os objetos do painel
   string objects[] = {
      "DS_Background", "DS_Header", "DS_Title", "DS_Toggle", "DS_Minimize",
      "DS_Magic_Label", "DS_Magic", "DS_Status_Label", "DS_Status", 
      "DS_Symbol_Label", "DS_Symbol", "DS_ResAberto_Label", "DS_ResAberto",
      "DS_ResDia_Label", "DS_ResDia", "DS_DateTime_Label", "DS_DateTime",
      "DS_MaiorLucro_Label", "DS_MaiorLucro", "DS_BtnZero",
      "DS_BtnDaily", "DS_BtnWeekly", "DS_BtnMonthly", "DS_BtnTotal",
      "DS_Rentabilidade_Label", "DS_Rentabilidade", "DS_QtdOp_Label", "DS_QtdOp",
      "DS_PctAcerto_Label", "DS_PctAcerto", "DS_FatorLucro_Label", "DS_FatorLucro",
      "DS_Drawdown_Label", "DS_Drawdown"
   };
   
   // Remover seções
   string sections[] = {"ENTRADA", "ESTATÍSTICAS"};
   for(int i = 0; i < ArraySize(sections); i++)
   {
      ObjectDelete(0, "DS_Sep_" + sections[i]);
      ObjectDelete(0, "DS_Header_" + sections[i]);
   }
   
   // Remover objetos principais
   for(int i = 0; i < ArraySize(objects); i++)
   {
      ObjectDelete(0, objects[i]);
   }
   
   g_panel_initialized = false;
   g_updating_panel = false;
   ChartRedraw();
}

//+------------------------------------------------------------------+
//| Fechar todas as posições                                        |
//+------------------------------------------------------------------+
bool CloseAllPositions()
{
   bool result = true;
   
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(PositionSelectByTicket(PositionGetTicket(i)))
      {
         if(PositionGetString(POSITION_SYMBOL) == g_symbol &&
            PositionGetInteger(POSITION_MAGIC) == InpMagicNumber)
         {
            ulong ticket = PositionGetTicket(i);
            if(!trade.PositionClose(ticket))
            {
               result = false;
            }
         }
      }
   }
   
   if(result)
   {
      UpdateStats();
   }
   
   return result;
}

//+------------------------------------------------------------------+