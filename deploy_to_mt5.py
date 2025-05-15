#!/usr/bin/env python3
"""
Script de Deployment Automático - Duarte-Scalper
Copia arquivos do Git para estrutura MT5
"""

import os
import shutil
import sys
from pathlib import Path
import json

class DuarteDeployment:
    """Gerenciador de deployment para MT5"""
    
    def __init__(self):
        # Paths do projeto
        self.project_root = Path(__file__).parent
        self.src_path = self.project_root / "src"
        
        # Detectar path do MT5 automaticamente
        self.mt5_paths = self.detect_mt5_paths()
        self.selected_mt5_path = None
        
    def detect_mt5_paths(self):
        """Detecta possíveis instalações do MT5"""
        possible_paths = []
        
        # Windows paths comuns
        if os.name == 'nt':
            base_paths = [
                Path.home() / "AppData" / "Roaming" / "MetaQuotes" / "Terminal",
                Path("C:") / "Program Files" / "MetaTrader 5",
                Path("D:") / "MetaTrader 5",
                Path("E:") / "MetaTrader 5",
                # Adicionar mais paths se necessário
            ]
            
            print("🔍 Procurando instalações do MT5...")
            for base_path in base_paths:
                print(f"   Checking: {base_path}")
                if base_path.exists():
                    print(f"   ✅ Encontrado: {base_path}")
            
            for base_path in base_paths:
                if base_path.exists():
                    # Buscar por subdiretórios com hash (terminais específicos)
                    for item in base_path.iterdir():
                        if item.is_dir() and len(item.name) == 32:  # Hash MT5
                            mql5_path = item / "MQL5"
                            if mql5_path.exists():
                                possible_paths.append(mql5_path)
                    
                    # Também verificar instalação direta
                    mql5_path = base_path / "MQL5"
                    if mql5_path.exists():
                        possible_paths.append(mql5_path)
        
        return possible_paths
    
    def select_mt5_installation(self):
        """Permite usuário selecionar instalação MT5"""
        if not self.mt5_paths:
            print("❌ Nenhuma instalação do MT5 encontrada!")
            return False
            
        if len(self.mt5_paths) == 1:
            self.selected_mt5_path = self.mt5_paths[0]
            print(f"✅ MT5 encontrado: {self.selected_mt5_path}")
            return True
        
        print("\n📁 Múltiplas instalações MT5 encontradas:")
        for i, path in enumerate(self.mt5_paths):
            print(f"  {i+1}. {path}")
        
        while True:
            try:
                choice = int(input("\nEscolha o número da instalação: ")) - 1
                if 0 <= choice < len(self.mt5_paths):
                    self.selected_mt5_path = self.mt5_paths[choice]
                    print(f"✅ Selecionado: {self.selected_mt5_path}")
                    return True
                else:
                    print("❌ Opção inválida!")
            except ValueError:
                print("❌ Por favor, digite um número!")
    
    def create_mt5_structure(self):
        """Cria estrutura de diretórios no MT5"""
        if not self.selected_mt5_path:
            print("❌ Path MT5 não selecionado!")
            return False
        
        # Criar diretórios necessários
        dirs_to_create = [
            self.selected_mt5_path / "Include" / "DuarteScalper",
            self.selected_mt5_path / "Experts" / "DuarteScalper",
            self.selected_mt5_path / "Indicators" / "DuarteScalper",
            self.selected_mt5_path / "Files" / "DuarteScalper"
        ]
        
        for dir_path in dirs_to_create:
            dir_path.mkdir(parents=True, exist_ok=True)
            print(f"📁 Criado: {dir_path}")
        
        return True
    
    def deploy_mql5_files(self):
        """Copia arquivos MQL5 para MT5"""
        if not self.selected_mt5_path:
            return False
        
        # Mapping de origem -> destino
        file_mappings = [
            # Include files
            (
                self.src_path / "mql5" / "include" / "Communication.mqh",
                self.selected_mt5_path / "Include" / "DuarteScalper" / "Communication.mqh"
            ),
            # Expert Advisors
            (
                self.src_path / "mql5" / "experts" / "DuarteScalerBase.mq5",
                self.selected_mt5_path / "Experts" / "DuarteScalper" / "DuarteScalerBase.mq5"
            ),
            (
                self.src_path / "mql5" / "experts" / "Duarte-Scalper.mq5",
                self.selected_mt5_path / "Experts" / "DuarteScalper" / "Duarte-Scalper.mq5"
            )
        ]
        
        copied_files = 0
        for src, dst in file_mappings:
            if src.exists():
                # Backup do arquivo existente
                if dst.exists():
                    backup_path = dst.with_suffix(dst.suffix + ".backup")
                    shutil.copy2(dst, backup_path)
                    print(f"📄 Backup: {dst.name}")
                
                # Copiar arquivo
                shutil.copy2(src, dst)
                print(f"✅ Copiado: {src.name} → {dst}")
                copied_files += 1
            else:
                print(f"⚠️  Arquivo não encontrado: {src}")
        
        return copied_files > 0
    
    def create_deployment_config(self):
        """Cria arquivo de configuração do deployment"""
        config_file = self.project_root / "deployment_config.json"
        
        config = {
            "mt5_path": str(self.selected_mt5_path),
            "last_deployment": str(Path.now()),
            "deployed_files": [
                "Include/DuarteScalper/Communication.mqh",
                "Experts/DuarteScalper/DuarteScalerBase.mq5",
                "Experts/DuarteScalper/Duarte-Scalper.mq5"
            ],
            "deployment_notes": "Estrutura atualizada para Duarte-Scalper"
        }
        
        with open(config_file, 'w') as f:
            json.dump(config, f, indent=4)
        
        print(f"💾 Config salva: {config_file}")
    
    def run_deployment(self):
        """Executa deployment completo"""
        print("🚀 INICIANDO DEPLOYMENT DUARTE-SCALPER")
        print("="*50)
        
        # 1. Selecionar MT5
        if not self.select_mt5_installation():
            return False
        
        # 2. Criar estrutura
        print("\n📁 Criando estrutura de diretórios...")
        if not self.create_mt5_structure():
            return False
        
        # 3. Copiar arquivos
        print("\n📄 Copiando arquivos MQL5...")
        if not self.deploy_mql5_files():
            print("❌ Falha ao copiar arquivos!")
            return False
        
        # 4. Salvar configuração
        print("\n💾 Salvando configuração...")
        self.create_deployment_config()
        
        print("\n✅ DEPLOYMENT CONCLUÍDO!")
        print(f"   Path MT5: {self.selected_mt5_path}")
        print("\n📋 PRÓXIMOS PASSOS:")
        print("1. Abrir MetaEditor")
        print("2. Compilar Communication.mqh")
        print("3. Compilar Duarte-Scalper.mq5")
        print("4. Executar no MT5")
        
        return True

# Script utilitário para desenvolvimento
class DuarteDevTools:
    """Ferramentas úteis para desenvolvimento"""
    
    @staticmethod
    def create_symlinks(src_path, mt5_path):
        """Cria links simbólicos (requer admin no Windows)"""
        try:
            import os
            
            # Links para arquivos principais
            links = [
                (
                    src_path / "mql5" / "include" / "Communication.mqh",
                    mt5_path / "Include" / "DuarteScalper" / "Communication.mqh"
                )
            ]
            
            for src, dst in links:
                if dst.exists():
                    dst.unlink()
                os.symlink(src, dst)
                print(f"🔗 Link criado: {dst.name}")
            
            return True
        except Exception as e:
            print(f"❌ Erro ao criar links: {e}")
            return False
    
    @staticmethod
    def watch_files():
        """Watch para auto-deployment em desenvolvimento"""
        try:
            from watchdog.observers import Observer
            from watchdog.events import FileSystemEventHandler
            
            class DeploymentHandler(FileSystemEventHandler):
                def on_modified(self, event):
                    if event.src_path.endswith(('.mq5', '.mqh')):
                        print(f"📄 Arquivo modificado: {event.src_path}")
                        # Trigger re-deployment
            
            # Setup watch
            observer = Observer()
            handler = DeploymentHandler()
            observer.schedule(handler, "src/mql5", recursive=True)
            observer.start()
            
            print("👀 Watching for changes... Press Ctrl+C to stop")
            import time
            while True:
                time.sleep(1)
                
        except ImportError:
            print("⚠️  Para usar file watching, instale: pip install watchdog")
        except KeyboardInterrupt:
            print("\n✅ File watching stopped")

def main():
    """Função principal"""
    if len(sys.argv) > 1:
        command = sys.argv[1].lower()
        
        if command == "deploy":
            deployer = DuarteDeployment()
            deployer.run_deployment()
            
        elif command == "watch":
            DuarteDevTools.watch_files()
            
        elif command == "symlink":
            print("🔗 Criando links simbólicos...")
            # Implementar se necessário
            
        else:
            print("❌ Comando não reconhecido!")
            print("Uso: python deploy_to_mt5.py [deploy|watch|symlink]")
    else:
        # Deployment padrão
        deployer = DuarteDeployment()
        deployer.run_deployment()

if __name__ == "__main__":
    main()