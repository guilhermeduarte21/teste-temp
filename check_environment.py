#!/usr/bin/env python3
"""
Script de verificação completa do ambiente de desenvolvimento
Duarte-Scalper
"""

import os
import sys
import subprocess
from pathlib import Path
import platform

class EnvironmentChecker:
    def __init__(self):
        self.project_root = Path(__file__).parent
        self.errors = []
        self.warnings = []
        
    def print_header(self, title):
        print(f"\n{'='*60}")
        print(f" {title}")
        print(f"{'='*60}")
    
    def check_python_version(self):
        """Verificar versão do Python"""
        self.print_header("VERIFICAÇÃO DE PYTHON")
        
        version = sys.version_info
        print(f"Versão do Python: {version.major}.{version.minor}.{version.micro}")
        
        if version.major < 3 or (version.major == 3 and version.minor < 8):
            self.errors.append("Python 3.8+ é obrigatório")
            print("❌ Python 3.8+ é obrigatório")
        else:
            print("✅ Versão do Python adequada")
    
    def check_virtual_environment(self):
        """Verificar se está em ambiente virtual"""
        self.print_header("VERIFICAÇÃO DE AMBIENTE VIRTUAL")
        
        if hasattr(sys, 'real_prefix') or (hasattr(sys, 'base_prefix') and sys.base_prefix != sys.prefix):
            print("✅ Executando em ambiente virtual")
            print(f"   Ambiente: {sys.prefix}")
        else:
            self.warnings.append("Não está em ambiente virtual - recomendado usar venv")
            print("⚠️  Não está em ambiente virtual")
    
    def check_packages(self):
        """Verificar pacotes instalados"""
        self.print_header("VERIFICAÇÃO DE PACOTES")
        
        required_packages = {
            'numpy': '1.20+',
            'pandas': '1.3+',
            'scikit-learn': '1.0+',
            'xgboost': '1.5+',
            'MetaTrader5': '5.0+',
            'matplotlib': '3.5+',
            'pyyaml': '5.0+'
        }
        
        # TensorFlow como opcional
        optional_packages = {
            'tensorflow': '2.8+'
        }
        
        # Verificar pacotes obrigatórios
        for package, min_version in required_packages.items():
            try:
                if package == 'scikit-learn':
                    import sklearn
                    version = sklearn.__version__
                    package_name = 'sklearn'
                elif package == 'pyyaml':
                    import yaml
                    version = yaml.__version__ if hasattr(yaml, '__version__') else 'unknown'
                    package_name = package
                else:
                    mod = __import__(package)
                    version = mod.__version__ if hasattr(mod, '__version__') else 'unknown'
                    package_name = package
                
                print(f"✅ {package_name} {version} (requerido: {min_version})")
                
            except ImportError:
                self.errors.append(f"Pacote {package} não instalado")
                print(f"❌ {package} - NÃO INSTALADO")
        
        # Verificar pacotes opcionais
        for package, min_version in optional_packages.items():
            try:
                mod = __import__(package)
                version = mod.__version__ if hasattr(mod, '__version__') else 'unknown'
                print(f"✅ {package} {version} (opcional - {min_version})")
            except ImportError:
                self.warnings.append(f"Pacote opcional {package} não instalado (pode ser instalado depois)")
                print(f"⚠️  {package} - NÃO INSTALADO (opcional)")
    
    def check_directory_structure(self):
        """Verificar estrutura de diretórios"""
        self.print_header("VERIFICAÇÃO DE ESTRUTURA DE DIRETÓRIOS")
        
        required_dirs = [
            "data", "data/raw", "data/raw/historical", "data/raw/live",
            "data/processed", "data/processed/features", "data/processed/labels",
            "data/processed/datasets", "data/models", "data/backup",
            "src", "src/python", "src/python/data_collection",
            "src/python/feature_engineering", "src/python/model_training",
            "src/python/prediction", "src/python/communication", "src/python/utils",
            "src/mql5", "src/mql5/experts", "src/mql5/include", "src/mql5/indicators",
            "config", "logs", "tests", "docs"
        ]
        
        missing_dirs = []
        for dir_path in required_dirs:
            full_path = self.project_root / dir_path
            if full_path.exists():
                print(f"✅ {dir_path}")
            else:
                missing_dirs.append(dir_path)
                print(f"❌ {dir_path} - AUSENTE")
        
        if missing_dirs:
            self.warnings.append(f"Diretórios ausentes: {', '.join(missing_dirs)}")
    
    def check_mt5_connection(self):
        """Testar conexão com MT5"""
        self.print_header("VERIFICAÇÃO DE CONEXÃO MT5")
        
        try:
            import MetaTrader5 as mt5
            
            # Tentar inicializar
            if mt5.initialize():
                print("✅ MT5 inicializado com sucesso")
                
                # Verificar conta
                account_info = mt5.account_info()
                if account_info:
                    print(f"✅ Conta conectada: {account_info.login}")
                    print(f"   Servidor: {account_info.server}")
                    print(f"   Saldo: {account_info.balance:.2f}")
                else:
                    self.warnings.append("Não foi possível obter informações da conta")
                
                # Verificar símbolos
                test_symbols = ["WINM25", "WDOM25"]
                for symbol in test_symbols:
                    if mt5.symbol_info(symbol):
                        print(f"✅ Símbolo {symbol} disponível")
                    else:
                        # Tentar variações
                        variations = [f"{symbol}.BMF", f"{symbol}.SIR"]
                        found = False
                        for var in variations:
                            if mt5.symbol_info(var):
                                print(f"✅ Símbolo {symbol} encontrado como {var}")
                                found = True
                                break
                        if not found:
                            self.warnings.append(f"Símbolo {symbol} não encontrado")
                            print(f"⚠️  Símbolo {symbol} não encontrado")
                
                mt5.shutdown()
            else:
                self.errors.append("Não foi possível conectar ao MT5")
                print("❌ Não foi possível conectar ao MT5")
                print(f"   Erro: {mt5.last_error()}")
        
        except ImportError:
            self.errors.append("MetaTrader5 package não instalado")
            print("❌ MetaTrader5 package não instalado")
    
    def check_config_files(self):
        """Verificar arquivos de configuração"""
        self.print_header("VERIFICAÇÃO DE ARQUIVOS DE CONFIGURAÇÃO")
        
        config_files = [
            "config/config.yaml"
        ]
        
        for config_file in config_files:
            file_path = self.project_root / config_file
            if file_path.exists():
                print(f"✅ {config_file}")
                
                # Verificar se é válido
                if config_file.endswith('.yaml'):
                    try:
                        import yaml
                        with open(file_path, 'r') as f:
                            yaml.safe_load(f)
                        print(f"   └─ YAML válido")
                    except Exception as e:
                        self.errors.append(f"Erro no YAML {config_file}: {e}")
                        print(f"   └─ ❌ Erro no YAML: {e}")
            else:
                self.warnings.append(f"Arquivo de configuração ausente: {config_file}")
                print(f"⚠️  {config_file} - AUSENTE (será criado)")
    
    def create_missing_directories(self):
        """Criar diretórios ausentes"""
        self.print_header("CRIAÇÃO DE DIRETÓRIOS AUSENTES")
        
        required_dirs = [
            "data", "data/raw", "data/raw/historical", "data/raw/live",
            "data/processed", "data/processed/features", "data/processed/labels",
            "data/processed/datasets", "data/models", "data/backup",
            "src", "src/python", "src/python/data_collection",
            "src/python/feature_engineering", "src/python/model_training",
            "src/python/prediction", "src/python/communication", "src/python/utils",
            "src/mql5", "src/mql5/experts", "src/mql5/include", "src/mql5/indicators",
            "config", "logs", "tests", "docs"
        ]
        
        created_dirs = []
        for dir_path in required_dirs:
            full_path = self.project_root / dir_path
            if not full_path.exists():
                full_path.mkdir(parents=True, exist_ok=True)
                created_dirs.append(dir_path)
                print(f"✅ Criado: {dir_path}")
        
        if not created_dirs:
            print("✅ Todos os diretórios já existem")
        else:
            print(f"\n✅ {len(created_dirs)} diretórios criados")
    
    def create_init_files(self):
        """Criar arquivos __init__.py necessários"""
        self.print_header("CRIAÇÃO DE ARQUIVOS __init__.py")
        
        python_dirs = [
            "src/python",
            "src/python/data_collection",
            "src/python/feature_engineering",
            "src/python/model_training",
            "src/python/prediction",
            "src/python/communication",
            "src/python/utils"
        ]
        
        for dir_path in python_dirs:
            init_file = self.project_root / dir_path / "__init__.py"
            if not init_file.exists():
                init_file.write_text('"""' + dir_path.replace('/', '.') + ' module"""\n')
                print(f"✅ Criado: {dir_path}/__init__.py")
            else:
                print(f"✅ Existe: {dir_path}/__init__.py")
    
    def create_gitignore(self):
        """Criar arquivo .gitignore"""
        self.print_header("CRIAÇÃO DE .gitignore")
        
        gitignore_content = """# Byte-compiled / optimized / DLL files
__pycache__/
*.py[cod]
*$py.class

# Distribution / packaging
.Python
build/
develop-eggs/
dist/
downloads/
eggs/
.eggs/
lib/
lib64/
parts/
sdist/
var/
wheels/
*.egg-info/
.installed.cfg
*.egg

# Data files
data/raw/
data/processed/
data/backup/
*.csv
*.parquet
*.h5
*.pkl

# Models
data/models/
*.joblib
*.pkl
*.h5
*.pb

# Logs
logs/
*.log

# Environment
.env
.venv
venv/
venv_duarte/

# IDE
.vscode/
.idea/
*.swp
*.swo

# OS
.DS_Store
Thumbs.db

# MT5 files
*.ex5
*.ex4

# Jupyter
.jupyter/
*.ipynb_checkpoints/

# Temporary files
*.tmp
*.temp
temp/
"""
        
        gitignore_path = self.project_root / ".gitignore"
        if not gitignore_path.exists():
            gitignore_path.write_text(gitignore_content)
            print("✅ .gitignore criado")
        else:
            print("✅ .gitignore já existe")
    
    def create_requirements_txt(self):
        """Criar arquivo requirements.txt"""
        self.print_header("CRIAÇÃO DE requirements.txt")
        
        requirements_content = """# Core packages
numpy>=1.24.0
pandas>=2.0.0
scikit-learn>=1.3.0
tensorflow>=2.13.0
xgboost>=1.7.0
MetaTrader5>=5.0.45

# Data processing
pyarrow>=12.0.0
numba>=0.57.0
joblib>=1.3.0

# Visualization
matplotlib>=3.7.0
seaborn>=0.12.0
plotly>=5.15.0

# Configuration
pyyaml>=6.0
python-dotenv>=1.0.0

# System monitoring
psutil>=5.9.0

# Testing
pytest>=7.4.0
pytest-cov>=4.1.0

# Development
black>=23.0.0
flake8>=6.0.0
isort>=5.12.0
"""
        
        requirements_path = self.project_root / "requirements.txt"
        if not requirements_path.exists():
            requirements_path.write_text(requirements_content)
            print("✅ requirements.txt criado")
        else:
            print("✅ requirements.txt já existe")
    
    def generate_summary(self):
        """Gerar resumo final"""
        self.print_header("RESUMO DA VERIFICAÇÃO")
        
        total_checks = 6  # número de verificações principais
        
        print(f"Total de verificações: {total_checks}")
        print(f"Erros encontrados: {len(self.errors)}")
        print(f"Avisos: {len(self.warnings)}")
        
        if self.errors:
            print("\n❌ ERROS QUE PRECISAM SER CORRIGIDOS:")
            for i, error in enumerate(self.errors, 1):
                print(f"   {i}. {error}")
        
        if self.warnings:
            print("\n⚠️  AVISOS E RECOMENDAÇÕES:")
            for i, warning in enumerate(self.warnings, 1):
                print(f"   {i}. {warning}")
        
        if not self.errors and not self.warnings:
            print("\n🎉 PARABÉNS! Ambiente configurado perfeitamente!")
            print("✅ Pronto para prosseguir para o próximo passo")
        elif not self.errors:
            print("\n✅ AMBIENTE OK - apenas avisos menores")
            print("✅ Pode prosseguir para o próximo passo")
        else:
            print(f"\n❌ CORRIGIR {len(self.errors)} ERRO(S) ANTES DE PROSSEGUIR")
    
    def run_complete_check(self):
        """Executar verificação completa"""
        print("🔍 INICIANDO VERIFICAÇÃO COMPLETA DO AMBIENTE")
        print(f"📁 Diretório do projeto: {self.project_root}")
        print(f"🖥️  Sistema: {platform.system()} {platform.release()}")
        
        # Executar todas as verificações
        self.check_python_version()
        self.check_virtual_environment()
        self.check_packages()
        self.check_directory_structure()
        self.check_config_files()
        self.check_mt5_connection()
        
        # Criar arquivos/diretórios ausentes
        self.create_missing_directories()
        self.create_init_files()
        self.create_gitignore()
        self.create_requirements_txt()
        
        # Resumo final
        self.generate_summary()

def main():
    """Função principal"""
    checker = EnvironmentChecker()
    checker.run_complete_check()
    
    print(f"\n📋 PRÓXIMOS PASSOS:")
    print("1. Corrigir erros encontrados (se houver)")
    print("2. Instalar pacotes ausentes: pip install -r requirements.txt")
    print("3. Verificar símbolos no MT5 (WINM25, WDOM25)")
    print("4. Prosseguir para Passo 2: Implementação do coletor de dados")

if __name__ == "__main__":
    main()