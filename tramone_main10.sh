#!/bin/bash
TRAMONE_folder="/home/pi/TRAMONE"
grassdb="grassdata"
loc_jtsk="cr-jtsk"
loc_wgs84="cr-wgs84"
mapset="TRAMONE"
cekej_sec=0
max_traj_time=86400
repre_range=1500

mapmaker() {
	region="reg1"
	sleep 0.1
	png_name="tramone.png"
	~/TRAMONE/map_maker.sh ${TRAMONE_folder} ${grassdb} ${loc_jtsk} ${mapset} ${region} ${png_name}
	region="reg2"
	sleep 0.1
	png_name="tramone2.png"
	~/TRAMONE/map_maker.sh ${TRAMONE_folder} ${grassdb} ${loc_jtsk} ${mapset} ${region}	${png_name}
}



pinctrl set 4 op
pinctrl set 4 dl

export GRASS_OVERWRITE=1

sudo timedatectl set-timezone UTC

if [ ! -d "${TRAMONE_folder}" ]; then
	echo "FATAL!!! TRAMONE folder not found. Rebooting OS."
	sudo reboot
fi


if [ -f "${TRAMONE_folder}/${grassdb}/${loc_jtsk}/${mapset}/.gislock" ]; then
	rm /home/pi/TRAMONE/grassdata/cr-jtsk/TRAMONE/.gislock
fi


if [ ! -f "${TRAMONE_folder}/${grassdb}/${loc_jtsk}/${mapset}/sqlite/TRAMONE.db" ]; then
	grass --text ${TRAMONE_folder}/${grassdb}/${loc_jtsk}/${mapset} --exec db.createdb database=${TRAMONE_folder}/${grassdb}/${loc_jtsk}/${mapset}/sqlite/TRAMONE.db driver=sqlite
fi
grass --text ${TRAMONE_folder}/${grassdb}/${loc_jtsk}/${mapset} --exec db.connect database=${TRAMONE_folder}/${grassdb}/${loc_jtsk}/${mapset}/sqlite/TRAMONE.db driver=sqlite

grass --text ${TRAMONE_folder}/${grassdb}/${loc_wgs84}/${mapset} --exec v.in.ascii input=${TRAMONE_folder}/Geography_2024_Radim.csv output=meteo_sites sep="," x=4 y=5 columns="Gh_id varchar(10),Name varchar(60),Station_type varchar(10),Geogr1 double,Geogr2 double,Elevation double" skip=1
grass --text ${TRAMONE_folder}/${grassdb}/${loc_jtsk}/${mapset} --exec v.proj location=${loc_wgs84} mapset=${mapset} input=meteo_sites out=meteo_sites 
grass --text ${TRAMONE_folder}/${grassdb}/${loc_jtsk}/${mapset} --exec v.out.ascii -c meteo_sites out=${TRAMONE_folder}/meteo_sites.txt columns="Gh_id,Elevation" separator=" "

grass --text ${TRAMONE_folder}/${grassdb}/${loc_wgs84}/${mapset} --exec v.in.ascii input=${TRAMONE_folder}/sampling_sites.txt out=sampling_sites x=2 y=3 sep="," columns="site varchar(3),x double,y double" skip=1
grass --text ${TRAMONE_folder}/${grassdb}/${loc_jtsk}/${mapset} --exec v.proj location=${loc_wgs84} mapset=${mapset} input=sampling_sites out=sampling_sites 
sampling_sites=`grass --text ${TRAMONE_folder}/${grassdb}/${loc_jtsk}/${mapset} --exec v.db.select sampling_sites column=site|tail -n +2|sort|uniq`
pary_lokalit=`echo $sampling_sites | tr ' ' '\n' | cut -c1 | sort -u`
echo "Pairs: "${pary_lokalit}

#projection to JTSK for main loop
grass --text ${TRAMONE_folder}/${grassdb}/${loc_jtsk}/${mapset} --exec v.to.db sampling_sites option=coor columns=x,y
grass --text ${TRAMONE_folder}/${grassdb}/${loc_jtsk}/${mapset} --exec v.db.select sampling_sites columns="site,x,y" sep="," | tail -n +2 > ${TRAMONE_folder}/sampling_sites_jtsk.txt

grass --text ${TRAMONE_folder}/${grassdb}/${loc_jtsk}/${mapset} --exec v.buffer input=sampling_sites output=sampling_sites_buf distance=${repre_range}
grass --text ${TRAMONE_folder}/${grassdb}/${loc_jtsk}/${mapset}  --exec g.region vect=sampling_sites_buf res=100 -a
grass --text ${TRAMONE_folder}/${grassdb}/${loc_jtsk}/${mapset}  --exec v.in.region region
grass --text ${TRAMONE_folder}/${grassdb}/${loc_jtsk}/${mapset}  --exec r.mapcalc expression="u_wind=0"
grass --text ${TRAMONE_folder}/${grassdb}/${loc_jtsk}/${mapset} --exec r.mapcalc expression="v_wind=0"

for pair in $pary_lokalit
do
	grass --text ${TRAMONE_folder}/${grassdb}/${loc_jtsk}/${mapset} --exec v.extract sampling_sites out=site_${pair}A where="site='${pair}A'" 
	grass --text ${TRAMONE_folder}/${grassdb}/${loc_jtsk}/${mapset} --exec v.extract sampling_sites out=site_${pair}B where="site='${pair}B'" 
	grass --text ${TRAMONE_folder}/${grassdb}/${loc_jtsk}/${mapset} --exec v.buffer site_${pair}A out=site_${pair}A_buf distance=${repre_range}
	grass --text ${TRAMONE_folder}/${grassdb}/${loc_jtsk}/${mapset} --exec v.buffer site_${pair}B out=site_${pair}B_buf distance=${repre_range}
done

if [ ! -d "${TRAMONE_folder}/shp" ]; then
	mkdir ${TRAMONE_folder}/shp
fi
if [ ! -d "${TRAMONE_folder}/img" ]; then
	mkdir ${TRAMONE_folder}/img
fi
if [ ! -d "${TRAMONE_folder}/wind" ]; then
	mkdir ${TRAMONE_folder}/wind
fi
if [ ! -f "${TRAMONE_folder}/time_prev_hour.txt" ]; then
	time_prev_hour=`TZ=UTC date +"%Y%m%d%H"`
	echo $time_prev_hour > ${TRAMONE_folder}/time_prev_hour.txt
fi

time_shp=0

#sampling_sites=`grass --text ${TRAMONE_folder}/${grassdb}/${loc_jtsk}/${mapset} --exec v.db.select sampling_sites column=site|tail -n -2|sort|uniq`
#pary_lokalit=`echo $sampling_sites|cut -c1-1|sort|uniq`

if [ -f "/home/pi/TRAMONE/networking_on" ]; then
	rm "/home/pi/TRAMONE/networking_on"
fi

while :
do
	#check and restart networking
	date_UTC=`date -u +"%Y-%m-%d %H:%M:%S"`
	#if networking is dead
	if ! pgrep -f "networking.py" > /dev/null; then
		if [ -f "/home/pi/TRAMONE/networking_on" ]; then
			echo "${date_UTC}|ALL|MAIN|NETWORKING|DEAD|ERR" >> "/home/pi/TRAMONE/log.txt"
			rm "/home/pi/TRAMONE/networking_on"
		fi
		lxterminal -e bash -c "python ${TRAMONE_folder}/networking.py" &
		echo "${date_UTC}|ALL|MAIN|NETWORKING|RESTART|" >> "/home/pi/TRAMONE/log.txt"
			while [ ! -f "/home/pi/TRAMONE/networking_on" ]
			do
				echo "Waiting for networking..."
				sleep 1
			done			
	else 
	#if networking hangs
		time_now_sec=`TZ=UTC date +"%s"`
		last_networking_loop_time=$(cat "/home/pi/TRAMONE/last_networking_loop_time.txt")
		if [ `echo "$time_now_sec - $last_networking_loop_time"|bc` -gt 180 ]; then
			echo "No network response for 3 minutes! Connection lost? Restarting networking..."
			echo "${date_UTC}|ALL|MAIN|NETWORKING|HANG|ERR" >> "/home/pi/TRAMONE/log.txt"
			sudo pkill -f networking.py
			sleep 0.5
			lxterminal -e bash -c "python ${TRAMONE_folder}/networking.py" &
			echo "${date_UTC}|ALL|MAIN|NETWORKING|RESTART|" >> "/home/pi/TRAMONE/log.txt"
		fi
	fi

# R script 	
	Rscript ${TRAMONE_folder}/wind_preparation.R ${TRAMONE_folder}/wind.txt ${TRAMONE_folder}/meteo_sites.txt ${TRAMONE_folder}

	wait
	
	if [ -e "/home/pi/TRAMONE/grassdata/cr-jtsk/TRAMONE/.gislock" ]; then
		rm "/home/pi/TRAMONE/grassdata/cr-jtsk/TRAMONE/.gislock"
	fi
	
	grass --text ${TRAMONE_folder}/${grassdb}/${loc_jtsk}/${mapset} --exec v.in.ascii input=${TRAMONE_folder}/wind.csv output=wind sep="," skip=1 x=6 y=7 columns="EG_GH_ID varchar(8),wd integer,ws real,u_wind real,v_wind real,x real,y real,elevation integer,date varchar(50),ws_ASL_slope real,ws_ASL_intercept real,ws_ASL_R2 real"
	grass --text ${TRAMONE_folder}/${grassdb}/${loc_jtsk}/${mapset} --exec v.buffer wind out=wind_buf distance=10000
	grass --text ${TRAMONE_folder}/${grassdb}/${loc_jtsk}/${mapset} --exec g.region vect=wind_buf res=500 -a
	grass --text ${TRAMONE_folder}/${grassdb}/${loc_jtsk}/${mapset} --exec v.in.region region
	grass --text ${TRAMONE_folder}/${grassdb}/${loc_jtsk}/${mapset} --exec v.surf.rst wind zcolumn=u_wind elevation=u_wind tension=60 smooth=0.05
	grass --text ${TRAMONE_folder}/${grassdb}/${loc_jtsk}/${mapset} --exec v.surf.rst wind zcolumn=v_wind elevation=v_wind tension=60 smooth=0.05
	grass --text ${TRAMONE_folder}/${grassdb}/${loc_jtsk}/${mapset} --exec r.mapcalc expression="ws=if(sqrt(u_wind^2+v_wind^2)<0.2,0.1,sqrt(u_wind^2+v_wind^2))"

# ws regression
	grass --text ${TRAMONE_folder}/${grassdb}/${loc_jtsk}/${mapset} --exec v.surf.rst wind zcolumn=ws_ASL_slope elevation=ws_ASL_slope tension=60 smooth=0.05
	grass --text ${TRAMONE_folder}/${grassdb}/${loc_jtsk}/${mapset} --exec v.surf.rst wind zcolumn=ws_ASL_intercept elevation=ws_ASL_intercept tension=60 smooth=0.05
	grass --text ${TRAMONE_folder}/${grassdb}/${loc_jtsk}/${mapset} --exec v.surf.rst wind zcolumn=ws_ASL_R2 elevation=ws_ASL_R2 tension=60 smooth=0.05
	grass --text ${TRAMONE_folder}/${grassdb}/${loc_jtsk}/${mapset} --exec r.mapcalc expression="ws_ASL_R2=if(ws_ASL_R2<0,0,ws_ASL_R2)"
	grass --text ${TRAMONE_folder}/${grassdb}/${loc_jtsk}/${mapset} --exec r.mapcalc expression="wsregression=if(ws_ASL_slope*dem_CR_90m+ws_ASL_intercept<0.2,0.1,ws_ASL_slope*dem_CR_90m+ws_ASL_intercept)"
	grass --text ${TRAMONE_folder}/${grassdb}/${loc_jtsk}/${mapset} --exec v.to.rast wind out=wind use=val value=1
	grass --text ${TRAMONE_folder}/${grassdb}/${loc_jtsk}/${mapset} --exec r.grow.distance input=wind distance=distance_korr value=value
	grass --text ${TRAMONE_folder}/${grassdb}/${loc_jtsk}/${mapset} --exec r.mapcalc expression="distance_korr=if(distance_korr/5000>1,1,distance_korr/5000)"
	grass --text ${TRAMONE_folder}/${grassdb}/${loc_jtsk}/${mapset} --exec r.mapcalc expression="wscorrected=if(ws+distance_korr*sqrt(ws_ASL_R2)*(wsregression-ws)<0.2,0.1,ws+distance_korr*sqrt(ws_ASL_R2)*(wsregression-ws))"
	grass --text ${TRAMONE_folder}/${grassdb}/${loc_jtsk}/${mapset} --exec r.mapcalc expression="wscorrected_diff_ws=wscorrected-ws"

#wind field	corrected based on regression
	grass --text ${TRAMONE_folder}/${grassdb}/${loc_jtsk}/${mapset} --exec r.mapcalc expression="u_wind=wscorrected/ws*u_wind"
	grass --text ${TRAMONE_folder}/${grassdb}/${loc_jtsk}/${mapset} --exec r.mapcalc expression="v_wind=wscorrected/ws*v_wind"
	grass --text ${TRAMONE_folder}/${grassdb}/${loc_jtsk}/${mapset} --exec r.mapcalc expression="wd=atan(v_wind,u_wind)"
	grass --text ${TRAMONE_folder}/${grassdb}/${loc_jtsk}/${mapset} --exec r.mapcalc expression="wd_inv=if(wd+180>360,wd+180-360,wd+180)"

#recent time and loop time increment for traj
	time_prev_sec=`cat ${TRAMONE_folder}/time_prev_sec.txt`
	time_now_sec=`TZ=UTC date +"%s"`
	diff_time_sec=`echo "$time_now_sec - $time_prev_sec"|bc`
	echo $time_now_sec > ${TRAMONE_folder}/time_prev_sec.txt
	echo "time_now_sec: " $time_now_sec
	echo "time_prev_sec: " $time_prev_sec
	echo "diff_time_sec: " $diff_time_sec
	
#add new trajectory point at each monitoring site buffer zone
	while read radek
	do
		IFS="," read -r pairsite x y <<< ${radek}
		echo "-----------------------------------"
		echo $pairsite"|"$x"|"$y
		echo "time_now_sec: " $time_now_sec
		for i in {1..9}
		do
			angle=$(echo "scale=6; 2 * 3.141593 * $RANDOM / 32767" | bc)
			distance=$(echo "scale=6; $RANDOM / 32767 * $repre_range" | bc)
			dx=$(echo "scale=6; $distance * c($angle)" | bc -l)
			dy=$(echo "scale=6; $distance * s($angle)" | bc -l)
			echo "distance   dx     dy"
			echo $distance   $dx   $dy
			x_perturb=`echo "$x + $dx"|bc`
			y_perturb=`echo "$y + $dy"|bc`
			echo ${pairsite},${x_perturb},${y_perturb},${time_now_sec},${x},${y},999,999 >> ${TRAMONE_folder}/traj.txt
		done
	done < ${TRAMONE_folder}/sampling_sites_jtsk.txt

#remove corrupted lines (with no coords)
	sed -i s/,,,/,0,0,/g ${TRAMONE_folder}/traj.txt
	sed -i s/,,/,0,/g ${TRAMONE_folder}/traj.txt

#move all trajectory points according the wind and time increment
	grass --text ${TRAMONE_folder}/${grassdb}/${loc_jtsk}/${mapset} --exec v.in.ascii input="${TRAMONE_folder}/traj.txt" out=traj x=2 y=3 sep="," columns="site varchar(3),x real,y real,time integer,x_puv real,y_puv real,u_wind_prev real,v_wind_prev real"
	grass --text ${TRAMONE_folder}/${grassdb}/${loc_jtsk}/${mapset} --exec v.db.addcolumn traj column="u_wind real,v_wind real,x_new real,y_new real"
	grass --text ${TRAMONE_folder}/${grassdb}/${loc_jtsk}/${mapset} --exec v.what.rast traj raster=u_wind column=u_wind 
	sleep 0.1
	grass --text ${TRAMONE_folder}/${grassdb}/${loc_jtsk}/${mapset} --exec v.what.rast traj raster=v_wind column=v_wind 
	sleep 0.1
	grass --text ${TRAMONE_folder}/${grassdb}/${loc_jtsk}/${mapset} --exec db.execute sql="UPDATE traj SET x_new=x-u_wind*${diff_time_sec}"
	sleep 0.1
	grass --text ${TRAMONE_folder}/${grassdb}/${loc_jtsk}/${mapset} --exec db.execute sql="UPDATE traj SET y_new=y-v_wind*${diff_time_sec}"
	sleep 0.1

#filter out points outside region and older than max_traj_time (sec)
	grass --text ${TRAMONE_folder}/${grassdb}/${loc_jtsk}/${mapset} --exec v.select ainput=traj binput=region operator="within" output=traj_reg
	sleep 0.1
	grass --text ${TRAMONE_folder}/${grassdb}/${loc_jtsk}/${mapset} --exec v.db.select traj_reg columns="site,x_new,y_new,time,x,y,u_wind,v_wind" where="${time_now_sec}-time<${max_traj_time}" separator=","|tail -n +2 > ${TRAMONE_folder}/traj.txt

#read trajectory points at updated (moved) coordinates 
	grass --text ${TRAMONE_folder}/${grassdb}/${loc_jtsk}/${mapset} --exec v.in.ascii input=${TRAMONE_folder}/traj.txt out=traj x=2 y=3 sep=","
	sleep 0.1
	
#draw the map (function)
	mapmaker 

#controlling the samplers
	grass --text ${TRAMONE_folder}/${grassdb}/${loc_jtsk}/${mapset} --exec v.in.ascii input=${TRAMONE_folder}/sampling_sites_jtsk.txt out=sampling_sites x=2 y=3 sep="," columns="site varchar(3),x real,y real"
	sampling_sites=`grass --text ${TRAMONE_folder}/${grassdb}/${loc_jtsk}/${mapset} --exec v.db.select sampling_sites column=site|tail -n +2|sort|uniq`
	pary_lokalit=`echo $sampling_sites | tr ' ' '\n' | cut -c1 | sort -u`
	for pair in $pary_lokalit
	do
	
		mkdir -p ${TRAMONE_folder}/MQTT/TRAMONE/${pair}A
		mkdir -p ${TRAMONE_folder}/MQTT/TRAMONE/${pair}B
			
		grass --text ${TRAMONE_folder}/${grassdb}/${loc_jtsk}/${mapset}  --exec v.edit map=traj_A_src tool=create 
		grass --text ${TRAMONE_folder}/${grassdb}/${loc_jtsk}/${mapset}  --exec v.edit map=traj_B_src tool=create 
		grass --text ${TRAMONE_folder}/${grassdb}/${loc_jtsk}/${mapset}  --exec v.edit map=traj_A_site_B tool=create
		grass --text ${TRAMONE_folder}/${grassdb}/${loc_jtsk}/${mapset}  --exec v.edit map=traj_B_site_A tool=create 

		grass --text ${TRAMONE_folder}/${grassdb}/${loc_jtsk}/${mapset} --exec v.extract traj out=traj_A where="str_1='${pair}A'" 
		grass --text ${TRAMONE_folder}/${grassdb}/${loc_jtsk}/${mapset} --exec v.extract traj out=traj_B where="str_1='${pair}B'" 
	
		grass --text ${TRAMONE_folder}/${grassdb}/${loc_jtsk}/${mapset} --exec v.select ainput=traj_A binput=source_area output=traj_A_src 
		grass --text ${TRAMONE_folder}/${grassdb}/${loc_jtsk}/${mapset} --exec v.select ainput=traj_B binput=source_area output=traj_B_src 
	
		grass --text ${TRAMONE_folder}/${grassdb}/${loc_jtsk}/${mapset} --exec v.select ainput=traj_A binput=site_${pair}B_buf output=traj_A_site_B 
		grass --text ${TRAMONE_folder}/${grassdb}/${loc_jtsk}/${mapset} --exec v.select ainput=traj_B binput=site_${pair}A_buf output=traj_B_site_A 
	
		
		poc_traj_A=`grass --text ${TRAMONE_folder}/${grassdb}/${loc_jtsk}/${mapset} --exec v.category traj_A option=print| wc -l `
		poc_traj_B=`grass --text ${TRAMONE_folder}/${grassdb}/${loc_jtsk}/${mapset} --exec v.category traj_B option=print| wc -l `
		
		
		poc_traj_A_src=`grass --text ${TRAMONE_folder}/${grassdb}/${loc_jtsk}/${mapset} --exec v.category traj_A_src option=print| wc -l `
		poc_traj_B_src=`grass --text ${TRAMONE_folder}/${grassdb}/${loc_jtsk}/${mapset} --exec v.category traj_B_src option=print| wc -l `
		poc_traj_A_site_B=`grass --text ${TRAMONE_folder}/${grassdb}/${loc_jtsk}/${mapset} --exec v.category traj_A_site_B option=print| wc -l `
		poc_traj_B_site_A=`grass --text ${TRAMONE_folder}/${grassdb}/${loc_jtsk}/${mapset} --exec v.category traj_B_site_A option=print| wc -l `
		
		
		echo "#############################################"
		echo "TRAJECTORY POINT NUMBERS"
		echo "---------------------------------------------"
		echo "Pair:"  ${pair}
		echo "A -> source: "${poc_traj_A_src}
		echo "A -> B:      "${poc_traj_A_site_B}
		echo "B -> source: "${poc_traj_B_src} 
		echo "B -> A:      "${poc_traj_B_site_A}  
		echo "#############################################"

# evaluate sampling conditions (switch on, if traj passed site A & source area & site B):
		if [ "$poc_traj_A_src" -gt 0 -a "$poc_traj_A_site_B" -gt 0 ]; then
			#first sampling direction - site config:
			request_A="10"
			request_B="10"
			request_explanation=`echo "Start sampling for pair ${pair} from site A to site B"`
		elif [ "$poc_traj_B_src" -gt 0 -a "$poc_traj_B_site_A" -gt 0 ]; then
			#opposite sampling direction - site config:
			request_A="01"
			request_B="01"
			request_explanation=`echo "Start sampling for pair ${pair} from site B to site A"`
		else
			#no sampling:
			request_A="00"
			request_B="00"
			request_explanation=`echo "Stop sampling for pair ${pair}"`
		fi	
		
# write a new request
#		if [ "$request_A" != "${request_prev_A[$pair]}" -o "$request_B" != "${request_prev_B[$pair]}" ]; then
			time_request=`TZ=UTC date +"%s"`
			time_logformat=`TZ=UTC date +"%F %T"`
			time_diff=0
#			if [ "$request_A" != "${request_prev_A[$pair]}"; then
				echo  $request_A > ${TRAMONE_folder}/MQTT/TRAMONE/${pair}A/request
#			fi
#			if [ "$request_B" != "${request_prev_B[$pair]}"; then
				echo  $request_B > ${TRAMONE_folder}/MQTT/TRAMONE/${pair}B/request
#			fi
#		fi

		#assign previous request
		#request_prev_A[$pair]=${request_A}
		#request_prev_B[$pair]=${request_B}

		grass --text ${TRAMONE_folder}/${grassdb}/${loc_jtsk}/${mapset} --exec g.remove -f type=vect name="traj_A_src,traj_B_src,traj_A_site_B,traj_B_site_A"
		
	done
	
	time_now_hour=`TZ=UTC date +"%Y%m%d%H"`
	time_prev_hour=`cat ${TRAMONE_folder}/time_prev_hour.txt`
	if [ "$time_now_hour" -gt "$time_prev_hour" ]; then
		wait 
		cp ${TRAMONE_folder}/wind.csv ${TRAMONE_folder}/wind/wind_${time_now_hour}.csv 
		grass --text ${TRAMONE_folder}/${grassdb}/${loc_jtsk}/${mapset} --exec v.out.ogr -s -e traj out=${TRAMONE_folder}/shp/traj_${time_now_hour}.shp format=ESRI_Shapefile
		cp "${TRAMONE_folder}/tramone.png" "${TRAMONE_folder}/img/tramone_${time_now_hour}.png"		
		cp "${TRAMONE_folder}/tramone2.png" "${TRAMONE_folder}/img/tramone2_${time_now_hour}.png"
		time_prev_hour=$time_now_hour
		echo $time_prev_hour > ${TRAMONE_folder}/time_prev_hour.txt
	fi
	
	

done





