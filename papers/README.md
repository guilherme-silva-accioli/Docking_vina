# Catálogo de Artigos Cristalográficos das Estruturas PDB (`papers/`)

Esta pasta armazena os artigos científicos originais referentes às estruturas cristalográficas (`.pdb`) utilizadas no pipeline de docking molecular, recuperados de forma reprodutível via **Europe PMC**, **NCBI PubMed/PMC**, **OpenAlex**, **Crossref**, **Semantic Scholar** e **Unpaywall**, e convertidos para Markdown via **`MarkItDown`** e **`jats_to_text.py`**.

## Estrutura da Pasta

- `markdown/` — Artigos convertidos para Markdown (`.md`), contendo tabela de proveniência, *Abstract*, texto completo seccionado (JATS XML) e conversão direta do PDF (`MarkItDown`).
- `pdfs/` — Arquivos PDF originais de acesso aberto (*Gold OA*).
- `xml/` — Arquivos JATS XML de texto completo com elemento `<body>` verificado pelo `jats_to_text.py`.
- `papers_catalog.csv` — Tabela resumo com metadados bibliográficos e status de acesso aberto.

## Tabela Resumo das Estruturas PDB e Artigos

| Alvo | PDB ID | Ligante | PMID | PMCID | DOI | Periódico (Ano) | Status OA | PDF Local | Texto Completo XML (`<body>`) | Arquivo Markdown |
|---|---|---|---|---|---|---|---|---|---|---|
| **AKT1** | `3O96` | `IQO` | `20886116` | `PMC2944833` | `10.1371/journal.pone.0012913` | PloS one (2010) | `gold` | Sim (`AKT1_3O96_20886116.pdf`) | Sim (`AKT1_3O96_PMC2944833.xml`) | [`markdown/AKT1_3O96_20886116.md`](markdown/AKT1_3O96_20886116.md) |
| **EGFR** | `3POZ` | `03P` | `21454582` | `PMC3099692` | `10.1074/jbc.M110.206193` | The Journal of biological chemistry (2011) | `hybrid` | Não (Restrito/HTML) | Restrito (`exit=2`, sem `<body>`) | [`markdown/EGFR_3POZ_21454582.md`](markdown/EGFR_3POZ_21454582.md) |
| **JAK2** | `6WTQ` | `U8J` | `34110416` | `PMC8662068` | `10.1182/blood.2020006846` | Blood (2021) | `green` | Não (Restrito/HTML) | Restrito (`exit=2`, sem `<body>`) | [`markdown/JAK2_6WTQ_34110416.md`](markdown/JAK2_6WTQ_34110416.md) |
| **MAPK14** | `4FA2` | `SB0` | `23840427` | `PMC3694096` | `10.1371/journal.pone.0066226` | PloS one (2013) | `gold` | Sim (`MAPK14_4FA2_23840427.pdf`) | Sim (`MAPK14_4FA2_PMC3694096.xml`) | [`markdown/MAPK14_4FA2_23840427.md`](markdown/MAPK14_4FA2_23840427.md) |
| **PIK3CA** | `5DXT` | `5H5` | `26741947` | `-` | `10.1021/acs.jmedchem.5b01483` | Journal of medicinal chemistry (2016) | `green` | Não (Restrito/HTML) | Não disponível | [`markdown/PIK3CA_5DXT_26741947.md`](markdown/PIK3CA_5DXT_26741947.md) |
| **PPARG** | `5GTN` | `Q35` | `28342850` | `-` | `10.1016/j.bbapap.2017.03.008` | Biochimica et biophysica acta. Proteins and proteomics (2017) | `closed` | Não (Restrito/HTML) | Não disponível | [`markdown/PPARG_5GTN_28342850.md`](markdown/PPARG_5GTN_28342850.md) |
| **STAT3** | `6NJS` | `KQV` | `31715132` | `PMC6880868` | `10.1016/j.ccell.2019.10.002` | Cancer cell (2019) | `bronze` | Não (Restrito/HTML) | Sim (`STAT3_6NJS_PMC6880868.xml`) | [`markdown/STAT3_6NJS_31715132.md`](markdown/STAT3_6NJS_31715132.md) |
| **HSP90AB1** | `5UCJ` | `KU3` | `29382832` | `PMC5789826` | `10.1038/s41467-017-02013-1` | Nature communications (2018) | `gold` | Sim (`HSP90AB1_5UCJ_29382832.pdf`) | Sim (`HSP90AB1_5UCJ_PMC5789826.xml`) | [`markdown/HSP90AB1_5UCJ_29382832.md`](markdown/HSP90AB1_5UCJ_29382832.md) |
