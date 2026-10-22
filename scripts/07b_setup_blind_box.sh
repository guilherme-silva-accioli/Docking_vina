#!/usr/bin/env bash
# ==============================================================================
# 07b_setup_blind_box.sh - Configuração Automática da Grid Box para Blind Docking
# Calcula o centro geométrico ((min+max)/2) e as dimensões totais da proteína
# somadas ao padding (padrão: +6.0 Å) e atualiza targets/<TARGET>/config.txt.
# ==============================================================================
set -e

ORIG_ARG2="${2:-}"
ORIG_ARG3="${3:-}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/load_config.sh" "$1"

TARGET="${TARGET:-}"
PDB_ID="${PDB_ID:-}"
PADDING="${ORIG_ARG2:-${BLIND_PADDING:-6.0}}"
MIN_EXH="${ORIG_ARG3:-${BLIND_EXHAUSTIVENESS:-16}}"
BASE_EXH="${EXHAUSTIVENESS:-8}"

if [ -z "$TARGET" ]; then
    echo "[-] Erro: TARGET não foi definido!"
    echo "    Uso: $0 [TARGET] [PADDING_ANGSTROMS] [EXHAUSTIVENESS]"
    exit 1
fi

CONFIG_TXT="targets/${TARGET}/config.txt"
RECEPTOR_PDBQT="targets/${TARGET}/receptor/prepared/receptor.pdbqt"
RECEPTOR_COF_PDB="targets/${TARGET}/receptor/prepared/receptor_with_cofactor.pdb"
CLEAN_PDB="targets/${TARGET}/receptor/prepared/protein_clean.pdb"
RAW_PDB="targets/${TARGET}/receptor/raw/${PDB_ID}.pdb"

# Selecionar a melhor estrutura disponível do receptor para medir a caixa
SOURCE_STRUCT=""
ONLY_ATOM_RECORDS="0"

if [ -f "$RECEPTOR_PDBQT" ] && [ -s "$RECEPTOR_PDBQT" ]; then
    SOURCE_STRUCT="$RECEPTOR_PDBQT"
elif [ -f "$RECEPTOR_COF_PDB" ] && [ -s "$RECEPTOR_COF_PDB" ]; then
    SOURCE_STRUCT="$RECEPTOR_COF_PDB"
elif [ -f "$CLEAN_PDB" ] && [ -s "$CLEAN_PDB" ]; then
    SOURCE_STRUCT="$CLEAN_PDB"
elif [ -n "$PDB_ID" ] && [ -f "$RAW_PDB" ] && [ -s "$RAW_PDB" ]; then
    SOURCE_STRUCT="$RAW_PDB"
    ONLY_ATOM_RECORDS="1"
else
    echo "[-] Erro: Nenhuma estrutura do receptor encontrada para '${TARGET}'!"
    echo "    Execute primeiro 04_prepare_receptor.sh (ou 02_download_pdb.sh)."
    exit 1
fi

echo "[+] Configurando Blind Docking (Docking Cego) para o alvo: ${TARGET}"
echo "    Estrutura base: ${SOURCE_STRUCT}"
echo "    Padding (margem): +${PADDING} Å em cada eixo"

# Garantir que o config.txt exista
mkdir -p "targets/${TARGET}"
if [ ! -f "$CONFIG_TXT" ]; then
    cat << EOF > "$CONFIG_TXT"
receptor = targets/${TARGET}/receptor/prepared/receptor.pdbqt

center_x = 
center_y = 
center_z = 

size_x = 22.0
size_y = 22.0
size_z = 22.0

exhaustiveness = ${BASE_EXH}
num_modes = ${NUM_MODES:-9}
energy_range = ${ENERGY_RANGE:-3}
EOF
fi

# Calcular Bounding Box e atualizar config.txt via Python
python3 - "$SOURCE_STRUCT" "$ONLY_ATOM_RECORDS" "$PADDING" "$BASE_EXH" "$MIN_EXH" "$CONFIG_TXT" << 'PYEOF'
import re
import sys

struct_path = sys.argv[1]
only_atom = sys.argv[2] == "1"
padding = float(sys.argv[3])
base_exh = int(float(sys.argv[4]))
min_exh = int(float(sys.argv[5]))
config_path = sys.argv[6]

xs, ys, zs = [], [], []
with open(struct_path, "r", encoding="utf-8", errors="ignore") as f:
    for line in f:
        if only_atom:
            if not line.startswith("ATOM  "):
                continue
        else:
            if not line.startswith(("ATOM  ", "HETATM")):
                continue
        try:
            x = float(line[30:38])
            y = float(line[38:46])
            z = float(line[46:54])
            xs.append(x)
            ys.append(y)
            zs.append(z)
        except ValueError:
            continue

if not xs:
    print(f"[-] Erro: Nenhuma coordenada atômica lida de {struct_path}", file=sys.stderr)
    sys.exit(1)

min_x, max_x = min(xs), max(xs)
min_y, max_y = min(ys), max(ys)
min_z, max_z = min(zs), max(zs)

prot_dx = max_x - min_x
prot_dy = max_y - min_y
prot_dz = max_z - min_z

cx = (min_x + max_x) / 2.0
cy = (min_y + max_y) / 2.0
cz = (min_z + max_z) / 2.0

sx = prot_dx + padding
sy = prot_dy + padding
sz = prot_dz + padding

final_exh = max(base_exh, min_exh)

print(f"    [✓] Átomos analisados: {len(xs)}")
print(f"    [✓] Extensão da proteína (Å): ΔX={prot_dx:.2f}, ΔY={prot_dy:.2f}, ΔZ={prot_dz:.2f}")
print(f"    [✓] Centro da Bounding Box:   center_x={cx:.3f}, center_y={cy:.3f}, center_z={cz:.3f}")
print(f"    [✓] Tamanho da Grid Box (Å):  size_x={sx:.2f}, size_y={sy:.2f}, size_z={sz:.2f}")
print(f"    [✓] Exaustividade ajustada:   exhaustiveness={final_exh}")

with open(config_path, "r", encoding="utf-8") as f:
    content = f.read()

replacements = {
    "center_x": f"{cx:.3f}",
    "center_y": f"{cy:.3f}",
    "center_z": f"{cz:.3f}",
    "size_x": f"{sx:.2f}",
    "size_y": f"{sy:.2f}",
    "size_z": f"{sz:.2f}",
    "exhaustiveness": str(final_exh),
}

for key, val in replacements.items():
    pattern = rf"^([ \t]*{key}[ \t]*=).*$"
    if re.search(pattern, content, flags=re.MULTILINE):
        content = re.sub(pattern, rf"\1 {val}", content, flags=re.MULTILINE)
    else:
        content += f"\n{key} = {val}\n"

with open(config_path, "w", encoding="utf-8", newline="\n") as f:
    f.write(content)

print(f"[✓] Arquivo {config_path} atualizado com sucesso para Blind Docking!")
PYEOF
