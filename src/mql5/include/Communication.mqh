//+------------------------------------------------------------------+
//|                  DuarteScalper\Communication.mqh                 |
//|                                  Copyright 2024, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property version   "1.00"
#property strict

//+------------------------------------------------------------------+
//| Includes necessários                                             |
//+------------------------------------------------------------------+
#include <Files\File.mqh>

//+------------------------------------------------------------------+
//| Definições e constantes                                          |
//+------------------------------------------------------------------+
#define DUARTE_COMM_NAME "DuarteScalper_Communication"
#define DUARTE_BUFFER_SIZE 2048
#define DUARTE_TIMEOUT_MS 1000

// Tipos de mensagem
enum ENUM_DUARTE_MESSAGE_TYPE
  {
   DUARTE_MESSAGE_TICK_DATA = 1,
   DUARTE_MESSAGE_SIGNAL_REQUEST = 2,
   DUARTE_MESSAGE_SIGNAL_RESPONSE = 3,
   DUARTE_MESSAGE_ORDER_REQUEST = 4,
   DUARTE_MESSAGE_ORDER_RESPONSE = 5,
   DUARTE_MESSAGE_STATUS_UPDATE = 6,
   DUARTE_MESSAGE_CONFIG_UPDATE = 7,
   DUARTE_MESSAGE_ERROR = 99
  };

// Status da comunicação
enum ENUM_DUARTE_COMM_STATUS
  {
   DUARTE_COMM_DISCONNECTED = 0,
   DUARTE_COMM_CONNECTING = 1,
   DUARTE_COMM_CONNECTED = 2,
   DUARTE_COMM_ERROR = 3
  };

//+------------------------------------------------------------------+
//| Estruturas de dados                                              |
//+------------------------------------------------------------------+
struct DuarteTickData
  {
   string            symbol;
   datetime          time;
   double            bid;
   double            ask;
   double            last;
   ulong             volume;
   double            spread;
   int               direction;
  };

struct DuarteSignalData
  {
   string            symbol;
   int               direction;        // 1=BUY, -1=SELL, 0=HOLD
   double            confidence;       // 0.0 - 1.0
   double            expected_move;    // Expected price movement
   int               time_horizon;     // Time horizon in seconds
   datetime          timestamp;
  };

struct DuarteOrderData
  {
   string            symbol;
   int               operation;        // ORDER_TYPE_BUY or ORDER_TYPE_SELL
   double            volume;
   double            price;
   double            sl;
   double            tp;
   string            comment;
   ulong             magic;
  };

//+------------------------------------------------------------------+
//| Classe principal de comunicação                                   |
//+------------------------------------------------------------------+
class CDuarteCommunication
  {
private:
   string            m_outbox_path;
   string            m_inbox_path;
   ENUM_DUARTE_COMM_STATUS m_status;
   datetime          m_last_heartbeat;
   int               m_connection_attempts;
   bool              m_debug_mode;

   // Estatísticas
   ulong             m_messages_sent;
   ulong             m_messages_received;
   ulong             m_errors_count;

   // Métodos privados
   bool              CreateCommunicationFiles();
   string            FormatTickMessage(const DuarteTickData& tick);
   string            FormatSignalRequest(const string symbol);
   bool              ParseSignalResponse(const string json, DuarteSignalData& signal);
   void              LogMessage(const string message, bool is_error = false);
   string            GetCurrentTimestamp();
   string            CreateJsonString(const string key, const string value);
   string            CreateJsonInt(const string key, long value);
   string            CreateJsonDouble(const string key, double value);
   bool              WriteToOutbox(const string message);
   string            ReadFromInbox();

public:
   // Construtor e destrutor
                     CDuarteCommunication();
                    ~CDuarteCommunication();

   // Métodos principais
   bool              Initialize(const string comm_name = DUARTE_COMM_NAME);
   void              Shutdown();
   bool              IsConnected() { return m_status == DUARTE_COMM_CONNECTED; }
   ENUM_DUARTE_COMM_STATUS GetStatus() { return m_status; }

   // Comunicação
   bool              SendTickData(const DuarteTickData& tick);
   bool              RequestSignal(const string symbol, DuarteSignalData& signal);
   bool              SendOrderRequest(const DuarteOrderData& order);
   bool              SendStatusUpdate(const string status, const string details = "");

   // Configuração
   void              SetDebugMode(bool enabled) { m_debug_mode = enabled; }
   bool              UpdateConfig(const string key, const string value);

   // Manutenção
   void              SendHeartbeat();
   bool              CheckConnection();
   void              ResetConnection();

   // Estatísticas
   void              GetStatistics(ulong& sent, ulong& received, ulong& errors);
   string            GetStatusReport();

   // Utilitários
   static string     JsonEscape(const string text);
   static double     NormalizePrice(double price, int digits);
  };

//+------------------------------------------------------------------+
//| Implementação da classe                                          |
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| Construtor                                                       |
//+------------------------------------------------------------------+
CDuarteCommunication::CDuarteCommunication()
  {
   m_outbox_path = "";
   m_inbox_path = "";
   m_status = DUARTE_COMM_DISCONNECTED;
   m_last_heartbeat = 0;
   m_connection_attempts = 0;
   m_debug_mode = false;
   m_messages_sent = 0;
   m_messages_received = 0;
   m_errors_count = 0;
  }

//+------------------------------------------------------------------+
//| Destrutor                                                        |
//+------------------------------------------------------------------+
CDuarteCommunication::~CDuarteCommunication()
  {
   Shutdown();
  }

//+------------------------------------------------------------------+
//| Inicialização                                                    |
//+------------------------------------------------------------------+
bool CDuarteCommunication::Initialize(const string comm_name = DUARTE_COMM_NAME)
  {
   if(m_status == DUARTE_COMM_CONNECTED)
     {
      LogMessage("Communication already initialized");
      return true;
     }

   // Definir caminhos dos arquivos
   m_outbox_path = "DuarteScalper\\" + comm_name + "_outbox.json";
   m_inbox_path = "DuarteScalper\\" + comm_name + "_inbox.json";
   
   m_status = DUARTE_COMM_CONNECTING;
   LogMessage("Initializing communication: " + comm_name);

   // Criar arquivos de comunicação
   if(!CreateCommunicationFiles())
     {
      LogMessage("Failed to create communication files", true);
      m_status = DUARTE_COMM_ERROR;
      return false;
     }

   // Tentar estabelecer comunicação
   for(int i = 0; i < 3; i++)
     {
      if(WriteToOutbox("{\"type\":6,\"status\":\"INIT\",\"message\":\"MT5 Ready\"}"))
        {
         m_status = DUARTE_COMM_CONNECTED;
         m_last_heartbeat = TimeCurrent();
         LogMessage("Communication initialized successfully");
         return true;
        }
      
      Sleep(1000);
      m_connection_attempts++;
     }

   m_status = DUARTE_COMM_ERROR;
   LogMessage("Failed to initialize communication", true);
   return false;
  }

//+------------------------------------------------------------------+
//| Finalização                                                      |
//+------------------------------------------------------------------+
void CDuarteCommunication::Shutdown()
  {
   if(m_status != DUARTE_COMM_DISCONNECTED)
     {
      LogMessage("Shutting down communication");
      WriteToOutbox("{\"type\":6,\"status\":\"SHUTDOWN\",\"message\":\"MT5 Disconnecting\"}");
      m_status = DUARTE_COMM_DISCONNECTED;
     }
  }

//+------------------------------------------------------------------+
//| Criar arquivos de comunicação                                    |
//+------------------------------------------------------------------+
bool CDuarteCommunication::CreateCommunicationFiles()
  {
   // Criar diretório DuarteScalper se não existir
   if(!FolderCreate("DuarteScalper", FILE_COMMON))
     {
      // Se der erro, verificar se já existe
      if(GetLastError() != 5018) // ERROR_DIRECTORY_ALREADY_EXISTS = 5018
        {
         LogMessage("Failed to create DuarteScalper directory", true);
         return false;
        }
     }

   // Criar arquivo outbox se não existir
   if(!FileIsExist(m_outbox_path, FILE_COMMON))
     {
      int handle = FileOpen(m_outbox_path, FILE_WRITE | FILE_TXT | FILE_COMMON);
      if(handle == INVALID_HANDLE)
        {
         LogMessage("Failed to create outbox file", true);
         return false;
        }
      FileClose(handle);
     }

   // Criar arquivo inbox se não existir
   if(!FileIsExist(m_inbox_path, FILE_COMMON))
     {
      int handle = FileOpen(m_inbox_path, FILE_WRITE | FILE_TXT | FILE_COMMON);
      if(handle == INVALID_HANDLE)
        {
         LogMessage("Failed to create inbox file", true);
         return false;
        }
      FileClose(handle);
     }

   return true;
  }

//+------------------------------------------------------------------+
//| Escrever no arquivo outbox                                       |
//+------------------------------------------------------------------+
bool CDuarteCommunication::WriteToOutbox(const string message)
  {
   int handle = FileOpen(m_outbox_path, FILE_WRITE | FILE_TXT | FILE_COMMON);
   if(handle == INVALID_HANDLE)
     {
      LogMessage("Failed to open outbox for writing", true);
      return false;
     }

   bool result = (FileWriteString(handle, message + "\n") > 0);
   FileFlush(handle);
   FileClose(handle);

   return result;
  }

//+------------------------------------------------------------------+
//| Ler do arquivo inbox                                             |
//+------------------------------------------------------------------+
string CDuarteCommunication::ReadFromInbox()
  {
   if(!FileIsExist(m_inbox_path, FILE_COMMON))
      return "";

   int handle = FileOpen(m_inbox_path, FILE_READ | FILE_TXT | FILE_COMMON);
   if(handle == INVALID_HANDLE)
      return "";

   string result = "";
   if(FileSize(handle) > 0)
     {
      result = FileReadString(handle);
      
      // Limpar o arquivo após leitura
      FileClose(handle);
      handle = FileOpen(m_inbox_path, FILE_WRITE | FILE_TXT | FILE_COMMON);
      FileClose(handle);
     }
   else
     {
      FileClose(handle);
     }

   return result;
  }

//+------------------------------------------------------------------+
//| Enviar dados de tick                                             |
//+------------------------------------------------------------------+
bool CDuarteCommunication::SendTickData(const DuarteTickData& tick)
  {
   if(!IsConnected())
      return false;

   string message = FormatTickMessage(tick);
   
   if(WriteToOutbox(message))
     {
      m_messages_sent++;
      if(m_debug_mode)
         LogMessage("Tick data sent: " + tick.symbol);
      return true;
     }
   else
     {
      m_errors_count++;
      LogMessage("Failed to send tick data", true);
      return false;
     }
  }

//+------------------------------------------------------------------+
//| Solicitar sinal                                                  |
//+------------------------------------------------------------------+
bool CDuarteCommunication::RequestSignal(const string symbol, DuarteSignalData& signal)
  {
   if(!IsConnected())
      return false;

   // Enviar solicitação
   string request = FormatSignalRequest(symbol);
   if(!WriteToOutbox(request))
     {
      m_errors_count++;
      LogMessage("Failed to send signal request", true);
      return false;
     }

   // Aguardar resposta
   for(int i = 0; i < 10; i++) // 10 tentativas, 100ms cada = 1 segundo total
     {
      Sleep(100);
      
      string response = ReadFromInbox();
      if(response != "")
        {
         m_messages_received++;
         if(ParseSignalResponse(response, signal))
           {
            if(m_debug_mode)
               LogMessage("Signal received: " + symbol + " = " + IntegerToString(signal.direction));
            return true;
           }
        }
     }

   LogMessage("Signal timeout for " + symbol, true);
   return false;
  }

//+------------------------------------------------------------------+
//| Enviar ordem                                                     |
//+------------------------------------------------------------------+
bool CDuarteCommunication::SendOrderRequest(const DuarteOrderData& order)
  {
   if(!IsConnected())
      return false;

   string message = "{" +
                    CreateJsonInt("type", DUARTE_MESSAGE_ORDER_REQUEST) + "," +
                    CreateJsonString("timestamp", GetCurrentTimestamp()) + "," +
                    CreateJsonString("symbol", order.symbol) + "," +
                    CreateJsonInt("operation", order.operation) + "," +
                    CreateJsonDouble("volume", order.volume) + "," +
                    CreateJsonDouble("price", order.price) + "," +
                    CreateJsonDouble("sl", order.sl) + "," +
                    CreateJsonDouble("tp", order.tp) + "," +
                    CreateJsonString("comment", order.comment) + "," +
                    CreateJsonInt("magic", (long)order.magic) +
                    "}";

   if(WriteToOutbox(message))
     {
      m_messages_sent++;
      if(m_debug_mode)
         LogMessage("Order request sent: " + order.symbol);
      return true;
     }
   else
     {
      m_errors_count++;
      LogMessage("Failed to send order request", true);
      return false;
     }
  }

//+------------------------------------------------------------------+
//| Enviar status                                                    |
//+------------------------------------------------------------------+
bool CDuarteCommunication::SendStatusUpdate(const string status, const string details = "")
  {
   if(!IsConnected())
      return false;

   string message = "{" +
                    CreateJsonInt("type", DUARTE_MESSAGE_STATUS_UPDATE) + "," +
                    CreateJsonString("timestamp", GetCurrentTimestamp()) + "," +
                    CreateJsonString("status", status) + "," +
                    CreateJsonString("details", details) + "," +
                    CreateJsonString("expert_id", "DUARTE-SCALPER") +
                    "}";

   if(WriteToOutbox(message))
     {
      m_messages_sent++;
      return true;
     }
   else
     {
      m_errors_count++;
      return false;
     }
  }

//+------------------------------------------------------------------+
//| Formatar mensagem de tick                                        |
//+------------------------------------------------------------------+
string CDuarteCommunication::FormatTickMessage(const DuarteTickData& tick)
  {
   return "{" +
          CreateJsonInt("type", DUARTE_MESSAGE_TICK_DATA) + "," +
          CreateJsonString("timestamp", GetCurrentTimestamp()) + "," +
          CreateJsonString("symbol", tick.symbol) + "," +
          CreateJsonInt("time", (long)tick.time) + "," +
          CreateJsonDouble("bid", tick.bid) + "," +
          CreateJsonDouble("ask", tick.ask) + "," +
          CreateJsonDouble("last", tick.last) + "," +
          CreateJsonInt("volume", (long)tick.volume) + "," +
          CreateJsonDouble("spread", tick.spread) + "," +
          CreateJsonInt("direction", tick.direction) +
          "}";
  }

//+------------------------------------------------------------------+
//| Formatar solicitação de sinal                                    |
//+------------------------------------------------------------------+
string CDuarteCommunication::FormatSignalRequest(const string symbol)
  {
   return "{" +
          CreateJsonInt("type", DUARTE_MESSAGE_SIGNAL_REQUEST) + "," +
          CreateJsonString("timestamp", GetCurrentTimestamp()) + "," +
          CreateJsonString("symbol", symbol) + "," +
          CreateJsonInt("request_id", GetTickCount()) +
          "}";
  }

//+------------------------------------------------------------------+
//| Parse resposta de sinal                                          |
//+------------------------------------------------------------------+
bool CDuarteCommunication::ParseSignalResponse(const string json_str, DuarteSignalData& signal)
  {
   // Verificar se é resposta de sinal
   if(StringFind(json_str, "\"type\":" + IntegerToString(DUARTE_MESSAGE_SIGNAL_RESPONSE)) < 0)
      return false;

   // Extrair symbol
   int pos = StringFind(json_str, "\"symbol\":");
   if(pos >= 0)
     {
      pos = StringFind(json_str, "\"", pos + 9) + 1;
      int end_pos = StringFind(json_str, "\"", pos);
      if(end_pos > pos)
         signal.symbol = StringSubstr(json_str, pos, end_pos - pos);
     }

   // Extrair direction
   pos = StringFind(json_str, "\"direction\":");
   if(pos >= 0)
     {
      pos += 12;
      int end_pos = StringFind(json_str, ",", pos);
      if(end_pos < 0) end_pos = StringFind(json_str, "}", pos);
      if(end_pos > pos)
         signal.direction = (int)StringToInteger(StringSubstr(json_str, pos, end_pos - pos));
     }

   // Extrair confidence
   pos = StringFind(json_str, "\"confidence\":");
   if(pos >= 0)
     {
      pos += 13;
      int end_pos = StringFind(json_str, ",", pos);
      if(end_pos < 0) end_pos = StringFind(json_str, "}", pos);
      if(end_pos > pos)
         signal.confidence = StringToDouble(StringSubstr(json_str, pos, end_pos - pos));
     }

   signal.timestamp = TimeCurrent();
   return true;
  }

//+------------------------------------------------------------------+
//| Configurar                                                       |
//+------------------------------------------------------------------+
bool CDuarteCommunication::UpdateConfig(const string key, const string value)
  {
   if(!IsConnected())
      return false;

   string message = "{" +
                    CreateJsonInt("type", DUARTE_MESSAGE_CONFIG_UPDATE) + "," +
                    CreateJsonString("timestamp", GetCurrentTimestamp()) + "," +
                    CreateJsonString("key", key) + "," +
                    CreateJsonString("value", value) +
                    "}";

   return WriteToOutbox(message);
  }

//+------------------------------------------------------------------+
//| Enviar heartbeat                                                 |
//+------------------------------------------------------------------+
void CDuarteCommunication::SendHeartbeat()
  {
   if(IsConnected())
     {
      SendStatusUpdate("HEARTBEAT", "System alive");
      m_last_heartbeat = TimeCurrent();
     }
  }

//+------------------------------------------------------------------+
//| Verificar conexão                                                |
//+------------------------------------------------------------------+
bool CDuarteCommunication::CheckConnection()
  {
   if(!IsConnected())
      return false;

   // Verificar timeout do heartbeat
   if(TimeCurrent() - m_last_heartbeat > 60)
     {
      LogMessage("Connection timeout - no heartbeat", true);
      m_status = DUARTE_COMM_ERROR;
      return false;
     }

   return true;
  }

//+------------------------------------------------------------------+
//| Reset da conexão                                                 |
//+------------------------------------------------------------------+
void CDuarteCommunication::ResetConnection()
  {
   LogMessage("Resetting connection");
   Shutdown();
   Sleep(1000);
   Initialize();
  }

//+------------------------------------------------------------------+
//| Obter estatísticas                                               |
//+------------------------------------------------------------------+
void CDuarteCommunication::GetStatistics(ulong& sent, ulong& received, ulong& errors)
  {
   sent = m_messages_sent;
   received = m_messages_received;
   errors = m_errors_count;
  }

//+------------------------------------------------------------------+
//| Relatório de status                                              |
//+------------------------------------------------------------------+
string CDuarteCommunication::GetStatusReport()
  {
   string status_text;
   switch(m_status)
     {
      case DUARTE_COMM_DISCONNECTED: status_text = "DISCONNECTED"; break;
      case DUARTE_COMM_CONNECTING: status_text = "CONNECTING"; break;
      case DUARTE_COMM_CONNECTED: status_text = "CONNECTED"; break;
      case DUARTE_COMM_ERROR: status_text = "ERROR"; break;
      default: status_text = "UNKNOWN";
     }

   return StringFormat(
             "Communication Status: %s\n" +
             "Messages Sent: %d\n" +
             "Messages Received: %d\n" +
             "Errors: %d\n" +
             "Last Heartbeat: %s",
             status_text,
             m_messages_sent,
             m_messages_received,
             m_errors_count,
             TimeToString(m_last_heartbeat)
          );
  }

//+------------------------------------------------------------------+
//| Log de mensagem                                                  |
//+------------------------------------------------------------------+
void CDuarteCommunication::LogMessage(const string message, bool is_error = false)
  {
   string prefix = is_error ? "[ERROR] " : "[INFO] ";
   string full_message = prefix + "DuarteComm: " + message;

   if(is_error || m_debug_mode)
      Print(full_message);
  }

//+------------------------------------------------------------------+
//| Timestamp atual                                                  |
//+------------------------------------------------------------------+
string CDuarteCommunication::GetCurrentTimestamp()
  {
   return TimeToString(TimeCurrent(), TIME_DATE | TIME_SECONDS);
  }

//+------------------------------------------------------------------+
//| Escape JSON                                                      |
//+------------------------------------------------------------------+
static string CDuarteCommunication::JsonEscape(const string text)
  {
   string result = text;
   StringReplace(result, "\\", "\\\\");
   StringReplace(result, "\"", "\\\"");
   StringReplace(result, "\n", "\\n");
   StringReplace(result, "\r", "\\r");
   StringReplace(result, "\t", "\\t");
   return result;
  }

//+------------------------------------------------------------------+
//| Normalizar preço                                                 |
//+------------------------------------------------------------------+
static double CDuarteCommunication::NormalizePrice(double price, int digits)
  {
   return NormalizeDouble(price, digits);
  }

//+------------------------------------------------------------------+
//| Criar JSON string                                                |
//+------------------------------------------------------------------+
string CDuarteCommunication::CreateJsonString(const string key, const string value)
  {
   return "\"" + key + "\":\"" + JsonEscape(value) + "\"";
  }

//+------------------------------------------------------------------+
//| Criar JSON int                                                   |
//+------------------------------------------------------------------+
string CDuarteCommunication::CreateJsonInt(const string key, long value)
  {
   return "\"" + key + "\":" + IntegerToString(value);
  }

//+------------------------------------------------------------------+
//| Criar JSON double                                                |
//+------------------------------------------------------------------+
string CDuarteCommunication::CreateJsonDouble(const string key, double value)
  {
   return "\"" + key + "\":" + DoubleToString(value, 8);
  }

//+------------------------------------------------------------------+
//| Classe auxiliar para envio de dados                              |
//+------------------------------------------------------------------+
class CDuarteDataSender
  {
private:
   CDuarteCommunication* m_comm;
   string            m_symbol;
   datetime          m_last_tick_time;

public:
                     CDuarteDataSender(CDuarteCommunication* comm, const string symbol)
     {
      m_comm = comm;
      m_symbol = symbol;
      m_last_tick_time = 0;
     }

   bool              SendCurrentTick()
     {
      MqlTick tick;
      if(!SymbolInfoTick(m_symbol, tick))
         return false;

      // Evitar ticks duplicados
      if(tick.time <= m_last_tick_time)
         return true;

      m_last_tick_time = tick.time;

      // Converter para DuarteTickData
      DuarteTickData tick_data;
      tick_data.symbol = m_symbol;
      tick_data.time = tick.time;
      tick_data.bid = tick.bid;
      tick_data.ask = tick.ask;
      tick_data.last = tick.last;
      tick_data.volume = tick.volume;
      tick_data.spread = tick.ask - tick.bid;

      // Calcular direção
      static double last_price = 0;
      if(last_price > 0)
        {
         if(tick.last > last_price)
            tick_data.direction = 1;
         else if(tick.last < last_price)
            tick_data.direction = -1;
         else
            tick_data.direction = 0;
        }
      else
         tick_data.direction = 0;

      last_price = tick.last;

      return m_comm.SendTickData(tick_data);
     }

   bool              RequestTradeSignal(DuarteSignalData& signal)
     {
      return m_comm.RequestSignal(m_symbol, signal);
     }
  };

//+------------------------------------------------------------------+