//+------------------------------------------------------------------+
//|                                               Communication.mqh |
//|                                  Copyright 2024, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property version   "1.00"

//+------------------------------------------------------------------+
//| Includes e importações                                           |
//+------------------------------------------------------------------+
#include <Files\FilePipe.h>
#include <JAson.mqh>

//+------------------------------------------------------------------+
//| Definições e constantes                                          |
//+------------------------------------------------------------------+
#define PIPE_NAME "\\\\.\\pipe\\duarte_scalper"
#define BUFFER_SIZE 2048
#define TIMEOUT_MS 1000

// Tipos de mensagem
enum ENUM_MESSAGE_TYPE
  {
   MESSAGE_TICK_DATA = 1,
   MESSAGE_SIGNAL_REQUEST = 2,
   MESSAGE_SIGNAL_RESPONSE = 3,
   MESSAGE_ORDER_REQUEST = 4,
   MESSAGE_ORDER_RESPONSE = 5,
   MESSAGE_STATUS_UPDATE = 6,
   MESSAGE_CONFIG_UPDATE = 7,
   MESSAGE_ERROR = 99
  };

// Status da comunicação
enum ENUM_COMM_STATUS
  {
   COMM_DISCONNECTED = 0,
   COMM_CONNECTING = 1,
   COMM_CONNECTED = 2,
   COMM_ERROR = 3
  };

//+------------------------------------------------------------------+
//| Estrutura para dados de tick                                     |
//+------------------------------------------------------------------+
struct TickData
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

//+------------------------------------------------------------------+
//| Estrutura para sinal de entrada                                  |
//+------------------------------------------------------------------+
struct SignalData
  {
   string            symbol;
   int               direction;        // 1=BUY, -1=SELL, 0=HOLD
   double            confidence;    // 0.0 - 1.0
   double            expected_move; // Expected price movement
   int               time_horizon;     // Time horizon in seconds
   datetime          timestamp;
  };

//+------------------------------------------------------------------+
//| Estrutura para ordem                                             |
//+------------------------------------------------------------------+
struct OrderData
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
   CFilePipe*        m_pipe;
   ENUM_COMM_STATUS  m_status;
   string            m_pipe_name;
   datetime          m_last_heartbeat;
   int               m_connection_attempts;
   bool              m_debug_mode;

   // Buffers
   string            m_send_buffer;
   string            m_receive_buffer;

   // Estatísticas
   ulong             m_messages_sent;
   ulong             m_messages_received;
   ulong             m_errors_count;

   // Métodos privados
   bool              CreatePipe();
   bool              ConnectToPipe();
   void              ClosePipe();
   string            FormatTickMessage(const TickData& tick);
   string            FormatSignalRequest(const string& symbol);
   bool              ParseSignalResponse(const string& json, SignalData& signal);
   bool              ParseOrderResponse(const string& json);
   void              LogMessage(const string& message, bool is_error = false);
   string            GetCurrentTimestamp();

public:
   // Construtor e destrutor
                     CDuarteCommunication();
                    ~CDuarteCommunication();

   // Métodos públicos
   bool              Initialize(const string& pipe_name = PIPE_NAME);
   void              Shutdown();
   bool              IsConnected() { return m_status == COMM_CONNECTED; }
   ENUM_COMM_STATUS  GetStatus() { return m_status; }

   // Comunicação principal
   bool              SendTickData(const TickData& tick);
   bool              RequestSignal(const string& symbol, SignalData& signal);
   bool              SendOrderRequest(const OrderData& order);
   bool              SendStatusUpdate(const string& status, const string& details = "");

   // Configuração
   void              SetDebugMode(bool enabled) { m_debug_mode = enabled; }
   bool              UpdateConfig(const string& key, const string& value);

   // Heartbeat e manutenção
   void              SendHeartbeat();
   bool              CheckConnection();
   void              ResetConnection();

   // Estatísticas
   void              GetStatistics(ulong& sent, ulong& received, ulong& errors);
   string            GetStatusReport();

   // Utilitários
   static string     JsonEscape(const string& text);
   static double     NormalizePrice(double price, int digits);
  };

//+------------------------------------------------------------------+
//| Construtor                                                       |
//+------------------------------------------------------------------+
CDuarteCommunication::CDuarteCommunication()
  {
   m_pipe = NULL;
   m_status = COMM_DISCONNECTED;
   m_pipe_name = PIPE_NAME;
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
//| Inicializa a comunicação                                         |
//+------------------------------------------------------------------+
bool CDuarteCommunication::Initialize(const string& pipe_name = PIPE_NAME)
  {
   if(m_status == COMM_CONNECTED)
     {
      LogMessage("Communication already initialized");
      return true;
     }

   m_pipe_name = pipe_name;
   m_status = COMM_CONNECTING;

   LogMessage("Initializing communication with pipe: " + m_pipe_name);

// Criar pipe
   if(!CreatePipe())
     {
      LogMessage("Failed to create pipe", true);
      m_status = COMM_ERROR;
      return false;
     }

// Tentar conectar
   for(int i = 0; i < 5; i++)
     {
      if(ConnectToPipe())
        {
         m_status = COMM_CONNECTED;
         m_last_heartbeat = TimeCurrent();
         LogMessage("Communication initialized successfully");
         return true;
        }

      Sleep(1000); // Aguardar 1 segundo entre tentativas
      m_connection_attempts++;
     }

   m_status = COMM_ERROR;
   LogMessage("Failed to connect after 5 attempts", true);
   return false;
  }

//+------------------------------------------------------------------+
//| Finaliza a comunicação                                           |
//+------------------------------------------------------------------+
void CDuarteCommunication::Shutdown()
  {
   if(m_status != COMM_DISCONNECTED)
     {
      LogMessage("Shutting down communication");
      ClosePipe();
      m_status = COMM_DISCONNECTED;
     }
  }

//+------------------------------------------------------------------+
//| Cria o pipe                                                      |
//+------------------------------------------------------------------+
bool CDuarteCommunication::CreatePipe()
  {
   if(m_pipe != NULL)
     {
      delete m_pipe;
      m_pipe = NULL;
     }

   m_pipe = new CFilePipe();
   if(m_pipe == NULL)
     {
      LogMessage("Failed to create pipe object", true);
      return false;
     }

   return true;
  }

//+------------------------------------------------------------------+
//| Conecta ao pipe                                                  |
//+------------------------------------------------------------------+
bool CDuarteCommunication::ConnectToPipe()
  {
   if(m_pipe == NULL)
      return false;

// Tentar abrir pipe existente primeiro (cliente)
   if(m_pipe.Open(m_pipe_name, FILE_READ | FILE_WRITE | FILE_BIN))
     {
      LogMessage("Connected to existing pipe");
      return true;
     }

// Se não conseguir, criar novo pipe (servidor)
   if(m_pipe.Open(m_pipe_name, FILE_WRITE | FILE_READ | FILE_BIN | FILE_PIPE))
     {
      LogMessage("Created new pipe");
      return true;
     }

   LogMessage("Failed to open pipe: " + IntegerToString(GetLastError()), true);
   return false;
  }

//+------------------------------------------------------------------+
//| Fecha o pipe                                                     |
//+------------------------------------------------------------------+
void CDuarteCommunication::ClosePipe()
  {
   if(m_pipe != NULL)
     {
      m_pipe.Close();
      delete m_pipe;
      m_pipe = NULL;
     }
  }

//+------------------------------------------------------------------+
//| Envia dados de tick                                              |
//+------------------------------------------------------------------+
bool CDuarteCommunication::SendTickData(const TickData& tick)
  {
   if(!IsConnected())
      return false;

   string message = FormatTickMessage(tick);

// Escrever no pipe
   uint bytes_written = m_pipe.WriteString(message);
   if(bytes_written > 0)
     {
      m_messages_sent++;
      if(m_debug_mode)
         LogMessage("Tick data sent: " + tick.symbol);
      return true;
     }
   else
     {
      m_errors_count++;
      LogMessage("Failed to send tick data for " + tick.symbol, true);
      return false;
     }
  }

//+------------------------------------------------------------------+
//| Solicita sinal para um símbolo                                   |
//+------------------------------------------------------------------+
bool CDuarteCommunication::RequestSignal(const string& symbol, SignalData& signal)
  {
   if(!IsConnected())
      return false;

// Enviar solicitação
   string request = FormatSignalRequest(symbol);
   uint bytes_written = m_pipe.WriteString(request);

   if(bytes_written == 0)
     {
      m_errors_count++;
      LogMessage("Failed to send signal request for " + symbol, true);
      return false;
     }

// Aguardar resposta
   Sleep(100); // Pequena pausa para resposta

   string response;
   uint bytes_read = m_pipe.ReadString(response);

   if(bytes_read > 0)
     {
      m_messages_received++;
      if(ParseSignalResponse(response, signal))
        {
         if(m_debug_mode)
            LogMessage("Signal received for " + symbol + ": " + IntegerToString(signal.direction));
         return true;
        }
     }

   m_errors_count++;
   LogMessage("Failed to receive signal for " + symbol, true);
   return false;
  }

//+------------------------------------------------------------------+
//| Envia solicitação de ordem                                       |
//+------------------------------------------------------------------+
bool CDuarteCommunication::SendOrderRequest(const OrderData& order)
  {
   if(!IsConnected())
      return false;

// Construir JSON da ordem
   CJAVal json;
   json["type"] = MESSAGE_ORDER_REQUEST;
   json["timestamp"] = GetCurrentTimestamp();
   json["symbol"] = order.symbol;
   json["operation"] = order.operation;
   json["volume"] = order.volume;
   json["price"] = order.price;
   json["sl"] = order.sl;
   json["tp"] = order.tp;
   json["comment"] = order.comment;
   json["magic"] = (long)order.magic;

   string message = json.Serialize();
   uint bytes_written = m_pipe.WriteString(message);

   if(bytes_written > 0)
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
//| Envia atualização de status                                      |
//+------------------------------------------------------------------+
bool CDuarteCommunication::SendStatusUpdate(const string& status, const string& details = "")
  {
   if(!IsConnected())
      return false;

   CJAVal json;
   json["type"] = MESSAGE_STATUS_UPDATE;
   json["timestamp"] = GetCurrentTimestamp();
   json["status"] = status;
   json["details"] = details;
   json["expert_id"] = "DUARTE-SCALPER";

   string message = json.Serialize();
   uint bytes_written = m_pipe.WriteString(message);

   if(bytes_written > 0)
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
//| Formata mensagem de tick                                         |
//+------------------------------------------------------------------+
string CDuarteCommunication::FormatTickMessage(const TickData& tick)
  {
   CJAVal json;
   json["type"] = MESSAGE_TICK_DATA;
   json["timestamp"] = GetCurrentTimestamp();
   json["symbol"] = tick.symbol;
   json["time"] = (long)tick.time;
   json["bid"] = tick.bid;
   json["ask"] = tick.ask;
   json["last"] = tick.last;
   json["volume"] = (long)tick.volume;
   json["spread"] = tick.spread;
   json["direction"] = tick.direction;

   return json.Serialize();
  }

//+------------------------------------------------------------------+
//| Formata solicitação de sinal                                     |
//+------------------------------------------------------------------+
string CDuarteCommunication::FormatSignalRequest(const string& symbol)
  {
   CJAVal json;
   json["type"] = MESSAGE_SIGNAL_REQUEST;
   json["timestamp"] = GetCurrentTimestamp();
   json["symbol"] = symbol;
   json["request_id"] = GetTickCount();

   return json.Serialize();
  }

//+------------------------------------------------------------------+
//| Parse resposta de sinal                                          |
//+------------------------------------------------------------------+
bool CDuarteCommunication::ParseSignalResponse(const string& json_str, SignalData& signal)
  {
   CJAVal json;
   if(!json.Deserialize(json_str))
     {
      LogMessage("Failed to parse signal response JSON", true);
      return false;
     }

// Verificar tipo de mensagem
   if(json["type"].ToInt() != MESSAGE_SIGNAL_RESPONSE)
     {
      LogMessage("Invalid message type in signal response", true);
      return false;
     }

// Extrair dados do sinal
   signal.symbol = json["symbol"].ToStr();
   signal.direction = json["direction"].ToInt();
   signal.confidence = json["confidence"].ToDbl();
   signal.expected_move = json["expected_move"].ToDbl();
   signal.time_horizon = json["time_horizon"].ToInt();
   signal.timestamp = TimeCurrent();

   return true;
  }

//+------------------------------------------------------------------+
//| Atualiza configuração                                            |
//+------------------------------------------------------------------+
bool CDuarteCommunication::UpdateConfig(const string& key, const string& value)
  {
   if(!IsConnected())
      return false;

   CJAVal json;
   json["type"] = MESSAGE_CONFIG_UPDATE;
   json["timestamp"] = GetCurrentTimestamp();
   json["key"] = key;
   json["value"] = value;

   string message = json.Serialize();
   uint bytes_written = m_pipe.WriteString(message);

   if(bytes_written > 0)
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

// Verificar se heartbeat não está muito antigo
   if(TimeCurrent() - m_last_heartbeat > 60) // 60 segundos sem heartbeat
     {
      LogMessage("Connection timeout - no heartbeat", true);
      m_status = COMM_ERROR;
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
   Initialize(m_pipe_name);
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
//| Gerar relatório de status                                        |
//+------------------------------------------------------------------+
string CDuarteCommunication::GetStatusReport()
  {
   string status_text;

   switch(m_status)
     {
      case COMM_DISCONNECTED:
         status_text = "DISCONNECTED";
         break;
      case COMM_CONNECTING:
         status_text = "CONNECTING";
         break;
      case COMM_CONNECTED:
         status_text = "CONNECTED";
         break;
      case COMM_ERROR:
         status_text = "ERROR";
         break;
      default:
         status_text = "UNKNOWN";
     }

   string report = StringFormat(
                      "Communication Status: %s\n" +
                      "Messages Sent: %d\n" +
                      "Messages Received: %d\n" +
                      "Errors: %d\n" +
                      "Last Heartbeat: %s\n" +
                      "Connection Attempts: %d",
                      status_text,
                      m_messages_sent,
                      m_messages_received,
                      m_errors_count,
                      TimeToString(m_last_heartbeat),
                      m_connection_attempts
                   );

   return report;
  }

//+------------------------------------------------------------------+
//| Log de mensagem                                                  |
//+------------------------------------------------------------------+
void CDuarteCommunication::LogMessage(const string& message, bool is_error = false)
  {
   string prefix = is_error ? "[ERROR] " : "[INFO] ";
   string full_message = prefix + "DuarteComm: " + message;

   if(is_error)
      Print(full_message);
   else
      if(m_debug_mode)
         Print(full_message);
  }

//+------------------------------------------------------------------+
//| Obter timestamp atual                                            |
//+------------------------------------------------------------------+
string CDuarteCommunication::GetCurrentTimestamp()
  {
   return TimeToString(TimeCurrent(), TIME_DATE | TIME_SECONDS) + "." +
          IntegerToString(GetMicrosecondCount() % 1000, 3, '0');
  }

//+------------------------------------------------------------------+
//| Escape de caracteres JSON                                        |
//+------------------------------------------------------------------+
static string CDuarteCommunication::JsonEscape(const string& text)
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
//| Classe para facilitar envio de dados                             |
//+------------------------------------------------------------------+
class CDuarteDataSender
  {
private:
   CDuarteCommunication* m_comm;
   string            m_symbol;
   datetime          m_last_tick_time;

public:
                     CDuarteDataSender(CDuarteCommunication* comm, const string& symbol)
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

      // Evitar envio de ticks duplicados
      if(tick.time == m_last_tick_time)
         return true;

      m_last_tick_time = tick.time;

      // Converter para estrutura TickData
      TickData tick_data;
      tick_data.symbol = m_symbol;
      tick_data.time = tick.time;
      tick_data.bid = tick.bid;
      tick_data.ask = tick.ask;
      tick_data.last = tick.last;
      tick_data.volume = tick.volume;
      tick_data.spread = tick.ask - tick.bid;

      // Calcular direção (simplificado)
      static double last_price = 0;
      if(last_price > 0)
        {
         if(tick.last > last_price)
            tick_data.direction = 1;
         else
            if(tick.last < last_price)
               tick_data.direction = -1;
            else
               tick_data.direction = 0;
        }
      else
         tick_data.direction = 0;

      last_price = tick.last;

      return m_comm.SendTickData(tick_data);
     }

   bool              RequestTradeSignal(SignalData& signal)
     {
      return m_comm.RequestSignal(m_symbol, signal);
     }
  };

//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
