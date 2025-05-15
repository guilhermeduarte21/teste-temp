#!/usr/bin/env python3
"""
Script de Deployment Automático - Duarte-Scalper
Deploy inteligente de arquivos MQL5 (.mq5, .mqh)
"""

import os
import shutil
import sys
from pathlib import Path
import json
from datetime import datetime
import time
import logging

class DuarteDeployment:
    """Gerenciador inteligente de deployment para MT5"""
    
    def __init__(self):
        # Paths do projeto
        self.project_root = Path(__file__).parent
        self.src_mql5_path = self.project_root / "src" / "mql5"
        
        # Configurar logging PRIMEIRO
        self.setup_logging()
        
        # Detectar path do MT5 automaticamente
        self.mt5_paths = self.detect_mt5_paths()
        self.selected_mt5_path = None
        
        # Extensões de arquivos que serão deployados
        self.deploy_extensions = ['.mq5', '.mqh', '.ex5']
        
        # Cache para timestamps dos arquivos
        self.file_timestamps = {}
        
    def setup_logging(self):
        """Configura logging para o deployment"""
        log_dir = self.project_root / "logs"
        log_dir.mkdir(exist_ok=True)
        
        # Configurar handlers com codificação UTF-8
        file_handler = logging.FileHandler(
            log_dir / 'deployment.log', 
            encoding='utf-8'
        )
        
        # Console handler sem emojis para evitar problemas de codificação
        console_handler = logging.StreamHandler(sys.stdout)
        
        # Formatters
        file_formatter = logging.Formatter(
            '%(asctime)s - %(levelname)s - %(message)s'
        )
        console_formatter = logging.Formatter(
            '%(levelname)s: %(message)s'
        )
        
        file_handler.setFormatter(file_formatter)
        console_handler.setFormatter(console_formatter)
        
        # Configurar logger
        logging.basicConfig(
            level=logging.INFO,
            handlers=[file_handler, console_handler]
        )
        
        self.logger = logging.getLogger(__name__)
        
    def detect_mt5_paths(self):
        """Detecta todas as instalações do MT5 disponíveis"""
        possible_paths = []
        
        if os.name == 'nt':  # Windows
            # Paths padrão do Windows
            search_paths = [
                Path.home() / "AppData" / "Roaming" / "MetaQuotes" / "Terminal",
                Path("C:") / "Program Files" / "MetaTrader 5",
                Path("C:") / "Program Files (x86)" / "MetaTrader 5",
                Path("D:") / "MetaTrader 5",
                Path("E:") / "MetaTrader 5"
            ]
            
            self.logger.info("Procurando instalações do MT5...")
            
            for base_path in search_paths:
                if base_path.exists():
                    self.logger.info(f"   Verificando: {base_path}")
                    
                    # Buscar por subdiretórios com hash (terminais específicos)
                    for item in base_path.iterdir():
                        if item.is_dir():
                            # Hash do terminal (32 caracteres) ou instalação direta
                            mql5_path = item / "MQL5"
                            if mql5_path.exists():
                                possible_paths.append(mql5_path)
                                self.logger.info(f"   Encontrado: {mql5_path}")
                            
                    # Verificar instalação direta
                    mql5_path = base_path / "MQL5"
                    if mql5_path.exists() and mql5_path not in possible_paths:
                        possible_paths.append(mql5_path)
                        self.logger.info(f"   Encontrado: {mql5_path}")
        
        return possible_paths
    
    def select_mt5_installation(self):
        """Permite usuário selecionar instalação MT5 ou carrega configuração salva"""
        config_file = self.project_root / "deployment_config.json"
        
        # Tentar carregar configuração anterior
        if config_file.exists():
            try:
                with open(config_file, 'r') as f:
                    config = json.load(f)
                    saved_path = Path(config.get('mt5_path', ''))
                    
                if saved_path.exists() and saved_path in self.mt5_paths:
                    self.selected_mt5_path = saved_path
                    self.logger.info(f"✅ Usando MT5 salvo: {self.selected_mt5_path}")
                    return True
            except Exception as e:
                self.logger.warning(f"Erro ao carregar config anterior: {e}")
        
        # Se não encontrou installation anteriores
        if not self.mt5_paths:
            self.logger.error("❌ Nenhuma instalação do MT5 encontrada!")
            return False
            
        # Se há apenas uma instalação
        if len(self.mt5_paths) == 1:
            self.selected_mt5_path = self.mt5_paths[0]
            self.logger.info(f"MT5 encontrado: {self.selected_mt5_path}")
            return True
        
        # Múltiplas instalações - let user choose
        print("\n📁 Múltiplas instalações MT5 encontradas:")
        for i, path in enumerate(self.mt5_paths):
            print(f"  {i+1}. {path}")
        
        while True:
            try:
                choice = int(input("\nEscolha o número da instalação: ")) - 1
                if 0 <= choice < len(self.mt5_paths):
                    self.selected_mt5_path = self.mt5_paths[choice]
                    self.logger.info(f"✅ Selecionado: {self.selected_mt5_path}")
                    return True
                else:
                    print("❌ Opção inválida!")
            except ValueError:
                print("❌ Por favor, digite um número!")
    
    def scan_mql5_files(self):
        """Escaneia todos os arquivos MQL5 no projeto"""
        mql5_files = []
        
        if not self.src_mql5_path.exists():
            self.logger.error(f"❌ Diretório MQL5 não encontrado: {self.src_mql5_path}")
            return mql5_files
        
        # Buscar recursivamente por arquivos MQL5
        for ext in self.deploy_extensions:
            files = list(self.src_mql5_path.glob(f"**/*{ext}"))
            mql5_files.extend(files)
        
        self.logger.info(f"Encontrados {len(mql5_files)} arquivos MQL5 para deploy")
        return mql5_files
    
    def get_deploy_mapping(self, mql5_files):
        """Cria mapeamento de arquivos origem -> destino"""
        file_mappings = []
        
        for src_file in mql5_files:
            # Calcular path relativo do arquivo dentro de src/mql5/
            rel_path = src_file.relative_to(self.src_mql5_path)
            
            # Determinar destino no MT5
            dest_path = self.map_to_mt5_structure(rel_path)
            
            if dest_path:
                full_dest = self.selected_mt5_path / dest_path
                file_mappings.append((src_file, full_dest))
        
        return file_mappings
    
    def map_to_mt5_structure(self, rel_path):
        """Mapeia estrutura do projeto para estrutura do MT5 dentro da pasta DuarteScalper"""
        parts = rel_path.parts
        
        if not parts:
            return None
        
        # Mapear diretórios com subpasta DuarteScalper
        if parts[0] == 'experts':
            return Path('Experts') / 'DuarteScalper' / Path(*parts[1:])
        elif parts[0] == 'include':
            return Path('Include') / 'DuarteScalper' / Path(*parts[1:])
        elif parts[0] == 'indicators':
            return Path('Indicators') / 'DuarteScalper' / Path(*parts[1:])
        elif parts[0] == 'scripts':
            return Path('Scripts') / 'DuarteScalper' / Path(*parts[1:])
        else:
            # Arquivos na raiz vão para Experts/DuarteScalper
            return Path('Experts') / 'DuarteScalper' / rel_path
    
    def create_mt5_directories(self, file_mappings):
        """Cria diretórios necessários no MT5"""
        dirs_created = set()
        
        for src, dest in file_mappings:
            dest_dir = dest.parent
            
            if dest_dir not in dirs_created:
                dest_dir.mkdir(parents=True, exist_ok=True)
                self.logger.info(f"Criado: {dest_dir}")
                dirs_created.add(dest_dir)
    
    def deploy_files(self, file_mappings, force=False):
        """Deploy dos arquivos com verificação de mudanças"""
        deployed_count = 0
        skipped_count = 0
        
        for src, dest in file_mappings:
            # Verificar se arquivo precisa ser atualizado
            if not force and not self.file_needs_update(src, dest):
                skipped_count += 1
                continue
            
            try:
                # Fazer backup se arquivo existir
                if dest.exists():
                    backup_path = dest.with_suffix(dest.suffix + '.backup')
                    shutil.copy2(dest, backup_path)
                    self.logger.info(f"Backup: {dest.name}")
                
                # Copiar arquivo
                shutil.copy2(src, dest)
                
                # Atualizar timestamp cache
                self.file_timestamps[str(src)] = src.stat().st_mtime
                
                self.logger.info(f"Deployed: {src.name} -> {dest.relative_to(self.selected_mt5_path)}")
                deployed_count += 1
                
            except Exception as e:
                self.logger.error(f"❌ Erro ao copiar {src.name}: {e}")
        
        return deployed_count, skipped_count
    
    def file_needs_update(self, src, dest):
        """Verifica se arquivo precisa ser atualizado"""
        # Se destino não existe, sempre atualizar
        if not dest.exists():
            return True
        
        # Comparar timestamps
        src_mtime = src.stat().st_mtime
        dest_mtime = dest.stat().st_mtime
        
        # Verificar cache
        cached_mtime = self.file_timestamps.get(str(src))
        if cached_mtime and cached_mtime == src_mtime:
            return False
        
        return src_mtime > dest_mtime
    
    def save_deployment_config(self, deployed_files):
        """Salva configuração do deployment"""
        config_file = self.project_root / "deployment_config.json"
        
        config = {
            "mt5_path": str(self.selected_mt5_path),
            "last_deployment": datetime.now().isoformat(),
            "deployed_files": [str(f[1]) for f in deployed_files],
            "project_version": "1.0.0",
            "deployment_type": "auto_scan"
        }
        
        with open(config_file, 'w') as f:
            json.dump(config, f, indent=2)
        
        self.logger.info(f"Configuração salva em: {config_file}")
    
    def run_deployment(self, force=False):
        """Executa deployment completo"""
        print("========================================")
        print("    DUARTE-SCALPER DEPLOYMENT")
        print("========================================")
        
        # 1. Selecionar MT5
        if not self.select_mt5_installation():
            return False
        
        # 2. Escanear arquivos MQL5
        print("\nEscaneando arquivos MQL5...")
        mql5_files = self.scan_mql5_files()
        
        if not mql5_files:
            self.logger.warning("Nenhum arquivo MQL5 encontrado para deploy")
            return False
        
        # 3. Criar mapeamento de arquivos
        print("\nCriando mapeamento de arquivos...")
        file_mappings = self.get_deploy_mapping(mql5_files)
        
        # 4. Criar diretórios
        print("\nCriando estrutura de diretórios...")
        self.create_mt5_directories(file_mappings)
        
        # 5. Deploy arquivos
        print(f"\nCopiando arquivos{'(forçado)' if force else ''}...")
        deployed_count, skipped_count = self.deploy_files(file_mappings, force)
        
        # 6. Salvar configuração
        print("\nSalvando configuração...")
        self.save_deployment_config(file_mappings)
        
        # 7. Resumo
        print(f"\nDEPLOYMENT CONCLUIDO!")
        print(f"   MT5 Path: {self.selected_mt5_path}")
        print(f"   Arquivos deployados: {deployed_count}")
        print(f"   Arquivos pulos: {skipped_count}")
        print(f"   Total de arquivos: {len(file_mappings)}")
        
        if deployed_count > 0:
            print("\nPROXIMOS PASSOS:")
            print("1. Abrir MetaEditor")
            print("2. Compilar arquivos modificados em:")
            print("   - Experts/DuarteScalper/")
            print("   - Include/DuarteScalper/")
            print("3. Executar/recarregar EA no MT5")
        
        return True
    
    def clean_deployment(self):
        """Remove todos os arquivos deployados"""
        config_file = self.project_root / "deployment_config.json"
        
        if not config_file.exists():
            self.logger.error("❌ Nenhuma configuração de deployment encontrada")
            return False
        
        try:
            with open(config_file, 'r') as f:
                config = json.load(f)
            
            deployed_files = config.get('deployed_files', [])
            removed_count = 0
            
            print("Limpando deployment anterior...")
            
            for file_path in deployed_files:
                file_path = Path(file_path)
                if file_path.exists():
                    file_path.unlink()
                    self.logger.info(f"Removido: {file_path}")
                    removed_count += 1
            
            print(f"CONCLUIDO: {removed_count} arquivos removidos")
            return True
            
        except Exception as e:
            self.logger.error(f"❌ Erro durante limpeza: {e}")
            return False
    
    def watch_files(self):
        """Assiste mudanças nos arquivos e auto-deploy"""
        try:
            print("MODO WATCH ATIVADO")
            print("Monitorando mudanças em arquivos MQL5...")
            print("Pressione Ctrl+C para parar\n")
            
            last_scan = {}
            
            while True:
                # Escanear arquivos
                mql5_files = self.scan_mql5_files()
                files_changed = []
                
                # Verificar mudanças
                for file_path in mql5_files:
                    mtime = file_path.stat().st_mtime
                    
                    if str(file_path) not in last_scan:
                        last_scan[str(file_path)] = mtime
                        continue
                    
                    if mtime > last_scan[str(file_path)]:
                        files_changed.append(file_path)
                        last_scan[str(file_path)] = mtime
                
                # Auto-deploy se houve mudanças
                if files_changed:
                    print(f"Detectadas mudanças em {len(files_changed)} arquivo(s)")
                    
                    # Deploy apenas arquivos modificados
                    file_mappings = self.get_deploy_mapping(files_changed)
                    if file_mappings:
                        self.create_mt5_directories(file_mappings)
                        deployed, _ = self.deploy_files(file_mappings, force=True)
                        print(f"CONCLUIDO: {deployed} arquivo(s) re-deployados\n")
                
                time.sleep(1)  # Check a cada segundo
                
        except KeyboardInterrupt:
            print("\nWatch mode finalizado")
        except ImportError:
            print("Para usar file watching, instale: pip install watchdog")


def main():
    """Função principal"""
    import argparse
    
    parser = argparse.ArgumentParser(description='Deploy Duarte-Scalper para MT5')
    parser.add_argument('command', nargs='?', default='deploy',
                       choices=['deploy', 'watch', 'clean', 'force'],
                       help='Comando a executar')
    
    args = parser.parse_args()
    
    deployer = DuarteDeployment()
    
    if args.command == 'deploy':
        deployer.run_deployment()
    elif args.command == 'force':
        deployer.run_deployment(force=True)
    elif args.command == 'watch':
        if not deployer.select_mt5_installation():
            return
        deployer.watch_files()
    elif args.command == 'clean':
        deployer.clean_deployment()
    else:
        print("Comando não reconhecido!")
        print("Uso: python deploy_to_mt5.py [deploy|watch|clean|force]")


if __name__ == "__main__":
    main()