#!/usr/bin/env bash
# ==============================================================================
# 04_prepare_receptor.sh - Preparação do receptor (sem cofator)
# Aceita estruturas brutas tanto em formato .pdb quanto .cif (mmCIF).
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

RAW_RECEPTOR=$(resolve_raw_receptor "$TARGET" "$PDB_ID")
CLEAN_PDB="targets/${TARGET}/receptor/prepared/protein_clean.pdb"
CLEAN_CIF="targets/${TARGET}/receptor/prepared/protein_clean.cif"
OUT_PDBQT="targets/${TARGET}/receptor/prepared/receptor.pdbqt"

mkdir -p "targets/${TARGET}/receptor/prepared"

# Passo 1: Obter estrutura limpa da proteína (protein_clean.pdb ou protein_clean.cif)
CLEAN_STRUCT=""
if [ -f "$CLEAN_PDB" ] && [ -s "$CLEAN_PDB" ]; then
    CLEAN_STRUCT="$CLEAN_PDB"
    echo "[.] Encontrado arquivo limpo existente: ${CLEAN_STRUCT}"
elif [ -f "$CLEAN_CIF" ] && [ -s "$CLEAN_CIF" ]; then
    CLEAN_STRUCT="$CLEAN_CIF"
    echo "[.] Encontrado arquivo limpo (.cif) existente: ${CLEAN_STRUCT}"
else
    echo "[+] Preparando proteína limpa a partir de ${RAW_RECEPTOR}..."
    if [ ! -f "$RAW_RECEPTOR" ] || [ ! -s "$RAW_RECEPTOR" ]; then
        echo "[-] Erro: Arquivo bruto ${RAW_RECEPTOR} não encontrado! Execute primeiro o script 02_download_pdb.sh"
        exit 1
    fi

    if command -v chimerax &> /dev/null; then
        echo "    [+] Usando ChimeraX headless para remover solvente e isolar a proteína..."
        chimerax --nogui --cmd "
        open ${RAW_RECEPTOR};
        delete solvent;
        select protein;
        save ${CLEAN_PDB} selectedOnly true;
        exit;
        " || true

        if [ -f "$CLEAN_PDB" ] && [ -s "$CLEAN_PDB" ]; then
            CLEAN_STRUCT="$CLEAN_PDB"
            echo "    [✓] Proteína isolada salva em: ${CLEAN_STRUCT}"
        else
            echo "    [!] Estrutura excede limites do formato .pdb legado; salvando como ${CLEAN_CIF}..."
            chimerax --nogui --cmd "
            open ${RAW_RECEPTOR};
            delete solvent;
            select protein;
            save ${CLEAN_CIF} selectedOnly true;
            exit;
            "
            CLEAN_STRUCT="$CLEAN_CIF"
            echo "    [✓] Proteína isolada (.cif) salva em: ${CLEAN_STRUCT}"
        fi
    else
        echo "    [+] Isolando proteína via Python/ProDy..."
        python3 - "$RAW_RECEPTOR" "$CLEAN_PDB" << 'PYEOF'
import sys
import prody

raw_path, out_pdb = sys.argv[1:3]
if raw_path.lower().endswith((".cif", ".mmcif")):
    atoms = prody.parseMMCIF(raw_path)
else:
    atoms = prody.parsePDB(raw_path)

prot = atoms.select("protein and not water")
prody.writePDB(out_pdb, prot)
PYEOF
        CLEAN_STRUCT="$CLEAN_PDB"
        echo "    [✓] Proteína isolada salva em: ${CLEAN_STRUCT}"
    fi
fi

# Passo 2: Preparar o receptor com Meeko (gerar PDBQT)
if ! command -v mk_prepare_receptor.py &> /dev/null; then
    echo "[-] Erro: 'mk_prepare_receptor.py' (Meeko) não encontrado no PATH!"
    echo "    Certifique-se de ativar o ambiente conda: conda activate docking_vina"
    exit 1
fi

echo "[+] Convertendo receptor (${CLEAN_STRUCT}) para PDBQT com Meeko..."
mk_prepare_receptor.py \
  -i "$CLEAN_STRUCT" \
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
