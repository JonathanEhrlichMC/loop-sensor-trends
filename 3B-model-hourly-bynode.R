##############
library(data.table)
library(foreach)
library(doParallel)
library(mgcv)
library(lubridate)
library(ggplot2)
library(gridExtra)
#############

hourlydat <- fread('data/data_hourly_bynode_clean.csv')

# Dealing with date ----
hourlydat[,date:=as.IDate(date)]
hourlydat[,dow:=wday(date)]
hourlydat[,doy:=yday(date)]
hourlydat[,year:=year(date)]
hourlydat[,woy:=week(date)]
hourlydat[,weekday:=factor(weekdays(date))]
hourlydat[,monthday:=format(date, "%b %d")]


# get rid of 2017 data: (december 15-31 included in this pull) ----
hourlydat <- hourlydat[year>2017,]

# get rid of december data: ----
hourlydat <- hourlydat[doy<100,]

dim(hourlydat) # 17254564       21


# ggplot(hourlydat, aes(x = volume.sum, fill = factor(year)))+
#   geom_density(alpha = 0.5)
# some very high numbers
hourlydat[volume.sum>num_sensors_this_year * 2000] # reasonable though


# must have 3 years of data, at least 60 days of data in each year ----
hourlydat[,'num_days_per_year':=uniqueN(date), by = .(r_node_name, year)]
hourlydat <- hourlydat[num_days_per_year>60]

has_2020_data <- unique(hourlydat$r_node_name[hourlydat$year == 2020])
has_2018_data <- unique(hourlydat$r_node_name[hourlydat$year == 2018])
has_2019_data <- unique(hourlydat$r_node_name[hourlydat$year == 2019])

hourlydat <- hourlydat[hourlydat$r_node_name %in% has_2020_data
                     & hourlydat$r_node_name %in% has_2019_data
                     & hourlydat$r_node_name %in% has_2018_data,]
dim(hourlydat) # 16231608       22

hourlydat_s <- split(hourlydat, hourlydat$r_node_name)

# length(hourlydat_s) # 1274
diffs_ls <- vector("list", length(hourlydat_s))
gam_list <- vector("list", length(hourlydat_s))


# MODEL TIME ----
for(s in seq_along(hourlydat_s)){
  # print(s)
  # flush.console()
  this_dat <- hourlydat_s[[s]]
  # subset to relevant dates: 
  modeling_dat <- this_dat[this_dat$date < '2020-03-01' 
                           & this_dat$doy <= 90 # feed it relevant dates - before april 1
                           & this_dat$doy >1,] # exclude the one major holiday in here - jan 1
  
  modeling_dat <- modeling_dat[!modeling_dat$date == '2020-01-17',] # cold snap - exclude
  modeling_dat <- modeling_dat[!modeling_dat$date == '2020-01-18',] # cold snap - exclude
  modeling_dat <- modeling_dat[!modeling_dat$date == '2020-02-09',] # snow day - exclude
  
  this_gam <- with(modeling_dat,
                   mgcv::gam(volume.sum ~ 
                               s(hour, by = as.factor(dow))
                             + s(dow, k = 7, by = as.factor(year)) # one knot for each day of the week
                             + s(doy, by = as.factor(year)) #general seasonal trend, let it vary by year, allow knots to be set by gam
                             + as.factor(year) # intercept for each year
                   ))
  
  gam_list[[s]] <- this_gam
  
  this_dat[,c('volume.predict', 'volume.predict.se'):=cbind(predict.gam(object = this_gam, newdata = this_dat, se.fit = T))]
  
  # difference from predicted, n volume:
  this_dat[,volume.diff.raw:=(volume.sum - volume.predict)]
  
  # difference from predicted, in %: 
  this_dat[,volume.diff := round( ( (volume.sum - volume.predict) / volume.predict) * 100, 1)]
  
  # store difference from normal for 2020 for mapping
  this_diff <- this_dat
  diffs_ls[[s]]<-this_diff
  
  # predicted_and_observed_plot<-
  #   ggplot(this_dat[doy>7*5], aes(x = hour, y = volume.sum, color = factor(woy)))+
  #   theme_minimal()+
  #   geom_ribbon(aes(ymin = volume.predict-volume.predict.se, ymax = volume.predict + volume.predict.se, fill = factor(woy)),
  #               alpha = 0.5, color = NA)+
  #   geom_point()+
  #   geom_line()+
  #   facet_wrap(year~dow, scales = "free_x", nrow = 3)
  # 
  # diff_from_normal_plot<-
  #   ggplot(this_dat[doy>7*5], aes(x = hour, y = volume.diff, color = factor(woy)))+
  #   theme_minimal()+
  #   geom_ribbon(aes(ymin = volume.predict-volume.predict.se, ymax = volume.predict + volume.predict.se, fill = factor(woy)),
  #               alpha = 0.5, color = NA)+
  #   geom_point()+
  #   geom_line()+
  #   facet_wrap(year~dow, scales = "free_x", nrow = 3)
  # 
  # grid.arrange(predicted_and_observed_plot, diff_from_normal_plot, nrow = 1)
}

diffs_dt <- rbindlist(diffs_ls)
saveRDS(gam_list, file = paste0('data/gam-models-hourly-', Sys.Date(), '.RData'))

# some very high numbers? 
# hist(diffs_dt[,volume.diff])
# summary(diffs_dt[,volume.diff])
unique(diffs_dt[volume.diff < (-100),.(r_node_name, r_node_n_type)])
# r_node_name r_node_n_type
# 1:    rnd_1576          Exit
# 2:    rnd_5932          Exit
# 3:    rnd_5948          Exit
# 4:    rnd_5950      Entrance
# 5:     rnd_841      Entrance
# 6:   rnd_85131          Exit
# 7:   rnd_85435      Entrance
# 8:   rnd_85649       Station
# 9:   rnd_85657       Station
# 10:   rnd_86223       Station
# 11:   rnd_86797      Entrance
# 12:   rnd_87263       Station
# 13:   rnd_87273       Station
# 14:   rnd_87565      Entrance
# 15:   rnd_87915      Entrance
# 16:   rnd_89115      Entrance
# 17:   rnd_89281          Exit
# 18:   rnd_89289      Entrance
# 19:   rnd_91110          Exit
# 20:   rnd_95341          Exit

unique(diffs_dt[volume.predict<0, .(r_node_name, r_node_n_type)])
# negative predicted values -- one spurious node 
# diffs_dt <- diffs_dt[!r_node_name == 'rnd_86223'] -- now many more
diffs_dt<-diffs_dt[!r_node_name %in% unique(diffs_dt[volume.predict<0, r_node_name])]

# other spurious observations (8 of them)
# diffs_dt<-diffs_dt[volume.diff < (100)]
# another problematic node:
# diffs_dt <- diffs_dt[!r_node_name %in% c('rnd_86469', 'rnd_95784')]

# very high values
summary(diffs_dt[volume.diff>100 & year == 2020,.(volume.predict, volume.diff)])
# how many of these?
unique(diffs_dt[volume.diff>500 & year == 2020, .(r_node_name, r_node_n_type, date)])
# r_node_name r_node_n_type       date
# 1:     rnd_849          Exit 2020-03-15
# 2:     rnd_849          Exit 2020-03-16
# 3:     rnd_849          Exit 2020-03-17
# 4:     rnd_849          Exit 2020-03-18
# 5:     rnd_849          Exit 2020-03-19
# 6:     rnd_849          Exit 2020-03-20
# 7:   rnd_86283      Entrance 2020-01-01
# 8:   rnd_86283      Entrance 2020-01-02
# 9:   rnd_88037      Entrance 2020-03-14
# 10:   rnd_88037      Entrance 2020-03-15
# 11:   rnd_88037      Entrance 2020-03-17
# 12:   rnd_88037      Entrance 2020-03-18
# 13:   rnd_89451      Entrance 2020-03-22

# get rid of thse as well
diffs_dt<-diffs_dt[!r_node_name %in% unique(diffs_dt[volume.diff>500 & year == 2020, r_node_name])]
diffs_dt[,date:=as.IDate(date)]
# Trim to after March 1 2020:
diffs_dt <- diffs_dt[date>='2020-03-01',]

fwrite(diffs_dt, paste0('output/hourly-pred-and-act-vol-by-node-', Sys.Date(), '.csv'))


# More data reshaping of model output ----


# Total difference from expected for whole metro area ----
diffs_4plot <- diffs_dt[r_node_n_type == "Station" & year == 2020 # this year's data, stations only. ####
                        ,lapply(.SD, FUN = function(x) sum(x, na.rm = T)),
                       .SDcols = c('volume.sum', 'volume.predict'), 
                       by = .(date, hour, dow, doy, year, woy, weekday, monthday)]

# vmt is 1/2 of volume ----
diffs_4plot[,c("vmt.sum", "vmt.predict"):=list(volume.sum*0.5, volume.predict * 0.5)]
diffs_4plot[,'Difference from Typical VMT (%)':=round(100*(vmt.sum-vmt.predict)/vmt.predict, 2)]
diffs_4plot[,difference_text:=ifelse(`Difference from Typical VMT (%)` <0, paste0(abs(round(`Difference from Typical VMT (%)`, 1)), " % less than typical"),
                                                 paste0(abs(round(`Difference from Typical VMT (%)`, 1)), " % more than typical"))]


fwrite(diffs_4plot, paste0('output/hourly-pred-and-act-vol-region-', Sys.Date(), '.csv'))

# # melt to long form for plotting predicted and acutals simultaneoulsy in plotly ----
# nahhhh this isn't useful really

# diffs_4plot_long <- melt(diffs_4plot[,.(vmt.sum, vmt.predict, date, dow, doy, year, woy, weekday, monthday, `Difference from Typical VMT (%)`)], 
#                         id.vars = c('date', 'dow', 'doy', 'year', 'woy', 'weekday', 'monthday', "Difference from Typical VMT (%)"),
#                         variable.name = "estimate_type", value.name = "VMT")
# diffs_4plot_long$estimate_type <- ifelse(diffs_4plot_long$estimate_type == "vmt.sum", "Actual Traffic", "Typical Traffic")
# 
# diffs_4plot_long[,difference_text:=ifelse(estimate_type == "Actual Traffic", 
#                                          ifelse(`Difference from Typical VMT (%)` <0, paste0(abs(`Difference from Typical VMT (%)`), " % less than typical"),
#                                                 paste0(abs(round(`Difference from Typical VMT (%)`, 1)), " % more than typical")),
#                                          ifelse(`Difference from Typical VMT (%)` <0, paste0(abs(`Difference from Typical VMT (%)`), " % more than actual"),
#                                                 paste0(abs(round(`Difference from Typical VMT (%)`, 1)), " % less than actual")))]
# fwrite(diffs_4plot_long, paste0('data/pred-and-act-vol-for-plotting-long-', Sys.Date(), '.csv'))
