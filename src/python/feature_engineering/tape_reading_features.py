"""
DUARTE-SCALPER: Tape Reading Features
Sistema de extração de features para simular tape reading
"""

import sys
sys.path.append(r'C:\DuarteScalper\src')

import pandas as pd
import numpy as np
from datetime import datetime, timedelta
import logging
from pathlib import Path
from typing import Dict, List, Tuple, Optional
import warnings
warnings.filterwarnings('ignore')

from python.utils.config_manager import ConfigManager

class TapeReadingFeatures:
    """
    Extrator de features para tape reading em scalping
    
    Features implementadas:
    1. Velocity Features: velocidade de ticks, preços, aceleração
    2. Price Action Features: momentum, rejeições, sequências
    3. Volume Flow Features: pressão compra/venda, desequilíbrios
    4. Market Microstructure: spread, frequência de mudanças
    """
    
    def __init__(self, config_path: str = None):
        """
        Inicializa o extrator de features
        
        Args:
            config_path: Caminho para arquivo de configuração
        """
        # Carregar configuração
        self.config = ConfigManager(config_path)
        
        # Setup logging
        self.setup_logging()
        
        # Janelas de tempo para features (segundos)
        self.time_windows = [10, 30, 60, 300, 600]  # 10s, 30s, 1m, 5m, 10m
        
        # Configurações padrão
        self.min_ticks_per_window = 5
        self.atr_period = 20
        self.volume_ma_period = 50
        
        self.logger.info("TapeReadingFeatures inicializado")
    
    def setup_logging(self):
        """Configura logging para feature engineering"""
        log_path = Path(self.config.get('paths.logs')) / 'feature_engineering.log'
        log_path.parent.mkdir(parents=True, exist_ok=True)
        
        self.logger = logging.getLogger('TapeReadingFeatures')
        self.logger.setLevel(logging.INFO)
        
        if not self.logger.handlers:
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
    
    def extract_features(self, tick_data: pd.DataFrame, ohlc_data: pd.DataFrame = None) -> pd.DataFrame:
        """
        Extrai todas as features para tape reading
        
        Args:
            tick_data: DataFrame com dados tick
            ohlc_data: DataFrame com dados OHLC (opcional)
            
        Returns:
            pd.DataFrame: Features extraídas
        """
        self.logger.info("Iniciando extração de features...")
        
        # Validar dados de entrada
        if not self._validate_tick_data(tick_data):
            raise ValueError("Dados tick inválidos")
        
        # Preparar dados
        df = self._prepare_tick_data(tick_data.copy())
        
        # Extrair features por categoria
        features_list = []
        
        # 1. Velocity Features
        self.logger.info("Extraindo velocity features...")
        velocity_features = self._extract_velocity_features(df)
        features_list.append(velocity_features)
        
        # 2. Price Action Features
        self.logger.info("Extraindo price action features...")
        price_action_features = self._extract_price_action_features(df)
        features_list.append(price_action_features)
        
        # 3. Volume Flow Features
        self.logger.info("Extraindo volume flow features...")
        volume_flow_features = self._extract_volume_flow_features(df)
        features_list.append(volume_flow_features)
        
        # 4. Market Microstructure Features
        self.logger.info("Extraindo microstructure features...")
        microstructure_features = self._extract_microstructure_features(df)
        features_list.append(microstructure_features)
        
        # 5. OHLC Features (se disponível)
        if ohlc_data is not None:
            self.logger.info("Extraindo OHLC features...")
            ohlc_features = self._extract_ohlc_features(df, ohlc_data)
            features_list.append(ohlc_features)
        
        # Combinar todas as features
        final_features = df[['time', 'symbol']].copy()
        for features in features_list:
            final_features = final_features.merge(features, on=['time', 'symbol'], how='left')
        
        # Preencher valores ausentes
        final_features = self._fill_missing_values(final_features)
        
        self.logger.info(f"Feature extraction completed: {len(final_features.columns)} features")
        return final_features
    
    def _validate_tick_data(self, tick_data: pd.DataFrame) -> bool:
        """
        Valida dados tick de entrada
        
        Args:
            tick_data: DataFrame com dados tick
            
        Returns:
            bool: True se válido
        """
        required_columns = ['time', 'bid', 'ask', 'symbol']
        
        # Verificar colunas obrigatórias
        for col in required_columns:
            if col not in tick_data.columns:
                self.logger.error(f"Coluna obrigatória ausente: {col}")
                return False
        
        # Verificar se há dados
        if len(tick_data) < 100:
            self.logger.error("Dados tick insuficientes (< 100 registros)")
            return False
        
        # Verificar ordenação por tempo
        if not tick_data['time'].is_monotonic_increasing:
            self.logger.warning("Dados não estão ordenados por tempo")
        
        return True
    
    def _prepare_tick_data(self, df: pd.DataFrame) -> pd.DataFrame:
        """
        Prepara dados tick para extração de features
        
        Args:
            df: DataFrame com dados tick
            
        Returns:
            pd.DataFrame: Dados preparados
        """
        # Garantir que time é datetime
        if not pd.api.types.is_datetime64_any_dtype(df['time']):
            df['time'] = pd.to_datetime(df['time'])
        
        # Ordenar por tempo
        df = df.sort_values('time').reset_index(drop=True)
        
        # Calcular preços derivados
        df['mid_price'] = (df['bid'] + df['ask']) / 2
        df['spread'] = df['ask'] - df['bid']
        
        # Usar 'last' se disponível, senão mid_price
        if 'last' not in df.columns:
            df['last'] = df['mid_price']
        
        # Calcular direção do tick se não existir
        if 'direction' not in df.columns:
            df['direction'] = self._calculate_tick_direction(df)
        
        # Volume padrão se não existir
        if 'volume' not in df.columns:
            df['volume'] = 1
        
        # Adicionar timestamp em segundos para cálculos
        df['timestamp'] = df['time'].astype('int64') / 1e9
        
        return df
    
    def _calculate_tick_direction(self, df: pd.DataFrame) -> pd.Series:
        """
        Calcula direção dos ticks
        
        Args:
            df: DataFrame com dados tick
            
        Returns:
            pd.Series: Direção (1=up, -1=down, 0=neutral)
        """
        price_diff = df['last'].diff()
        
        direction = pd.Series(0, index=df.index)
        direction[price_diff > 0] = 1   # Uptick
        direction[price_diff < 0] = -1  # Downtick
        
        # Primeiro tick sempre neutro
        direction.iloc[0] = 0
        
        return direction
    
    def _extract_velocity_features(self, df: pd.DataFrame) -> pd.DataFrame:
        """
        Extrai features de velocidade
        
        Features incluídas:
        - tick_velocity: ticks por segundo
        - price_velocity: pontos por segundo
        - acceleration: mudança na velocidade
        - volatility: desvio padrão dos retornos
        
        Args:
            df: DataFrame com dados tick
            
        Returns:
            pd.DataFrame: Features de velocidade
        """
        features = df[['time', 'symbol']].copy()
        
        for window in self.time_windows:
            suffix = f"_{window}s"
            
            # Rolling window baseado em tempo
            time_grouper = df.groupby('symbol').rolling(
                window=f'{window}s', 
                on='time', 
                min_periods=self.min_ticks_per_window
            )
            
            # 1. Tick Velocity - ticks por segundo
            tick_count = time_grouper.size()
            features[f'tick_velocity{suffix}'] = tick_count / window
            
            # 2. Price Velocity - variação de preço por segundo
            price_change = time_grouper['last'].apply(lambda x: x.iloc[-1] - x.iloc[0] if len(x) > 1 else 0)
            features[f'price_velocity{suffix}'] = price_change / window
            
            # 3. Acceleration - mudança na velocidade
            features[f'acceleration{suffix}'] = features[f'price_velocity{suffix}'].diff()
            
            # 4. Volatility - desvio padrão dos retornos
            returns = df.groupby('symbol')['last'].pct_change()
            volatility = returns.rolling(window=f'{window}s', on=df['time']).std()
            features[f'volatility{suffix}'] = volatility
            
            # 5. Range Velocity - velocidade de expansão do range
            high_low_range = time_grouper['last'].max() - time_grouper['last'].min()
            features[f'range_velocity{suffix}'] = high_low_range / window
        
        return features
    
    def _extract_price_action_features(self, df: pd.DataFrame) -> pd.DataFrame:
        """
        Extrai features de price action
        
        Features incluídas:
        - momentum: força direcional
        - rejection_strength: força de rejeição em níveis
        - trend_consistency: consistência da tendência
        - reversal_signals: sinais de reversão
        
        Args:
            df: DataFrame com dados tick
            
        Returns:
            pd.DataFrame: Features de price action
        """
        features = df[['time', 'symbol']].copy()
        
        for window in self.time_windows:
            suffix = f"_{window}s"
            
            # Rolling window baseado em tempo
            time_grouper = df.groupby('symbol').rolling(
                window=f'{window}s',
                on='time',
                min_periods=self.min_ticks_per_window
            )
            
            # 1. Momentum - soma das direções dos ticks
            momentum = time_grouper['direction'].sum()
            features[f'momentum{suffix}'] = momentum
            
            # 2. Trend Consistency - % de ticks na mesma direção
            def trend_consistency(directions):
                if len(directions) == 0:
                    return 0
                up_ticks = (directions > 0).sum()
                down_ticks = (directions < 0).sum()
                total_ticks = len(directions[directions != 0])
                if total_ticks == 0:
                    return 0
                return max(up_ticks, down_ticks) / total_ticks
            
            features[f'trend_consistency{suffix}'] = time_grouper['direction'].apply(trend_consistency)
            
            # 3. Rejection Strength - reversões rápidas
            def rejection_strength(prices):
                if len(prices) < 3:
                    return 0
                # Calcular máxima excursão vs. fechamento
                price_range = prices.max() - prices.min()
                if price_range == 0:
                    return 0
                final_move = abs(prices.iloc[-1] - prices.iloc[0])
                return 1 - (final_move / price_range)
            
            features[f'rejection_strength{suffix}'] = time_grouper['last'].apply(rejection_strength)
            
            # 4. Price Level Tests - testes de suporte/resistência
            def level_tests(prices):
                if len(prices) < 5:
                    return 0
                # Contar quantas vezes tocou nos extremos
                high_level = prices.max()
                low_level = prices.min()
                high_touches = (prices >= high_level * 0.9999).sum()
                low_touches = (prices <= low_level * 1.0001).sum()
                return max(high_touches, low_touches)
            
            features[f'level_tests{suffix}'] = time_grouper['last'].apply(level_tests)
            
            # 5. Directional Persistence - persistência direcional
            def directional_persistence(directions):
                if len(directions) < 2:
                    return 0
                # Contar sequências consecutivas na mesma direção
                changes = (directions.diff() != 0).sum()
                return 1 - (changes / len(directions)) if len(directions) > 0 else 0
            
            features[f'directional_persistence{suffix}'] = time_grouper['direction'].apply(directional_persistence)
        
        return features
    
    def _extract_volume_flow_features(self, df: pd.DataFrame) -> pd.DataFrame:
        """
        Extrai features de volume flow
        
        Features incluídas:
        - buy_pressure: pressão compradora
        - sell_pressure: pressão vendedora
        - volume_imbalance: desequilíbrio de volume
        - volume_spike: picos de volume
        
        Args:
            df: DataFrame com dados tick
            
        Returns:
            pd.DataFrame: Features de volume flow
        """
        features = df[['time', 'symbol']].copy()
        
        # Classificar volume por direção
        df['buy_volume'] = df['volume'] * (df['direction'] == 1).astype(int)
        df['sell_volume'] = df['volume'] * (df['direction'] == -1).astype(int)
        
        for window in self.time_windows:
            suffix = f"_{window}s"
            
            # Rolling window baseado em tempo
            time_grouper = df.groupby('symbol').rolling(
                window=f'{window}s',
                on='time',
                min_periods=self.min_ticks_per_window
            )
            
            # 1. Buy Pressure - % do volume que foi compra
            total_volume = time_grouper['volume'].sum()
            buy_volume = time_grouper['buy_volume'].sum()
            sell_volume = time_grouper['sell_volume'].sum()
            
            features[f'buy_pressure{suffix}'] = buy_volume / total_volume.replace(0, 1)
            features[f'sell_pressure{suffix}'] = sell_volume / total_volume.replace(0, 1)
            
            # 2. Volume Imbalance - diferença entre compra e venda
            features[f'volume_imbalance{suffix}'] = (buy_volume - sell_volume) / total_volume.replace(0, 1)
            
            # 3. Volume Spike - volume vs. média histórica
            volume_ma = df.groupby('symbol')['volume'].rolling(
                window=self.volume_ma_period,
                min_periods=10
            ).mean()
            current_volume = time_grouper['volume'].sum()
            features[f'volume_spike{suffix}'] = current_volume / volume_ma
            
            # 4. Large Print Detection - detecção de grandes negócios
            def large_print_ratio(volumes):
                if len(volumes) == 0:
                    return 0
                mean_vol = volumes.mean()
                large_prints = (volumes > mean_vol * 3).sum()
                return large_prints / len(volumes)
            
            features[f'large_print_ratio{suffix}'] = time_grouper['volume'].apply(large_print_ratio)
            
            # 5. Volume Velocity - aceleração do volume
            volume_velocity = time_grouper['volume'].sum() / window
            features[f'volume_velocity{suffix}'] = volume_velocity
        
        return features
    
    def _extract_microstructure_features(self, df: pd.DataFrame) -> pd.DataFrame:
        """
        Extrai features de microestrutura do mercado
        
        Features incluídas:
        - spread_normalized: spread normalizado
        - spread_volatility: volatilidade do spread
        - bid_ask_changes: frequência de mudanças bid/ask
        - tick_frequency: frequência de ticks
        
        Args:
            df: DataFrame com dados tick
            
        Returns:
            pd.DataFrame: Features de microestrutura
        """
        features = df[['time', 'symbol']].copy()
        
        for window in self.time_windows:
            suffix = f"_{window}s"
            
            # Rolling window baseado em tempo
            time_grouper = df.groupby('symbol').rolling(
                window=f'{window}s',
                on='time',
                min_periods=self.min_ticks_per_window
            )
            
            # 1. Spread normalizado pelo preço médio
            avg_price = time_grouper['mid_price'].mean()
            avg_spread = time_grouper['spread'].mean()
            features[f'spread_normalized{suffix}'] = avg_spread / avg_price.replace(0, 1)
            
            # 2. Volatilidade do spread
            features[f'spread_volatility{suffix}'] = time_grouper['spread'].std()
            
            # 3. Frequência de mudanças bid/ask
            bid_changes = time_grouper['bid'].apply(lambda x: (x.diff() != 0).sum())
            ask_changes = time_grouper['ask'].apply(lambda x: (x.diff() != 0).sum())
            features[f'bid_change_freq{suffix}'] = bid_changes / window
            features[f'ask_change_freq{suffix}'] = ask_changes / window
            
            # 4. Tempo entre ticks
            def time_between_ticks(timestamps):
                if len(timestamps) < 2:
                    return 0
                time_diffs = timestamps.diff().dropna()
                return time_diffs.mean() if len(time_diffs) > 0 else 0
            
            features[f'avg_time_between_ticks{suffix}'] = time_grouper['timestamp'].apply(time_between_ticks)
            
            # 5. Tick Size Adherence - aderência ao tick size
            def tick_size_adherence(prices):
                if len(prices) < 2:
                    return 1
                price_changes = prices.diff().dropna()
                # Assumir tick size mínimo (pode ser configurável)
                min_tick = 0.5  # Para índice Bovespa
                adherent_changes = (price_changes % min_tick == 0).sum()
                return adherent_changes / len(price_changes) if len(price_changes) > 0 else 1
            
            features[f'tick_size_adherence{suffix}'] = time_grouper['last'].apply(tick_size_adherence)
        
        return features
    
    def _extract_ohlc_features(self, tick_df: pd.DataFrame, ohlc_df: pd.DataFrame) -> pd.DataFrame:
        """
        Extrai features adicionais dos dados OHLC
        
        Args:
            tick_df: DataFrame com dados tick
            ohlc_df: DataFrame com dados OHLC
            
        Returns:
            pd.DataFrame: Features OHLC
        """
        features = tick_df[['time', 'symbol']].copy()
        
        # Merge OHLC com ticks baseado no tempo mais próximo
        ohlc_reindexed = ohlc_df.set_index('time').reindex(
            tick_df['time'],
            method='ffill'
        ).reset_index()
        
        # Features básicas OHLC
        features['ohlc_range'] = ohlc_reindexed['high'] - ohlc_reindexed['low']
        features['ohlc_body'] = abs(ohlc_reindexed['close'] - ohlc_reindexed['open'])
        features['upper_shadow'] = ohlc_reindexed['high'] - ohlc_reindexed[['open', 'close']].max(axis=1)
        features['lower_shadow'] = ohlc_reindexed[['open', 'close']].min(axis=1) - ohlc_reindexed['low']
        
        # Features de posição relativa
        features['price_position_in_range'] = (
            (tick_df['last'] - ohlc_reindexed['low']) / 
            (ohlc_reindexed['high'] - ohlc_reindexed['low']).replace(0, 1)
        )
        
        # ATR (Average True Range)
        for period in [14, 20, 50]:
            features[f'atr_{period}'] = self._calculate_atr(ohlc_df, period)
        
        return features
    
    def _calculate_atr(self, ohlc_df: pd.DataFrame, period: int) -> pd.Series:
        """
        Calcula Average True Range
        
        Args:
            ohlc_df: DataFrame com dados OHLC
            period: Período para cálculo
            
        Returns:
            pd.Series: ATR values
        """
        high = ohlc_df['high']
        low = ohlc_df['low']
        close = ohlc_df['close']
        
        # True Range
        tr1 = high - low
        tr2 = abs(high - close.shift())
        tr3 = abs(low - close.shift())
        
        true_range = pd.concat([tr1, tr2, tr3], axis=1).max(axis=1)
        
        # Average True Range
        atr = true_range.rolling(window=period).mean()
        
        return atr
    
    def _fill_missing_values(self, df: pd.DataFrame) -> pd.DataFrame:
        """
        Preenche valores ausentes nas features
        
        Args:
            df: DataFrame com features
            
        Returns:
            pd.DataFrame: DataFrame com valores preenchidos
        """
        # Preencher com forward fill primeiro
        df = df.fillna(method='ffill')
        
        # Depois com zeros para valores ainda ausentes
        df = df.fillna(0)
        
        # Substituir infinitos por zeros
        df = df.replace([np.inf, -np.inf], 0)
        
        return df
    
    def validate_features(self, features_df: pd.DataFrame) -> Dict:
        """
        Valida qualidade das features extraídas
        
        Args:
            features_df: DataFrame com features
            
        Returns:
            Dict: Relatório de validação
        """
        validation_report = {
            'total_features': len(features_df.columns),
            'total_rows': len(features_df),
            'missing_values': features_df.isnull().sum().to_dict(),
            'infinite_values': {},
            'feature_ranges': {},
            'correlation_matrix': None
        }
        
        # Verificar valores infinitos
        for col in features_df.columns:
            if features_df[col].dtype in ['float64', 'float32']:
                inf_count = np.isinf(features_df[col]).sum()
                validation_report['infinite_values'][col] = inf_count
                
                # Range das features
                validation_report['feature_ranges'][col] = {
                    'min': features_df[col].min(),
                    'max': features_df[col].max(),
                    'mean': features_df[col].mean(),
                    'std': features_df[col].std()
                }
        
        # Matriz de correlação (apenas colunas numéricas)
        numeric_cols = features_df.select_dtypes(include=[np.number]).columns
        if len(numeric_cols) > 1:
            validation_report['correlation_matrix'] = features_df[numeric_cols].corr()
        
        return validation_report


# Exemplo de uso
if __name__ == "__main__":
    # Criar extrator
    feature_extractor = TapeReadingFeatures()
    
    # Exemplo com dados sintéticos
    print("🔬 Testando feature extraction...")
    
    # Dados tick sintéticos
    dates = pd.date_range('2024-01-01 09:00:00', periods=1000, freq='100ms')
    tick_data = pd.DataFrame({
        'time': dates,
        'symbol': 'WINM25',
        'bid': 100000 + np.cumsum(np.random.randn(1000) * 5),
        'ask': 100005 + np.cumsum(np.random.randn(1000) * 5),
        'last': 100002.5 + np.cumsum(np.random.randn(1000) * 5),
        'volume': np.random.randint(1, 100, 1000)
    })
    
    # Extrair features
    features = feature_extractor.extract_features(tick_data)
    
    # Validar features
    validation = feature_extractor.validate_features(features)
    
    print(f"✅ Features extraídas: {validation['total_features']}")
    print(f"✅ Amostras processadas: {validation['total_rows']}")
    print(f"✅ Feature extraction concluída!")