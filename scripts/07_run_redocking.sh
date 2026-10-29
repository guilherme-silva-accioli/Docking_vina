#!/usr/bin/env bash
# ==============================================================================
# 07_run_redocking.sh - Extração do ligante nativo, docking e cálculo de RMSD
# ==============================================================================
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/load_config.sh" "$@"

TARGET="${TARGET:-}"
PDB_ID="${PDB_ID:-}"
NATIVE_LIG="${NATIVE_LIG:-}"

if [ -z "$TARGET" ] || [ -z "$PDB_ID" ] || [ -z "$NATIVE_LIG" ]; then
    echo "[-] Erro: TARGET, PDB_ID ou NATIVE_LIG não definidos!"
    echo "    Uso: $0 [TARGET] [PDB_ID] [NATIVE_LIG]"
    exit 1
fi

# Tentar carregar ambiente conda se ferramentas não estiverem no PATH
if ! command -v vina &> /dev/null || ! command -v mk_prepare_ligand.py &> /dev/null; then
    if [ -f "$HOME/miniconda3/etc/profile.d/conda.sh" ]; then
        # shellcheck source=/dev/null
        source "$HOME/miniconda3/etc/profile.d/conda.sh"
        conda activate docking_vina 2>/dev/null || conda activate vina 2>/dev/null || true
    fi
fi

RAW_RECEPTOR=$(resolve_raw_receptor "$TARGET" "$PDB_ID")
REDOCK_DIR="targets/${TARGET}/redocking"
CONFIG_TXT="targets/${TARGET}/config.txt"

mkdir -p "${REDOCK_DIR}/crystallographic"
mkdir -p "${REDOCK_DIR}/prepared"
mkdir -p "${REDOCK_DIR}/results"

LIG_RAW_PDB="${REDOCK_DIR}/crystallographic/ligante_raw.pdb"
LIG_SDF="${REDOCK_DIR}/crystallographic/ligante.sdf"
LIG_PREP_PDBQT="${REDOCK_DIR}/prepared/ligante_original_preparado.pdbqt"
LIG_PREP_SDF="${REDOCK_DIR}/prepared/ligante_original_preparado.sdf"
REDOCKED_PDBQT="${REDOCK_DIR}/native_ligand_redocked.pdbqt"
REDOCKED_SDF="${REDOCK_DIR}/results/native_ligand_redocked.sdf"
REDOCK_LOG="${REDOCK_DIR}/redocking.log"

echo "[+] Iniciando processo de Redocking para o alvo ${TARGET} (Ligante nativo: ${NATIVE_LIG})..."

# Passo 1: Extrair ligante nativo com ChimeraX (ou ProDy fallback, suportando .pdb e .cif)
if [ ! -f "$LIG_RAW_PDB" ] || [ ! -s "$LIG_RAW_PDB" ]; then
    if [ ! -f "$RAW_RECEPTOR" ] || [ ! -s "$RAW_RECEPTOR" ]; then
        echo "[-] Erro: Estrutura bruta não encontrada em ${RAW_RECEPTOR}"
        exit 1
    fi

    if command -v chimerax &> /dev/null; then
        echo "[+] Extraindo ligante nativo '${NATIVE_LIG}' de ${RAW_RECEPTOR} com ChimeraX..."
        chimerax --nogui --cmd "
        open ${RAW_RECEPTOR};
        delete ~:${NATIVE_LIG};
        save ${LIG_RAW_PDB};
        exit;
        " || true
    fi

    # Garantir que, se houver múltiplas cópias do ligante em cadeias distintas (homodímeros),
    # apenas a primeira molécula/resíduo seja mantida (ou extrair via ProDy caso ChimeraX falhe)
    python3 - "$RAW_RECEPTOR" "$NATIVE_LIG" "$LIG_RAW_PDB" << 'PYEOF'
import os
import sys
import prody

raw_rec, nat_lig, lig_pdb = sys.argv[1:4]

if not os.path.isfile(lig_pdb) or os.path.getsize(lig_pdb) == 0:
    if raw_rec.lower().endswith((".cif", ".mmcif")):
        atoms = prody.parseMMCIF(raw_rec)
    else:
        atoms = prody.parsePDB(raw_rec)
    sel = atoms.select(f"resname {nat_lig}")
    if sel is None or sel.numAtoms() == 0:
        print(f"[-] Erro: Ligante '{nat_lig}' não encontrado em {raw_rec}", file=sys.stderr)
        sys.exit(1)
    prody.writePDB(lig_pdb, sel)

# Filtrar apenas a primeira instância (cadeia + resnum) para evitar média entre subunidades de dímeros
kept_lines = []
first_id = None
with open(lig_pdb, "r", encoding="utf-8", errors="ignore") as f:
    for line in f:
        if line.startswith(("ATOM  ", "HETATM")):
            res_key = line[21:27]
            if first_id is None:
                first_id = res_key
            if res_key == first_id:
                kept_lines.append(line)
        elif not line.startswith("CONECT"):
            kept_lines.append(line)

if first_id is not None:
    with open(lig_pdb, "w", encoding="utf-8", newline="\n") as f:
        f.writelines(kept_lines)
PYEOF
else
    echo "[.] Ligante cristalográfico existente mantido: ${LIG_RAW_PDB}"
fi

# Passo 2: Calcular centróide da cavidade (colunas fixas PDB v3.3: 31-38, 39-46, 47-54) e atualizar config.txt
if [ -f "$LIG_RAW_PDB" ]; then
    COORD_DATA=$(awk '/^(ATOM  |HETATM)/ {
        x = substr($0, 31, 8) + 0;
        y = substr($0, 39, 8) + 0;
        z = substr($0, 47, 8) + 0;
        sumx += x; sumy += y; sumz += z; n++
    } END {
        if (n > 0) printf "%.3f %.3f %.3f", sumx/n, sumy/n, sumz/n
    }' "$LIG_RAW_PDB")
    if [ -n "$COORD_DATA" ]; then
        read -r CALC_CX CALC_CY CALC_CZ <<< "$COORD_DATA"
        echo "[✓] Centro do sítio ativo calculado a partir do ligante nativo:"
        echo "    center_x = ${CALC_CX}"
        echo "    center_y = ${CALC_CY}"
        echo "    center_z = ${CALC_CZ}"

        if [ -f "$CONFIG_TXT" ]; then
            CURRENT_CX=$(grep -E '^[[:space:]]*center_x[[:space:]]*=' "$CONFIG_TXT" | awk -F '=' '{gsub(/[[:space:]]/,"",$2); print $2}')
            CURRENT_CY=$(grep -E '^[[:space:]]*center_y[[:space:]]*=' "$CONFIG_TXT" | awk -F '=' '{gsub(/[[:space:]]/,"",$2); print $2}')
            CURRENT_CZ=$(grep -E '^[[:space:]]*center_z[[:space:]]*=' "$CONFIG_TXT" | awk -F '=' '{gsub(/[[:space:]]/,"",$2); print $2}')
            if [ -z "$CURRENT_CX" ] || [ "$CURRENT_CX" != "$CALC_CX" ] || [ "$CURRENT_CY" != "$CALC_CY" ] || [ "$CURRENT_CZ" != "$CALC_CZ" ]; then
                echo "[+] Atualizando coordenadas do centro em ${CONFIG_TXT}..."
                sed -i "s/^[[:space:]]*center_x[[:space:]]*=.*/center_x = ${CALC_CX}/" "$CONFIG_TXT"
                sed -i "s/^[[:space:]]*center_y[[:space:]]*=.*/center_y = ${CALC_CY}/" "$CONFIG_TXT"
                sed -i "s/^[[:space:]]*center_z[[:space:]]*=.*/center_z = ${CALC_CZ}/" "$CONFIG_TXT"
            fi
        fi
    fi
fi

# Passo 3: Converter para SDF com OpenBabel (protonando a pH 7.4 + sanitização de valência)
echo "[+] Convertendo ligante original para SDF (pH 7.4 + cargas Gasteiger)..."
obabel "$LIG_RAW_PDB" -O "$LIG_SDF" -p 7.4 --partialcharge gasteiger
python3 "${SCRIPT_DIR}/sanitize_charged_sdf.py" "$LIG_SDF" "$LIG_SDF"

# Passo 4: Preparar ligante original com Meeko
echo "[+] Preparando ligante nativo com Meeko..."
mk_prepare_ligand.py \
  -i "$LIG_SDF" \
  -o "$LIG_PREP_PDBQT" \
  --charge_model gasteiger \
  --add_index_map

# Passo 5: Exportar referência para SDF
echo "[+] Exportando referência preparada para SDF..."
mk_export.py "$LIG_PREP_PDBQT" -s "$LIG_PREP_SDF"

# Passo 6: Rodar Redocking no Vina
echo "[+] Executando Redocking no AutoDock Vina..."
vina --config "$CONFIG_TXT" \
     --ligand "$LIG_PREP_PDBQT" \
     --out "$REDOCKED_PDBQT" \
     > "$REDOCK_LOG" 2>&1

# Passo 7: Exportar pose redocada para SDF
echo "[+] Exportando melhor pose redocada para SDF..."
mk_export.py "$REDOCKED_PDBQT" -s "$REDOCKED_SDF"

echo "--------------------------------------------------------"
echo "[✓] Redocking concluído!"
echo "    Log:           ${REDOCK_LOG}"
echo "    Referência:    ${LIG_PREP_SDF}"
echo "    Pose redocada: ${REDOCKED_SDF}"

# Passo 8: Tentativa de cálculo do RMSD com Python / RDKit
echo ""
echo "[+] Verificando RMSD do controle positivo..."

python3 -c "
import sys
try:
    from rdkit import Chem
    from rdkit.Chem import rdMolAlign

    ref = Chem.MolFromMolFile('${LIG_PREP_SDF}', removeHs=False)
    redock = Chem.MolFromMolFile('${REDOCKED_SDF}', removeHs=False)

    if ref is not None and redock is not None:
        ref_heavy = Chem.RemoveHs(ref)
        redock_heavy = Chem.RemoveHs(redock)
        rmsd = rdMolAlign.CalcRMS(redock_heavy, ref_heavy)
        print(f'    RMSD (Heavy Atoms): {rmsd:.2f} Å')
        with open('${REDOCK_DIR}/rmsd_result.txt', 'w', encoding='utf-8') as rf:
            rf.write(f'TARGET=${TARGET}\nPDB_ID=${PDB_ID}\nNATIVE_LIG=${NATIVE_LIG}\nRMSD_HEAVY_A={rmsd:.4f}\n')
        if rmsd <= 2.0:
            print('    [✓] Validação: SUCESSO! RMSD <= 2.0 Å (Parâmetros de docking validados)')
        else:
            print('    [!] Atenção: RMSD > 2.0 Å. Verifique a caixa de busca e conformação.')
    else:
        print('    [i] Use o Discovery Studio para conferir o RMSD (Structure > RMSD > Heavy Atoms).')
except Exception as e:
    print('    [i] Para calcular no Discovery Studio:')
    print('        1. Abra ${LIG_PREP_SDF} -> Structure > RMSD > Set reference')
    print('        2. Abra ${REDOCKED_SDF} -> Structure > Superimpose > Molecular Overlay')
    print('        3. Structure > RMSD > Heavy Atoms')
"
