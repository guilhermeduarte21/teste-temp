import os
import yaml
import logging
import json
from pathlib import Path
from datetime import datetime
from dataclasses import dataclass
from typing import Dict, List, Optional

# Get project root directory
PROJECT_ROOT = Path(__file__).parent.parent
CONFIG_PATH = PROJECT_ROOT / "config" / "config.yaml"

@dataclass
class TradingConfig:
    symbols: List[str]
    magic_number: int
    robot_name: str
    default_lot_size: float
    max_positions_per_symbol: int

@dataclass
class RiskConfig:
    max_risk_per_trade: float
    max_daily_loss: float
    max_consecutive_losses: int
    max_position_time_minutes: int
    cool_down_after_limit_hours: int

@dataclass
class DataConfig:
    historical_months: int
    tick_collection_interval_ms: int
    ohlc_timeframes: List[str]
    save_interval_hours: int
    backup_interval_days: int

@dataclass
class MLConfig:
    ensemble_weights: Dict[str, float]
    training: Dict
    prediction: Dict

@dataclass
class CommunicationConfig:
    method: str
    pipe_name: str
    timeout_seconds: float
    max_buffer_size: int

@dataclass
class LoggingConfig:
    level: str
    max_file_size_mb: int
    backup_count: int
    files: Dict[str, str]

class ConfigManager:
    """Gerenciador centralized de configurações do sistema"""
    
    def __init__(self, config_path: Optional[Path] = None):
        self.config_path = config_path or CONFIG_PATH
        self.config = self.load_config()
        self.setup_logging()
        
        # Parse specific configs
        self.trading = TradingConfig(**self.config['trading'])
        self.risk = RiskConfig(**self.config['risk'])
        self.data = DataConfig(**self.config['data'])
        self.ml = MLConfig(**self.config['ml'])
        self.communication = CommunicationConfig(**self.config['communication'])
        self.logging_config = LoggingConfig(**self.config['logging'])
        
        # Setup paths
        self.setup_paths()
    
    def load_config(self) -> Dict:
        """Carrega configurações do arquivo YAML"""
        try:
            with open(self.config_path, 'r', encoding='utf-8') as file:
                config = yaml.safe_load(file)
            print(f"✅ Configurações carregadas de: {self.config_path}")
            return config
        except FileNotFoundError:
            print(f"❌ Arquivo de configuração não encontrado: {self.config_path}")
            return self.get_default_config()
        except yaml.YAMLError as e:
            print(f"❌ Erro ao parsear YAML: {e}")
            return self.get_default_config()
    
    def get_default_config(self) -> Dict:
        """Configurações padrão caso o arquivo não exista"""
        return {
            'trading': {
                'symbols': ["WINM25", "WDOM25"],
                'magic_number': 778899,
                'robot_name': "DUARTE-SCALPER",
                'default_lot_size': 1.0,
                'max_positions_per_symbol': 3
            },
            'risk': {
                'max_risk_per_trade': 0.01,
                'max_daily_loss': 0.03,
                'max_consecutive_losses': 5,
                'max_position_time_minutes': 10,
                'cool_down_after_limit_hours': 1
            },
            'data': {
                'historical_months': 6,
                'tick_collection_interval_ms': 1,
                'ohlc_timeframes': ["M1"],
                'save_interval_hours': 1,
                'backup_interval_days': 7
            },
            'ml': {
                'ensemble_weights': {
                    'lstm': 0.40,
                    'xgboost': 0.35,
                    'random_forest': 0.25
                },
                'training': {
                    'validation_split': 0.2,
                    'epochs': 100,
                    'batch_size': 32,
                    'retrain_interval_days': 1
                },
                'prediction': {
                    'min_confidence': 0.7,
                    'signal_timeframes': [10, 30, 60, 300]
                }
            },
            'communication': {
                'method': 'named_pipes',
                'pipe_name': '\\\\\\\\.\\\\pipe\\\\duarte_scalper',
                'timeout_seconds': 1.0,
                'max_buffer_size': 1024
            },
            'logging': {
                'level': 'INFO',
                'max_file_size_mb': 10,
                'backup_count': 5,
                'files': {
                    'main': 'logs/duarte_scalper.log',
                    'trading': 'logs/trading.log',
                    'data': 'logs/data_collection.log',
                    'model': 'logs/model_training.log'
                }
            },
            'paths': {
                'data_root': 'data',
                'models_path': 'data/models',
                'logs_path': 'logs',
                'config_path': 'config'
            }
        }
    
    def setup_paths(self):
        """Configura paths absolutos baseados no projeto"""
        self.paths = {}
        self.paths['root'] = PROJECT_ROOT
        self.paths['data'] = PROJECT_ROOT / self.config['paths']['data_root']
        self.paths['models'] = PROJECT_ROOT / self.config['paths']['models_path']
        self.paths['logs'] = PROJECT_ROOT / self.config['paths']['logs_path']
        self.paths['config'] = PROJECT_ROOT / self.config['paths']['config_path']
        
        # Create directories if they don't exist
        for path in self.paths.values():
            path.mkdir(parents=True, exist_ok=True)
    
    def setup_logging(self):
        """Configura sistema de logging"""
        log_config = self.config['logging']
        log_level = getattr(logging, log_config['level'].upper())
        
        # Create logs directory
        logs_dir = PROJECT_ROOT / "logs"
        logs_dir.mkdir(exist_ok=True)
        
        # Configure root logger
        logging.basicConfig(
            level=log_level,
            format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
            handlers=[
                logging.FileHandler(logs_dir / 'duarte_scalper.log'),
                logging.StreamHandler()
            ]
        )
        
        # Configure specific loggers
        for logger_name, log_file in log_config['files'].items():
            logger = logging.getLogger(logger_name)
            handler = logging.FileHandler(logs_dir / Path(log_file).name)
            handler.setFormatter(
                logging.Formatter('%(asctime)s - %(levelname)s - %(message)s')
            )
            logger.addHandler(handler)
    
    def save_config(self, config_dict: Optional[Dict] = None):
        """Salva configurações no arquivo"""
        config_to_save = config_dict or self.config
        try:
            with open(self.config_path, 'w', encoding='utf-8') as file:
                yaml.dump(config_to_save, file, default_flow_style=False)
            print(f"✅ Configurações salvas em: {self.config_path}")
        except Exception as e:
            print(f"❌ Erro ao salvar configurações: {e}")
    
    def get_symbol_config(self, symbol: str) -> Dict:
        """Obter configurações específicas de um símbolo"""
        # Aqui você pode adicionar configurações específicas por símbolo
        # Por enquanto, retorna configurações padrão
        return {
            'symbol': symbol,
            'lot_size': self.trading.default_lot_size,
            'max_positions': self.trading.max_positions_per_symbol
        }
    
    def update_runtime_config(self, section: str, key: str, value):
        """Atualiza configuração em runtime"""
        if section in self.config and key in self.config[section]:
            self.config[section][key] = value
            # Recarregar objetos de configuração
            self.__init__(self.config_path)
            print(f"✅ Configuração atualizada: {section}.{key} = {value}")
        else:
            print(f"❌ Configuração não encontrada: {section}.{key}")
    
    def export_config_json(self, filepath: Optional[Path] = None):
        """Exporta configurações para JSON (útil para debugging)"""
        if filepath is None:
            filepath = self.paths['config'] / f"config_export_{datetime.now().strftime('%Y%m%d_%H%M%S')}.json"
        
        try:
            with open(filepath, 'w', encoding='utf-8') as file:
                json.dump(self.config, file, indent=4, default=str)
            print(f"✅ Configurações exportadas para: {filepath}")
        except Exception as e:
            print(f"❌ Erro ao exportar configurações: {e}")
    
    def validate_config(self) -> bool:
        """Valida se as configurações estão corretas"""
        errors = []
        
        # Validar trading config
        if not self.trading.symbols:
            errors.append("Nenhum símbolo configurado")
        
        if self.trading.magic_number <= 0:
            errors.append("Magic number deve ser maior que 0")
        
        # Validar risk config
        if not (0 < self.risk.max_risk_per_trade <= 0.1):
            errors.append("Risk per trade deve estar entre 0 e 10%")
        
        if not (0 < self.risk.max_daily_loss <= 0.2):
            errors.append("Max daily loss deve estar entre 0 e 20%")
        
        # Validar ML config
        ensemble_sum = sum(self.ml.ensemble_weights.values())
        if abs(ensemble_sum - 1.0) > 0.01:
            errors.append(f"Soma dos pesos do ensemble deve ser 1.0 (atual: {ensemble_sum})")
        
        if errors:
            print("❌ Erros na configuração:")
            for error in errors:
                print(f"  - {error}")
            return False
        
        print("✅ Configurações validadas com sucesso")
        return True

# Global config instance
config = ConfigManager()

def get_config() -> ConfigManager:
    """Função helper para obter instância global de configuração"""
    return config

# Logging utilities
def get_logger(name: str) -> logging.Logger:
    """Get logger instance"""
    return logging.getLogger(name)

def log_system_info():
    """Log informações do sistema"""
    logger = get_logger("system")
    logger.info(f"=== DUARTE-SCALPER INICIADO ===")
    logger.info(f"Project Root: {PROJECT_ROOT}")
    logger.info(f"Python Version: {os.sys.version}")
    logger.info(f"Config File: {config.config_path}")
    logger.info(f"Symbols: {config.trading.symbols}")
    logger.info(f"Magic Number: {config.trading.magic_number}")
    logger.info("===============================")

if __name__ == "__main__":
    # Test configuration
    print("=== TESTE DE CONFIGURAÇÃO ===")
    
    # Load and validate config
    config.validate_config()
    
    # Export config for inspection
    config.export_config_json()
    
    # Log system info
    log_system_info()
    
    # Print some config values
    print(f"\nSímbolos configurados: {config.trading.symbols}")
    print(f"Magic Number: {config.trading.magic_number}")
    print(f"Risk per trade: {config.risk.max_risk_per_trade*100}%")
    print(f"Ensemble weights: {config.ml.ensemble_weights}")
    
    print("\n✅ Configuração carregada com sucesso!")