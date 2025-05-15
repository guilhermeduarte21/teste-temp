#!/usr/bin/env python3
"""
Script para criar estrutura de diretórios e arquivos
do sistema de comunicação
"""

import os
from pathlib import Path

def create_communication_structure():
    """Cria estrutura de diretórios para comunicação"""
    
    # Diretório base do projeto
    base_dir = Path(r"C:\DuarteScalper")
    
    # Diretórios Python
    python_dirs = [
        "src/python/communication",
        "src/python/prediction", 
        "src/python/model_training"
    ]
    
    # Diretórios MQL5
    mql5_dirs = [
        "src/mql5/experts",
        "src/mql5/include",
        "src/mql5/indicators"
    ]
    
    # Criar diretórios
    all_dirs = python_dirs + mql5_dirs
    
    for dir_path in all_dirs:
        full_path = base_dir / dir_path
        full_path.mkdir(parents=True, exist_ok=True)
        print(f"✅ Criado: {full_path}")
        
        # Criar __init__.py para diretórios Python
        if "python" in dir_path:
            init_file = full_path / "__init__.py"
            if not init_file.exists():
                init_file.write_text(f'"""{dir_path.replace("/", ".")} module"""\n')
                print(f"   └─ __init__.py criado")
    
    print(f"\n🎯 **ESTRUTURA CRIADA!**")
    print(f"\n📁 **ONDE SALVAR OS ARQUIVOS:**")
    print(f"")
    print(f"1. **communication_handler.py**")
    print(f"   → {base_dir}/src/python/communication/communication_handler.py")
    print(f"")
    print(f"2. **DuarteCommunication.mqh**")
    print(f"   → {base_dir}/src/mql5/include/DuarteCommunication.mqh")
    print(f"")
    print(f"3. **DuarteScalerBase.mq5**")
    print(f"   → {base_dir}/src/mql5/experts/DuarteScalerBase.mq5")
    print(f"")
    print(f"4. **duarte_scalper_system.py**")
    print(f"   → {base_dir}/src/python/duarte_scalper_system.py")

if __name__ == "__main__":
    create_communication_structure()