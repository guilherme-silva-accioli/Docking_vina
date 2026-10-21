#!/usr/bin/env bash
# ==============================================================================
# 01_setup_target.sh - Criação da estrutura de pastas e arquivo de configuração
# ==============================================================================
set -e

# Carregar configurações
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/load_config.sh" "$@"

TARGET="${TARGET:-}"
PDB_ID="${PDB_ID:-}"
NATIVE_LIG="${NATIVE_LIG:-}"
INCHIKEY_SRC="${INCHIKEY_SRC:-}"

if [ -z "$TARGET" ]; then
    echo "[-] Erro: TARGET não foi definido!"
    echo "    Uso: $0 [TARGET] [PDB_ID] [NATIVE_LIG] [CAMINHO_INCHIKEY_TXT]"
    echo "    Ou defina as variáveis em configs/<TARGET>.env ou scripts/config.env"
    exit 1
fi

echo "[+] Configurando estrutura para o alvo: ${TARGET}"

# Criar estrutura de pastas (sem cofator)
mkdir -p scripts
mkdir -p "targets/${TARGET}/receptor/raw"
mkdir -p "targets/${TARGET}/receptor/prepared"
mkdir -p "targets/${TARGET}/redocking/crystallographic"
mkdir -p "targets/${TARGET}/redocking/prepared"
mkdir -p "targets/${TARGET}/redocking/results"
mkdir -p "targets/${TARGET}/ligands/raw"
mkdir -p "targets/${TARGET}/ligands/prepared"
mkdir -p "targets/${TARGET}/results/poses"
mkdir -p "targets/${TARGET}/results/logs"
mkdir -p "targets/${TARGET}/results/summary"

# Copiar ou criar arquivo de InChIKeys
INCHIKEYS_FILE="targets/${TARGET}/ligands/inchikeys.txt"
HUB_FILE="${HUB_INCHIKEYS_DIR}/${TARGET}.txt"

if [ -n "$INCHIKEY_SRC" ] && [ -f "$INCHIKEY_SRC" ]; then
    echo "    [+] Copiando InChIKeys do arquivo fornecido: ${INCHIKEY_SRC}..."
    tr -d '\r' < "$INCHIKEY_SRC" > "$INCHIKEYS_FILE"
    echo "    [✓] InChIKeys carregados ($(wc -l < "$INCHIKEYS_FILE") linhas)"
elif [ -f "$HUB_FILE" ]; then
    echo "    [+] Arquivo de InChIKeys encontrado em: ${HUB_FILE}"
    tr -d '\r' < "$HUB_FILE" > "$INCHIKEYS_FILE"
    echo "    [✓] InChIKeys copiados com sucesso de ${HUB_FILE} ($(wc -l < "$INCHIKEYS_FILE") linhas)"
elif [ ! -f "$INCHIKEYS_FILE" ]; then
    cat << 'EOF' > "$INCHIKEYS_FILE"
# Adicione um InChiKey por linha ou copie de hub_inchikeys/<TARGET>.txt
EOF
    echo "    [+] Criado template vazio: ${INCHIKEYS_FILE}"
else
    echo "    [.] Arquivo existente mantido: ${INCHIKEYS_FILE} ($(wc -l < "$INCHIKEYS_FILE") linhas)"
fi

# Criar arquivo de configuração do Vina se não existir
CONFIG_VINA="targets/${TARGET}/config.txt"
if [ ! -f "$CONFIG_VINA" ]; then
    cat << EOF > "$CONFIG_VINA"
receptor = targets/${TARGET}/receptor/prepared/receptor.pdbqt

center_x = 
center_y = 
center_z = 

size_x = ${SIZE_X:-22.0}
size_y = ${SIZE_Y:-22.0}
size_z = ${SIZE_Z:-22.0}

exhaustiveness = ${EXHAUSTIVENESS:-8}
num_modes = ${NUM_MODES:-9}
energy_range = ${ENERGY_RANGE:-3}
EOF
    echo "    [+] Criado arquivo de configuração: ${CONFIG_VINA}"
else
    echo "    [.] Arquivo de configuração existente mantido: ${CONFIG_VINA}"
fi

echo "[✓] Estrutura do alvo '${TARGET}' pronta!"
