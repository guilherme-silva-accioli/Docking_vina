#!/usr/bin/env bash
# ==============================================================================
# 02_download_pdb.sh - Download da estrutura do receptor (.pdb ou .cif) do RCSB
# Tenta .pdb primeiro e faz fallback automático para .cif (mmCIF) se necessário.
# ==============================================================================
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/load_config.sh" "$@"

TARGET="${TARGET:-}"
PDB_ID="${PDB_ID:-}"
RECEPTOR_FORMAT="${RECEPTOR_FORMAT:-auto}"

if [ -z "$TARGET" ]; then
    echo "[-] Erro: TARGET não foi definido!"
    echo "    Uso: $0 [TARGET] [PDB_ID]"
    exit 1
fi

OUT_DIR="targets/${TARGET}/receptor/raw"
mkdir -p "$OUT_DIR"

# Verificar se já existe um arquivo .pdb ou .cif válido em receptor/raw/
EXISTING_RAW=$(resolve_raw_receptor "$TARGET" "$PDB_ID")
if [ -f "$EXISTING_RAW" ] && [ -s "$EXISTING_RAW" ]; then
    echo "[.] Estrutura bruta já existente em: ${EXISTING_RAW} ($(wc -l < "$EXISTING_RAW") linhas)"
    exit 0
fi

if [ -z "$PDB_ID" ]; then
    echo "[-] Erro: PDB_ID não definido e nenhum arquivo .pdb/.cif local encontrado em ${OUT_DIR}/"
    exit 1
fi

# Limpar eventual extensão informada no PDB_ID (ex: 6NJS.cif -> 6NJS)
WANT_CIF="0"
if [[ "${PDB_ID,,}" == *.cif ]] || [[ "${PDB_ID,,}" == *.mmcif ]] || [ "${RECEPTOR_FORMAT,,}" = "cif" ]; then
    WANT_CIF="1"
fi

CLEAN_ID="${PDB_ID%.pdb}"
CLEAN_ID="${CLEAN_ID%.cif}"
CLEAN_ID="${CLEAN_ID%.mmcif}"
PDB_UPPER=$(echo "$CLEAN_ID" | tr '[:lower:]' '[:upper:]')

OUT_PDB="${OUT_DIR}/${CLEAN_ID}.pdb"
OUT_CIF="${OUT_DIR}/${CLEAN_ID}.cif"
URL_PDB="https://files.rcsb.org/download/${PDB_UPPER}.pdb"
URL_CIF="https://files.rcsb.org/download/${PDB_UPPER}.cif"

if [ "$WANT_CIF" = "0" ]; then
    echo "[+] Baixando estrutura PDB '${PDB_UPPER}' para ${OUT_PDB}..."
    if curl -s -f -L "$URL_PDB" -o "$OUT_PDB" && [ -s "$OUT_PDB" ]; then
        echo "[✓] Estrutura (.pdb) baixada com sucesso: ${OUT_PDB} ($(wc -l < "$OUT_PDB") linhas)"
        exit 0
    else
        rm -f "$OUT_PDB"
        echo "[!] Formato .pdb não disponível no RCSB para '${PDB_UPPER}'. Tentando formato .cif (mmCIF)..."
    fi
fi

echo "[+] Baixando estrutura mmCIF '${PDB_UPPER}' para ${OUT_CIF}..."
if curl -s -f -L "$URL_CIF" -o "$OUT_CIF" && [ -s "$OUT_CIF" ]; then
    echo "[✓] Estrutura (.cif) baixada com sucesso: ${OUT_CIF} ($(wc -l < "$OUT_CIF") linhas)"
    exit 0
else
    rm -f "$OUT_CIF"
    echo "[-] Erro ao baixar '${PDB_UPPER}' (tanto em .pdb quanto em .cif) do RCSB."
    echo "    Verifique se o código '${PDB_UPPER}' está correto ou coloque o arquivo .pdb/.cif manualmente em ${OUT_DIR}/"
    exit 1
fi
