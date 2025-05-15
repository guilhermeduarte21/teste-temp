"""
DUARTE-SCALPER: Coletor de Dados em Tempo Real
Sistema assíncrono para coleta contínua de ticks e OHLC
"""

import sys
sys.path.append(r'C:\DuarteScalper\src')

import MetaTrader5 as mt5
import pandas as pd
import numpy as np
from datetime import datetime, timedelta
import time
import asyncio
import threading
import queue
import os
import logging
from pathlib import Path
import pyarrow as pa
import pyarrow.parquet as pq
from collections import deque
from typing import Dict, List, Optional, Tuple
import json

from python.utils.config_manager import ConfigManager

class RealTimeDataCollector:
    """
    Coletor de dados em tempo real com buffer inteligente
    """
    
    def __init__(self, config_path: str = None):
        """
        Inicializa o coletor em tempo real
        
        Args:
            config_path: Caminho para arquivo de configuração
        """
        # Carregar configuração
        self.config = ConfigManager(config_path)
        
        # Setup logging
        self.setup_logging()
        
        # Paths para dados
        self.raw_live_path = Path(self.config.get('paths.data.raw_live'))
        self.raw_live_path.mkdir(parents=True, exist_ok=True)
        
        # Estados de controle
        self.mt5_initialized = False
        self.is_collecting = False
        self.stop_event = threading.Event()
        
        # Símbolos para coleta
        self.symbols = self.config.get('trading.symbols', ['WINM25', 'WDOM25'])
        
        # Configurações de coleta
        self.tick_collection_interval = 0.01  # 10ms entre coletas
        self.buffer_size = 10000
        self.save_interval_minutes = 60  # Salvar a cada hora
        
        # Buffers para cada símbolo
        self.tick_buffers: Dict[str, deque] = {}
        self.ohlc_buffers: Dict[str, Dict] = {}
        
        # Queues para processamento assíncrono
        self.tick_queue = queue.Queue(maxsize=50000)
        self.processing_thread = None
        
        # Estatísticas
        self.stats = {
            'total_ticks': 0,
            'ticks_per_second': 0,
            'last_save': datetime.now(),
            'collection_errors': 0,
            'symbols_stats': {}
        }
        
        # Inicializar buffers
        self._initialize_buffers()
        
        self.logger.info("RealTimeDataCollector inicializado")
    
    def setup_logging(self):
        """Configura logging específico para coleta em tempo real"""
        log_path = Path(self.config.get('paths.logs')) / 'realtime_collection.log'
        log_path.parent.mkdir(parents=True, exist_ok=True)
        
        self.logger = logging.getLogger('RealTimeCollector')
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
    
    def _initialize_buffers(self):
        """Inicializa buffers para cada símbolo"""
        for symbol in self.symbols:
            self.tick_buffers[symbol] = deque(maxlen=self.buffer_size)
            self.ohlc_buffers[symbol] = {
                'current_minute': None,
                'open': None,
                'high': None,
                'low': None,
                'close': None,
                'volume': 0,
                'tick_count': 0,
                'total_price': 0,
                'completed_bars': deque(maxlen=1440)  # 24 horas de barras M1
            }
            self.stats['symbols_stats'][symbol] = {
                'total_ticks': 0,
                'last_tick_time': None,
                'avg_spread': 0,
                'ohlc_bars': 0
            }
    
    def initialize_mt5(self) -> bool:
        """
        Inicializa conexão com MT5
        
        Returns:
            bool: True se sucesso
        """
        if self.mt5_initialized:
            return True
            
        if not mt5.initialize():
            self.logger.error(f"MT5 initialization failed: {mt5.last_error()}")
            return False
        
        # Verificar símbolos
        for symbol in self.symbols:
            if not mt5.symbol_select(symbol, True):
                self.logger.warning(f"Symbol {symbol} not available")
        
        self.logger.info("MT5 inicializado para coleta em tempo real")
        self.mt5_initialized = True
        return True
    
    def start_collection(self):
        """
        Inicia coleta de dados em tempo real
        """
        if not self.initialize_mt5():
            raise Exception("Failed to initialize MT5")
        
        if self.is_collecting:
            self.logger.warning("Collection already running")
            return
        
        self.is_collecting = True
        self.stop_event.clear()
        
        # Iniciar thread de processamento
        self.processing_thread = threading.Thread(target=self._processing_worker)
        self.processing_thread.start()
        
        # Iniciar loop de coleta
        asyncio.run(self._collection_loop())
        
        self.logger.info("Real-time collection started")
    
    def stop_collection(self):
        """
        Para coleta de dados
        """
        if not self.is_collecting:
            return
        
        self.logger.info("Stopping real-time collection...")
        self.is_collecting = False
        self.stop_event.set()
        
        # Esperar thread de processamento terminar
        if self.processing_thread and self.processing_thread.is_alive():
            self.processing_thread.join(timeout=5)
        
        # Salvar dados pendentes
        self._save_all_buffers()
        
        # Fechar MT5
        if self.mt5_initialized:
            mt5.shutdown()
            self.mt5_initialized = False
        
        self.logger.info("Real-time collection stopped")
    
    async def _collection_loop(self):
        """
        Loop principal de coleta assíncrona
        """
        last_stats_update = datetime.now()
        last_save = datetime.now()
        tick_count_for_stats = 0
        
        while self.is_collecting and not self.stop_event.is_set():
            try:
                # Coletar ticks para todos os símbolos
                for symbol in self.symbols:
                    tick = self._collect_single_tick(symbol)
                    if tick:
                        self.tick_queue.put(tick, block=False)
                        tick_count_for_stats += 1
                
                # Atualizar estatísticas a cada segundo
                if (datetime.now() - last_stats_update).seconds >= 1:
                    self.stats['ticks_per_second'] = tick_count_for_stats
                    tick_count_for_stats = 0
                    last_stats_update = datetime.now()
                    self._log_collection_stats()
                
                # Salvar buffers periodicamente
                if (datetime.now() - last_save).seconds >= self.save_interval_minutes * 60:
                    self._save_all_buffers()
                    last_save = datetime.now()
                
                # Sleep para controlar frequência
                await asyncio.sleep(self.tick_collection_interval)
                
            except Exception as e:
                self.logger.error(f"Error in collection loop: {e}")
                self.stats['collection_errors'] += 1
                await asyncio.sleep(0.1)
    
    def _collect_single_tick(self, symbol: str) -> Optional[Dict]:
        """
        Coleta um tick para o símbolo especificado
        
        Args:
            symbol: Nome do símbolo
            
        Returns:
            Dict com dados do tick ou None
        """
        try:
            # Obter tick atual
            tick = mt5.symbol_info_tick(symbol)
            if tick is None:
                return None
            
            # Converter para dicionário
            tick_data = {
                'symbol': symbol,
                'time': datetime.fromtimestamp(tick.time),
                'bid': tick.bid,
                'ask': tick.ask,
                'last': tick.last,
                'volume': tick.volume,
                'time_msc': tick.time_msc,
                'flags': tick.flags,
                'volume_real': tick.volume_real
            }
            
            # Calcular campos adicionais
            tick_data['spread'] = tick.ask - tick.bid
            tick_data['mid_price'] = (tick.bid + tick.ask) / 2
            
            return tick_data
            
        except Exception as e:
            self.logger.error(f"Error collecting tick for {symbol}: {e}")
            return None
    
    def _processing_worker(self):
        """
        Worker thread para processar ticks coletados
        """
        while self.is_collecting or not self.tick_queue.empty():
            try:
                # Obter tick da queue (timeout 1s)
                try:
                    tick = self.tick_queue.get(timeout=1)
                except queue.Empty:
                    continue
                
                # Processar tick
                self._process_tick(tick)
                self.tick_queue.task_done()
                
            except Exception as e:
                self.logger.error(f"Error in processing worker: {e}")
    
    def _process_tick(self, tick: Dict):
        """
        Processa um tick individual
        
        Args:
            tick: Dados do tick
        """
        symbol = tick['symbol']
        
        # Atualizar buffer de ticks
        self.tick_buffers[symbol].append(tick)
        
        # Atualizar estatísticas
        self.stats['total_ticks'] += 1
        self.stats['symbols_stats'][symbol]['total_ticks'] += 1
        self.stats['symbols_stats'][symbol]['last_tick_time'] = tick['time']
        
        # Calcular spread médio
        current_spread = self.stats['symbols_stats'][symbol]['avg_spread']
        tick_count = self.stats['symbols_stats'][symbol]['total_ticks']
        new_spread = tick['spread']
        self.stats['symbols_stats'][symbol]['avg_spread'] = (
            (current_spread * (tick_count - 1) + new_spread) / tick_count
        )
        
        # Processar OHLC
        self._update_ohlc_buffer(tick)
        
        # Calcular direção do tick
        tick['direction'] = self._calculate_tick_direction(symbol, tick)
    
    def _update_ohlc_buffer(self, tick: Dict):
        """
        Atualiza buffer OHLC com novo tick
        
        Args:
            tick: Dados do tick
        """
        symbol = tick['symbol']
        ohlc = self.ohlc_buffers[symbol]
        
        # Obter minuto atual
        current_time = tick['time']
        current_minute = current_time.replace(second=0, microsecond=0)
        
        # Verificar se é novo minuto
        if ohlc['current_minute'] != current_minute:
            # Salvar barra anterior se existir
            if ohlc['current_minute'] is not None:
                completed_bar = {
                    'symbol': symbol,
                    'time': ohlc['current_minute'],
                    'open': ohlc['open'],
                    'high': ohlc['high'],
                    'low': ohlc['low'],
                    'close': ohlc['close'],
                    'volume': ohlc['volume'],
                    'tick_count': ohlc['tick_count'],
                    'typical_price': ohlc['total_price'] / max(ohlc['tick_count'], 1)
                }
                ohlc['completed_bars'].append(completed_bar)
                self.stats['symbols_stats'][symbol]['ohlc_bars'] += 1
            
            # Iniciar nova barra
            ohlc['current_minute'] = current_minute
            ohlc['open'] = tick['mid_price']
            ohlc['high'] = tick['mid_price']
            ohlc['low'] = tick['mid_price']
            ohlc['close'] = tick['mid_price']
            ohlc['volume'] = 0
            ohlc['tick_count'] = 0
            ohlc['total_price'] = 0
        
        # Atualizar barra atual
        ohlc['high'] = max(ohlc['high'], tick['mid_price'])
        ohlc['low'] = min(ohlc['low'], tick['mid_price'])
        ohlc['close'] = tick['mid_price']
        ohlc['volume'] += tick.get('volume_real', 1)
        ohlc['tick_count'] += 1
        ohlc['total_price'] += tick['mid_price']
    
    def _calculate_tick_direction(self, symbol: str, tick: Dict) -> int:
        """
        Calcula direção do tick baseado no histórico
        
        Args:
            symbol: Nome do símbolo
            tick: Dados do tick atual
            
        Returns:
            int: 1 (up), -1 (down), 0 (neutral)
        """
        buffer = self.tick_buffers[symbol]
        
        if len(buffer) < 2:
            return 0
        
        # Comparar com tick anterior
        prev_tick = buffer[-2]
        current_price = tick['mid_price']
        prev_price = prev_tick['mid_price']
        
        if current_price > prev_price:
            return 1
        elif current_price < prev_price:
            return -1
        else:
            return 0
    
    def _log_collection_stats(self):
        """Log estatísticas de coleta periodicamente"""
        self.logger.info(f"Collecting {self.stats['ticks_per_second']} ticks/sec")
        
        for symbol, stats in self.stats['symbols_stats'].items():
            self.logger.info(f"{symbol}: {stats['total_ticks']} ticks, "
                           f"avg spread: {stats['avg_spread']:.2f}, "
                           f"OHLC bars: {stats['ohlc_bars']}")
    
    def _save_all_buffers(self):
        """
        Salva todos os buffers em arquivo
        """
        timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
        
        for symbol in self.symbols:
            try:
                # Salvar ticks
                self._save_tick_buffer(symbol, timestamp)
                
                # Salvar OHLC
                self._save_ohlc_buffer(symbol, timestamp)
                
            except Exception as e:
                self.logger.error(f"Error saving buffers for {symbol}: {e}")
        
        self.stats['last_save'] = datetime.now()
        self.logger.info(f"Buffers saved at {self.stats['last_save']}")
    
    def _save_tick_buffer(self, symbol: str, timestamp: str):
        """
        Salva buffer de ticks em arquivo Parquet
        
        Args:
            symbol: Nome do símbolo
            timestamp: Timestamp para nome do arquivo
        """
        buffer = self.tick_buffers[symbol]
        
        if len(buffer) == 0:
            return
        
        # Converter para DataFrame
        df = pd.DataFrame(list(buffer))
        
        # Arquivo de saída
        filename = f"{symbol}_ticks_{timestamp}.parquet"
        filepath = self.raw_live_path / filename
        
        # Salvar em Parquet
        table = pa.Table.from_pandas(df)
        pq.write_table(
            table,
            filepath,
            compression='snappy',
            use_dictionary=True,
            row_group_size=10000
        )
        
        file_size = filepath.stat().st_size / (1024*1024)
        self.logger.info(f"Saved {len(df)} ticks to {filename} ({file_size:.2f} MB)")
        
        # Limpar buffer após salvar
        buffer.clear()
    
    def _save_ohlc_buffer(self, symbol: str, timestamp: str):
        """
        Salva buffer OHLC em arquivo Parquet
        
        Args:
            symbol: Nome do símbolo
            timestamp: Timestamp para nome do arquivo
        """
        ohlc_buffer = self.ohlc_buffers[symbol]
        completed_bars = ohlc_buffer['completed_bars']
        
        if len(completed_bars) == 0:
            return
        
        # Converter para DataFrame
        df = pd.DataFrame(list(completed_bars))
        
        # Arquivo de saída
        filename = f"{symbol}_ohlc_M1_{timestamp}.parquet"
        filepath = self.raw_live_path / filename
        
        # Salvar em Parquet
        table = pa.Table.from_pandas(df)
        pq.write_table(
            table,
            filepath,
            compression='snappy',
            use_dictionary=True,
            row_group_size=5000
        )
        
        file_size = filepath.stat().st_size / (1024*1024)
        self.logger.info(f"Saved {len(df)} OHLC bars to {filename} ({file_size:.2f} MB)")
        
        # Limpar buffer após salvar (manter apenas algumas barras para histórico)
        while len(completed_bars) > 100:
            completed_bars.popleft()
    
    def get_latest_ticks(self, symbol: str, count: int = 100) -> List[Dict]:
        """
        Obtém os últimos N ticks para um símbolo
        
        Args:
            symbol: Nome do símbolo
            count: Número de ticks a retornar
            
        Returns:
            List[Dict]: Lista dos últimos ticks
        """
        if symbol not in self.tick_buffers:
            return []
        
        buffer = self.tick_buffers[symbol]
        return list(buffer)[-count:]
    
    def get_latest_ohlc_bars(self, symbol: str, count: int = 100) -> List[Dict]:
        """
        Obtém as últimas N barras OHLC para um símbolo
        
        Args:
            symbol: Nome do símbolo
            count: Número de barras a retornar
            
        Returns:
            List[Dict]: Lista das últimas barras OHLC
        """
        if symbol not in self.ohlc_buffers:
            return []
        
        completed_bars = self.ohlc_buffers[symbol]['completed_bars']
        return list(completed_bars)[-count:]
    
    def get_collection_stats(self) -> Dict:
        """
        Obtém estatísticas de coleta
        
        Returns:
            Dict: Estatísticas detalhadas
        """
        return {
            'is_collecting': self.is_collecting,
            'total_ticks': self.stats['total_ticks'],
            'ticks_per_second': self.stats['ticks_per_second'],
            'last_save': self.stats['last_save'],
            'collection_errors': self.stats['collection_errors'],
            'symbols_stats': self.stats['symbols_stats'].copy(),
            'buffer_sizes': {
                symbol: len(buffer) 
                for symbol, buffer in self.tick_buffers.items()
            },
            'ohlc_bars_completed': {
                symbol: len(ohlc['completed_bars'])
                for symbol, ohlc in self.ohlc_buffers.items()
            }
        }
    
    def export_collection_report(self) -> str:
        """
        Gera relatório detalhado de coleta
        
        Returns:
            str: Relatório formatado
        """
        stats = self.get_collection_stats()
        
        report = []
        report.append("📊 DUARTE-SCALPER - RELATÓRIO DE COLETA EM TEMPO REAL")
        report.append("="*60)
        report.append(f"Data do relatório: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
        report.append(f"Status: {'COLETANDO' if stats['is_collecting'] else 'PARADO'}")
        report.append("")
        
        # Estatísticas gerais
        report.append("📈 ESTATÍSTICAS GERAIS")
        report.append("-" * 30)
        report.append(f"Total de ticks coletados: {stats['total_ticks']:,}")
        report.append(f"Taxa atual: {stats['ticks_per_second']} ticks/segundo")
        report.append(f"Último salvamento: {stats['last_save']}")
        report.append(f"Erros de coleta: {stats['collection_errors']}")
        report.append("")
        
        # Estatísticas por símbolo
        for symbol, symbol_stats in stats['symbols_stats'].items():
            report.append(f"📊 {symbol}")
            report.append("-" * 20)
            report.append(f"  Ticks coletados: {symbol_stats['total_ticks']:,}")
            report.append(f"  Último tick: {symbol_stats['last_tick_time']}")
            report.append(f"  Spread médio: {symbol_stats['avg_spread']:.4f}")
            report.append(f"  Barras OHLC: {symbol_stats['ohlc_bars']}")
            report.append(f"  Buffer atual: {stats['buffer_sizes'][symbol]} ticks")
            report.append(f"  Barras completadas: {stats['ohlc_bars_completed'][symbol]}")
            report.append("")
        
        return "\n".join(report)


# Exemplo de uso e teste
if __name__ == "__main__":
    import signal
    
    # Criar coletor
    collector = RealTimeDataCollector()
    
    def signal_handler(sig, frame):
        """Handler para parar coleta com Ctrl+C"""
        print("\n🛑 Parando coleta...")
        collector.stop_collection()
        exit(0)
    
    # Configurar handler para Ctrl+C
    signal.signal(signal.SIGINT, signal_handler)
    
    try:
        print("🚀 Iniciando coleta em tempo real...")
        print("Pressione Ctrl+C para parar")
        
        # Iniciar coleta (loop infinito)
        collector.start_collection()
        
    except Exception as e:
        print(f"❌ Erro durante coleta: {e}")
        collector.stop_collection()
    
    # Gerar relatório final
    print("\n📊 Relatório final:")
    print(collector.export_collection_report())
    
    print("\n✅ Coleta finalizada!")