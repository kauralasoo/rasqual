#' Save a list of matrices into a suitable format for RASQUAL
#'
#' Works with expression and covariates matrices.
#' 
#' @param data_list list of matrices
#' @param output_dir relative path to the output dir
#' @param file_suffix suffix added to each file after their name in the list.
#' @return None
#' @author Kaur Alasoo
#' @export 
saveRasqualMatrices <- function(data_list, output_dir, file_suffix = "expression"){
  #Save data for FastQTL to disk
  
  #Save each matrix as a separate  txt file
  for (sn in names(data_list)){
    file_path = file.path(output_dir, paste(sn,file_suffix, "txt", sep = "."))
    file_path_bin = file.path(output_dir, paste(sn,file_suffix, "bin", sep = "."))
    print(file_path)
    write.table(data_list[[sn]], file_path, quote = FALSE, row.names = TRUE, col.names = FALSE, sep = "\t")
    writeBin(as.double(c(t(data_list[[sn]]))), file_path_bin)
  }
}

#' Fetch particular genes from tabix indexed Rasqual output file.
#'
#' @param gene_ranges GRanges object with coordinates of the cis regions around genes.
#' @param tabix_file Tabix-indexed Rasqual output file.
#'
#' @return List of data frames containing Rasqual results for each gene.
#' @export
tabixFetchGenes <- function(gene_ranges, tabix_file){
  #Set column names for rasqual
  rasqual_columns = c("gene_id", "snp_id", "chr", "pos", "allele_freq", "HWE", "IA", "chisq", 
                      "effect_size", "delta", "phi", "overdisp", "n_feature_snps", "n_cis_snps", "converged")
  
  result = list()
  for (i in seq_along(gene_ranges)){
    selected_gene_id = gene_ranges[i]$gene_id
    print(i)
    tabix_table = scanTabixDataFrame(tabix_file, gene_ranges[i], col_names = rasqual_columns)[[1]] %>%
      dplyr::filter(gene_id == selected_gene_id)
    
    #Add additional columns
    tabix_table = postprocessRasqualResults(tabix_table)
    result[[selected_gene_id]] = tabix_table
  }
  return(result)
}

#' Fetch particular SNPs from tabix indexed Rasqual output file.
#'
#' @param snp_ranges GRanges object with SNP coordinates.
#' @param tabix_file Tabix-indexed Rasqual output file.
#'
#' @return Data frame that contains all tested rasqual p-values fir each SNP.
#' @export
tabixFetchSNPs <- function(snp_ranges, tabix_file){
  #Set column names for rasqual
  rasqual_columns = c("gene_id", "snp_id", "chr", "pos", "allele_freq", "HWE", "IA", "chisq", 
                      "effect_size", "delta", "phi", "overdisp", "n_feature_snps", "n_cis_snps", "converged")
  
  tabix_table = scanTabixDataFrame(tabix_file, snp_ranges, col_names = rasqual_columns)
  tabix_df = plyr::ldply(tabix_table, .id = NULL) %>%
    postprocessRasqualResults() %>%
    dplyr::tbl_df()
  return(tabix_df)
}

#' Helper function for tabixFetchGenes and tabixFetchSNPs
postprocessRasqualResults <- function(rasqual_df){
  result = dplyr::mutate(rasqual_df, p_nominal = pchisq(chisq, df = 1, lower = FALSE)) %>% #Add nominal p-value
    dplyr::mutate(MAF = pmin(allele_freq, 1-allele_freq)) %>% #Add MAF
    dplyr::mutate(beta = -log(effect_size/(1-effect_size),2)) #Calculate beta from rasqual pi
  return(result)
}


#' Construct GRanges object for tabixFetchGenes to fetch cis regions around each gene.
#'
#' @param selected_genes data frame containing at least gene_id column.
#' @param gene_metadata data frame with gene metadata (required columns: gene_id, chr, start, end)
#' @param cis_window Size fo the cis-window around the gene
#'
#' @return GRanges object with cooridnates of cis regions around genes.
#' @export
constructGeneRanges <- function(selected_genes, gene_metadata, cis_window){
  
  #Check that gene_metadata has required columns
  assertthat::assert_that(assertthat::has_name(gene_metadata, "gene_id"))
  assertthat::assert_that(assertthat::has_name(gene_metadata, "chr"))
  assertthat::assert_that(assertthat::has_name(gene_metadata, "start"))
  assertthat::assert_that(assertthat::has_name(gene_metadata, "end"))
  
  #Assert other parameters
  assertthat::assert_that(assertthat::has_name(gene_metadata, "gene_id"))
  assertthat::assert_that(assertthat::is.number(cis_window))
  
  filtered_metadata = dplyr::semi_join(gene_metadata, selected_genes, by = "gene_id")
  print(filtered_metadata)
  granges = dplyr::mutate(filtered_metadata, range_start = pmax(0, start - cis_window), range_end = end + cis_window) %>%
    dplyr::select(gene_id, chr, range_start, range_end) %>%
    dplyr::transmute(gene_id, seqnames = chr, start = range_start, end = range_end, strand = "*") %>% 
    dataFrameToGRanges()
  return(granges)
}

#' A general function to quickly import tabix indexed tab-separated files into data_frame
#'
#' @param tabix_file Path to tabix-indexed text file
#' @param param A instance of GRanges, RangedData, or RangesList 
#' provide the sequence names and regions to be parsed. Passed onto Rsamtools::scanTabix()
#' @param ... Additional parameters to be passed on to readr::read_delim()
#'
#' @return List of data_frames, one for each entry in the param GRanges object.
#' @export
scanTabixDataFrame <- function(tabix_file, param, ...){
  tabix_list = Rsamtools::scanTabix(tabix_file, param = param)
  df_list = lapply(tabix_list, function(x,...){
    if(length(x) > 0){
      if(length(x) == 1){
        #Hack to make sure that it also works for data frames with only one row
        #Adds an empty row and then removes it
        result = paste(paste(x, collapse = "\n"),"\n",sep = "")
        result = readr::read_delim(result, delim = "\t", ...)[1,]
      }else{
        result = paste(x, collapse = "\n")
        result = readr::read_delim(result, delim = "\t", ...)
      }
    } else{
      #Return NULL if the nothing is returned from tabix file
      result = NULL
    }
    return(result)
  }, ...)
  return(df_list)
}
