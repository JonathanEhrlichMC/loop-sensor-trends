# toolbox #####
library(sf)
library(data.table)
library(tidyverse)
################

# CTUS ----
# ...shapefile ####
# library(DBI)
# db <- DBI::dbConnect(odbc::odbc(), "GISLibrary")
# metro_area_shp <- DBI::dbGetQuery(db,"SELECT
#                         *,
#                         SHAPE.STAsText() as geometry
#                         FROM GISLibrary.DBO.MetropolitanPlanningOrganizationArea;") %>%
#   st_as_sf(wkt = "geometry", crs = "+init=epsg:26915") %>%
#   st_transform(crs = "+init=epsg:26915 +proj=longlat +datum=WGS84")
# ctu_sf <- DBI::dbGetQuery(db,"SELECT
#                         *,
#                         SHAPE.STAsText() as geometry
#                         FROM GISLibrary.DBO.ThriveMSP2040CommunityDesignation;") %>%
#   st_as_sf(wkt = "geometry", crs = "+init=epsg:26915") %>%
#   st_transform(crs = "+init=epsg:26915 +proj=longlat +datum=WGS84")
# st_write(ctu_sf, 'thrive2040shapefile', driver = 'ESRI Shapefile')

ctu_sf <- st_read("thrive2040shapefile/thrive2040shapefile.shp")
ctu_sf <- st_transform(ctu_sf, crs = 4326)



# SENSOR DATA ----
# ....data table ####
sensor_dt <- fread("data/Configuration of Metro Detectors 2020-03-24.csv")
node_dt <- unique(sensor_dt[, .(r_node_name, r_node_n_type, r_node_lon, r_node_lat, r_node_station_id, corridor_route, corridor_dir)])


# ...shapefile ####
node_sf <- st_as_sf(node_dt, coords = c("r_node_lon", "r_node_lat"), crs = 4326)
# leaflet(node_sf)%>%
#   addCircleMarkers(label = node_sf$r_node_name)%>%
#   addProviderTiles('CartoDB.Positron')

# st_write(node_sf, 'node', driver = 'ESRI Shapefile')


# PREDICTED & ACTUAL VOLUME, BY NODE ----
# ....DATA TABLE ####
diffs_dt <- fread("output/pred-and-act-vol-by-node-2020-03-26.csv") # our golden ticket!
diffs_dt[, date := as.IDate(date)]
diffs_dt <- diffs_dt[date > "2020-03-01", ]
diffs_dt[, scl_volume := scale(volume.predict, center = F)]

# ....SHAPEFILE ####
diffs_sf <- st_as_sf(diffs_dt, coords = c("r_node_lon", "r_node_lat"), crs = 4326)
# st_write(diffs_sf, 'volumes-by-node', driver = 'ESRI Shapefile')


# VOLUMES, BY CTU ----
ctu_diffs_join <- st_join(diffs_sf, ctu_sf, join = st_within) # this takes TIME, especially with a lot of data.

# Aggregate predicted & actual volumes by CTU ####
ctu_diffs_join <- ctu_diffs_join %>%
  group_by(CTU_NAME, date, year, dow, doy, woy, weekday, monthday) %>%
  summarise(
    avg.diff = mean(volume.diff),
    total.vol = sum(volume.sum),
    pred.vol = sum(volume.predict),
    num.nodes = uniqueN(r_node_name)
  )

ctu_diffs_sf <- st_join(ctu_sf, ctu_diffs_join, on = "CTU_NAME")
ctu_diffs_sf <- ctu_diffs_sf %>% filter(!is.na(date))
rm(ctu_diffs_join)

st_write(ctu_diffs_sf, "volumes-by-CTU", driver = "ESRI Shapefile")

ctu_diffs_dt <- data.table(ctu_diffs_sf)
ctu_diffs_dt$geometry <- NULL


# CTU LABELS ----
ctu_labels <- sprintf(
  "<strong>%s</strong>
      <br>Expected Volume: %s vehicles
      <br>Actual Volume: %s vehicles
      <br>Difference from Expected:<strong> %s %%</strong>",
  ctu_diffs_dt[, CTU_NAME.x],
  ctu_diffs_dt[, round(pred.vol)],
  ctu_diffs_dt[, round(total.vol)],
  ctu_diffs_dt[, round(avg.diff, 1)]
) %>%
  lapply(htmltools::HTML)

# NODE LABELS ----
node_labels <- sprintf(
  "<strong>%s %s</strong>
  <br>Node ID: %s
      <br>Expected Volume: %s vehicles
      <br>Actual Volume: %s vehicles
      <br>Difference from Expected:<strong> %s %%</strong>",
  diffs_dt[, corridor_route],
  diffs_dt[, corridor_dir],
  diffs_dt[, r_node_name],
  diffs_dt[, round(volume.predict)],
  diffs_dt[, volume.sum],
  diffs_dt[, round(volume.diff, 1)]
) %>%
  lapply(htmltools::HTML)


# rm(diffs_sf)
# rm(ctu_diffs_sf)
# rm(ctu_sf)
# rm(sensor_dt)
# rm(node_sf)

load("councilcolors.Rdata")
##########################


hh_total <- 1213980 # https://metrocouncil.org/Data-and-Maps/Publications-And-Resources/Files-and-reports/2018-Population-Estimates-(FINAL,-July-2019)-(1).aspx

rm(ctu_diffs_dt)
rm(diffs_dt)
diffs_4plot <- fread(paste0("output/pred-and-act-vol-for-plotting-wide", Sys.Date(), ".csv"))
diffs_4plot[, date := as.IDate(date)]
diffs_4plot_long <- fread(paste0("output/pred-and-act-vol-for-plotting-long", Sys.Date(), ".csv"))
diffs_4plot_long[, date := as.IDate(date)]

# save.image(file = 'traffic-trends-app/appdata.RData')

#########################
# MNDOT Traffic Trends
yesterday <- Sys.Date() - 1
yesterday <- as.IDate(yesterday)
yesterday <- paste0(month(yesterday), "-", mday(yesterday), "-", year(yesterday))

data <- fread(paste0("http://www.dot.state.mn.us/traffic/data/reports/COVD19/Daily_Volume_Change_", yesterday, "_update.csv"))
data <- data[District %in% c("MnDOT Statewide")]
data <- melt(data, id.vars = c("District"), variable.name = "date", value.name = "Difference from Typical VMT (%)")
data[, date := as.IDate(date, format = "%m/%d/%Y")]

write.csv(data, paste0("output/diff-vol-state-", Sys.Date(), ".csv"), row.names = F)
#############################
