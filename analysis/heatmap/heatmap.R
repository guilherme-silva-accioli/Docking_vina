# %% cell 1
# ------------------------------------------------------------
# 1. Instalar e carregar pacotes
# ------------------------------------------------------------
pacotes <- c(
  "openxlsx",
  "dplyr",
  "tidyr",
  "tibble",
  "pheatmap",
  "ggplot2",
  "jsonlite"
)
for (p in pacotes) {
  if (!requireNamespace(p, quietly = TRUE)) {
    install.packages(p, repos = "https://cloud.r-project.org")
  }
}
suppressPackageStartupMessages({
  library(openxlsx)
  library(dplyr)
  library(tidyr)
  library(tibble)
  library(pheatmap)
  library(ggplot2)
  library(jsonlite)
})

# %% cell 2
# ------------------------------------------------------------
# 2. Configuração e detecção de diretórios
# ------------------------------------------------------------
args <- commandArgs(trailingOnly = TRUE)
TOP_N <- if (length(args) >= 1 && !is.na(suppressWarnings(as.integer(args[1])))) {
  as.integer(args[1])
} else {
  10L
}

# Detectar diretório do script (funciona via Rscript, RStudio ou VS Code)
get_script_dir <- function() {
  cmd_args <- commandArgs(trailingOnly = FALSE)
  file_arg <- grep("^--file=", cmd_args, value = TRUE)
  if (length(file_arg) > 0) {
    return(dirname(normalizePath(sub("^--file=", "", file_arg[1]), winslash = "/")))
  }
  if (file.exists("heatmap.R")) {
    return(normalizePath(getwd(), winslash = "/"))
  }
  if (file.exists("analysis/heatmap/heatmap.R")) {
    return(normalizePath("analysis/heatmap", winslash = "/"))
  }
  return(normalizePath(getwd(), winslash = "/"))
}

HEATMAP_DIR <- get_script_dir()
PROJECT_ROOT <- if (length(args) >= 2 && dir.exists(args[2])) {
  normalizePath(args[2], winslash = "/")
} else {
  normalizePath(file.path(HEATMAP_DIR, "..", ".."), winslash = "/")
}

TARGETS_DIR <- file.path(PROJECT_ROOT, "targets")
CACHE_FILE <- file.path(HEATMAP_DIR, "compound_names.csv")
MATRIX_CSV <- file.path(HEATMAP_DIR, "results_matrix.csv")
OUT_PNG <- file.path(HEATMAP_DIR, "heatmap_docking.png")

cat(sprintf("[+] Diretório do projeto: %s\n", PROJECT_ROOT))
cat(sprintf("[+] Selecionando Top-%d ligantes únicos (sem repetir estereoisômeros) por alvo...\n", TOP_N))

# %% cell 3
# ------------------------------------------------------------
# 3. Ler CSVs de todos os alvos, deduplicar estereoisômeros e buscar nomes/CIDs no PubChem
# ------------------------------------------------------------
csv_files <- Sys.glob(file.path(TARGETS_DIR, "*", "results", "summary", "docking_affinities.csv"))
if (length(csv_files) == 0) {
  stop("Nenhum arquivo docking_affinities.csv encontrado em: ", TARGETS_DIR)
}

lista_alvos <- lapply(csv_files, function(f) {
  partes <- strsplit(normalizePath(f, winslash = "/"), "/")[[1]]
  idx_targets <- which(partes == "targets")
  gene <- if (length(idx_targets) > 0) partes[idx_targets[length(idx_targets)] + 1] else basename(dirname(dirname(dirname(f))))
  df <- read.csv(f, stringsAsFactors = FALSE)
  df$Gene <- gene
  df
})

todos_resultados_raw <- bind_rows(lista_alvos) %>%
  mutate(
    InChIKey = sub("_charged$", "", trimws(ligand)),
    Bloco1 = substr(InChIKey, 1, 14),
    Docking = suppressWarnings(as.numeric(affinity_kcal_mol))
  ) %>%
  filter(!is.na(Docking), nzchar(InChIKey))

# Identificar o melhor estereoisômero global para cada conectividade (Bloco1)
melhor_isomero_por_bloco <- todos_resultados_raw %>%
  group_by(Bloco1, InChIKey) %>%
  summarise(melhor_global = min(Docking, na.rm = TRUE), .groups = "drop") %>%
  arrange(Bloco1, melhor_global, InChIKey) %>%
  group_by(Bloco1) %>%
  slice(1) %>%
  ungroup() %>%
  select(Bloco1, Rep_InChIKey = InChIKey)

# Para cada (Gene, Bloco1), manter apenas a melhor afinidade (melhor estereoisômero)
todos_resultados <- todos_resultados_raw %>%
  group_by(Gene, Bloco1) %>%
  slice_min(order_by = Docking, n = 1, with_ties = FALSE) %>%
  ungroup() %>%
  left_join(melhor_isomero_por_bloco, by = "Bloco1")

# Selecionar a união dos Top-N compostos (por conectividade Bloco1) de cada alvo
top_blocos <- todos_resultados %>%
  group_by(Gene) %>%
  slice_min(order_by = Docking, n = TOP_N, with_ties = FALSE) %>%
  ungroup() %>%
  pull(Bloco1) %>%
  unique()

top_inchikeys <- melhor_isomero_por_bloco %>%
  filter(Bloco1 %in% top_blocos) %>%
  pull(Rep_InChIKey) %>%
  unique()

cat(sprintf("[+] Total de alvos lidos: %d | Compostos únicos no Top-%d: %d\n",
            n_distinct(todos_resultados$Gene), TOP_N, length(top_inchikeys)))

# Funções auxiliares para classificar nomes triviais vs. códigos/IUPAC
eh_nome_trivial <- function(s) {
  if (is.null(s) || is.na(s) || !nzchar(trimws(s))) return(FALSE)
  s <- trimws(s)
  if (nchar(s) < 4 || nchar(s) > 30) return(FALSE)
  # Ignorar fórmulas moleculares (ex: C25H26O4, C16H12O6)
  if (grepl("^C[0-9]+H[0-9]+", s, ignore.case = TRUE)) return(FALSE)
  # Ignorar siglas curtas com hífen e número (ex: SPF-1, SPF-2, HY-123)
  if (grepl("^[A-Z]{1,4}-[0-9]+", s, ignore.case = TRUE)) return(FALSE)
  # Ignorar InChI, SMILES, URLs ou códigos de bancos de dados / números CAS
  if (grepl("^(InChI|1S/|https?:|SCHEMBL|CHEMBL|DTXSID|DTXCID|CHEBI:|HMS|BDBM|ZINC|AKOS|CS-|HY-|MFCD|AS-|FT-|ST[0-9]|AC1[0-9]|AB[0-9]|NCGC|LS-|DB-|SB-|MLS|SMR|SR-|RefChem|LMPK|AA-|CID|CNP|MTBLC|NSC|EINECS|CCRIS|GTPL|UNII|HSDB|BRN|NCI|C[0-9]{5,}|Q[0-9]{4,}|J[0-9]+\\.)", s, ignore.case = TRUE)) return(FALSE)
  if (grepl("^[0-9]+-[0-9]+-[0-9]+$", s)) return(FALSE)
  if (grepl("^[0-9A-Z]{10,}$", s)) return(FALSE)
  if (grepl("^[A-Z]{14}-[A-Z]{10}-[A-Z]$", s)) return(FALSE)
  if (grepl("^[0-9., %+-]+$", s)) return(FALSE)
  if (grepl("[=\\#\\@\\/\\\\]", s)) return(FALSE)
  # Permitir nomes triviais de 1 ou 2 palavras sem locantes numéricos (ex: Abyssinone III, Ovalichromene, Shinflavanone, Mosloflavanone, Pongamone C)
  if (grepl("^[A-Za-z]{4,}( [A-Za-z0-9]{1,4})?$", s)) return(TRUE)
  # Ignorar nomes sistemáticos IUPAC com locantes/parênteses/colchetes
  if (grepl("(dihydro|chromen|pyrano|benzodioxol|benzofuran|methoxyphenyl|hydroxyphenyl|dimethoxyphenyl|methylenedioxy|flavanone|cyclohex|furo\\[|dioxolo\\[|benzo\\[|dipyran|propenyl|butenyl|pentenyl|\\[|\\]|\\([0-9RSEZ,]+\\))", s, ignore.case = TRUE)) {
    return(FALSE)
  }
  return(TRUE)
}

limpar_nome_trivial <- function(s) {
  s <- trimws(s)
  # Corrigir "PongamoneC" -> "Pongamone C"
  s <- sub("^([A-Za-z]{5,})([A-Z])$", "\\1 \\2", s)
  if (toupper(s) == s && nchar(s) > 5) {
    # Converter "CRYPTOCARYANONE A" -> "Cryptocaryanone A"
    palavras <- strsplit(s, " ")[[1]]
    palavras <- sapply(palavras, function(w) {
      if (nchar(w) <= 2) w else paste0(toupper(substr(w, 1, 1)), tolower(substr(w, 2, nchar(w))))
    })
    s <- paste(palavras, collapse = " ")
  }
  return(s)
}

buscar_info_pubchem <- function(ik) {
  bloco1 <- substr(ik, 1, 14)
  cid_principal <- NA_character_
  nome_iupac <- NA_character_

  # 1. Propriedades básicas (CID, Title, IUPACName) do InChIKey exato
  url_prop <- sprintf("https://pubchem.ncbi.nlm.nih.gov/rest/pug/compound/inchikey/%s/property/Title,IUPACName/JSON", ik)
  res_prop <- tryCatch(jsonlite::fromJSON(url_prop), error = function(e) NULL)
  if (!is.null(res_prop) && !is.null(res_prop$PropertyTable$Properties)) {
    props <- res_prop$PropertyTable$Properties
    cid_principal <- as.character(props$CID[1])
    titulo <- if ("Title" %in% names(props)) as.character(props$Title[1]) else NA_character_
    iupac <- if ("IUPACName" %in% names(props)) as.character(props$IUPACName[1]) else NA_character_
    nome_iupac <- if (!is.na(titulo) && nzchar(titulo)) titulo else iupac
    if (eh_nome_trivial(titulo)) {
      return(list(CID = cid_principal, Nome = limpar_nome_trivial(titulo), Nome_Completo = nome_iupac, Fonte = "PubChem_Title"))
    }
  }

  # 1b. Verificar conectividade plana (<Bloco1>-UHFFFAOYSA-N) diretamente
  flat_ik <- paste0(bloco1, "-UHFFFAOYSA-N")
  if (ik != flat_ik) {
    Sys.sleep(0.12)
    url_flat <- sprintf("https://pubchem.ncbi.nlm.nih.gov/rest/pug/compound/inchikey/%s/property/Title/JSON", flat_ik)
    res_flat <- tryCatch(jsonlite::fromJSON(url_flat), error = function(e) NULL)
    if (!is.null(res_flat) && !is.null(res_flat$PropertyTable$Properties)) {
      t_flat <- as.character(res_flat$PropertyTable$Properties$Title[1])
      if (eh_nome_trivial(t_flat)) {
        return(list(CID = cid_principal, Nome = limpar_nome_trivial(t_flat), Nome_Completo = nome_iupac, Fonte = "PubChem_Flat_Title"))
      }
    }
  }

  # 2. Verificar todos os CIDs de mesma conectividade (cids_type=same_connectivity)
  cids_conect <- character()
  url_cids <- sprintf("https://pubchem.ncbi.nlm.nih.gov/rest/pug/compound/inchikey/%s/cids/JSON?cids_type=same_connectivity", ik)
  res_cids <- tryCatch(jsonlite::fromJSON(url_cids), error = function(e) NULL)
  if (!is.null(res_cids) && !is.null(res_cids$IdentifierList$CID)) {
    cids_conect <- as.character(head(res_cids$IdentifierList$CID, 15))
  }
  if (!is.na(cid_principal)) {
    cids_conect <- unique(c(cid_principal, cids_conect))
  }

  if (length(cids_conect) > 0) {
    cid_csv <- paste(cids_conect, collapse = ",")
    # 2a. Títulos dos isômeros de mesma conectividade
    Sys.sleep(0.15)
    url_t <- sprintf("https://pubchem.ncbi.nlm.nih.gov/rest/pug/compound/cid/%s/property/Title/JSON", cid_csv)
    res_t <- tryCatch(jsonlite::fromJSON(url_t), error = function(e) NULL)
    if (!is.null(res_t) && !is.null(res_t$PropertyTable$Properties)) {
      for (t_cand in res_t$PropertyTable$Properties$Title) {
        if (eh_nome_trivial(t_cand)) {
          return(list(CID = cid_principal, Nome = limpar_nome_trivial(t_cand), Nome_Completo = nome_iupac, Fonte = "PubChem_Connectivity_Title"))
        }
      }
    }

    # 2b. Sinônimos de todos os CIDs de mesma conectividade
    Sys.sleep(0.15)
    url_s <- sprintf("https://pubchem.ncbi.nlm.nih.gov/rest/pug/compound/cid/%s/synonyms/JSON", cid_csv)
    res_s <- tryCatch(jsonlite::fromJSON(url_s), error = function(e) NULL)
    if (!is.null(res_s) && !is.null(res_s$InformationList$Information)) {
      syns <- unlist(res_s$InformationList$Information$Synonym)
      for (s_cand in syns) {
        if (eh_nome_trivial(s_cand)) {
          return(list(CID = cid_principal, Nome = limpar_nome_trivial(s_cand), Nome_Completo = nome_iupac, Fonte = "PubChem_Synonym"))
        }
      }
    }
  }

  # 3. Verificar PUG View (Names and Identifiers -> Wikidata / Removed Synonyms como Khonklonginol G, Carsifuran A, Pongamone C, SPF-1/2)
  if (!is.na(cid_principal)) {
    Sys.sleep(0.15)
    url_pv <- sprintf("https://pubchem.ncbi.nlm.nih.gov/rest/pug_view/data/compound/%s/JSON?heading=Names+and+Identifiers", cid_principal)
    txt_pv <- tryCatch(suppressWarnings(paste(readLines(url_pv, warn = FALSE, encoding = "UTF-8"), collapse = "\n")), error = function(e) "")
    if (nzchar(txt_pv)) {
      matches <- regmatches(txt_pv, gregexpr('"String"\\s*:\\s*"([^"\\\\]{3,30})"', txt_pv, perl = TRUE))[[1]]
      candidatos <- sub('^"String"\\s*:\\s*"(.*)"$', "\\1", matches)
      for (c_cand in candidatos) {
        if (eh_nome_trivial(c_cand) && c_cand != cid_principal) {
          return(list(CID = cid_principal, Nome = limpar_nome_trivial(c_cand), Nome_Completo = nome_iupac, Fonte = "PubChem_PUGView"))
        }
      }
    }
  }

  # 4. Fallback limpo: usar "CID <numero>" quando só existir nome IUPAC longo
  rotulo_cid <- if (!is.na(cid_principal) && nzchar(cid_principal)) paste0("CID ", cid_principal) else bloco1
  return(list(
    CID = ifelse(is.na(cid_principal), "", cid_principal),
    Nome = rotulo_cid,
    Nome_Completo = ifelse(is.na(nome_iupac), "", nome_iupac),
    Fonte = "PubChem_CID"
  ))
}

# Carregar ou criar cache de nomes de compostos
if (file.exists(CACHE_FILE)) {
  cache_nomes <- read.csv(CACHE_FILE, stringsAsFactors = FALSE)
  if (!("CID" %in% names(cache_nomes))) {
    cache_nomes <- data.frame(InChIKey = character(), CID = character(), Nome = character(), Nome_Completo = character(), Fonte = character(), stringsAsFactors = FALSE)
  } else {
    cache_nomes$CID <- as.character(cache_nomes$CID)
  }
} else {
  cache_nomes <- data.frame(InChIKey = character(), CID = character(), Nome = character(), Nome_Completo = character(), Fonte = character(), stringsAsFactors = FALSE)
}

faltantes <- setdiff(top_inchikeys, cache_nomes$InChIKey)
if (length(faltantes) > 0) {
  cat(sprintf("[+] Consultando nomes/CIDs no PubChem para %d composto(s)...\n", length(faltantes)))
  for (ik in faltantes) {
    info <- buscar_info_pubchem(ik)
    cache_nomes <- cache_nomes %>% filter(InChIKey != ik)
    cache_nomes <- bind_rows(
      cache_nomes,
      data.frame(
        InChIKey = ik,
        CID = as.character(info$CID),
        Nome = info$Nome,
        Nome_Completo = info$Nome_Completo,
        Fonte = info$Fonte,
        stringsAsFactors = FALSE
      )
    )
    Sys.sleep(0.18)
  }
  cache_nomes <- cache_nomes %>% arrange(InChIKey)
  write.csv(cache_nomes, CACHE_FILE, row.names = FALSE)
  cat(sprintf("[✓] Cache de nomes atualizado em: %s\n", CACHE_FILE))
}

# Mapear cada conectividade (Bloco1) ao seu rótulo limpo
mapa_rotulos <- tibble(Rep_InChIKey = top_inchikeys) %>%
  mutate(Bloco1 = substr(Rep_InChIKey, 1, 14)) %>%
  left_join(cache_nomes, by = c("Rep_InChIKey" = "InChIKey")) %>%
  mutate(
    Composto = ifelse(is.na(Nome) | !nzchar(Nome), paste0("CID ", CID), Nome)
  )

# Construir e salvar a matriz larga (sem repetir estereoisômeros)
dados_filtrados <- todos_resultados %>%
  filter(Bloco1 %in% top_blocos) %>%
  inner_join(mapa_rotulos %>% select(Bloco1, Composto), by = "Bloco1") %>%
  group_by(Gene, Composto) %>%
  summarise(Docking = min(Docking, na.rm = TRUE), .groups = "drop")

ordem_compostos <- dados_filtrados %>%
  group_by(Composto) %>%
  summarise(melhor = min(Docking, na.rm = TRUE), .groups = "drop") %>%
  arrange(melhor) %>%
  pull(Composto)

dados_matriz <- dados_filtrados %>%
  select(Gene, Composto, Docking) %>%
  mutate(Composto = factor(Composto, levels = ordem_compostos)) %>%
  arrange(Gene, Composto) %>%
  pivot_wider(names_from = Composto, values_from = Docking)

write.csv(dados_matriz, MATRIX_CSV, row.names = FALSE, na = "")
cat(sprintf("[✓] Matriz larga salva em: %s\n", MATRIX_CSV))

# Ler de volta exatamente como no script de referência
dados <- read.csv(
  MATRIX_CSV,
  header = TRUE,
  fill = TRUE,
  dec = ".",
  strip.white = TRUE,
  na.strings = c("", "NA"),
  check.names = FALSE
)
colnames(dados)[1] <- "Gene"

# %% cell 4
# ------------------------------------------------------------
# 4. Converter para formato longo
# ------------------------------------------------------------
dados_long <- dados %>%
  pivot_longer(
    cols = -Gene,
    names_to = "Composto",
    values_to = "Docking"
  ) %>%
  mutate(
    Composto = factor(Composto, levels = colnames(dados)[-1]),
    Gene = factor(Gene, levels = sort(unique(Gene)))
  )

# %% cell 5
# ------------------------------------------------------------
# 5. Heatmap com ggplot2 (estilo idêntico ao teste heatmap)
# ------------------------------------------------------------
p <- ggplot(dados_long, aes(x = Composto, y = Gene, fill = Docking)) +

  geom_tile(color = "grey85", linewidth = 0.4) +

  geom_text(
    data = subset(dados_long, !is.na(Docking)),
    aes(label = sprintf("%.2f", Docking)),
    size = 3,
    color = "black"
  ) +

  scale_fill_gradientn(
    colours = c(
      "#800026", # mais negativo/intenso = vermelho escuro
      "#BD0026",
      "#E31A1C",
      "#FC4E2A",
      "#FD8D3C",
      "#FEB24C",
      "#FED976",
      "#FFFFCC",
      "#FFFFFF"  # neutro / zero = mais claro
    ),
    na.value = "white",
    name = "Binding Affinity\n(kcal/mol)"
  ) +

  labs(
    title = "",
    subtitle = "",
    x = "ligands",
    y = "Receptors"
  ) +

  theme_minimal(base_size = 13) +

  theme(
    panel.grid = element_blank(),
    axis.text.x = element_text(angle = 45, hjust = 1),
    axis.text.y = element_text(face = "bold"),
    plot.title = element_text(face = "bold", hjust = 0.5),
    plot.subtitle = element_text(hjust = 0.5),
    legend.position = "right",
    plot.margin = margin(10, 20, 15, 30),
    plot.background = element_rect(fill = "white", color = NA)
  )

# %% save the plot
# ------------------------------------------------------------
# 6. Salvar o gráfico em alta resolução (600 dpi)
# ------------------------------------------------------------
n_cols <- ncol(dados) - 1
n_rows <- nrow(dados)
largura <- max(10, min(28, 4 + n_cols * 0.42))
altura <- max(8, min(16, 4 + n_rows * 0.65))

ggsave(
  filename = OUT_PNG,
  plot = p,
  width = largura,
  height = altura,
  dpi = 600
)
cat(sprintf("[✓] Heatmap salvo com sucesso em: %s (%.1f x %.1f in, 600 dpi)\n", OUT_PNG, largura, altura))
