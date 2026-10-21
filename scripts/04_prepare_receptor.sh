#!/usr/bin/env bash
# ==============================================================================
# 04_prepare_receptor.sh - Preparação do receptor (sem cofator)
# ==============================================================================
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/load_config.sh" "$@"

TARGET="${TARGET:-}"
PDB_ID="${PDB_ID:-}"

if [ -z "$TARGET" ]; then
    echo "[-] Erro: TARGET não foi definido!"
    echo "    Uso: $0 [TARGET] [PDB_ID]"
    exit 1
fi

# Tentar carregar ambiente conda se meeko não estiver no PATH
if ! command -v mk_prepare_receptor.py &> /dev/null; then
    if [ -f "$HOME/miniconda3/etc/profile.d/conda.sh" ]; then
        # shellcheck source=/dev/null
        source "$HOME/miniconda3/etc/profile.d/conda.sh"
        conda activate docking_vina 2>/dev/null || conda activate vina 2>/dev/null || true
    fi
fi

RAW_PDB="targets/${TARGET}/receptor/raw/${PDB_ID}.pdb"
CLEAN_PDB="targets/${TARGET}/receptor/prepared/protein_clean.pdb"
OUT_PDBQT="targets/${TARGET}/receptor/prepared/receptor.pdbqt"

mkdir -p "targets/${TARGET}/receptor/prepared"

# Passo 1: Obter protein_clean.pdb
if [ -f "$CLEAN_PDB" ]; then
    echo "[.] Encontrado arquivo limpo existente: ${CLEAN_PDB}"
else
    echo "[+] ${CLEAN_PDB} não encontrado. Tentando preparar a partir de ${RAW_PDB}..."
    if [ ! -f "$RAW_PDB" ]; then
        echo "[-] Erro: Arquivo bruto ${RAW_PDB} não encontrado! Execute primeiro o script 02_download_pdb.sh"
        exit 1
    fi

    if command -v chimerax &> /dev/null; then
        echo "    [+] Usando ChimeraX headless para remover solvente e isolar a proteína..."
        chimerax --nogui --cmd "
        open ${RAW_PDB};
        delete solvent;
        select protein;
        save ${CLEAN_PDB} selectedOnly true;
        exit;
        "
        echo "    [✓] Proteína isolada salva em: ${CLEAN_PDB}"
    else
        echo "[-] Aviso: 'chimerax' não encontrado no PATH."
        echo "    Por favor, abra ${RAW_PDB} no Discovery Studio ou ChimeraX,"
        echo "    remova águas/solventes e o ligante, e salve como:"
        echo "    -> ${CLEAN_PDB}"
        exit 1
    fi
fi

# Passo 2: Preparar o receptor com Meeko (gerar PDBQT)
if ! command -v mk_prepare_receptor.py &> /dev/null; then
    echo "[-] Erro: 'mk_prepare_receptor.py' (Meeko) não encontrado no PATH!"
    echo "    Certifique-se de ativar o ambiente conda: conda activate docking_vina"
    exit 1
fi

echo "[+] Convertendo receptor para PDBQT com Meeko..."
mk_prepare_receptor.py \
  -i "$CLEAN_PDB" \
  -p "$OUT_PDBQT" \
  --default_altloc A \
  --delete_bad_res

if [ -f "$OUT_PDBQT" ] && [ -s "$OUT_PDBQT" ]; then
    echo "[✓] Receptor preparado com sucesso!"
    echo "    Arquivo: ${OUT_PDBQT}"
else
    echo "[-] Falha ao gerar: ${OUT_PDBQT}"
    exit 1
fi
