#!/usr/bin/env bash
# ==============================================================================
# 08_plot_heatmap.sh - Gera a matriz consolidada e o Heatmap de Afinidades em R
# Uso:
#   ./scripts/08_plot_heatmap.sh [TOP_N_POR_ALVO]
# Exemplo:
#   ./scripts/08_plot_heatmap.sh 10
# ==============================================================================
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
HEATMAP_R="${PROJECT_ROOT}/analysis/heatmap/heatmap.R"
TOP_N="${1:-10}"

if [ ! -f "$HEATMAP_R" ]; then
    echo "[-] Erro: Script R não encontrado em ${HEATMAP_R}"
    exit 1
fi

echo "=========================================================="
echo "    GERANDO HEATMAP DE AFINIDADES DE DOCKING"
echo "    Top-N por alvo: ${TOP_N}"
echo "=========================================================="

if command -v Rscript &> /dev/null; then
    Rscript "$HEATMAP_R" "$TOP_N" "$PROJECT_ROOT"
else
    # Buscar Rscript.exe instalado no Windows (via WSL interop)
    WIN_RSCRIPT=$(ls -1 /mnt/c/Program\ Files/R/R-*/bin/Rscript.exe 2>/dev/null | sort -V | tail -n 1 || true)
    if [ -z "$WIN_RSCRIPT" ] || [ ! -x "$WIN_RSCRIPT" ]; then
        echo "[-] Erro: Rscript não encontrado no Linux nem em 'C:\\Program Files\\R\\'."
        exit 1
    fi
    WIN_SCRIPT_PATH=$(wslpath -w "$HEATMAP_R")
    WIN_ROOT_PATH=$(wslpath -w "$PROJECT_ROOT")
    "$WIN_RSCRIPT" "$WIN_SCRIPT_PATH" "$TOP_N" "$WIN_ROOT_PATH"
fi

echo "=========================================================="
echo "    [✓] Arquivos disponíveis em: analysis/heatmap/"
echo "        - Matriz CSV: analysis/heatmap/results_matrix.csv"
echo "        - Nomes:      analysis/heatmap/compound_names.csv"
echo "        - Gráfico:    analysis/heatmap/heatmap_docking.png"
echo "=========================================================="
