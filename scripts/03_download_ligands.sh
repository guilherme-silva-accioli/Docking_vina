#!/usr/bin/env bash
# ==============================================================================
# 03_download_ligands.sh - Download de ligantes 3D do PubChem via InChIKey
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

INCHIKEYS_FILE="targets/${TARGET}/ligands/inchikeys.txt"
RAW_DIR="targets/${TARGET}/ligands/raw"
HUB_FILE="${HUB_INCHIKEYS_DIR}/${TARGET}.txt"
mkdir -p "$RAW_DIR"

# Se o arquivo não existir ou estiver vazio, tenta copiar da pasta de hubs
if [ ! -s "$INCHIKEYS_FILE" ] && [ -f "$HUB_FILE" ]; then
    echo "[+] Copiando InChIKeys de: ${HUB_FILE}"
    tr -d '\r' < "$HUB_FILE" > "$INCHIKEYS_FILE"
fi

if [ ! -f "$INCHIKEYS_FILE" ]; then
    echo "[-] Erro: Arquivo de InChIKeys não encontrado em: ${INCHIKEYS_FILE}"
    echo "    Coloque os InChIKeys em ${INCHIKEYS_FILE} ou em ${HUB_FILE}"
    exit 1
fi

echo "[+] Lendo InChIKeys de: ${INCHIKEYS_FILE}"

TOTAL=0
DOWNLOADED=0
SKIPPED=0
FAILED=0

while IFS= read -r line || [ -n "$line" ]; do
    # Remover espaços em branco e quebras de linha Windows (\r)
    key=$(echo "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | tr -d '\r')

    # Ignorar linhas vazias ou comentários que começam com #
    if [ -z "$key" ] || [[ "$key" =~ ^# ]]; then
        continue
    fi

    TOTAL=$((TOTAL + 1))
    OUT_SDF="${RAW_DIR}/${key}.sdf"

    if [ -f "$OUT_SDF" ] && [ -s "$OUT_SDF" ]; then
        echo "    [.] Já existente (pulando): ${key}.sdf"
        SKIPPED=$((SKIPPED + 1))
        continue
    fi

    echo "    [↓] Baixando [${TOTAL}]: ${key}..."
    URL="https://pubchem.ncbi.nlm.nih.gov/rest/pug/compound/inchikey/${key}/SDF?record_type=3d"

    if curl -s -f -L "$URL" -o "$OUT_SDF"; then
        if [ -s "$OUT_SDF" ]; then
            DOWNLOADED=$((DOWNLOADED + 1))
        else
            echo "    [-] Falha: Arquivo recebido está vazio para ${key}"
            rm -f "$OUT_SDF"
            FAILED=$((FAILED + 1))
        fi
    else
        echo "    [-] Falha no download do PubChem para ${key} (InChIKey pode não ter conformação 3D)"
        rm -f "$OUT_SDF"
        FAILED=$((FAILED + 1))
    fi
done < "$INCHIKEYS_FILE"

echo "--------------------------------------------------------"
echo "[✓] Concluído! Total: ${TOTAL} | Baixados: ${DOWNLOADED} | Existentes: ${SKIPPED} | Falhas: ${FAILED}"
echo "    Arquivos salvos em: ${RAW_DIR}/"
