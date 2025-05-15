import MetaTrader5 as mt5
import pandas as pd
from datetime import datetime, timedelta

def test_mt5_connection():
    """Teste de conexão e funcionalidades básicas do MT5"""
    
    print("=== TESTE DE CONEXÃO MT5 ===")
    
    # 1. Inicializar MT5
    if not mt5.initialize():
        print("❌ Falha ao inicializar MT5")
        print("Erro:", mt5.last_error())
        return False
    
    print("✅ MT5 inicializado com sucesso")
    
    # 2. Informações da conta
    account_info = mt5.account_info()
    if account_info:
        print(f"✅ Conta: {account_info.login}")
        print(f"✅ Servidor: {account_info.server}")
        print(f"✅ Saldo: {account_info.balance}")
    else:
        print("❌ Erro ao obter informações da conta")
    
    # 3. Testar símbolos
    symbols_to_test = ["WINM25", "WDOM25"]
    
    for symbol in symbols_to_test:
        # Verificar se símbolo existe
        symbol_info = mt5.symbol_info(symbol)
        if symbol_info:
            print(f"✅ Símbolo {symbol} encontrado")
            
            # Obter último tick
            tick = mt5.symbol_info_tick(symbol)
            if tick:
                print(f"  - Bid: {tick.bid}, Ask: {tick.ask}")
                print(f"  - Spread: {tick.ask - tick.bid}")
            
            # Testar dados históricos
            rates = mt5.copy_rates_from_pos(symbol, mt5.TIMEFRAME_M1, 0, 10)
            if rates is not None and len(rates) > 0:
                print(f"  - ✅ Dados históricos obtidos: {len(rates)} barras")
            else:
                print(f"  - ❌ Erro ao obter dados históricos")
        else:
            print(f"❌ Símbolo {symbol} não encontrado")
            # Tentar symbol + extensão
            extended_symbols = [f"{symbol}.SIR", f"{symbol}.BMF", f"{symbol}.WDO"]
            for ext_symbol in extended_symbols:
                if mt5.symbol_info(ext_symbol):
                    print(f"  → Encontrado como: {ext_symbol}")
                    break
    
    # 4. Testar coleta de ticks
    print("\n=== TESTE DE COLETA DE TICKS ===")
    if symbols_to_test:
        symbol = symbols_to_test[0]
        print(f"Coletando ticks de {symbol}...")
        
        # Método alternativo: usar copy_rates para teste inicial
        try:
            # Primeiro, vamos testar com rates (mais confiável)
            rates = mt5.copy_rates_from_pos(symbol, mt5.TIMEFRAME_M1, 0, 10)
            if rates is not None and len(rates) > 0:
                print(f"✅ Obtidos {len(rates)} candles de 1 minuto")
                df_rates = pd.DataFrame(rates)
                df_rates['time'] = pd.to_datetime(df_rates['time'], unit='s')
                print("Últimos 3 candles:")
                print(df_rates[['time', 'open', 'high', 'low', 'close', 'tick_volume']].tail(3))
                
                # Tentar coleta de ticks com método mais simples
                print("\nTentando coleta de ticks...")
                import time
                current_time = int(time.time())
                utc_from = current_time - 3600  # 1 hora atrás
                utc_to = current_time
                
                ticks = mt5.copy_ticks_from(symbol, utc_from, utc_to, mt5.COPY_TICKS_ALL)
                if ticks is not None and len(ticks) > 0:
                    print(f"✅ Coletados {len(ticks)} ticks da última hora")
                    # Mostrar alguns ticks
                    df_ticks = pd.DataFrame(ticks)
                    print(f"Exemplo de ticks:")
                    print(df_ticks[['time', 'bid', 'ask', 'last']].head(3))
                else:
                    print("⚠️  Ticks não disponíveis, mas rates funcionam")
            else:
                print(f"❌ Erro ao coletar dados de {symbol}")
        except Exception as e:
            print(f"⚠️  Erro na coleta: {e}")
            print("Isso é normal em alguns brokers - o importante é que rates funcionam")
    
    # 5. Finalizar
    mt5.shutdown()
    print("\n✅ Teste concluído - MT5 desconectado")
    return True

def check_python_packages():
    """Verificar se todos os pacotes necessários estão instalados"""
    
    print("\n=== VERIFICAÇÃO DE PACOTES PYTHON ===")
    
    required_packages = {
        'numpy': 'Manipulação de arrays',
        'pandas': 'Análise de dados',
        'sklearn': 'Machine Learning',
        'xgboost': 'Gradient Boosting',
        'matplotlib': 'Visualização',
        'MetaTrader5': 'Conexão MT5'
    }
    
    optional_packages = {
        'tensorflow': 'Deep Learning (opcional por agora)'
    }
    
    # Verificar pacotes obrigatórios
    for package, description in required_packages.items():
        try:
            if package == 'sklearn':
                import sklearn
            else:
                __import__(package)
            print(f"✅ {package} - {description}")
        except ImportError:
            print(f"❌ {package} - NÃO INSTALADO - {description}")
    
    # Verificar pacotes opcionais
    for package, description in optional_packages.items():
        try:
            __import__(package)
            print(f"✅ {package} - {description}")
        except ImportError:
            print(f"⚠️  {package} - NÃO INSTALADO - {description}")
    
    print("\n=== VERSÕES DOS PACOTES ===")
    try:
        import numpy as np
        import pandas as pd
        import sklearn
        import xgboost as xgb
        
        print(f"NumPy: {np.__version__}")
        print(f"Pandas: {pd.__version__}")
        print(f"Scikit-learn: {sklearn.__version__}")
        print(f"XGBoost: {xgb.__version__}")
        
        # TensorFlow opcional
        try:
            import tensorflow as tf
            print(f"TensorFlow: {tf.__version__} ✅")
        except ImportError:
            print(f"TensorFlow: NÃO INSTALADO (pode instalar depois) ⚠️")
            
    except Exception as e:
        print(f"Erro ao verificar versões: {e}")

if __name__ == "__main__":
    # Verificar pacotes primeiro
    check_python_packages()
    
    # Testar conexão MT5
    test_mt5_connection()
    
    print("\n=== PRÓXIMOS PASSOS ===")
    print("1. Corrigir erros encontrados (se houver)")
    print("2. Verificar símbolos não encontrados na sua corretora")
    print("3. Prosseguir para criação da estrutura de diretórios")