"""
DUARTE-SCALPER: Coletor de Dados Históricos
Responsável por baixar e processar dados históricos do MT5
"""

import sys
sys.path.append(r'C:\DuarteScalper\src')

import MetaTrader5 as mt5
import pandas as pd
import numpy as np
from datetime import datetime, timedelta
import time
import os
import logging
from pathlib import Path
import pyarrow as pa
import pyarrow.parquet as pq

from python.utils.config_manager import ConfigManager

class HistoricalDataCollector:
    """
    Coletor de dados históricos com otimizações para scalping
    """
    
    def __init__(self, config_path: str = None):
        """
        Inicializa o coletor histórico
        
        Args:
            config_path: Caminho para arquivo de configuração
        """
        # Carregar configuração
        self.config = ConfigManager(config_path)
        
        # Setup logging
        self.setup_logging()
        
        # Paths para dados
        self.raw_historical_path = Path(self.config.get('paths.data.raw_historical'))
        self.raw_historical_path.mkdir(parents=True, exist_ok=True)
        
        # Estado da conexão MT5
        self.mt5_initialized = False
        
        # Símbolos para coleta
        self.symbols = self.config.get('trading.symbols', ['WINM25', 'WDOM25'])
        
        # Períodos para coleta  
        self.collection_months = self.config.get('data_collection.historical_months', 6)
        
        self.logger.info("HistoricalDataCollector inicializado")
    
    def setup_logging(self):
        """Configura logging específico para coleta histórica"""
        log_path = Path(self.config.get('paths.logs')) / 'historical_collection.log'
        log_path.parent.mkdir(parents=True, exist_ok=True)
        
        self.logger = logging.getLogger('HistoricalCollector')
        self.logger.setLevel(logging.INFO)
        
        # File handler
        file_handler = logging.FileHandler(log_path)
        file_handler.setLevel(logging.INFO)
        
        # Console handler
        console_handler = logging.StreamHandler()
        console_handler.setLevel(logging.INFO)
        
        # Formatter
        formatter = logging.Formatter(
            '%(asctime)s - %(name)s - %(levelname)s - %(message)s'
        )
        file_handler.setFormatter(formatter)
        console_handler.setFormatter(formatter)
        
        self.logger.addHandler(file_handler)
        self.logger.addHandler(console_handler)
    
    def initialize_mt5(self) -> bool:
        """
        Inicializa conexão com MT5
        
        Returns:
            bool: True se sucesso, False caso contrário
        """
        if self.mt5_initialized:
            return True
            
        # Tentar conectar MT5
        if not mt5.initialize():
            self.logger.error(f"MT5 initialization failed: {mt5.last_error()}")
            return False
        
        # Verificar conexão
        terminal_info = mt5.terminal_info()
        if terminal_info is None:
            self.logger.error("Failed to get terminal info")
            return False
        
        self.logger.info(f"MT5 conectado: {terminal_info.name} v{terminal_info.build}")
        self.mt5_initialized = True
        return True
    
    def get_symbol_info(self, symbol: str) -> dict:
        """
        Obtém informações sobre o símbolo
        
        Args:
            symbol: Nome do símbolo
            
        Returns:
            dict: Informações do símbolo
        """
        symbol_info = mt5.symbol_info(symbol)
        if symbol_info is None:
            self.logger.error(f"Symbol {symbol} not found")
            return None
        
        return {
            'symbol': symbol,
            'point': symbol_info.point,
            'digits': symbol_info.digits,
            'tick_size': symbol_info.trade_tick_size,
            'contract_size': symbol_info.trade_contract_size,
            'margin_initial': symbol_info.margin_initial,
            'currency_base': symbol_info.currency_base,
            'currency_profit': symbol_info.currency_profit,
            'currency_margin': symbol_info.currency_margin
        }
    
    def calculate_date_range(self, months: int = None) -> tuple:
        """
        Calcula range de datas para coleta
        
        Args:
            months: Número de meses para coletar
            
        Returns:
            tuple: (date_from, date_to)
        """
        if months is None:
            months = self.collection_months
        
        # Data final = hoje
        date_to = datetime.now()
        
        # Data inicial = X meses atrás
        date_from = date_to - timedelta(days=months * 30)
        
        # Ajustar para horário de mercado (09:00 BRT)
        date_from = date_from.replace(hour=9, minute=0, second=0, microsecond=0)
        date_to = date_to.replace(hour=23, minute=59, second=59, microsecond=0)
        
        self.logger.info(f"Date range: {date_from} to {date_to}")
        return date_from, date_to
    
    def collect_historical_ticks(self, symbol: str, date_from: datetime, 
                                date_to: datetime, chunk_hours: int = 24) -> bool:
        """
        Coleta dados tick históricos em chunks
        
        Args:
            symbol: Símbolo para coletar
            date_from: Data inicial
            date_to: Data final  
            chunk_hours: Horas por chunk para evitar timeout
            
        Returns:
            bool: True se sucesso
        """
        self.logger.info(f"Starting tick collection for {symbol}")
        
        # Arquivo de saída
        output_file = self.raw_historical_path / f"{symbol}_ticks_historical.parquet"
        
        all_ticks = []
        current_date = date_from
        total_ticks = 0
        
        while current_date < date_to:
            # Data final do chunk
            chunk_end = min(current_date + timedelta(hours=chunk_hours), date_to)
            
            self.logger.info(f"Collecting ticks from {current_date} to {chunk_end}")
            
            # Tentar várias vezes em caso de erro
            for attempt in range(3):
                try:
                    # Coletar ticks do período
                    ticks = mt5.copy_ticks_range(
                        symbol, 
                        current_date, 
                        chunk_end, 
                        mt5.COPY_TICKS_ALL
                    )
                    
                    if ticks is None:
                        self.logger.warning(f"No ticks returned for {current_date}")
                        break
                    
                    # Converter para DataFrame
                    ticks_df = pd.DataFrame(ticks)
                    
                    # Adicionar informações
                    ticks_df['time'] = pd.to_datetime(ticks_df['time'], unit='s')
                    ticks_df['symbol'] = symbol
                    
                    # Calcular direção do tick
                    ticks_df['direction'] = self._calculate_tick_direction(ticks_df)
                    
                    # Adicionar spread
                    ticks_df['spread'] = ticks_df['ask'] - ticks_df['bid']
                    
                    all_ticks.append(ticks_df)
                    total_ticks += len(ticks_df)
                    
                    self.logger.info(f"Collected {len(ticks_df)} ticks. Total: {total_ticks}")
                    break
                    
                except Exception as e:
                    self.logger.error(f"Attempt {attempt+1} failed: {e}")
                    if attempt == 2:
                        self.logger.error(f"Failed to collect chunk {current_date}")
                        return False
                    time.sleep(5)
            
            current_date = chunk_end
            time.sleep(1)  # Rate limiting
        
        # Consolidar todos os chunks
        if all_ticks:
            self.logger.info("Consolidating tick data...")
            final_df = pd.concat(all_ticks, ignore_index=True)
            
            # Remover duplicatas e ordenar
            final_df = final_df.drop_duplicates(['time', 'bid', 'ask'])
            final_df = final_df.sort_values('time').reset_index(drop=True)
            
            # Salvar em Parquet
            self._save_to_parquet(final_df, output_file)
            
            self.logger.info(f"Tick collection completed: {len(final_df)} ticks saved")
            return True
        else:
            self.logger.error("No ticks collected")
            return False
    
    def collect_historical_ohlc(self, symbol: str, date_from: datetime, 
                               date_to: datetime, timeframe=mt5.TIMEFRAME_M1) -> bool:
        """
        Coleta dados OHLC históricos
        
        Args:
            symbol: Símbolo para coletar
            date_from: Data inicial
            date_to: Data final
            timeframe: Timeframe (padrão M1)
            
        Returns:
            bool: True se sucesso
        """
        self.logger.info(f"Starting OHLC collection for {symbol}")
        
        # Arquivo de saída
        timeframe_str = self._timeframe_to_string(timeframe)
        output_file = self.raw_historical_path / f"{symbol}_ohlc_{timeframe_str}_historical.parquet"
        
        # Tentar várias vezes
        for attempt in range(3):
            try:
                # Coletar dados OHLC
                rates = mt5.copy_rates_range(symbol, timeframe, date_from, date_to)
                
                if rates is None:
                    self.logger.error(f"No OHLC data returned for {symbol}")
                    return False
                
                # Converter para DataFrame
                rates_df = pd.DataFrame(rates)
                
                # Processar dados
                rates_df['time'] = pd.to_datetime(rates_df['time'], unit='s')
                rates_df['symbol'] = symbol
                rates_df['timeframe'] = timeframe_str
                
                # Calcular indicadores básicos
                rates_df['typical_price'] = (rates_df['high'] + rates_df['low'] + rates_df['close']) / 3
                rates_df['range'] = rates_df['high'] - rates_df['low']
                rates_df['body'] = abs(rates_df['close'] - rates_df['open'])
                rates_df['upper_shadow'] = rates_df['high'] - rates_df[['open', 'close']].max(axis=1)
                rates_df['lower_shadow'] = rates_df[['open', 'close']].min(axis=1) - rates_df['low']
                
                # Verificar qualidade
                if len(rates_df) == 0:
                    self.logger.error("Empty OHLC dataset")
                    return False
                
                # Salvar em Parquet
                self._save_to_parquet(rates_df, output_file)
                
                self.logger.info(f"OHLC collection completed: {len(rates_df)} bars saved")
                return True
                
            except Exception as e:
                self.logger.error(f"OHLC collection attempt {attempt+1} failed: {e}")
                if attempt == 2:
                    return False
                time.sleep(5)
    
    def _calculate_tick_direction(self, ticks_df: pd.DataFrame) -> pd.Series:
        """
        Calcula direção dos ticks (uptick/downtick)
        
        Args:
            ticks_df: DataFrame com dados tick
            
        Returns:
            pd.Series: Direção dos ticks (1=up, -1=down, 0=neutral)
        """
        # Usar preço 'last' para determinar direção
        if 'last' not in ticks_df.columns:
            # Se não tiver 'last', calcular mid price
            ticks_df['last'] = (ticks_df['bid'] + ticks_df['ask']) / 2
        
        # Calcular diferença de preços
        price_diff = ticks_df['last'].diff()
        
        # Definir direção
        direction = pd.Series(0, index=ticks_df.index)
        direction[price_diff > 0] = 1   # Uptick
        direction[price_diff < 0] = -1  # Downtick
        
        # Primeiro tick sempre neutro
        direction.iloc[0] = 0
        
        return direction
    
    def _timeframe_to_string(self, timeframe) -> str:
        """Converte timeframe MT5 para string"""
        timeframe_map = {
            mt5.TIMEFRAME_M1: "M1",
            mt5.TIMEFRAME_M5: "M5", 
            mt5.TIMEFRAME_M15: "M15",
            mt5.TIMEFRAME_M30: "M30",
            mt5.TIMEFRAME_H1: "H1",
            mt5.TIMEFRAME_H4: "H4",
            mt5.TIMEFRAME_D1: "D1"
        }
        return timeframe_map.get(timeframe, "M1")
    
    def _save_to_parquet(self, df: pd.DataFrame, file_path: Path):
        """
        Salva DataFrame em formato Parquet otimizado
        
        Args:
            df: DataFrame para salvar
            file_path: Caminho do arquivo
        """
        try:
            # Configurações de compressão
            table = pa.Table.from_pandas(df)
            
            # Salvar com compressão snappy
            pq.write_table(
                table,
                file_path,
                compression='snappy',
                use_dictionary=True,
                row_group_size=50000
            )
            
            file_size = file_path.stat().st_size / (1024*1024)  # MB
            self.logger.info(f"Saved {len(df)} rows to {file_path.name} ({file_size:.2f} MB)")
            
        except Exception as e:
            self.logger.error(f"Error saving to parquet: {e}")
            raise
    
    def collect_all_symbols(self, months: int = None) -> dict:
        """
        Coleta dados históricos para todos os símbolos
        
        Args:
            months: Número de meses para coletar
            
        Returns:
            dict: Status da coleta por símbolo
        """
        if not self.initialize_mt5():
            return {}
        
        # Calcular período
        date_from, date_to = self.calculate_date_range(months)
        
        results = {}
        
        for symbol in self.symbols:
            self.logger.info(f"\n{'='*50}")
            self.logger.info(f"COLLECTING DATA FOR {symbol}")
            self.logger.info(f"{'='*50}")
            
            # Verificar se símbolo existe
            symbol_info = self.get_symbol_info(symbol)
            if symbol_info is None:
                results[symbol] = {'status': 'failed', 'error': 'Symbol not found'}
                continue
            
            self.logger.info(f"Symbol info: {symbol_info}")
            
            # Coletar ticks
            tick_success = self.collect_historical_ticks(symbol, date_from, date_to)
            
            # Coletar OHLC M1
            ohlc_success = self.collect_historical_ohlc(symbol, date_from, date_to)
            
            # Status final
            if tick_success and ohlc_success:
                results[symbol] = {'status': 'success'}
                self.logger.info(f"✅ {symbol} collection completed successfully")
            else:
                results[symbol] = {
                    'status': 'partial',
                    'ticks': tick_success,
                    'ohlc': ohlc_success
                }
                self.logger.warning(f"⚠️  {symbol} collection completed with issues")
        
        # Finalizar MT5
        mt5.shutdown()
        self.mt5_initialized = False
        
        return results
    
    def validate_collected_data(self) -> dict:
        """
        Valida dados coletados
        
        Returns:
            dict: Relatório de validação
        """
        validation_report = {}
        
        for symbol in self.symbols:
            symbol_report = {}
            
            # Verificar arquivos tick
            tick_file = self.raw_historical_path / f"{symbol}_ticks_historical.parquet"
            if tick_file.exists():
                ticks_df = pd.read_parquet(tick_file)
                symbol_report['ticks'] = {
                    'count': len(ticks_df),
                    'date_range': (ticks_df['time'].min(), ticks_df['time'].max()),
                    'file_size_mb': tick_file.stat().st_size / (1024*1024)
                }
            else:
                symbol_report['ticks'] = {'status': 'missing'}
            
            # Verificar arquivos OHLC
            ohlc_file = self.raw_historical_path / f"{symbol}_ohlc_M1_historical.parquet"
            if ohlc_file.exists():
                ohlc_df = pd.read_parquet(ohlc_file)
                symbol_report['ohlc'] = {
                    'count': len(ohlc_df),
                    'date_range': (ohlc_df['time'].min(), ohlc_df['time'].max()),
                    'file_size_mb': ohlc_file.stat().st_size / (1024*1024)
                }
            else:
                symbol_report['ohlc'] = {'status': 'missing'}
            
            validation_report[symbol] = symbol_report
        
        return validation_report
    
    def generate_collection_report(self) -> str:
        """
        Gera relatório detalhado da coleta
        
        Returns:
            str: Relatório formatado
        """
        validation_data = self.validate_collected_data()
        
        report = []
        report.append("📊 DUARTE-SCALPER - HISTÓRICO DE COLETA DE DADOS")
        report.append("="*60)
        report.append(f"Data do relatório: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
        report.append("")
        
        for symbol, data in validation_data.items():
            report.append(f"📈 {symbol}")
            report.append("-" * 20)
            
            # Ticks
            if 'ticks' in data and 'count' in data['ticks']:
                ticks = data['ticks']
                report.append(f"  Ticks: {ticks['count']:,} registros")
                report.append(f"  Período: {ticks['date_range'][0]} até {ticks['date_range'][1]}")
                report.append(f"  Tamanho: {ticks['file_size_mb']:.2f} MB")
            else:
                report.append("  Ticks: ❌ Não coletado")
            
            # OHLC
            if 'ohlc' in data and 'count' in data['ohlc']:
                ohlc = data['ohlc']
                report.append(f"  OHLC: {ohlc['count']:,} barras M1")
                report.append(f"  Período: {ohlc['date_range'][0]} até {ohlc['date_range'][1]}")
                report.append(f"  Tamanho: {ohlc['file_size_mb']:.2f} MB")
            else:
                report.append("  OHLC: ❌ Não coletado")
            
            report.append("")
        
        return "\n".join(report)


# Exemplo de uso
if __name__ == "__main__":
    # Criar coletor
    collector = HistoricalDataCollector()
    
    # Coletar dados (últimos 6 meses)
    print("🚀 Iniciando coleta de dados históricos...")
    results = collector.collect_all_symbols(months=6)
    
    # Gerar relatório
    print("\n📊 Gerando relatório...")
    report = collector.generate_collection_report()
    print(report)
    
    # Salvar relatório
    report_path = Path("C:/DuarteScalper/logs/collection_report.txt")
    with open(report_path, 'w', encoding='utf-8') as f:
        f.write(report)
    
    print(f"\n✅ Coleta concluída! Relatório salvo em {report_path}")