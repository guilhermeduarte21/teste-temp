# 🚀 DUARTE-SCALPER - Setup e Comandos

![Python](https://img.shields.io/badge/Python-3.13.3-blue?style=flat-square&logo=python&logoColor=white)
![MT5](https://img.shields.io/badge/MT5-Compatible-green?style=flat-square&logo=metatrader&logoColor=white)
![Status](https://img.shields.io/badge/Status-Active%20Development-brightgreen?style=flat-square)
![Trading](https://img.shields.io/badge/Trading-Scalping%20Robot-orange?style=flat-square&logo=tradingview&logoColor=white)
![AI](https://img.shields.io/badge/AI-Ensemble%20Model-purple?style=flat-square&logo=tensorflow&logoColor=white)

## ⚙️ Setup Inicial

```bash
# 1. Clonar projeto
git clone https://github.com/seu-user/duarte-scalper.git
cd duarte-scalper

# 2. Criar ambiente virtual
python -m venv venv_duarte
venv_duarte\Scripts\activate  # Windows
source venv_duarte/bin/activate  # Linux/Mac

# 3. Instalar dependências
pip install -r requirements.txt

# 4. Verificar ambiente
python check_environment.py

# 5. Primeira deployment
python deploy_to_mt5.py deploy
```

## 💻 Desenvolvimento Diário

```bash
# Ativar ambiente
venv_duarte\Scripts\activate

# Para sair do venv
deactivate

# Modo desenvolvimento (auto-deploy)
python deploy_to_mt5.py watch

# Editar e testar...
# Os arquivos são copiados automaticamente para MT5!
```

## 📋 Comandos Principais

### 1. Deployment para MT5
```bash
# Deploy inicial (detecta MT5 automaticamente)
python deploy_to_mt5.py deploy

# Deploy com modo watch (auto-copy quando editar)
python deploy_to_mt5.py watch

# Deploy com links simbólicos (dev avançado)
python deploy_to_mt5.py symlink
```

### 2. Verificação de Ambiente
```bash
# Verificar instalação completa
python check_environment.py

# Testar conexão MT5
python test_mt5_connection.py
```

### 3. Coleta de Dados
```bash
# Coleta dados históricos
python -m src.python.data_collection.historical_collector

# Coleta em tempo real
python -m src.python.data_collection.realtime_collector
```

### 4. Feature Engineering
```bash
# Extrair features de tape reading
python -m src.python.feature_engineering.tape_reading_features

# Validar features
python -m src.python.feature_engineering.feature_validator
```

### 5. Sistema Principal
```bash
# Executar sistema completo
python src/python/duarte_scalper_system.py

# Modo debug
python src/python/duarte_scalper_system.py --debug

# Modo paper trading
python src/python/duarte_scalper_system.py --paper-trading
```

## 🏃‍♂️ Comandos Rápidos

| Comando | Descrição |
|---------|-----------|
| `python deploy_to_mt5.py deploy` | Deploy para MT5 |
| `python deploy_to_mt5.py watch` | Desenvolvimento contínuo |
| `python check_environment.py` | Verificar setup |
| `tail -f logs/duarte_scalper.log` | Monitorar logs |

## 📁 Estrutura do Projeto

```
DuarteScalper/
├── src/
│   ├── mql5/           # Código MT5
│   └── python/         # Código Python
├── data/               # Dados de trading
├── logs/               # Logs do sistema
├── config/             # Configurações
└── deploy_to_mt5.py    # Script de deployment
```

## ⚡ Workflow Típico

1. **Setup inicial** → `python check_environment.py`
2. **Deploy** → `python deploy_to_mt5.py deploy`
3. **Desenvolvimento** → `python deploy_to_mt5.py watch`
4. **Executar** → `python src/python/duarte_scalper_system.py`

---

## 🎯 Próximos Passos

1. Verificar símbolos no MT5 (WINM25, WDOM25)
2. Configurar broker em `config/config.yaml`
3. Executar coleta de dados históricos
4. Treinar modelos de IA
5. Iniciar trading automatizado

**📢 Importante**: Execute sempre `python deploy_to_mt5.py deploy` após modificar arquivos MQL5!