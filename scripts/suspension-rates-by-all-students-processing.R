library(dplyr)
library(datapkg)

##################################################################
#
# Processing Script for Suspension-Rates-by-All-Students
# Created by Jenna Daly
# On 04/24/17
#
##################################################################

#Setup environment
sub_folders <- list.files()
data_location <- grep("All-Students", sub_folders, value=T)
path_to_top_level <- (paste0(getwd(), "/", data_location))
path_to_raw_data <- (paste0(getwd(), "/", data_location, "/", "raw"))
all_csvs <- dir(path_to_raw_data, recursive=T, pattern = ".csv") 
all_state_csvs <- dir(path_to_raw_data, recursive=T, pattern = "ct.csv") 
all_dist_csvs <- all_csvs[!all_csvs %in% all_state_csvs]

#District level data
susp_rates_dist <- data.frame(stringsAsFactors = F)
susp_rates_dist_noTrend <- grep("trend", all_dist_csvs, value=T, invert=T)
for (i in 1:length(susp_rates_dist_noTrend)) {
  current_file <- read.csv(paste0(path_to_raw_data, "/", susp_rates_dist_noTrend[i]), stringsAsFactors=F, header=F )
  #set column names to first row
  colnames(current_file) = current_file[1,]
  #remove first row
  current_file <- current_file[-c(1),]
  current_file <- current_file[, !(names(current_file) == "District Code")]
  get_year <- as.numeric(substr(unique(unlist(gsub("[^0-9]", "", unlist(susp_rates_dist_noTrend[i])), "")), 1, 4))
  get_year <- paste0(get_year, "-", get_year + 1) 
  current_file$Year <- get_year
  susp_rates_dist <- rbind(susp_rates_dist, current_file)
}

#State level data
susp_rates_state <- data.frame(stringsAsFactors = F)
susp_rates_state_noTrend <- grep("trend", all_state_csvs, value=T, invert=T)
for (i in 1:length(susp_rates_state_noTrend)) {
  current_file <- read.csv(paste0(path_to_raw_data, "/", susp_rates_state_noTrend[i]), stringsAsFactors=F, header=F )
  #set column names to first row
  colnames(current_file) = current_file[1,]
  #remove first row
  current_file <- current_file[-c(1),]
  current_file <- current_file[, !(names(current_file) == "Organization Code")]
  current_file$District <- "Connecticut"
  get_year <- as.numeric(substr(unique(unlist(gsub("[^0-9]", "", unlist(susp_rates_state_noTrend[i])), "")), 1, 4))
  get_year <- paste0(get_year, "-", get_year + 1) 
  current_file$Year <- get_year
  susp_rates_state <- rbind(susp_rates_state, current_file)
}

#Combine district and state
susp_rates <- rbind(susp_rates_state, susp_rates_dist)

#backfill Districts
district_dp_URL <- 'https://raw.githubusercontent.com/CT-Data-Collaborative/ct-school-district-list/master/datapackage.json'
district_dp <- datapkg_read(path = district_dp_URL)
districts <- (district_dp$data[[1]])

susp_rates_fips <- merge(susp_rates, districts, by.x = "District", by.y = "District", all=T)

susp_rates_fips$District <- NULL

susp_rates_fips<-susp_rates_fips[!duplicated(susp_rates_fips), ]

#backfill year
years <- c("2009-2010",
           "2010-2011",
           "2011-2012",
           "2012-2013",
           "2013-2014",
           "2014-2015",
           "2015-2016", 
           "2016-2017")

backfill_years <- expand.grid(
  `FixedDistrict` = unique(districts$`FixedDistrict`),
  `Year` = years 
)

backfill_years$FixedDistrict <- as.character(backfill_years$FixedDistrict)
backfill_years$Year <- as.character(backfill_years$Year)

backfill_years <- arrange(backfill_years, FixedDistrict)

complete_susp_rates <- merge(susp_rates_fips, backfill_years, all=T)

#remove duplicated Year rows
complete_susp_rates <- complete_susp_rates[!with(complete_susp_rates, is.na(complete_susp_rates$Year)),]

#return blank in FIPS if not reported
complete_susp_rates$FIPS <- as.character(complete_susp_rates$FIPS)
complete_susp_rates[["FIPS"]][is.na(complete_susp_rates[["FIPS"]])] <- ""

#recode missing data with -6666
complete_susp_rates[is.na(complete_susp_rates)] <- -6666
complete_susp_rates[complete_susp_rates == "N/A"]<- -6666

#recode suppressed data with -9999
complete_susp_rates[complete_susp_rates == "*"]<- -9999

#reshape from wide to long format
cols_to_stack <- c("%")

long_row_count = nrow(complete_susp_rates) * length(cols_to_stack)

complete_susp_rates_long <- reshape(complete_susp_rates,
                                    varying = cols_to_stack,
                                    v.names = "Value",
                                    timevar = "Variable",
                                    times = cols_to_stack,
                                    new.row.names = 1:long_row_count,
                                    direction = "long"
)

#Rename FixedDistrict to District
names(complete_susp_rates_long)[names(complete_susp_rates_long) == 'FixedDistrict'] <- 'District'


#reorder columns and remove ID column
complete_susp_rates_long <- complete_susp_rates_long[order(complete_susp_rates_long$District, complete_susp_rates_long$Year),]
complete_susp_rates_long$id <- NULL

#Add Measure Type
complete_susp_rates_long$`Measure Type` <- "Percent"

#Rename Variable columns
complete_susp_rates_long$`Variable` <- "Suspensions"

#Order columns
complete_susp_rates_long <- complete_susp_rates_long %>% 
  select(`District`, `FIPS`, `Year`, `Variable`, `Measure Type`, `Value`)

#Use this to find if there are any duplicate entires for a given district
# test <- complete_susp_rates_long[,c("District", "Year")]
# test2<-test[duplicated(test), ]

#Write CSV
write.table(
  complete_susp_rates_long,
  file.path(path_to_top_level, "data", "suspension_rates_all_students_2020.csv"),
  sep = ",",
  row.names = F
)

