#!/bin/bash
TRAMONE_folder=$1
grassdb=$2
loc_jtsk=$3
mapset=$4
region=$5
png_name=$6


export GRASS_RENDER_IMMEDIATE=cairo
export GRASS_RENDER_WIDTH=800
export GRASS_RENDER_HEIGHT=800
export GRASS_RENDER_TRANSPARENT=TRUE
export GRASS_RENDER_FILE_READ=TRUE
export GRASS_RENDER_LINE_WIDTH=1

echo "*********************"
echo "Mapmaker started."
echo "*********************"

	export GRASS_RENDER_FILE="${TRAMONE_folder}/${png_name}"
	grass --text ${TRAMONE_folder}/${grassdb}/${loc_jtsk}/${mapset} --exec d.erase bgcolor=white
	#grass --text ${TRAMONE_folder}/${grassdb}/${loc_jtsk}/${mapset} --exec g.region vect=sampling_sites_buf res=60
	
	#set resolution
	grass --text ${TRAMONE_folder}/${grassdb}/${loc_jtsk}/${mapset} --exec g.region raster=bg_map_grey
	#set range
	grass --text ${TRAMONE_folder}/${grassdb}/${loc_jtsk}/${mapset} --exec g.region vect=${region}	
	
	grass --text ${TRAMONE_folder}/${grassdb}/${loc_jtsk}/${mapset} --exec d.rast bg_map_grey
	grass --text ${TRAMONE_folder}/${grassdb}/${loc_jtsk}/${mapset} --exec g.region res=1000 -a
	grass --text ${TRAMONE_folder}/${grassdb}/${loc_jtsk}/${mapset} --exec d.vect source_area color="240:133:144" fill_color=none width=2
	
	grass --text ${TRAMONE_folder}/${grassdb}/${loc_jtsk}/${mapset} --exec d.rast.arrow map=wd_inv type=compass magnitude_map=wscorrected scale=2 skip=2 grid=none color="aqua"
	#grass --text ${TRAMONE_folder}/${grassdb}/${loc_jtsk}/${mapset} --exec d.vect sampling_sites size=15 color="none" fill_color="red" icon=basic/star
	
	lokality=`grass --text ${TRAMONE_folder}/${grassdb}/${loc_jtsk}/${mapset} --exec v.db.select sampling_sites column=site|tail -n +2|sort|uniq`
	pary_lokalit=`echo $lokality | tr ' ' '\n' | cut -c1-1|sort|uniq`
	for par in $pary_lokalit
	do
		grass --text ${TRAMONE_folder}/${grassdb}/${loc_jtsk}/${mapset} --exec d.vect site_${par}A_buf color="20:56:127" fill_color="none" width=2
		grass --text ${TRAMONE_folder}/${grassdb}/${loc_jtsk}/${mapset} --exec d.vect site_${par}B_buf color="231:51:49" fill_color="none" width=2
		grass --text ${TRAMONE_folder}/${grassdb}/${loc_jtsk}/${mapset} --exec d.vect traj size=3 color=none fill_color="20:56:127" icon=basic/circle where="str_1=='${par}A'"
		grass --text ${TRAMONE_folder}/${grassdb}/${loc_jtsk}/${mapset} --exec d.vect traj size=3 color=none fill_color="231:51:49" icon=basic/circle where="str_1=='${par}B'"
	done
	
	grass --text ${TRAMONE_folder}/${grassdb}/${loc_jtsk}/${mapset} --exec d.vect wind size=8 width=2 color="none" fill_color="aqua" icon=basic/circle
	grass --text ${TRAMONE_folder}/${grassdb}/${loc_jtsk}/${mapset} --exec v.label map=wind labels=ws column="ws" fontsize=7 color="aqua" reference=lower,left xoffset=4 yoffset=0 border="white" width=8
	grass --text ${TRAMONE_folder}/${grassdb}/${loc_jtsk}/${mapset} --exec d.labels ws
	grass --text ${TRAMONE_folder}/${grassdb}/${loc_jtsk}/${mapset} --exec v.label map=wind labels=wd column="wd" fontsize=7 color="aqua" reference=center,left xoffset=3 yoffset=5 border="white" width=8
	grass --text ${TRAMONE_folder}/${grassdb}/${loc_jtsk}/${mapset} --exec d.labels wd
	
	grass --text ${TRAMONE_folder}/${grassdb}/${loc_jtsk}/${mapset} --exec v.label map=wind labels=ws column="ws" fontsize=7 color="aqua" reference=lower,left xoffset=4 yoffset=0 border="white" width=8
	grass --text ${TRAMONE_folder}/${grassdb}/${loc_jtsk}/${mapset} --exec d.labels ws
	grass --text ${TRAMONE_folder}/${grassdb}/${loc_jtsk}/${mapset} --exec v.label map=wind labels=wd column="wd" fontsize=7 color="aqua" reference=center,left xoffset=3 yoffset=5 border="white" width=8
	grass --text ${TRAMONE_folder}/${grassdb}/${loc_jtsk}/${mapset} --exec d.labels wd

	if ! pgrep -fa "feh ${TRAMONE_folder}/${png_name}"; then
		feh ${TRAMONE_folder}/${png_name} &
	fi
	#sudo pkill -f "feh ${TRAMONE_folder}/${png_name}"
	#feh ${TRAMONE_folder}/${png_name} &
