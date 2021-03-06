# Author:    Lerato E. Magosi
# R version: 3.1.0 (2014-04-10)
# Platform:  x86_64-apple-darwin10.8.0 (64-bit)
# Date:      20Apr2017


# Goal: Copute M statistics to identify systematic (non-random multi-variant) heterogeneity
#       patterns in GWAS meta-analysis.


# Required libraries ---------------------------
# foreign            # needed to load stata datasets
# metafor            # needed to estimate standardized predicted random effects
# ggplot2            # needed to plot M statistics
# psych	             # needed for summary statistics
# gridExtra          # needed for pretty tables
# stargazer          # needed for exporting dataframes to latex
# stats              # needed for the following functions: qt, qnorm, pnorm, p.adjust
# utils              # needed for the following functions: str, head, tail
# grDevices          # needed for the following functions: dev.new, rainbow
# graphics           # needed for the hist function


# Calling globalVariables on the following variables to address 
# the note: "no visible binding for global variable" generated by "R CMD check"
utils::globalVariables(c("usta_mean", "study_names", "study", "yval", "usta_lb", "usta_ub", 
                         "xb", "tau2", "xbse", "rawresid", "uncondse", "oddsratio", "zustamean", 
                         "pval_ustamean", "bonf_pval_ustamean"))


# Function: compute_m_statistics ---------------------------
#
# goal: use standardized predicted random effects (obtained via metafor) to compute M statistics
#
# parameters: 
#
#
#   beta_in                   (numeric)   vector of effect-sizes, 
#   lambda_se_in              (numeric)   vector of standard errors genomically corrected at study-level, 
#   study_names_in            (character) vector of study names, 
#   variant_names_in          (character) vector of variant neames,
#   save_dir                  (character) scalar giving a path to the directory where plots should be stored,
#   tau2_method               (character) method to estimate heterogeneity: either "DL" or "REML",
#   x_axis_increment_in       (numeric)   value by which x-axis of M scatterplot will be incremented,
#   x_axis_round_in           (numeric)   value to which x-axis labels of M scatterplot will be rounded,
#   produce_plots             (boolean)   value to generate plots
#   verbose_output            (boolean)   value to produce detailed output
#
# returns: a list containing:
#
#
# 	M_expected_mean            (numeric), 
# 	M_expected_sd              (numeric),
# 	M_crit_alpha_0_05 (numeric), 
#   number_variants            (numeric),
#   number_studies             (numeric),           
# 	M_dataset                  (dataframe),
# 	influential_studies_0_05   (dataframe),
# 	weaker_studies_0_05        (dataframe)
#
# ------------------------------------------------------------------------------------


compute_m_statistics <- function(beta_in, lambda_se_in, variant_names_in, 
                                 study_names_in, save_dir = getwd(), tau2_method = "DL",
                                 x_axis_increment_in = 0.02, x_axis_round_in = 2,
                                 produce_plots = TRUE, verbose_output = FALSE) {

	# Assemble dataset

	beta <- base::as.numeric(beta_in)
	lambda_se <- base::as.numeric(lambda_se_in)
	study_names <- base::factor(study_names_in)
	variant_names <- base::factor(variant_names_in)

	m <- base::data.frame(beta, lambda_se, variant_names, study_names)

    # View dataset structure
    if (verbose_output) utils::str(m)

    # ---------------------------
    
    
    # Assign study numbers
	m$study <- m$study_names
	base::levels(m$study) <- base::seq_along(base::levels(m$study))

    # Calculate no. of studies
    nstudies <- base::nlevels(m$study_names)
    
    # Assign snp/variant numbers
    m$snp <- m$variant_names
    base::levels(m$snp) <- base::seq_along(base::levels(m$snp))

    # Calculate no. of variants
    nsnps <- base::nlevels(m$variant_names)

    # Set alpha at 5% level
	usta_alpha <- 0.05

    
    # Print numbers of studies and snps
	if (verbose_output) {

		base::writeLines("\n")
		base::print(base::paste("Summary: This heterogeneity analysis is based on ", nsnps, " SNPs and ", nstudies, " studies"))
		base::print("***************** end of part 1: assign snp and study numbers	 ****************")
		base::writeLines("")
		
		}


	# -----------------------------------


    # Define function to align study effects i.e. betas
    align_betas <- function(dframe_current_snp) {
    
        if (tau2_method == "DL") {

			metafor_res <- metafor::rma.uni(yi = dframe_current_snp[, "beta"], sei = dframe_current_snp[, "lambda_se"], weighted = TRUE, knha = TRUE, method = tau2_method)

			if (metafor_res$b[1] < 0) {
		
				if (verbose_output) { base::print(base::paste0("Aligning study effects in variant: ", base::unique(dframe_current_snp[, "variant_names"]))) }
		
				dframe_current_snp$beta <- -dframe_current_snp$beta
				
			}                        
        }
        
        else {

			metafor_res <- metafor::rma.uni(yi = dframe_current_snp[, "beta"], sei = dframe_current_snp[, "lambda_se"], weighted = TRUE, knha = TRUE, method = tau2_method, control=list(stepadj=0.5, maxiter=10000))

			if (metafor_res$b[1] < 0) {
		
				if (verbose_output) { base::print(base::paste0("Aligning study effects in variant: ", base::unique(dframe_current_snp[, "variant_names"]))) }
		
				dframe_current_snp$beta <- -dframe_current_snp$beta
				
			}        
        }
    

        dframe_current_snp
        
    }
 
 
    # Split dataset by snp to obtain mini-datasets for each snp, then align study effects i.e. betas 
    list_snp_minidatasets <- base::split(m, m$variant_names)
    align_betas_results <- base::lapply(list_snp_minidatasets, align_betas)

	# -----------------------------------
    
    
    
    # Define function to extract standardized shrunken residuals i.e. usta
    
    
    metafor_weighted_least_squares_rand_effects_regression <- function(dframe_current_snp) {
    
        # Run random effects meta-analysis (inverse variance weighted least sq regression) on current snp
        
        if (tau2_method == "DL") {

			metafor_results <- metafor::rma.uni(yi = dframe_current_snp[, "beta"], sei = dframe_current_snp[, "lambda_se"], weighted = TRUE, knha = TRUE, method = tau2_method)        
        } 
        else {
        
			metafor_results <- metafor::rma.uni(yi = dframe_current_snp[, "beta"], sei = dframe_current_snp[, "lambda_se"], weighted = TRUE, knha = TRUE, method = tau2_method, control=list(stepadj=0.5, maxiter=10000))        
        }
        
        
        # Compute predicted values for the metafor_results
        metafor_results_predict <- metafor::predict.rma(metafor_results, digits = 8)

		# Warning note: Although the prediction's including random effects were similar i.e. 
		# (Empirical Bayes estimates in metafor and xbu in Stata's metareg) the values of 
		# their corresponding standard errors were quite different.

        
        # Compute Best Linear Unbiased Predictions i.e. Blups for the metafor_results
        metafor_results_blup <- metafor::blup.rma.uni(metafor_results, digits = 8)
        
        # Compute outlier diagnostics
        metafor_results_influence <- metafor::influence.rma.uni(metafor_results)
        
        # Extract hat values i.e. leverage a.k.a diagonals of hat matrix
        metafor_results_influence_hat <- (metafor_results_influence$inf)$hat
 
        # Print metafor results
 		if (verbose_output) {
		
		    base::writeLines("")
            base::print(paste("Random effects meta-analysis for variant: ", base::unique(dframe_current_snp$variant_names)))
            base::writeLines("")
            base::print(paste("snp_no: ", base::unique(dframe_current_snp$snp)))
            base::writeLines("")

            base::print("metafor_results: ")
		    base::print(metafor_results)
		    base::writeLines("")
		    
		    }
       
        
        # Create a data.frame comprising results to return 
        output <- base::data.frame(
            dframe_current_snp,
            tau2 = metafor_results$tau2,           # estimate of between-study variance
            I2 = metafor_results$I2,               # Higgins inconsistency metric
            Q = metafor_results$QE,                # Q-statistic 
            xb = metafor_results_predict$pred,     # predicition excluding random effects
            xbse = metafor_results_predict$se,     # standard error of prediction excluding random effects
            xbu = metafor_results_blup$pred,       # predictions including random effects
            stdxbu = metafor_results_blup$se,      # corresponding std. error of Empirical Bayes estimates in metafor
            hat = metafor_results_influence_hat,   # leverage a.k.a diagonals of hat matrix
            row.names = base::with(dframe_current_snp, base::interaction(variant_names, study_names)))

        output
            
    }
    

 
    metafor_weighted_least_squares_rand_effects_regression_results <- base::lapply(align_betas_results, metafor_weighted_least_squares_rand_effects_regression)

    # View structure 
	if (verbose_output) {

		base::writeLines("\n")
		base::writeLines("Dataset structure for individual variants: ")
		base::writeLines("")
		utils::str(metafor_weighted_least_squares_rand_effects_regression_results)
		base::writeLines("")
		
		}
    
    # Append snp mini-datasets into a single file
    meta_analysis_results <- base::data.frame(base::do.call(rbind, metafor_weighted_least_squares_rand_effects_regression_results))


    # Compute raw residuals, unconditional standard error and ustas (a.k.a spres: standardized predicted random effects)
    # notes: R. M. Harbord and J. P. T. Higgins, pg. 517 sbe23, Stata journal
	# Reference: Meta-regression in Stata, The Stata Journal (2008) 8, Number 4, pp. 493 to 519

    meta_analysis_results_incl_spres <- meta_analysis_results
    
    meta_analysis_results_incl_spres$rawresid <- base::with(meta_analysis_results_incl_spres, beta - xb)
    meta_analysis_results_incl_spres$uncondse <- base::with(meta_analysis_results_incl_spres, base::sqrt(lambda_se**2 + tau2 - xbse**2))
    meta_analysis_results_incl_spres$usta <- base::with(meta_analysis_results_incl_spres, rawresid / uncondse)

		

    # View structure 
	if (verbose_output) {

		base::writeLines("\n")

		base::writeLines("Dataset structure for whole dataset: ")
		base::writeLines("")
	
		utils::str(meta_analysis_results_incl_spres)
		base::writeLines("")

		
		}
    
    
	# -----------------------------------
	


    # Define function to compute M-statistics for each study by taking the mean of their ustas
    compute_ustamean <- function(dframe_current_study) {
    
        # Extract mean, sd and number of observations for usta variable in current study
        usta_describe <- psych::describe(dframe_current_study$usta)
        
		umean <- usta_describe$mean
		umean_se <- usta_describe$se
		usd <- usta_describe$sd
		uobs <- usta_describe$n

		# Determine lower and upper bound of Bonferroni corrected usta mean confidence interval for current study
		usta_df <- uobs - 1
		usta_tcrit_95 <- stats::qt(1 - ((usta_alpha / 2) / nstudies), usta_df)
		ulb <- umean - (usta_tcrit_95 * usd / base::sqrt(uobs))
		uub <- umean + (usta_tcrit_95 * usd / base::sqrt(uobs))

		# Top up allocates missing snps the average mean and sd 
		#topup <- (nsnps - uobs) * (1 / uobs) * 0
		umean_topup <- (nsnps - uobs) * ((1 / uobs) * 0)
		

		
		# Create a data.frame comprising results to return
        output_compute_ustamean <- base::data.frame(dframe_current_study,
                                                    usta_mean = umean + umean_topup,      # M-statistics
                                                    usta_mean_se = umean_se,              # M-statistic standard errors   
                                                    usta_sd = usd,                        # M-statistic standard deviations
                                                    usta_lb = ulb,                        # M-statistic lower bound
                                                    usta_ub = uub,                        # M-statistic upper bound
			                                        row.names = base::with(dframe_current_study, base::interaction(variant_names, study_names)))  # label row names with study and variant names


		if (verbose_output) {
		
		    base::print(paste0("study_name: ", base::unique(dframe_current_study$study_names), 
		    "; Mstatistic(usta_mean): ", base::unique(output_compute_ustamean$usta_mean), 
		    "; Mstatistic std.error(usta_mean_se): ", base::unique(output_compute_ustamean$usta_mean_se), 
		    "; CI: ", base::unique(output_compute_ustamean$usta_lb), " ", base::unique(output_compute_ustamean$usta_ub)))
		    base::writeLines("\n")
		    base::print("Summary statistics of the usta variable")
		    base::writeLines("\n")
		    base::print(usta_describe, digits = 8)		
		    base::writeLines("\n")
		    
		    }
			                                 			                                                         
        
        output_compute_ustamean



    }
    
    
    # Split dataset by study to obtain mini-datasets for each study, then compute M-statistics 
    list_study_minidatasets <- base::split(meta_analysis_results_incl_spres, meta_analysis_results_incl_spres$study_names)
    compute_ustamean_results <- base::lapply(list_study_minidatasets, compute_ustamean)


	# View structure 
	if (verbose_output) {

		base::writeLines("\n")

		base::writeLines("Dataset structure for individual studies: ")
		base::writeLines("")
	
		utils::str(compute_ustamean_results)
		
		}

    # Append snp mini-datasets into a single file
    mstatistic_results <- base::data.frame(base::do.call(rbind, compute_ustamean_results))


	if (verbose_output) {
		
		base::writeLines("Dataset structure after computing M-statistics i.e. ustamean: ")
		base::writeLines("")
			   
		utils::str(mstatistic_results)
		
		}
    
	# -----------------------------------


	# Calculating the expected mean and sd for the M-statistic

	# The expected mean under the Ho:
	# If have 50 variants, Mmu = 50 * (1 / 50) * 0
	Mmu <- nsnps * (1 / nsnps) * 0

	# The expected spread under the Ho:
	# If have 50 variants, Msd = ((50 * (1 / 50)^2) * 1)^0.5
	Msd <- ((nsnps * (1 / nsnps)^2) * 1)^0.5

    base::writeLines("")
	if (verbose_output) base::print(base::paste("expected mean for M statistic = ", Mmu, "; SD = ", Msd, "; Snps = ", nsnps))
    
	# -----------------------------------



    # Compute average variant effect-size
    
    compute_avg_variant_effectsize <- function(dframe_mstatistic_results) {
    
		# Sort aggregated ustas (i.e. ustamean) to determine rank
		dframe_mstatistic_results_srtdby_usta_mean <- dframe_mstatistic_results[base::order(dframe_mstatistic_results[, "usta_mean"]), ]

		# Rank studies by usta_mean
		dframe_mstatistic_results_srtdby_usta_mean$rank <- base::factor(dframe_mstatistic_results_srtdby_usta_mean[, "usta_mean"])
		base::levels(dframe_mstatistic_results_srtdby_usta_mean$rank) <- base::seq_along(base::levels(dframe_mstatistic_results_srtdby_usta_mean$rank))


        # Extract beta values to compute average variant effect-size    
		list_betas_splitby_study_names <- base::split(dframe_mstatistic_results_srtdby_usta_mean[, "beta"], dframe_mstatistic_results_srtdby_usta_mean[, "study_names"])
		list_describe_betas <- base::lapply(list_betas_splitby_study_names, psych::describe)


		if (verbose_output) {
		    base::writeLines("")
			base::print(" Summary statistics for effect-sizes (betas) in each study")
			base::print(list_describe_betas)
		}


        
        # Compute average variant effect-size and number of variants in each study        
        populate_study_mean_beta_vec <- function(current_study_betas) {
  
            current_study_mean_beta <- current_study_betas$mean   
        
        }

        study_mean_beta <- base::unlist(base::lapply(list_describe_betas, populate_study_mean_beta_vec))
 
 
        
        populate_study_n_beta_vec <- function(current_study_betas) {
  
            current_study_n_beta <- current_study_betas$n   
        
        }
        
        study_n_beta <- base::unlist(base::lapply(list_describe_betas, populate_study_n_beta_vec))

        # Note: list_describe_betas is sorted by study_names hence need to 
        #       re-sort dframe_mstatistic_results_srtdby_usta_mean before assembling the output
        #       data.frame
        
        dframe_mstatistic_srtd_by_study_names <- dframe_mstatistic_results_srtdby_usta_mean[base::order(dframe_mstatistic_results_srtdby_usta_mean[, "study_names"]), ]

		output_compute_avg_variant_effectsize <- base::data.frame(
			study_names = base::unique(dframe_mstatistic_srtd_by_study_names$study_names),
			usta_mean = base::unique(dframe_mstatistic_srtd_by_study_names$usta_mean),        # M-statistics
			usta_mean_se = base::unique(dframe_mstatistic_srtd_by_study_names$usta_mean_se),  # M-statistic standard errors
			study_mean_beta,                                                                  # average variant effect-sizes
			oddsratio = base::exp(study_mean_beta),                                           # average variant effect-sizes expressed as oddsratios               
			study_n_beta,                                                                     # number of loci in each study
			study = base::unique(dframe_mstatistic_srtd_by_study_names$study),                # study numbers
			rank = base::unique(dframe_mstatistic_srtd_by_study_names$rank),                  # study ranks determined by size of M-statistics
			row.names = NULL)


        output_compute_avg_variant_effectsize <- output_compute_avg_variant_effectsize[base::order(output_compute_avg_variant_effectsize[, "study_names"]), ]
	
		output_compute_avg_variant_effectsize


    }
    
    
    compute_avg_variant_effectsize_results <- compute_avg_variant_effectsize(mstatistic_results)    
    
	# -----------------------------------

     
    
    
    # Generate plots

	# Histogram of M statistics
	if (produce_plots) {
		filename_histogram_mstats <- base::paste0("Histogram_Mstatistics_", nstudies, "studies_", nsnps, "snps.tif")
		grDevices::tiff(file.path(save_dir, filename_histogram_mstats), width = 17.35, height = 23.35, units = "cm", res = 300, compression = "lzw", pointsize = 14)
		usta_mean_hist <- base::unique(mstatistic_results[, c("study_names", "usta_mean")])
		graphics::hist(usta_mean_hist[, "usta_mean"], main="Histogram of M statistics", xlab="M statistics")
		grDevices::dev.off()
	}
	
	# ** * **
	
	
	# Plot M statistic(ustamean) against average variant effect size



	# Subset compute_avg_variant_effectsize_results into strong and weak studies
	compute_avg_variant_effectsize_results_srtby_usta_mean <- compute_avg_variant_effectsize_results[base::order(compute_avg_variant_effectsize_results[, "usta_mean"]), ]
	
	usta_mean_scatter_strong <- base::subset(compute_avg_variant_effectsize_results_srtby_usta_mean, compute_avg_variant_effectsize_results_srtby_usta_mean$usta_mean >= 0)
	usta_mean_scatter_strong$strength <- base::rep("strong", base::nrow(usta_mean_scatter_strong))

	usta_mean_scatter_weak <- base::subset(compute_avg_variant_effectsize_results_srtby_usta_mean, compute_avg_variant_effectsize_results_srtby_usta_mean$usta_mean < 0)
    usta_mean_scatter_weak$strength <- base::rep("weak", base::nrow(usta_mean_scatter_weak))
    
    # Now that we have succesfully added the strength column, we shall
	# combine the usta_mean_scatter_strong and usta_mean_scatter_weak subsets

	usta_mean_scatter_strength <- base::rbind(usta_mean_scatter_weak, usta_mean_scatter_strong)
	

	# Calculating expected i.e. theoretical Mstatistic threshold
	mstat_threshold_zscore <- base::abs(stats::qnorm((usta_alpha / nstudies) / 2))
	mstat_threshold_zscore

	mstat_threshold <- mstat_threshold_zscore * base::sqrt((1 / nsnps^2) * nsnps) + ((1 / nsnps) * 0) 
	mstat_threshold


	if (verbose_output) { 
	
	    base::writeLines("\n")
	    base::print("Table of Mstatistics highlighting strong (M >= 0) and weak (M < 0) studies: ")
	    base::writeLines("\n")
	    base::print(usta_mean_scatter_strength)
	    base::writeLines("\n")
	    base::print(base::paste0("Mstatistic threshold: ", mstat_threshold))
	    
	    
	    }


     # Set ustamean threshold     
     dat_hlines <- data.frame(strength = base::levels(base::as.factor(usta_mean_scatter_strength$strength)), yval = c(-mstat_threshold, mstat_threshold))

	# Plotting - with study numbers
	x_axis_min <- base::min(base::log(usta_mean_scatter_strength$oddsratio))
	x_axis_max <- base::max(base::log(usta_mean_scatter_strength$oddsratio))

	if (produce_plots) {	
		filename_mstats_vs_avg_effectsize <- base::paste0("Mstatistics_vs_average_variant_effectsize_", nstudies, "studies_", nsnps, "snps.tif")
		grDevices::tiff(file.path(save_dir, filename_mstats_vs_avg_effectsize), width = 23.35, height = 17.35, units = "cm", res = 300, compression = "lzw", pointsize = 14)
		h <- ggplot2::ggplot(usta_mean_scatter_strength, ggplot2::aes(base::log(oddsratio), usta_mean, colour = usta_mean, label = study_names)) + ggplot2::geom_point(size = 4.5) + ggplot2::geom_text(ggplot2::aes(label = study), hjust = 1.2, vjust = -0.5, size = 2.5, colour = "azure4") + ggplot2::scale_colour_gradientn(name = "M statistic", colours = grDevices::rainbow(11)) + ggplot2::scale_x_continuous(trans="log", limits=c(x_axis_min, x_axis_max), breaks=base::round(base::seq(x_axis_min, x_axis_max, x_axis_increment_in),x_axis_round_in), minor_breaks=ggplot2::waiver(), labels = base::round(base::exp(base::seq(x_axis_min, x_axis_max, x_axis_increment_in)),x_axis_round_in)) + ggplot2::theme_bw() + ggplot2::scale_fill_hue(c = 45, l = 40) + ggplot2::xlab("Average effect size (oddsratio)") + ggplot2::ylab("M statistic") + ggplot2::theme(panel.grid.minor = ggplot2::element_blank(), panel.grid.major = ggplot2::element_blank()) + ggplot2::theme(axis.title.x = ggplot2::element_text(size = 14), axis.text.x = ggplot2::element_text(size = 14)) + ggplot2::theme(axis.title.y = ggplot2::element_text(size = 14), axis.text.y = ggplot2::element_text(size = 14))
		hi <- h + ggplot2::geom_hline(ggplot2::aes(yintercept = yval), data = dat_hlines, colour = "grey80", linetype = "dashed", lwd = 0.4) + ggplot2::theme(legend.text = ggplot2::element_text(size = 10)) + ggplot2::theme(legend.title = ggplot2::element_text(size = 12)) + ggplot2::theme(legend.position = "bottom")
		base::print(hi + ggplot2::geom_hline(ggplot2::aes(yintercept = c(0,0)), data = dat_hlines, colour = "grey80", linetype = "solid", lwd = 0.4))
		grDevices::dev.off()
    }
    	
	# -----------------------------------
	     
    
    
   # Generate tables

    # Compute 2-sided Bonferroni correction of M statistic p-values
  
	# Using 2sided pval
    usta_mean_scatter_strength$zustamean <- base::with(usta_mean_scatter_strength, (usta_mean - Mmu) / Msd)
    usta_mean_scatter_strength$pval_ustamean <- base::with(usta_mean_scatter_strength, 2 * (stats::pnorm(-base::abs(zustamean))))
    usta_mean_scatter_strength$bonf_pval_ustamean <- base::with(usta_mean_scatter_strength, pval_ustamean * nstudies)
    usta_mean_scatter_strength$bonf_pval_ustamean[usta_mean_scatter_strength$bonf_pval_ustamean > 1] <- 1
    usta_mean_scatter_strength$qval_ustamean <- base::with(usta_mean_scatter_strength, stats::p.adjust(bonf_pval_ustamean, method = "fdr"))
    

    # Diagnose influential studies and underperforming studies 
    usta_mean_influential_studies <- base::subset(usta_mean_scatter_strength, usta_mean_scatter_strength$usta_mean >= mstat_threshold)   

    usta_mean_influential_studies <- usta_mean_influential_studies[, c("study_names", "usta_mean", "bonf_pval_ustamean")]
    base::names(usta_mean_influential_studies) <- c("Study", "M", "Bonferroni_pvalue")

	if (produce_plots) {
    
		if (base::nrow(usta_mean_influential_studies) >= 1) {
			title_influential_studies <- "Table: M and Bonferroni p-values \nof systematically stronger studies \nat the 5% significant level."

			filename_influential_studies <- base::paste0("table_influential_studies.tif")
			grDevices::tiff(file.path(save_dir, filename_influential_studies), width = 17.35, height = 23.35, units = "cm", res = 300, compression = "lzw", pointsize = 14)
			table_influential_studies <- draw_table(body = usta_mean_influential_studies, heading = title_influential_studies)
			grDevices::dev.off()
	
		} else {
			base::writeLines("")
			base::print("Table not generated as there were no influential \nstudies found at alpha = 0.05")
	
		}
    }


	# Latex output
	base::writeLines("")
	if (base::nrow(usta_mean_influential_studies) >= 1) {
	    stargazer::stargazer(usta_mean_influential_studies, summary = FALSE, rownames = FALSE, title = "M statistics and Bonferroni p-values showing systematically stronger studies at the 5 percent significant level.", style = "aer")
    } else {
        base::writeLines("")
        base::print("Latex table not generated as there were no influential studies found at alpha = 0.05")
    
    }

	# ---- ** ----
    
    
    usta_mean_underperforming_studies <- base::subset(usta_mean_scatter_strength, usta_mean_scatter_strength$usta_mean <= -mstat_threshold)

    usta_mean_underperforming_studies <- usta_mean_underperforming_studies[, c("study_names", "usta_mean", "bonf_pval_ustamean")]
    base::names(usta_mean_underperforming_studies) <- c("Study", "M", "Bonferroni_pvalue")
 
 	if (produce_plots) {
   
		if (base::nrow(usta_mean_underperforming_studies) >= 1) {    
			title_underperforming_studies <- "Table: M and Bonferroni p-values \nof systematically weaker studies \nat the 5% significant level"

			filename_underperforming_studies <- base::paste0("table_underperforming_studies.tif")
			grDevices::tiff(file.path(save_dir, filename_underperforming_studies), width = 17.35, height = 23.35, units = "cm", res = 300, compression = "lzw", pointsize = 14)
			table_underperforming_studies <- draw_table(body = usta_mean_underperforming_studies, heading = title_underperforming_studies)
			grDevices::dev.off()
		
		} else {
			base::writeLines("")
			base::print("Table not generated as there were no \nunder-performing studies found at alpha = 0.05")
	
		}
    }

	# Latex output
	base::writeLines("")
	if (base::nrow(usta_mean_underperforming_studies) >= 1) { 
	    stargazer::stargazer(usta_mean_underperforming_studies, summary = FALSE, rownames = FALSE, title = "M statistics and Bonferroni p-values showing systematically weaker studies at the 5 percent significant level.", style = "aer")
    } else {
        base::print("Latex table not generated as there were no under-performing studies found at alpha = 0.05")
    
    }


	# -----------------------------------


       
		
    # Merge usta_mean_scatter_strength with mstatistic_results to generate Mdataset

    # Since usta_mean, ustamean_se and study already appear in mstatistic_results, we shall exclude them from the merge
    # get indices corresponding to usta_mean, ustamean_se and study  
    idx_ustamean <- base::which(base::names(usta_mean_scatter_strength) == "usta_mean")
    idx_usta_mean_se <- base::which(base::names(usta_mean_scatter_strength) == "usta_mean_se")
    idx_study <- base::which(base::names(usta_mean_scatter_strength) == "study")
    
    mstatistic_results_incl_usta_mean_scatter_strength <- base::merge(mstatistic_results, usta_mean_scatter_strength[, -c(idx_ustamean, idx_usta_mean_se, idx_study)], by = "study_names")
    
    mstatistic_dataset <- mstatistic_results_incl_usta_mean_scatter_strength[, c("study_names", "beta", "lambda_se", "variant_names", "usta_mean", "usta_sd", "usta_mean_se", 
                                                           "usta_lb", "usta_ub", "bonf_pval_ustamean", "qval_ustamean", "tau2", "I2", "Q", "xb", "usta", 
                                                           "xbu", "stdxbu", "hat", "study", "snp", "study_mean_beta", "oddsratio", "study_n_beta")]
    
    names(mstatistic_dataset) <- c("study_names_in", "beta_in", "lambda_se_in", "variant_names_in", "M", "M_sd", "M_se", "lowerbound", "upperbound", "bonfpvalue", "qvalue", "tau2", "I2", "Q", "xb", "usta", 
                                                           "xbu", "stdxbu", "hat", "study", "snp", "beta_mean", "oddsratio", "beta_n")
    # View structure 
    base::writeLines("Structure for dataset of computed M statistics: ")
    base::writeLines("")
    
    utils::str(mstatistic_dataset)
    base::writeLines("")

	# -----------------------------------
	

	# List of items to return
	list(M_expected_mean = Mmu, 
	M_expected_sd = Msd,
	M_crit_alpha_0_05 = mstat_threshold,
	number_variants = nsnps,
	number_studies = nstudies, 
	M_dataset = mstatistic_dataset,
	influential_studies_0_05 = usta_mean_influential_studies,
	weaker_studies_0_05 = usta_mean_underperforming_studies)
	    

}


