# Rscript
library(dplyr)
library(lubridate)
args=commandArgs(trailingOnly=T)
wind=args[1]
stanice=args[2]
TRAMONE_folder=args[3]

wind=read.table(wind,sep="",quote="",skip=0,dec=",",header=T, fill=T)
wind=wind[2:nrow(wind),]
wind[,7]=gsub(",","\\.",wind[,7])
colnames(wind)[colnames(wind)=="DPRUM"]="D"
colnames(wind)[colnames(wind)=="FPRUM"]="F"
wind[,c(2:4,6,7)]=as.numeric(unlist(wind[,c(2:4,6,7)]))
wind=wind[which(!(wind$F==0&wind$D==0)),]
wind$HOUR=as.numeric(substr(wind$TIME,1,2))
wind$MINUTE=as.numeric(substr(wind$TIME,4,5))
wind$date=ISOdate(wind$YEAR,wind$MONTH,wind$DAY,wind$HOUR,wind$MINUTE,tz="CET")
#impoted CLIDATA are in CET => conversion to UTC
wind$date=with_tz(wind$date,tzone="UTC")

#filter only last from duplicite rows for each station
wind=wind %>% group_by(EG_GH_ID) %>% slice_tail(n=1) %>% ungroup()

maxdate=max(wind$date)
wind=wind %>% filter(date>maxdate-minutes(15))

#wind_time=max(wind$date)

wind$u_wind=-wind$F*sin((wind$D+180)*pi/180)
wind$v_wind=-wind$F*cos((wind$D+180)*pi/180)

stanice=read.table(stanice,sep="",quote="",header=T, fill=T)
data=left_join(wind,stanice,by=c("EG_GH_ID"="Gh_id"))
data$Elevation=round(data$Elevation)
data=data[,c("EG_GH_ID","D","F","u_wind","v_wind","east","north","Elevation","date")]
#write.table(as.numeric(wind_time),paste0(TRAMONE_folder,"/wind_time.csv"),sep=",",col.names=F,row.names=F,quote=F)

#regresion wind speed ~ height ASL
data$ws_ASL_slope=0
data$ws_ASL_intercept=0
data$ws_ASL_R2=0
for (row in 1:nrow(data)) {
  distance = sqrt((data$east - data$east[row])^2 + (data$north - data$north[row])^2)
  data_within_distance = data[distance <= 35000, ]
  if (nrow(data_within_distance) > 1) 
  {
    reg_model <- lm(data_within_distance$F~data_within_distance$Elevation)
	data$ws_ASL_slope[row] = coef(reg_model)["data_within_distance$Elevation"]
	data$ws_ASL_intercept[row] = coef(reg_model)["(Intercept)"]
    data$ws_ASL_R2[row] = summary(reg_model)$r.squared
    if (!dir.exists(paste0(TRAMONE_folder,"/reg_ws"))) {
		dir.create(paste0(TRAMONE_folder,"/reg_ws"))
	}
	png(paste0(TRAMONE_folder,"/reg_ws/graph_elev_ws_",row,".png"))
		plot(data_within_distance$Elevation,data_within_distance$F, main=data[row,1], xlab="Height ASL [m]",ylab="ws [m/s]")
		abline(lm(data_within_distance$F~data_within_distance$Elevation), col = "red", lwd = 1)
		mtext(paste0("slope=",round(data$ws_ASL_slope[row],3)),side=3,line=1.75,adj=0.95)
		mtext(paste0("R^2=",round(data$ws_ASL_R2[row],2)),side=3,line=0.5,adj=0.95)
	dev.off()  
  }
}
#data[data$ws_ASL_slope<0,c("ws_ASL_slope","ws_ASL_intercept","ws_ASL_R2")]=0
#data$ws_ASL_R2[data$ws_ASL_R2<0]=0
write.csv(data,paste0(TRAMONE_folder,"/wind.csv"),na="",row.names=F,quote=F)
