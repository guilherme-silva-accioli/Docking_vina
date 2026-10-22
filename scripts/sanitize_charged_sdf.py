#!/usr/bin/env python3
"""
Sanitiza arquivos SDF gerados pelo OpenBabel com '-p 7.4'.
Corrige erros conhecidos de valência atribuídos incorretamente pelo OpenBabel
(ex: carga formal -1 em oxigênios de éter com valência 2) sem alterar
as desprotonações/protonações fisiológicas reais (como fenóis, carboxilatos e aminas).
"""
import sys
from rdkit import Chem

def sanitize_sdf(input_sdf, output_sdf):
    # Carrega todos os mols na memória primeiro para permitir input_sdf == output_sdf com segurança
    suppl = Chem.SDMolSupplier(input_sdf, sanitize=False, removeHs=False)
    mols = [m for m in suppl if m is not None]

    writer = Chem.SDWriter(output_sdf)
    fixed_count = 0
    total_count = len(mols)

    for mol in mols:
        modified = False

        for atom in mol.GetAtoms():
            sym = atom.GetSymbol()
            chg = atom.GetFormalCharge()
            val = atom.GetValence(Chem.ValenceType.EXPLICIT)

            # Oxigênio com 2 ligações não pode ter carga -1 (bug do OpenBabel em éteres conjugados)
            if sym == "O" and val == 2 and chg == -1:
                atom.SetFormalCharge(0)
                modified = True

            # Nitrogênio com 4 ligações simples neutro deve ser +1 se quaternário
            elif sym == "N" and val == 4 and chg == 0:
                atom.SetFormalCharge(1)
                modified = True

        try:
            Chem.SanitizeMol(mol)
        except Exception:
            try:
                mol.UpdatePropertyCache(strict=False)
            except Exception:
                pass

        if modified:
            fixed_count += 1

        writer.write(mol)

    writer.close()
    return total_count, fixed_count

if __name__ == "__main__":
    if len(sys.argv) < 3:
        print("Uso: python3 sanitize_charged_sdf.py <input.sdf> <output.sdf>")
        sys.exit(1)
    
    in_file = sys.argv[1]
    out_file = sys.argv[2]
    total, fixed = sanitize_sdf(in_file, out_file)
    if fixed > 0:
        print(f"[i] {fixed} molécula(s) com valência de éter corrigida mantendo pH 7.4 em: {out_file}")
