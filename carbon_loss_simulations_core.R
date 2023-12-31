# 1a. Set parameters for numerical projects with exponential C loss distribution ----
if(type == "expo") {
  year_pres_obs = 2021 #actually no observed data; all are simulated
  t0 = 2023
  lambda_p = 1
  lambda_c = 1 / scale_c
  
  absloss_p_samp = rexp(1000, lambda_p)
  absloss_c_samp = rexp(1000, lambda_c)
  
  #input that we need for the following steps: expost_p/c_loss, loss_postproj, aomega
  expost_p_loss = absloss_p_samp
  expost_c_loss = absloss_c_samp
  
  #post-project release rate:
  #double the counterfactual deforestation rate, which has now changed compared to before the project starts
  #always use theoretical
  loss_postproj = rate_postproj / lambda_c
  
  add_samp = rexp(1000, lambda_c) - rexp(1000, lambda_p)
  aomega = ifelse(use_theo,
                  1 / lambda_p * log(omega * (lambda_p + lambda_c) / lambda_c),
                  quantile(add_samp, omega))
  
  # 1b. Load data and set parameters for portfolios of real-life projects ----
} else if(type == "expo_portfolio") {
  year_pres_obs = 2021 #actually no observed data; all are simulated
  t0 = 2023
  
  scale_c_vec = switch(expo_portfolio_type,
                 "A" = c(1.5, 1.5, 1.5, 10),
                 "B" = c(1.5, 1.5, 10, 10),
                 "C" = c(1.5, 10, 10, 10))
  lambda_p_vec = rep(1, length(scale_c_vec))
  lambda_c_vec = 1 / scale_c_vec
  
  absloss_p_samp_list = lapply(lambda_p_vec, function(x) rexp(1000, x))
  absloss_c_samp_list = lapply(lambda_c_vec, function(x) rexp(1000, x))
  
  #input that we need for the following steps: expost_p/c_loss, loss_postproj, add_samp, aomega
  expost_p_loss = apply(as.data.frame(absloss_p_samp_list), 1, sum)
  expost_c_loss = apply(as.data.frame(absloss_c_samp_list), 1, sum)
  
  #post-project release rate:
  #double the counterfactual deforestation rate, which has now changed compared to before the project starts
  #always use theoretical
  loss_postproj = sum(rate_postproj / lambda_c_vec)
  
  #a-omega: use sampling approach because no analytical a-omega exists yet for portfolio
  add_samp = mapply(function(x, y) x - y,
                    x = absloss_c_samp_list, y = absloss_p_samp_list) %>%
    apply(1, sum)
  aomega = quantile(add_samp, omega)
  
} else if(type == "portfolio") {
  year_pres_obs = 2021
  
  sites = switch(portfolio_type,
                 "all" = c("Gola_country", "WLT_VNCC_KNT", "CIF_Alto_Mayo", "VCS_1396", "VCS_934"),
                 "good" = c("Gola_country", "CIF_Alto_Mayo", "VCS_1396"),
                 "four" = c("Gola_country", "CIF_Alto_Mayo", "VCS_1396", "VCS_934"))
  
  summ_flux = vector("list", length(sites))
  absloss_p_init_list = vector("list", length(sites))
  absloss_c_init_list = vector("list", length(sites))
  t0_vec = rep(NA, length(sites))
  
  for(s in sites){
    i = which(sites %in% s)
    load(file = paste0(file_path, s, ".Rdata")) #load data
    t0_vec[i] = t0
    
    flux_series_sim = mapply(function(x, y) makeFlux(project_series = x, leakage_series = y)$flux,
                             x = agb_series_project_sim,
                             y = vector("list", length = length(agb_series_project_sim)),
                             SIMPLIFY = F)
    
    summ_flux[[i]] = rbind(summariseSeries(flux_series_sim, "treatment_proj"),
                           summariseSeries(flux_series_sim, "control_proj"))
    
    absloss_p_init_list[[i]] = summ_flux[[i]] %>%
      subset(var == "treatment_proj" & year >= t0 & series != "mean") %>%
      mutate(val = val * (-1), var = NULL, series = NULL)
    absloss_c_init_list[[i]] = summ_flux[[i]] %>%
      subset(var == "control_proj" & year >= t0 & series != "mean") %>%
      mutate(val = val * (-1), var = NULL, series = NULL)
  }
  
  site = "portfolio"
  t0 = min(t0_vec)
  
  absloss_p_init_comb = mapply(function(x, y) {
    x = x %>%
      mutate(site = y)
  }, x = absloss_p_init_list, y = sites, SIMPLIFY = F) %>%
    do.call(rbind, .)
  absloss_c_init_comb = mapply(function(x, y) {
    x = x %>%
      mutate(site = y)
  }, x = absloss_c_init_list, y = sites, SIMPLIFY = F) %>%
    do.call(rbind, .)
  
  absloss_p_init_yearsum = absloss_p_init_comb %>%
    group_by(year, site) %>%
    summarise(val = mean(val)) %>%
    ungroup(site) %>%
    summarise(val = sum(val)) %>%
    ungroup()
  absloss_c_init_yearsum = absloss_c_init_comb %>%
    group_by(year, site) %>%
    summarise(val = mean(val)) %>%
    ungroup(site) %>%
    summarise(val = sum(val)) %>%
    ungroup()
  
  absloss_p_fit_list = lapply(absloss_p_init_list, function(x) FitGMM(x$val))
  absloss_p_samp_list = lapply(absloss_p_fit_list, function(x) SampGMM(x, n = 1000))
  
  absloss_c_fit_list = lapply(absloss_p_init_list, function(x) FitGMM(x$val))
  absloss_c_samp_list = lapply(absloss_c_fit_list, function(x) SampGMM(x, n = 1000))
  
  #input that we need for the following steps: expost_p/c_loss, loss_postproj, aomega
  expost_p_loss = absloss_p_init_yearsum$val
  expost_c_loss = absloss_c_init_yearsum$val
  
  #post-project release rate:
  #double the mean of counterfactual carbon loss distribution
  loss_postproj = absloss_c_fit_list %>%
    sapply(function(x) SampGMM(x, n = 1000)) %>%
    apply(1, sum) %>%
    mean() * rate_postproj
  
  add_samp = mapply(function(x, y) x - y,
                    x = absloss_c_samp_list,
                    y = absloss_p_samp_list) %>%
    as.data.frame() %>%
    apply(1, function(x) sum(x, na.rm = T))
  aomega = quantile(add_samp, omega)
  
  # 1c. Load data and set parameters for individual projects ----
} else if(type == "project") {
  load(file = paste0(file_path, project_site, ".Rdata"))
  
  flux_series_sim = mapply(function(x, y) makeFlux(project_series = x, leakage_series = y)$flux,
                           x = agb_series_project_sim,
                           y = vector("list", length = length(agb_series_project_sim)),
                           SIMPLIFY = F)
  
  summ_flux = rbind(summariseSeries(flux_series_sim, "treatment_proj"),
                    summariseSeries(flux_series_sim, "control_proj"))
  year_pres_obs = max(summ_flux$year)
  
  absloss_p_init = summ_flux %>%
    subset(var == "treatment_proj" & year >= t0 & series != "mean") %>%
    mutate(val = val * (-1), var = NULL, series = NULL)
  absloss_c_init = summ_flux %>%
    subset(var == "control_proj" & year >= t0 & series != "mean") %>%
    mutate(val = val * (-1), var = NULL, series = NULL)
  
  absloss_p_init_comb = absloss_p_init %>%
    group_by(year) %>%
    summarise(val = mean(val)) %>%
    ungroup()
  
  absloss_c_init_comb = absloss_c_init %>%
    group_by(year) %>%
    summarise(val = mean(val)) %>%
    ungroup()
  
  absloss_p_fit = FitGMM(absloss_p_init$val)
  absloss_c_fit = FitGMM(absloss_c_init$val)
  
  #input that we need for the following steps: expost_p/c_loss, loss_postproj, aomega
  expost_p_loss = absloss_p_init_comb$val
  expost_c_loss = absloss_c_init_comb$val
  
  #post-project release rate:
  #double the mean of counterfactual carbon loss distribution
  loss_postproj = mean(SampGMM(absloss_c_fit, n = 1000)) * rate_postproj
  
  add_samp = SampGMM(absloss_c_fit, n = 1000) - SampGMM(absloss_p_fit, n = 1000)
  aomega = quantile(add_samp, omega)
}


# 2. Perform simulations ----
H_rel = year_max - t0 + 1

sim_p_loss = matrix(0, H, n_rep)
sim_c_loss = matrix(0, H, n_rep)
sim_additionality = matrix(0, H, n_rep)
sim_credit = matrix(0, H, n_rep)
sim_benefit = matrix(0, H, n_rep)
sim_aomega = matrix(0, H, n_rep)
sim_release = matrix(0, H_rel, n_rep)
sim_damage = matrix(0, H, n_rep)
sim_ep = matrix(0, H, n_rep)
sim_credibility = matrix(1, H, n_rep)
sim_buffer = matrix(0, H, n_rep)
sim_r_sched = vector("list", n_rep)

a = Sys.time()
for(j in 1:n_rep){
  r_sched = matrix(0, H, H_rel) #release schedule
  buffer_pool = 0
  #cat("Buffer at start: ", buffer_pool, "\n")
  for(i in 1:H){
    year_i = t0 + i - 1
    
    #get carbon loss values: use ex post values in years where they are available
    if(year_i <= year_pres_obs) {
      sim_p_loss[i, j] = expost_p_loss[i]
      sim_c_loss[i, j] = expost_c_loss[i]
      
      #calculate a-omega based on carbon loss distributions
      if(type == "expo") {
        samp_additionality = rexp(1000, lambda_c) - rexp(1000, lambda_p)
      } else if(type == "expo_portfolio") {
        samp_additionality = mapply(function(x, y) rexp(1000, x) - rexp(1000, y),
                                    x = lambda_c_vec, y = lambda_p_vec) %>%
          apply(1, sum)
      } else if(type == "portfolio") {
        absloss_p_fit_list = lapply(absloss_p_init_list, function(x) {
          FitGMM(subset(x, year <= year_i & year >= t0)$val)})
        absloss_p_samp_list = lapply(absloss_p_fit_list, function(x) SampGMM(x, n = 1000))
        
        absloss_c_fit_list = lapply(absloss_c_init_list, function(x) {
          FitGMM(subset(x, year <= year_i & year >= t0)$val)})
        absloss_c_samp_list = lapply(absloss_c_fit_list, function(x) SampGMM(x, n = 1000))
        
        samp_additionality = mapply(function(x, y) x - y,
                                    x = absloss_c_samp_list,
                                    y = absloss_p_samp_list) %>%
          as.data.frame() %>%
          apply(1, function(x) sum(x, na.rm = T))
      } else if(type == "project") {
        absloss_p_fit = FitGMM(subset(absloss_p_init, year <= year_i)$val)
        absloss_c_fit = FitGMM(subset(absloss_c_init, year <= year_i)$val)
        samp_additionality = SampGMM(absloss_c_fit, n = 1000) - SampGMM(absloss_p_fit, n = 1000)
      }
      aomega = quantile(samp_additionality, omega)
      #if(j < 5) cat(year_i, aomega, "\n")
      
      #get carbon loss values: sample from fitted distributions when ex post values not available
    } else {
      if(type == "expo") {
        sim_p_loss[i, j] = rexp(1, lambda_p)
        sim_c_loss[i, j] = rexp(1, lambda_c)
      } else if(type == "expo_portfolio") {
        sim_p_loss[i, j] = sum(sapply(lambda_p_vec, function(x) rexp(1, x)))
        sim_c_loss[i, j] = sum(sapply(lambda_c_vec, function(x) rexp(1, x)))
      } else if(type == "portfolio") {
        sim_p_loss[i, j] = sum(sapply(absloss_p_fit_list, function(x) SampGMM(x, n = 1)))
        sim_c_loss[i, j] = sum(sapply(absloss_c_fit_list, function(x) SampGMM(x, n = 1)))
      } else if(type == "project") {
        sim_p_loss[i, j] = SampGMM(absloss_p_fit, n = 1)
        sim_c_loss[i, j] = SampGMM(absloss_c_fit, n = 1)
      }
    }
    sim_additionality[i, j] = sim_c_loss[i, j] - sim_p_loss[i, j]
    sim_aomega[i, j] = aomega
    
    if(i <= bp) {
      #first five years: no credits/releases; positive additionality added to buffer pool
      if(sim_additionality[i, j] > 0) buffer_pool = buffer_pool + sim_additionality[i, j]
      sim_credit[i, j] = 0
      #cat("Buffer at year", i, ": ", buffer_pool, "\n")
    } else {
      #from sixth year on: get credits and anticipated releases
      
      #use buffer pool to fill anticipated releases first
      #only deduct from buffer pool at each year if there is space left for that year
      if(buffer_pool > 0) {
        max_release = ifelse(aomega > 0, 0, -aomega) #if a-omega is positive, maximum release is zero
        can_be_released = min(max(0, max_release - sim_release[i, j]), buffer_pool)
        #if(j < 5) cat("at year", i, ", can be released from buffer =", max_release, "-", sim_release[i, j], "=", can_be_released, "\n")
        sim_release[i, j] = sim_release[i, j] + can_be_released
        buffer_pool = buffer_pool - can_be_released
        #if(j < 5) cat("total release now =", sim_release[i, j], ", left in buffer =", buffer_pool, "\n")
      }
      
      sim_credit[i, j] = sim_additionality[i, j] + sim_release[i, j]
      if(sim_credit[i, j] > 0){
        to_be_released = sim_credit[i, j]
        #cat("credits at year ", i, ": ", to_be_released, "\n")
        sim_benefit[i, j] = sim_credit[i, j] * filter(scc_extrap, year == year_i)$central
        k = i #kth year(s), for which we estimate anticipated release
        while(to_be_released > 0 & k < H_rel){
          k = k + 1
          if(k > H) {
            max_release = loss_postproj #post-project release rate
          } else {
            max_release = ifelse(aomega > 0, 0, -aomega) #if a-omega is positive, maximum release is zero
          }
          #cat("at year", k, ", can be released =", max_release, "-", sim_release[k, j], "=", can_be_released, "\n")
          
          can_be_released = max(0, max_release - sim_release[k, j])
          r_sched[i, k] = min(to_be_released, can_be_released)
          to_be_released = to_be_released - r_sched[i, k]
          sim_release[k, j] = sim_release[k, j] + r_sched[i, k]
          #cat("actually released =", r_sched[i, k], ", total release now =", sim_release[k, j], ", left to release =", to_be_released, "\n")
        }
        sim_damage[i, j] = sum(r_sched[i, (i + 1):H_rel] * filter(scc_extrap, year %in% (year_i + 1):year_max)$central / ((1 + D) ^ (1:(year_max - year_i))))
        sim_ep[i, j] = (sim_benefit[i, j] - sim_damage[i, j]) / sim_benefit[i, j]
        #cat("Credit =", sim_credit[i, j], ", Benefit =", sim_benefit[i, j], ", Damage =", sim_damage[i, j], ", eP =", sim_ep[i, j], "\n")
      } else if(sim_credit[i, j] <= 0){
        sim_ep[i, j] = 0
        sim_credibility[i, j] = 0
      }
    }
    sim_buffer[i, j] = buffer_pool
  }
  sim_r_sched[[j]] = r_sched
}
b = Sys.time()
b - a


# 3. Summarise results ----

SummariseSim = function(mat){
  df = mat %>%
    as.data.frame() %>%
    reframe(
      year = row_number(),
      p05 = apply(., 1, function(x) quantile(x, 0.05, na.rm = T)),
      p25 = apply(., 1, function(x) quantile(x, 0.25, na.rm = T)),
      median = apply(., 1, median, na.rm = T),
      p75 = apply(., 1, function(x) quantile(x, 0.75, na.rm = T)),
      p95 = apply(., 1, function(x) quantile(x, 0.95, na.rm = T)),
      mean = apply(., 1, mean, na.rm = T),
      sd = apply(., 1, function(x) sd(x, na.rm = T)),
      ci_margin = qt(0.975, df = n_rep - 1) * sd / sqrt(n_rep),
      ci_low = mean - ci_margin,
      ci_high = mean + ci_margin
    )
  return(df)
}

#view evolution of a particular iteration
if(view_snapshot) {
  j = 1
  snapshot = data.frame(additionality = sim_additionality[1:50, j],
                        aomega = sim_aomega[1:50, j],
                        release = sim_release[1:50, j],
                        credit = sim_credit[1:50, j],
                        rsched = apply(sim_r_sched[[j]], 1, sum),
                        buffer = sim_buffer[1:50, j])
  View(snapshot)
}

sim_credit_long = sim_credit %>%
  as.data.frame() %>%
  mutate(t = row_number()) %>%
  pivot_longer(V1:V100, names_to = "rep", values_to = "val")

sim_release_long = sim_release %>%
  as.data.frame() %>%
  mutate(t = row_number()) %>%
  pivot_longer(V1:V100, names_to = "rep", values_to = "val")

summ_additionality = SummariseSim(sim_additionality)
summ_credit = SummariseSim(sim_credit)
summ_release = SummariseSim(sim_release[1:H, ])
summ_buffer = SummariseSim(sim_buffer)
summ_aomega = SummariseSim(sim_aomega)

summ_ep = sim_ep %>%
  replace(., . == 0, NA) %>%
  SummariseSim() %>%
  replace(., . == Inf| . == -Inf, NA)

summ_cred = sim_ep %>%
  as.data.frame() %>%
  reframe(
    year = row_number(),
    cred = apply(., 1, function(x) length(which(x > 0)) / n_rep))
summ_cred$cred[1:bp] = NA


#4. Set file prefixes and save results ----

if(type == "expo") {
  expo_text = ifelse(exists("scale_c"), gsub("\\.", "_", as.character(scale_c)), "")  
  if(bp_sensitivity) {
    subfolder = "bp_sensitivity/"
    file_pref = paste0(subfolder, "expo_", expo_text, "_bp_", bp)
    save(scale_c, bp,
         file_pref, t0, scc_extrap,
         sim_credit_long, sim_release_long,
         summ_credit, summ_release, summ_ep, summ_cred, file = paste0(file_path, file_pref, "_simulations.Rdata"))
    
  } else if(ppr_sensitivity) {
    subfolder = "ppr_sensitivity/"
    file_pref = paste0(subfolder, "expo_", expo_text, "_ppr_", gsub("\\.", "_", as.character(rate_postproj)))
    save(scale_c, rate_postproj,
         file_pref, t0, scc_extrap,
         sim_credit_long, sim_release_long,
         summ_credit, summ_release, summ_ep, summ_cred, file = paste0(file_path, file_pref, "_simulations.Rdata"))
    
  } else {
    subfolder = ifelse(use_theo,
                       "theoretical_figures_analytical_aomega/",
                       "theoretical_figures_sampled_aomega/")
    file_pref = paste0(subfolder, "expo_", expo_text, ifelse(use_theo, "_theo", ""))
    save(scale_c,
         file_pref, t0, scc_extrap,
         sim_credit_long, sim_release_long,
         summ_credit, summ_release, summ_ep, summ_cred, file = paste0(file_path, file_pref, "_simulations.Rdata"))
  }
} else if(type == project){
  subfolder = "projects/"
  file_pref = paste0(subfolder, switch(project_site,
                                       "Gola_country" = "Gola",
                                       "WLT_VNCC_KNT" = "KNT",
                                       "CIF_Alto_Mayo" = "Alto_Mayo",
                                       "VCS_1396" = "RPA",
                                       "VCS_934" = "Mai_Ndombe"))
  save(project_site, summ_flux,
       file_pref, t0, scc_extrap,
       sim_credit_long, sim_release_long,
       summ_credit, summ_release, summ_ep, summ_cred, file = paste0(file_path, file_pref, "_simulations.Rdata"))
  
} else if(type == "portfolio") {
  subfolder = ""
  file_pref = paste0("portfolio_", portfolio_type)
  save(portfolio_type, sites, summ_flux,
       file_pref, t0, scc_extrap,
       sim_credit_long, sim_release_long,
       summ_credit, summ_release, summ_ep, summ_cred, file = paste0(file_path, file_pref, "_simulations.Rdata"))
  
} else if(type == "expo_portfolio") {
  subfolder = ""
  file_pref = paste0("expo_portfolio_", expo_portfolio_type)
  save(expo_portfolio_type, scale_c_vec,
       file_pref, t0, scc_extrap,
       sim_credit_long, sim_release_long,
       summ_credit, summ_release, summ_ep, summ_cred, file = paste0(file_path, file_pref, "_simulations.Rdata"))
}