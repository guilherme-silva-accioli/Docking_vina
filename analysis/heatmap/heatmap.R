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
PROJECT_ROOT <- if ( length(args) >= 2 && dir.exists(args[2]) ) {
  normalizePath(args[2], winslash = "/")
} else {
  normalizePath(file.path(HEATMAP_DIR, "..", ".."), winslash = "/")
}

TARGETS_DIR <- file.path(PROJECT_ROOT, "targets")
CACHE_FILE <- file.path(HEATMAP_DIR, "compound_names.csv")
MATRIX_CSV <- file.path(HEATMAP_DIR, "results_matrix.csv")
OUT_PNG <- file.path(HEATMAP_DIR, "heatmap_docking.png")

cat(sprintf("[+] Diretório do projeto: %s\n", PROJECT_ROOT))
cat(sprintf("[+] Selecionando Top-%d ligantes por alvo...\n", TOP_N))

# %% cell 3
# ------------------------------------------------------------
# 3. Ler CSVs de todos os alvos, buscar nomes no PubChem e gerar matriz
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

todos_resultados <- bind_rows(lista_alvos) %>%
  mutate(
    InChIKey = sub("_charged$", "", trimws(ligand)),
    Docking = suppressWarnings(as.numeric(affinity_kcal_mol))
  ) %>%
  filter(!is.na(Docking), nzchar(InChIKey))

# Selecionar a união dos Top-N ligantes (menor energia = mais negativo) de cada alvo
top_inchikeys <- todos_resultados %>%
  group_by(Gene) %>%
  slice_min(order_by = Docking, n = TOP_N, with_ties = FALSE) %>%
  ungroup() %>%
  pull(InChIKey) %>%
  unique()

cat(sprintf("[+] Total de alvos lidos: %d | Ligantes únicos no Top-%d: %d\n",
            n_distinct(todos_resultados$Gene), TOP_N, length(top_inchikeys)))

# Carregar ou criar cache de nomes de compostos (PubChem Title / IUPAC)
if (file.exists(CACHE_FILE)) {
  cache_nomes <- read.csv(CACHE_FILE, stringsAsFactors = FALSE)
} else {
  cache_nomes <- data.frame(InChIKey = character(), Nome = character(), Fonte = character(), stringsAsFactors = FALSE)
}

buscar_titulo_pubchem <- function(ik) {
  url <- sprintf("https://pubchem.ncbi.nlm.nih.gov/rest/pug/compound/inchikey/%s/property/Title,IUPACName/JSON", ik)
  res <- tryCatch(jsonlite::fromJSON(url), error = function(e) NULL)
  if (!is.null(res) && !is.null(res$PropertyTable$Properties)) {
    props <- res$PropertyTable$Properties
    titulo <- if ("Title" %in% names(props)) props$Title[1] else NA_character_
    iupac <- if ("IUPACName" %in% names(props)) props$IUPACName[1] else NA_character_
    nome <- if (!is.na(titulo) && nzchar(titulo)) titulo else iupac
    if (!is.na(nome) && nzchar(nome)) {
      return(trimws(nome))
    }
  }
  return(NA_character_)
}

buscar_nome_pubchem <- function(ik) {
  nome <- buscar_titulo_pubchem(ik)
  bloco1 <- substr(ik, 1, 14)
  partes <- strsplit(ik, "-", fixed = TRUE)[[1]]
  bloco2 <- if (length(partes) >= 2) partes[2] else ""

  # Se o estereoisômero retornou apenas nome sistemático longo (> 30 caracteres),
  # consulta também a conectividade plana (UHFFFAOYSA-N) para verificar se há nome trivial curto
  if ((is.na(nome) || nchar(nome) > 30) && bloco2 != "UHFFFAOYSA") {
    Sys.sleep(0.18)
    flat_nome <- buscar_titulo_pubchem(paste0(bloco1, "-UHFFFAOYSA-N"))
    if (!is.na(flat_nome) && nchar(flat_nome) <= 30) {
      return(list(Nome = flat_nome, Fonte = "PubChem"))
    }
  }

  if (!is.na(nome) && nzchar(nome)) {
    return(list(Nome = nome, Fonte = "PubChem"))
  }
  return(list(Nome = bloco1, Fonte = "InChIKey_Fallback"))
}

faltantes <- setdiff(top_inchikeys, cache_nomes$InChIKey[cache_nomes$Fonte != "InChIKey_Fallback"])
if (length(faltantes) > 0) {
  cat(sprintf("[+] Consultando nomes no PubChem para %d ligante(s)...\n", length(faltantes)))
  for (ik in faltantes) {
    info <- buscar_nome_pubchem(ik)
    cache_nomes <- cache_nomes %>% filter(InChIKey != ik)
    cache_nomes <- bind_rows(
      cache_nomes,
      data.frame(InChIKey = ik, Nome = info$Nome, Fonte = info$Fonte, stringsAsFactors = FALSE)
    )
    Sys.sleep(0.22)
  }
  cache_nomes <- cache_nomes %>% arrange(InChIKey)
  write.csv(cache_nomes, CACHE_FILE, row.names = FALSE)
  cat(sprintf("[✓] Cache de nomes atualizado em: %s\n", CACHE_FILE))
}

# Tratar estereoisômeros com o mesmo nome (adiciona o 2º bloco do InChIKey se houver duplicata)
mapa_rotulos <- tibble(InChIKey = top_inchikeys) %>%
  left_join(cache_nomes, by = "InChIKey") %>%
  mutate(
    Nome = ifelse(is.na(Nome) | !nzchar(Nome), substr(InChIKey, 1, 14), Nome),
    Bloco1 = substr(InChIKey, 1, 14),
    Bloco2 = sapply(strsplit(InChIKey, "-"), function(x) if (length(x) >= 2) substr(x[2], 1, 6) else "")
  ) %>%
  group_by(Bloco1) %>%
  mutate(
    nome_trivial_curto = {
      curtos <- Nome[nchar(Nome) <= 30 & Fonte != "InChIKey_Fallback"]
      if (length(curtos) > 0) curtos[1] else NA_character_
    },
    Nome = ifelse(!is.na(nome_trivial_curto) & nchar(Nome) > 30, nome_trivial_curto, Nome)
  ) %>%
  ungroup() %>%
  mutate(
    Nome_Curto = ifelse(nchar(Nome) > 38, paste0(substr(Nome, 1, 35), "..."), Nome)
  ) %>%
  group_by(Nome_Curto) %>%
  mutate(
    Composto = if (n() > 1) paste0(Nome_Curto, " (", Bloco2, ")") else Nome_Curto
  ) %>%
  ungroup()

# Construir e salvar a matriz larga (idêntica ao formato results_insomnia.csv)
dados_filtrados <- todos_resultados %>%
  filter(InChIKey %in% top_inchikeys) %>%
  inner_join(mapa_rotulos %>% select(InChIKey, Composto), by = "InChIKey")

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
    plot.margin = margin(10, 20, 15, 55),
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
