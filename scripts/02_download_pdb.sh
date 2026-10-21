#!/usr/bin/env bash
# ==============================================================================
# 02_download_pdb.sh - Download da estrutura PDB do RCSB
# ==============================================================================
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/load_config.sh" "$@"

TARGET="${TARGET:-}"
PDB_ID="${PDB_ID:-}"

if [ -z "$TARGET" ] || [ -z "$PDB_ID" ]; then
    echo "[-] Erro: TARGET ou PDB_ID não definidos!"
    echo "    Uso: $0 [TARGET] [PDB_ID]"
    exit 1
fi

OUT_DIR="targets/${TARGET}/receptor/raw"
mkdir -p "$OUT_DIR"
OUT_FILE="${OUT_DIR}/${PDB_ID}.pdb"

# Normalizar PDB_ID (maiúsculas para URL do RCSB)
PDB_UPPER=$(echo "$PDB_ID" | tr '[:lower:]' '[:upper:]')
URL="https://files.rcsb.org/download/${PDB_UPPER}.pdb"

echo "[+] Baixando PDB '${PDB_UPPER}' para ${OUT_FILE}..."

if curl -s -f -L "$URL" -o "$OUT_FILE"; then
    if [ -s "$OUT_FILE" ]; then
        echo "[✓] Estrutura baixada com sucesso: ${OUT_FILE} ($(wc -l < "$OUT_FILE") linhas)"
    else
        echo "[-] Erro: O arquivo baixado está vazio!"
        rm -f "$OUT_FILE"
        exit 1
    fi
else
    echo "[-] Erro ao baixar PDB da URL: ${URL}"
    echo "    Verifique se o código PDB '${PDB_UPPER}' está correto e sua conexão com a internet."
    exit 1
fi
