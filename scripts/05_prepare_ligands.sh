#!/usr/bin/env bash
# ==============================================================================
# 05_prepare_ligands.sh - Protonação a pH 7.4 (OpenBabel) + PDBQT (Meeko)
# ==============================================================================
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/load_config.sh" "$@"

TARGET="${TARGET:-}"

if [ -z "$TARGET" ]; then
    echo "[-] Erro: TARGET não foi definido!"
    echo "    Uso: $0 [TARGET]"
    exit 1
fi

# Tentar carregar ambiente conda se ferramentas não estiverem no PATH
if ! command -v obabel &> /dev/null || ! command -v mk_prepare_ligand.py &> /dev/null; then
    if [ -f "$HOME/miniconda3/etc/profile.d/conda.sh" ]; then
        # shellcheck source=/dev/null
        source "$HOME/miniconda3/etc/profile.d/conda.sh"
        conda activate docking_vina 2>/dev/null || conda activate vina 2>/dev/null || true
    fi
fi

if ! command -v obabel &> /dev/null; then
    echo "[-] Erro: 'obabel' (OpenBabel) não encontrado no PATH!"
    exit 1
fi

if ! command -v mk_prepare_ligand.py &> /dev/null; then
    echo "[-] Erro: 'mk_prepare_ligand.py' (Meeko) não encontrado no PATH!"
    exit 1
fi

RAW_DIR="targets/${TARGET}/ligands/raw"
PREP_DIR="targets/${TARGET}/ligands/prepared"
ERR_LOG_DIR="targets/${TARGET}/results/logs"
SANITIZER="${SCRIPT_DIR}/sanitize_charged_sdf.py"

mkdir -p "$PREP_DIR" "$ERR_LOG_DIR"

echo "[+] Preparando ligantes a pH 7.4 para o alvo '${TARGET}'..."
echo "    Diretório de entrada: ${RAW_DIR}/"
echo "    Diretório de saída:   ${PREP_DIR}/"

# Selecionar arquivos SDF originais
RAW_SDFS=()
for f in "${RAW_DIR}"/*.sdf; do
    [ -e "$f" ] || continue
    if [[ "$f" != *"_charged"* ]]; then
        RAW_SDFS+=("$f")
    fi
done

TOTAL_FILES=${#RAW_SDFS[@]}
if [ "$TOTAL_FILES" -eq 0 ]; then
    echo "[-] Nenhum arquivo .sdf bruto encontrado em: ${RAW_DIR}"
    exit 1
fi

echo "[+] Total de ${TOTAL_FILES} estruturas para protonar a pH 7.4 e preparar."

SUCCESS_COUNT=0
SKIPPED_COUNT=0
FAILED_COUNT=0

IDX=0
for sdf in "${RAW_SDFS[@]}"; do
    IDX=$((IDX + 1))
    base=$(basename "$sdf" .sdf)
    out_pdbqt="${PREP_DIR}/${base}_charged.pdbqt"
    charged_sdf="${RAW_DIR}/${base}_charged.sdf"
    err_log="${ERR_LOG_DIR}/prepare_err_${base}.log"

    # Se já foi preparado com sucesso, pula
    if [ -f "$out_pdbqt" ] && [ -s "$out_pdbqt" ]; then
        SKIPPED_COUNT=$((SKIPPED_COUNT + 1))
        continue
    fi

    echo -n "    [${IDX}/${TOTAL_FILES}] Protonando pH 7.4 e preparando: ${base}... "

    # 1. Protonar a pH 7.4 e calcular cargas parciais com OpenBabel
    tmp_obabel="/tmp/${base}_obabel.sdf"
    if ! obabel "$sdf" -O "$tmp_obabel" -p 7.4 --partialcharge gasteiger >/dev/null 2>"$err_log"; then
        echo "FALHA no OpenBabel (ver ${err_log})"
        rm -f "$tmp_obabel"
        FAILED_COUNT=$((FAILED_COUNT + 1))
        continue
    fi

    # 2. Sanitizar anomalias de valência de éter do OpenBabel preservando o estado de protonação a pH 7.4
    if [ -f "$SANITIZER" ]; then
        python3 "$SANITIZER" "$tmp_obabel" "$charged_sdf" >/dev/null 2>>"$err_log" || cp "$tmp_obabel" "$charged_sdf"
    else
        cp "$tmp_obabel" "$charged_sdf"
    fi
    rm -f "$tmp_obabel"

    # 3. Gerar PDBQT flexível com Meeko
    if mk_prepare_ligand.py -i "$charged_sdf" -o "$out_pdbqt" >/dev/null 2>>"$err_log"; then
        if [ -s "$out_pdbqt" ]; then
            echo "OK"
            rm -f "$err_log"
            SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
            continue
        fi
    fi

    # Se falhou
    echo "FALHA no Meeko (ver ${err_log})"
    rm -f "$out_pdbqt"
    FAILED_COUNT=$((FAILED_COUNT + 1))
done

echo "--------------------------------------------------------"
echo "[✓] Concluído! Ligantes protonados a pH 7.4 e preparados:"
echo "    Sucessos:   ${SUCCESS_COUNT}"
echo "    Existentes: ${SKIPPED_COUNT}"
echo "    Falhas:     ${FAILED_COUNT}"
echo "    Arquivos em: ${PREP_DIR}/"
