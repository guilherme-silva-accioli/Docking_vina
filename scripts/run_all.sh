#!/usr/bin/env bash
# ==============================================================================
# run_all.sh - Pipeline Completo de Docking Molecular (com ou sem cofator)
# ==============================================================================
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/load_config.sh" "$@"

TARGET="${TARGET:-}"
PDB_ID="${PDB_ID:-}"
NATIVE_LIG="${NATIVE_LIG:-}"
INCHIKEY_SRC="${INCHIKEY_SRC:-}"
COFACTOR_RES="${COFACTOR_RES:-}"

if [ -z "$TARGET" ]; then
    echo "[-] Erro: TARGET não foi definido!"
    echo "    Formas de uso:"
    echo "      1) Passando o nome do alvo (se existir configs/<ALVO>.env):"
    echo "         $0 CCND1"
    echo "      2) Passando o arquivo de configuração diretamente:"
    echo "         $0 configs/CCND1.env"
    echo "         $0 --config configs/JAK2.env"
    echo "      3) Passando argumentos manuais:"
    echo "         $0 CCND1 2W96 Z36"
    echo "      4) Usando scripts/config.env padrão:"
    echo "         $0"
    exit 1
fi

echo "=========================================================="
echo "    INICIANDO PIPELINE DE DOCKING MOLECULAR"
echo "    Alvo:        ${TARGET}"
echo "    PDB ID:      ${PDB_ID}"
echo "    Ligante Nat: ${NATIVE_LIG}"
if [ -n "$COFACTOR_RES" ]; then
    echo "    Cofatores:   ${COFACTOR_RES}"
fi
if [ -n "$CONFIG_FILE" ]; then
    echo "    Config:      ${CONFIG_FILE}"
fi
if [ -n "$INCHIKEY_SRC" ]; then
    echo "    InChIKeys:   ${INCHIKEY_SRC}"
fi
echo "=========================================================="

echo ""
echo ">>> [ETAPA 1/7] Criando estrutura de pastas e carregando InChIKeys..."
bash "${SCRIPT_DIR}/01_setup_target.sh" "$TARGET" "$PDB_ID" "$NATIVE_LIG" "$INCHIKEY_SRC"

echo ""
echo ">>> [ETAPA 2/7] Baixando estrutura do receptor..."
bash "${SCRIPT_DIR}/02_download_pdb.sh" "$TARGET" "$PDB_ID"

if [ -n "$NATIVE_LIG" ]; then
    echo ""
    echo ">>> [ETAPA 3/7] Executando Redocking (Controle Positivo e Centro do Grid)..."
    bash "${SCRIPT_DIR}/07_run_redocking.sh" "$TARGET" "$PDB_ID" "$NATIVE_LIG" || {
        echo "[-] Redocking falhou ou foi ignorado. Continuando..."
    }
else
    echo ""
    echo ">>> [ETAPA 3/7] NATIVE_LIG não definido. Pulando redocking."
fi

echo ""
if [ -n "$COFACTOR_RES" ]; then
    echo ">>> [ETAPA 4/7] Preparando receptor COM cofatores (${COFACTOR_RES})..."
    bash "${SCRIPT_DIR}/04b_prepare_receptor_cofactor.sh" "$TARGET" "$PDB_ID" "$COFACTOR_RES"
else
    echo ">>> [ETAPA 4/7] Preparando receptor (sem cofator)..."
    bash "${SCRIPT_DIR}/04_prepare_receptor.sh" "$TARGET" "$PDB_ID"
fi

echo ""
echo ">>> [ETAPA 5/7] Baixando ligantes do PubChem..."
bash "${SCRIPT_DIR}/03_download_ligands.sh" "$TARGET"

echo ""
echo ">>> [ETAPA 6/7] Preparando ligantes (cargas + PDBQT)..."
bash "${SCRIPT_DIR}/05_prepare_ligands.sh" "$TARGET"

echo ""
echo ">>> [ETAPA 7/7] Executando Docking Molecular no Vina..."
bash "${SCRIPT_DIR}/06_run_docking.sh" "$TARGET"

echo ""
echo "=========================================================="
echo "    [✓] PIPELINE CONCLUÍDO COM SUCESSO PARA: ${TARGET}"
echo "=========================================================="
