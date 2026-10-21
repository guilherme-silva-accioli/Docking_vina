#!/usr/bin/env python3
"""
build_cofactor_templates.py - Gera o arquivo JSON de templates de cofatores
compatível com Meeko v0.6+ (ResidueChemTemplates).

Uso:
    python3 scripts/build_cofactor_templates.py "GNP,MG" cofactor_atoms.pdb cofactor_template.json
"""

import json
import os
import sys
from rdkit import Chem
from meeko.polymer import (
    ResidueChemTemplates,
    build_noncovalent_CC,
    export_chem_templates_to_json,
)


def extract_single_residue_pdb_block(pdb_path: str, target_resname: str) -> str:
    """Extrai o primeiro resíduo correspondente a target_resname de um arquivo PDB."""
    lines = []
    first_res_id = None
    with open(pdb_path, "r", encoding="utf-8", errors="ignore") as f:
        for line in f:
            if line.startswith(("ATOM  ", "HETATM")):
                resname = line[17:20].strip()
                if resname != target_resname:
                    continue
                chain_res = line[21:27]
                if first_res_id is None:
                    first_res_id = chain_res
                if chain_res == first_res_id:
                    lines.append(line)
    return "".join(lines)


def build_fallback_template_from_pdb(pdb_path: str, resname: str) -> dict:
    """Fallback offline: gera template compatível com Meeko v0.6+ a partir do PDB."""
    block = extract_single_residue_pdb_block(pdb_path, resname)
    if not block:
        raise RuntimeError(f"Resíduo '{resname}' não encontrado em {pdb_path}")

    mol = Chem.MolFromPDBBlock(block, removeHs=False)
    if mol is None:
        raise RuntimeError(f"RDKit não conseguiu ler o bloco PDB do resíduo '{resname}'")

    mol_h = Chem.AddHs(mol)

    # Preservar nomes dos átomos originais do PDB e nomear Hs adicionados
    raw_names = []
    h_counter = 1
    for atom in mol_h.GetAtoms():
        info = atom.GetPDBResidueInfo()
        if info is not None and info.GetName().strip():
            raw_names.append(info.GetName().strip())
        else:
            raw_names.append(f"H{h_counter}")
            h_counter += 1

    # Garantir que a ordem dos átomos em atom_name corresponda ao SMILES gerado
    smiles = Chem.MolToSmiles(mol_h)
    atom_order_str = mol_h.GetProp("_smilesAtomOutputOrder")
    atom_order = [int(x) for x in atom_order_str.strip("[]").split(",") if x.strip()]
    ordered_atom_names = [raw_names[i] for i in atom_order]

    return {
        "ambiguous": {resname: [resname]},
        "residue_templates": {
            resname: {
                "smiles": smiles,
                "atom_name": ordered_atom_names,
                "link_labels": {},
            }
        },
    }


def main() -> int:
    if len(sys.argv) < 4:
        print(
            "Uso: python3 build_cofactor_templates.py <COFACTOR_RES> <COFACTOR_PDB> <OUT_JSON>",
            file=sys.stderr,
        )
        return 1

    cofactor_res_arg = sys.argv[1]
    cofactor_pdb = sys.argv[2]
    out_json = sys.argv[3]

    resnames = [r.strip().upper() for r in cofactor_res_arg.split(",") if r.strip()]
    if not resnames:
        print("[-] Nenhum resíduo de cofator informado.", file=sys.stderr)
        return 1

    default_templates = ResidueChemTemplates.create_from_defaults()
    combined_data = {"ambiguous": {}, "residue_templates": {}}

    for resname in resnames:
        if (
            resname in default_templates.residue_templates
            or resname in default_templates.ambiguous
        ):
            print(
                f"    [.] '{resname}' já possui template nativo no Meeko (ex: íon metálico/padrão)."
            )
            continue

        # 1. Tentar construir via CCD oficial do Meeko (mantém ordens de ligação e cargas exatas)
        try:
            print(f"    [+] Construindo template químico para '{resname}' via RCSB CCD (Meeko)...")
            cc = build_noncovalent_CC(resname, ignore_https_cert=True)
            if cc is None:
                raise RuntimeError(f"build_noncovalent_CC retornou None para {resname}")
            cc_json_str = export_chem_templates_to_json([cc])
            cc_data = json.loads(cc_json_str)
            combined_data["ambiguous"].update(cc_data.get("ambiguous", {}))
            combined_data["residue_templates"].update(
                cc_data.get("residue_templates", {})
            )
            print(f"    [✓] Template de '{resname}' construído com sucesso via CCD.")
            continue
        except Exception as e:
            print(
                f"    [!] Aviso: Falha ao obter '{resname}' via CCD ({e}). Tentando fallback local via PDB..."
            )

        # 2. Fallback local via RDKit a partir de cofactor_atoms.pdb
        if os.path.isfile(cofactor_pdb):
            fb_data = build_fallback_template_from_pdb(cofactor_pdb, resname)
            combined_data["ambiguous"].update(fb_data["ambiguous"])
            combined_data["residue_templates"].update(fb_data["residue_templates"])
            print(f"    [✓] Template de '{resname}' construído via fallback local (PDB).")
        else:
            print(
                f"    [-] Erro: Arquivo {cofactor_pdb} não encontrado para fallback de '{resname}'.",
                file=sys.stderr,
            )
            return 1

    if combined_data["residue_templates"]:
        os.makedirs(os.path.dirname(os.path.abspath(out_json)), exist_ok=True)
        with open(out_json, "w", encoding="utf-8") as f:
            json.dump(combined_data, f, indent=2)
        print(f"    [✓] Arquivo de templates salvo em: {out_json}")
    else:
        # Todos os cofatores informados já são nativos do Meeko (ex: apenas MG ou ZN)
        if os.path.exists(out_json):
            os.remove(out_json)
        print("    [.] Todos os cofatores informados já são nativos do Meeko; JSON extra não é necessário.")

    return 0


if __name__ == "__main__":
    sys.exit(main())
