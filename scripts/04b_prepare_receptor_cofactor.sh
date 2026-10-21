#!/usr/bin/env bash
# ==============================================================================
# 04b_prepare_receptor_cofactor.sh - Preparação do receptor COM cofatores
# Isola proteína + cofatores (ChimeraX), gera templates JSON (Meeko v0.6+)
# e converte para receptor.pdbqt mantendo cofatores e íons coordenados.
# ==============================================================================
set -e

ORIG_ARG3="${3:-}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/load_config.sh" "$@"

TARGET="${TARGET:-}"
PDB_ID="${PDB_ID:-}"
if [ -n "$ORIG_ARG3" ]; then
    COFACTOR_RES="$ORIG_ARG3"
fi
COFACTOR_RES="${COFACTOR_RES:-}"

if [ -z "$TARGET" ]; then
    echo "[-] Erro: TARGET não foi definido!"
    echo "    Uso: $0 [TARGET] [PDB_ID] [COFACTOR_RES]"
    exit 1
fi

if [ -z "$COFACTOR_RES" ]; then
    echo "[-] Erro: COFACTOR_RES não foi definido para o alvo '${TARGET}'!"
    echo "    Defina COFACTOR_RES=\"GNP,MG\" no arquivo configs/${TARGET}.env"
    echo "    ou passe como argumento: $0 ${TARGET} ${PDB_ID} \"GNP,MG\""
    exit 1
fi

# Carregar ambiente conda se mk_prepare_receptor.py não estiver no PATH
if ! command -v mk_prepare_receptor.py &> /dev/null; then
    if [ -f "$HOME/miniconda3/etc/profile.d/conda.sh" ]; then
        # shellcheck source=/dev/null
        source "$HOME/miniconda3/etc/profile.d/conda.sh"
        conda activate docking_vina 2>/dev/null || conda activate vina 2>/dev/null || true
    fi
fi

RAW_PDB="targets/${TARGET}/receptor/raw/${PDB_ID}.pdb"
COFACTOR_DIR="targets/${TARGET}/receptor/cofactor"
TEMPLATES_DIR="targets/${TARGET}/receptor/templates"
PREPARED_DIR="targets/${TARGET}/receptor/prepared"

COFACTOR_PDB="${COFACTOR_DIR}/cofactor_atoms.pdb"
RECEPTOR_COF_PDB="${PREPARED_DIR}/receptor_with_cofactor.pdb"
TEMPLATE_JSON="${TEMPLATES_DIR}/cofactor_template.json"
OUT_PDBQT="${PREPARED_DIR}/receptor.pdbqt"

mkdir -p "$COFACTOR_DIR" "$TEMPLATES_DIR" "$PREPARED_DIR"

echo "[+] Preparando receptor '${TARGET}' (${PDB_ID}) com cofator(es): ${COFACTOR_RES}"

# Passo 1: Extrair cofatores e combinar proteína + cofatores
if [ -f "$RECEPTOR_COF_PDB" ] && [ -s "$RECEPTOR_COF_PDB" ]; then
    echo "[.] Encontrado arquivo existente: ${RECEPTOR_COF_PDB}"
else
    if [ ! -f "$RAW_PDB" ]; then
        echo "[-] Erro: Arquivo bruto ${RAW_PDB} não encontrado! Execute primeiro 02_download_pdb.sh"
        exit 1
    fi

    if command -v chimerax &> /dev/null; then
        echo "    [+] Usando ChimeraX headless para isolar proteína e cofator(es) (${COFACTOR_RES})..."
        chimerax --nogui --cmd "
        open ${RAW_PDB};
        delete solvent;
        select :${COFACTOR_RES};
        save ${COFACTOR_PDB} selectedOnly true;
        select protein | :${COFACTOR_RES};
        save ${RECEPTOR_COF_PDB} selectedOnly true;
        exit;
        "
    fi

    # Fallback via Python/ProDy caso o ChimeraX não esteja instalado ou não tenha gerado os arquivos
    if [ ! -f "$RECEPTOR_COF_PDB" ] || [ ! -s "$RECEPTOR_COF_PDB" ]; then
        echo "    [+] Isolando proteína e cofator(es) (${COFACTOR_RES}) via ProDy..."
        python3 - "$RAW_PDB" "$COFACTOR_RES" "$COFACTOR_PDB" "$RECEPTOR_COF_PDB" << 'PYEOF'
import sys
import prody

raw_pdb, cofactor_res, cof_pdb, rec_cof_pdb = sys.argv[1:5]
res_list = [r.strip().upper() for r in cofactor_res.split(",") if r.strip()]
res_sel_str = " or ".join([f"resname {r}" for r in res_list])

atoms = prody.parsePDB(raw_pdb)
cof_sel = atoms.select(f"({res_sel_str}) and not water")
if cof_sel is None or cof_sel.numAtoms() == 0:
    print(f"[-] Erro: Nenhum átomo encontrado para os cofatores {res_list} em {raw_pdb}", file=sys.stderr)
    sys.exit(1)
prody.writePDB(cof_pdb, cof_sel)

rec_sel = atoms.select(f"(protein or ({res_sel_str})) and not water")
prody.writePDB(rec_cof_pdb, rec_sel)
PYEOF
    fi

    echo "    [✓] Cofator isolado salvo em: ${COFACTOR_PDB}"
    echo "    [✓] Proteína + cofator salvos em: ${RECEPTOR_COF_PDB}"
fi

# Passo 2: Construir template JSON para cofatores orgânicos (Meeko v0.6+)
echo "[+] Verificando/construindo templates químicos para os cofatores (${COFACTOR_RES})..."
python3 "${SCRIPT_DIR}/build_cofactor_templates.py" "$COFACTOR_RES" "$COFACTOR_PDB" "$TEMPLATE_JSON"

ADD_TEMPLATES_ARGS=()
if [ -f "$TEMPLATE_JSON" ] && [ -s "$TEMPLATE_JSON" ]; then
    ADD_TEMPLATES_ARGS=(--add_templates "$TEMPLATE_JSON")
fi

# Passo 3: Converter receptor + cofator para PDBQT com Meeko
if ! command -v mk_prepare_receptor.py &> /dev/null; then
    echo "[-] Erro: 'mk_prepare_receptor.py' (Meeko) não encontrado no PATH!"
    echo "    Ative o ambiente conda: conda activate docking_vina"
    exit 1
fi

echo "[+] Convertendo receptor com cofator para PDBQT via Meeko..."
mk_prepare_receptor.py \
  -i "$RECEPTOR_COF_PDB" \
  "${ADD_TEMPLATES_ARGS[@]}" \
  -p "$OUT_PDBQT" \
  --default_altloc A \
  --delete_bad_res \
  --forgive_extra_bonds

if [ -f "$OUT_PDBQT" ] && [ -s "$OUT_PDBQT" ]; then
    echo "[✓] Receptor com cofator(es) (${COFACTOR_RES}) preparado com sucesso!"
    echo "    Arquivo: ${OUT_PDBQT}"
else
    echo "[-] Falha ao gerar: ${OUT_PDBQT}"
    exit 1
fi
