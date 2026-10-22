#!/usr/bin/env bash
# ==============================================================================
# load_config.sh - Carregador flexível de arquivos de configuração
# Suporta múltiplos arquivos .env (ex: configs/CCND1.env, configs/JAK2.env)
# ==============================================================================

LOAD_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${LOAD_SCRIPT_DIR}/.." && pwd)"

SELECTED_CONFIG=""
EXPLICIT_TARGET=""

# 1. Flag explícita: --config <arquivo> ou -c <arquivo>
if [ "${1:-}" = "--config" ] || [ "${1:-}" = "-c" ]; then
    SELECTED_CONFIG="$2"
    shift 2
# 2. Argumento com extensão .env ou caminho direto para arquivo existente
elif [[ "${1:-}" == *.env ]]; then
    SELECTED_CONFIG="$1"
    shift 1
elif [ -n "${1:-}" ] && [ -f "${1:-}" ] && [[ "${1:-}" != *.sh ]]; then
    SELECTED_CONFIG="$1"
    shift 1
# 3. Argumento é o nome de um alvo com arquivo em configs/ (ex: CCND1 -> configs/CCND1.env)
elif [ -n "${1:-}" ] && [ -f "${PROJECT_ROOT}/configs/${1}.env" ]; then
    SELECTED_CONFIG="${PROJECT_ROOT}/configs/${1}.env"
    EXPLICIT_TARGET="$1"
    shift 1
# 4. Variável de ambiente CONFIG_FILE definida externamente
elif [ -n "${CONFIG_FILE:-}" ] && [ -f "$CONFIG_FILE" ]; then
    SELECTED_CONFIG="$CONFIG_FILE"
# 5. Padrão: scripts/config.env
elif [ -f "${LOAD_SCRIPT_DIR}/config.env" ]; then
    SELECTED_CONFIG="${LOAD_SCRIPT_DIR}/config.env"
fi

# Se o caminho for relativo e não existir no diretório atual, tenta a partir de PROJECT_ROOT
if [ -n "$SELECTED_CONFIG" ] && [ ! -f "$SELECTED_CONFIG" ] && [ -f "${PROJECT_ROOT}/${SELECTED_CONFIG}" ]; then
    SELECTED_CONFIG="${PROJECT_ROOT}/${SELECTED_CONFIG}"
fi

# Carrega o arquivo selecionado (removendo possíveis quebras de linha CRLF do Windows)
if [ -n "$SELECTED_CONFIG" ] && [ -f "$SELECTED_CONFIG" ]; then
    sed -i 's/\r$//' "$SELECTED_CONFIG" 2>/dev/null || true
    # shellcheck source=/dev/null
    source "$SELECTED_CONFIG"
    CONFIG_FILE="$SELECTED_CONFIG"
    export CONFIG_FILE
fi

# Atribuição de variáveis considerando o método utilizado:
if [ -n "$EXPLICIT_TARGET" ]; then
    # Alvo veio de 'configs/<ALVO>.env'
    TARGET="${EXPLICIT_TARGET}"
    PDB_ID="${1:-${PDB_ID:-}}"
    NATIVE_LIG="${2:-${NATIVE_LIG:-}}"
    INCHIKEY_SRC="${3:-${INCHIKEY_SRC:-}}"
else
    # Alvo veio de arquivo .env, argumento direto ou config.env padrão
    TARGET="${1:-${TARGET:-}}"
    PDB_ID="${2:-${PDB_ID:-}}"
    NATIVE_LIG="${3:-${NATIVE_LIG:-}}"
    INCHIKEY_SRC="${4:-${INCHIKEY_SRC:-}}"
fi

# Exporta para que todos os subprocessos e scripts herdem
COFACTOR_RES="${COFACTOR_RES:-}"
BLIND_DOCKING="${BLIND_DOCKING:-false}"
BLIND_PADDING="${BLIND_PADDING:-6.0}"
BLIND_EXHAUSTIVENESS="${BLIND_EXHAUSTIVENESS:-16}"
export TARGET PDB_ID NATIVE_LIG INCHIKEY_SRC COFACTOR_RES
export BLIND_DOCKING BLIND_PADDING BLIND_EXHAUSTIVENESS
export SIZE_X SIZE_Y SIZE_Z EXHAUSTIVENESS NUM_MODES ENERGY_RANGE HUB_INCHIKEYS_DIR
