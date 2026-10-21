#!/usr/bin/env bash
# ==============================================================================
# 06_run_docking.sh - Execução do Docking Molecular com AutoDock Vina
# ==============================================================================
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/load_config.sh" "$@"

TARGET="${TARGET:-}"

if [ -z "$TARGET" ]; then
    echo "[-] Erro: TARGET não foi definido!"
    echo "    Uso: $0 [TARGET]"
    exit 1
fi

# Tentar carregar ambiente conda se vina não estiver no PATH
if ! command -v vina &> /dev/null; then
    if [ -f "$HOME/miniconda3/etc/profile.d/conda.sh" ]; then
        # shellcheck source=/dev/null
        source "$HOME/miniconda3/etc/profile.d/conda.sh"
        conda activate docking_vina 2>/dev/null || conda activate vina 2>/dev/null || true
    fi
fi

if ! command -v vina &> /dev/null; then
    echo "[-] Erro: 'vina' (AutoDock Vina) não encontrado no PATH!"
    echo "    Ative o ambiente conda: conda activate docking_vina"
    exit 1
fi

CONFIG_TXT="targets/${TARGET}/config.txt"
RECEPTOR_PDBQT="targets/${TARGET}/receptor/prepared/receptor.pdbqt"
LIGANDS_DIR="targets/${TARGET}/ligands/prepared"
RESULTS_POSES="targets/${TARGET}/results/poses"
RESULTS_LOGS="targets/${TARGET}/results/logs"
RESULTS_SUMMARY="targets/${TARGET}/results/summary"

mkdir -p "$RESULTS_POSES" "$RESULTS_LOGS" "$RESULTS_SUMMARY"

# Verificações prévias
if [ ! -f "$CONFIG_TXT" ]; then
    echo "[-] Erro: Arquivo ${CONFIG_TXT} não encontrado!"
    exit 1
fi

# Verificar se as coordenadas do centro foram preenchidas no config.txt
CX=$(grep -E '^[[:space:]]*center_x[[:space:]]*=' "$CONFIG_TXT" | awk -F '=' '{gsub(/[[:space:]]/,"",$2); print $2}')
CY=$(grep -E '^[[:space:]]*center_y[[:space:]]*=' "$CONFIG_TXT" | awk -F '=' '{gsub(/[[:space:]]/,"",$2); print $2}')
CZ=$(grep -E '^[[:space:]]*center_z[[:space:]]*=' "$CONFIG_TXT" | awk -F '=' '{gsub(/[[:space:]]/,"",$2); print $2}')

if [ -z "$CX" ] || [ -z "$CY" ] || [ -z "$CZ" ]; then
    echo "[-] Erro: As coordenadas do centro da caixa (center_x, center_y, center_z)"
    echo "    não estão preenchidas no arquivo: ${CONFIG_TXT}"
    echo "    Por favor, preencha-as ou execute o script 07_run_redocking.sh para cálculo automático."
    exit 1
fi

if [ ! -f "$RECEPTOR_PDBQT" ]; then
    echo "[-] Erro: Receptor preparado não encontrado: ${RECEPTOR_PDBQT}"
    echo "    Execute primeiro o script 04_prepare_receptor.sh"
    exit 1
fi

# Contar ligantes disponíveis
LIG_COUNT=$(find "$LIGANDS_DIR" -maxdepth 1 -name "*_charged.pdbqt" 2>/dev/null | wc -l)
if [ "$LIG_COUNT" -eq 0 ]; then
    echo "[-] Erro: Nenhum ligante preparado (*_charged.pdbqt) encontrado em: ${LIGANDS_DIR}"
    echo "    Execute primeiro o script 05_prepare_ligands.sh"
    exit 1
fi

echo "[+] Iniciando Docking Molecular no Vina para ${LIG_COUNT} ligantes..."
echo "    Alvo: ${TARGET} | Centro: (${CX}, ${CY}, ${CZ})"

SUMMARY_CSV="${RESULTS_SUMMARY}/docking_affinities.csv"
echo "ligand,affinity_kcal_mol,log_file,pose_file" > "$SUMMARY_CSV"

DOCK_IDX=0
for lig in "${LIGANDS_DIR}"/*_charged.pdbqt; do
    [ -e "$lig" ] || continue
    DOCK_IDX=$((DOCK_IDX + 1))
    name=$(basename "$lig" .pdbqt)
    out_pose="${RESULTS_POSES}/${name}_out.pdbqt"
    out_log="${RESULTS_LOGS}/${name}.log"

    echo -n "    [${DOCK_IDX}/${LIG_COUNT}] Docking: ${name}... "

    vina --config "$CONFIG_TXT" \
         --ligand "$lig" \
         --out "$out_pose" \
         > "$out_log" 2>&1

    # Extrair melhor afinidade (modo 1) do arquivo de log
    AFFINITY=$(grep -E '^[[:space:]]+1[[:space:]]+' "$out_log" | awk '{print $2}' || true)
    if [ -n "$AFFINITY" ]; then
        echo "Afinidade: ${AFFINITY} kcal/mol"
        echo "${name},${AFFINITY},${out_log},${out_pose}" >> "$SUMMARY_CSV"
    else
        echo "Concluído (verifique ${out_log})"
        echo "${name},N/A,${out_log},${out_pose}" >> "$SUMMARY_CSV"
    fi
done

echo "--------------------------------------------------------"
echo "[✓] Docking concluído com sucesso!"
echo "    Poses salvas em: ${RESULTS_POSES}/"
echo "    Logs salvos em:  ${RESULTS_LOGS}/"
echo "    Tabela resumo:   ${SUMMARY_CSV}"
echo ""
echo "Resumo das Melhores Afinidades:"
cat "$SUMMARY_CSV" | column -s, -t
