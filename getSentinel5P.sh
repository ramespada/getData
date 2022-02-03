#!/bin/bash
export LC_NUMERIC="en_US.UTF-8"

epsg_latlon=4326        #latlon wgs84
hoy=$(date +'%Y%m%d')

USERNAME=s5pguest
PASSWORD=s5pguest

platform="Sentinel-5 Precursor"
#----------------------------------------------
#Grid params:
nx=500
ny=500

yini=-55.000 #(arg) | -35.4 #(bsas)   
yfin=-20.000 #(arg) | -34.1 #(bsas)   
xini=-74.000 #(arg) | -59.3 #(bsas)   
xfin=-51.000 #(arg) | -57.5 #(bsas)   

dx=$(bc -l <<< "(${xfin} - ${xini}) / ${nx}")
dy=$(bc -l <<< "(${yfin} - ${yini}) / ${ny}")

POLYGON="${xini} ${yini}, ${xini} ${yfin}, ${xfin} ${yfin}, ${xfin} ${yfin},${xini} ${yini}"
#----------------------------------------------

case $1 in
	(-h | --help)
	echo -e "\e[33m Ayuda:\e[0m."
	echo "Opciones:"
	echo ""
	echo "(-h|--help):		Muestra este mensaje."
	echo ""
	echo "(-dwnld|--download) <prod-type>:	Descarga netcdf de sentinel-5P."
	echo "		    	donde <prod-type> puede tomar los siguientes valores:"
	echo "			L2__CH4   "
       	echo "			L2__CLOUD_"
        echo "			L2__CO____"
        echo "			L2__HCHO__" 
	echo "			L2__NO2___"
        echo "			L2__NP_BD3" 
	echo "			L2__NP_BD6" 
	echo "			L2__NP_BD7" 
	echo "			L2__O3_TCL"
        echo "			L2__O3____"
        echo "			L2__SO2___"
	#Sentinel-5P: L1B_IR_SIR, L1B_IR_UVN, L1B_RA_BD1, L1B_RA_BD2, L1B_RA_BD3, L1B_RA_BD4, L1B_RA_BD5, L1B_RA_BD6, L1B_RA_BD7, L1B_RA_BD8, L2__AER_AI, L2__AER_LH, L2__CH4, L2__CLOUD_, L2__CO____, L2__HCHO__, L2__NO2___, L2__NP_BD3, L2__NP_BD6, L2__NP_BD7, L2__O3_TCL, L2__O3____, L2__SO2___
	echo ""
	echo "(-pos) :			Post-procesamiento de archivos descargados, grillado y conversión a -tiff."
	echo ""
	echo "(-harp) <prod-type>:	Post-procesamiento de archivos descargados, grillado y conversión a -tiff."	
	
;;
(-dwnld | --download)
#
#Descarga
#=========
	echo -e "\e[33m Descarga:\e[0m"
	prodtype=$2 #"L2__SO2___"
	mkdir $prodtype
	URIquery="footprint:\"Intersects(POLYGON((${POLYGON})))\" AND ingestiondate:[NOW-1DAY TO NOW] AND producttype:${prodtype} AND platformname:${platform}"

	echo -e "\e[32m https://s5phub.copernicus.eu/dhus/search?q=${URIquery}\e[0m"
	wget --no-check-certificate --user=${USERNAME} --password=${PASSWORD} --output-document=query_results.txt "https://s5phub.copernicus.eu/dhus/search?q=${URIquery}&format=json"

	uuids=($(cat query_results.txt | jq -r '.. | select(.name=="uuid"?) | .content' | tr "\n" " "))
	
	for uuid in ${uuids[@]} ; do
		echo -e "\e[32m $uuid \e[0m"
		wget --content-disposition --continue --user=${USERNAME} --password=${PASSWORD} -P ${prodtype}/ "https://s5phub.copernicus.eu/dhus/odata/v1/Products('${uuid}')/\$value"
	done;

;;
#(-pos|--postprocess)
#	echo -e "\e[33m Posprocesamiento:\e[0m."
## postporcesamiento:
#	rm lat* lon* so2*
#	
#	
#	ncfiles=($(ls S5P_NRTI_L2__SO2____20220131T*))
#	for ncfile in ${ncfiles[@]} ; do
#		ncdump -v sulfurdioxide_total_vertical_column ${ncfile} | sed -e '1,/data:/d' -e '/group:/,$d' | tr " " "\n" | sed '/^$/d'> so2_tot_col
#		ncdump -v latitude ${ncfile} | sed -e '1,/data:/d' -e '/group:/,$d' | tr " " "\n" | sed '/^$/d'> latitude
#		ncdump -v longitude ${ncfile} | sed -e '1,/data:/d' -e '/group:/,$d' | tr " " "\n" | sed '/^$/d' > longitude
#		paste longitude latitude so2_tot_col >> so2_xyz
#	done
#	
#	sed -i '/^lon.*/d;/^=/d;/^\;/d' so2_xyz
#	file_inp=so2_xyz_
#	#cat ${file_inp} | awk 'BEGIN{print "x,y,conc \n"}{printf("%.5f,%.5f,%s\n",$1,$2,$3)}'> tmp.csv
#	#echo "x,y,conc" | cat - ${file_inp} >tmp.csv
#	#ogr2ogr -f GPKG tmp.gpkg tmp.csv -oo X_POSSIBLE_NAMES=x -oo Y_POSSIBLE_NAMES=y -a_srs EPSG:${epsg_latlon} 
#	nx=200
#	ny=300
#	yini=-58.000
#	yfin=-14.000
#	xini=-83.000
#	xfin=-32.000
#	dx=$(bc -l <<< "(${xfin} - ${xini}) / ${nx}")
#	dy=$(bc -l <<< "(${yfin} - ${yini}) / ${ny}")
#	file_out=so2_gridded
#	gdal_grid -of GTiff -ot Float64 -txe $xini $xfin -tye $yini $yfin -outsize $nx $ny -zfield "conc" -a linear tmp.gpkg ${file_out}.tif #GPKG!
#;;
(-harp)
	prodtype=$2
	pollut=$(echo ${prodtype:4:8} | sed 's/_//g')
	ncfiles=($(ls ${prodtype}))
	outdir=NRTI_${pollut};	mkdir ${outdir}
	
	if [ $pollut == NO2 ]
	then	
		var=tropospheric_${pollut}_column_number_density
		validity=${var}_validity
	else
		var=${pollut}_column_number_density
		validity=${var}_validity
	fi;

	for ncfile in ${ncfiles[@]} ; do
		echo -e "\e[31m ${ncfile}\e[0m."
		echo -e "\e[32m harpconvert...\e[0m."
		harpconvert -a "${validity}>50; keep(datetime_start,datetime_length,${var},latitude_bounds,longitude_bounds);bin_spatial(${ny},${yini},${dy},${nx},${xini},${dx});bin();squash(time, (latitude_bounds,longitude_bounds));derive(latitude {latitude});derive(longitude {longitude});exclude(latitude_bounds,longitude_bounds,latitude_bounds_weight,longitude_bounds_weight,count,weight)" ${prodtype}/${ncfile} tmp.nc 
		echo -e "\e[34m GDAL...\e[0m."
		gdal_translate NETCDF:"tmp.nc":$var tmp_${ncfile}.tif
	done
	echo -e "\e[33m Merge (GDAL)...\e[0m."
	#gdalbuildvrt mosaic.vrt tmp_*.tif
	#gdal_translate -of GTiff -co "TILED=YES" mosaic.vrt ${pollut}_NRTI_${hoy}.tif
        gdalwarp -ot FLOAT64 -te $xini $yini $xfin $yfin tmp_*.tif ${pollut}_NRTI_${hoy}.tif

;;
esac



## GOOGLE EARTH ENGINE procesamiento:
#
## CO
#harpconvert --format hdf5 --hdf5-compression 9
#-a 'CO_column_number_density_validity>50;derive(datetime_stop {time});
#bin_spatial(2001, 50.000000, 0.01, 2001, -120.000000, 0.01);
#keep(CO_column_number_density,H2O_column_number_density,cloud_height,
#sensor_altitude,sensor_azimuth_angle, sensor_zenith_angle,
#solar_azimuth_angle,solar_zenith_angle)'
#S5P_NRTI_L2__CO_____20181122T000018_20181122T000518_05741_01_010200_20181122T004844.nc
#output.h5
#
## NO2
#harpconvert --format hdf5 --hdf5-compression 9
#-a 'tropospheric_NO2_column_number_density_validity>50;derive(datetime_stop {time});
#bin_spatial(2001, 50.000000, 0.01, 2001, -120.000000, 0.01);
#keep(NO2_column_number_density,tropospheric_NO2_column_number_density,
#     stratospheric_NO2_column_number_density,NO2_slant_column_number_density,
#     tropopause_pressure,absorbing_aerosol_index,cloud_fraction,
#     sensor_altitude,sensor_azimuth_angle,
#     sensor_zenith_angle,solar_azimuth_angle,solar_zenith_angle)'
#S5P_NRTI_L2__NO2____20181107T013042_20181107T013542_05529_01_010200_20181107T021824.nc
#output.h5
#
## O3
#harpconvert --format hdf5 --hdf5-compression 9
#-a 'O3_column_number_density_validity>50;derive(datetime_stop {time});
#bin_spatial(2001, 50.000000, 0.01, 2001, -120.000000, 0.01);
#keep(O3_column_number_density,O3_column_number_density_amf,
#O3_slant_column_number_density,O3_effective_temperature,cloud_fraction,
#sensor_azimuth_angle,sensor_zenith_angle,solar_azimuth_angle,
#solar_zenith_angle)'
#
## SO2
#harpconvert --format hdf5 --hdf5-compression 9
#-a 'SO2_column_number_density_validity>50;derive(datetime_stop {time});
#bin_spatial(2001, 50.000000, 0.01, 2001, -120.000000, 0.01);
#keep(SO2_column_number_density,SO2_column_number_density_amf,
#     SO2_slant_column_number_density,cloud_fraction, sensor_altitude,
#     sensor_azimuth_angle, sensor_zenith_angle,solar_azimuth_angle,
#     solar_zenith_angle)'
#S5P_NRTI_L2__SO2____20190129T101503_20190129T102003_06711_01_010105_20190129T111328.nc
#output.h5
#
##    snow_ice < 0.5
##    sulfurdioxide_total_air_mass_factor_polluted > 0.1
##    sulfurdioxide_total_vertical_column > -0.001
##    qa_value > 0.5
##    cloud_fraction_crb < 0.3
##    solar_zenith_angle < 60
#
## HCHO Formaldehyde
#harpconvert --format hdf5 --hdf5-compression 9
#-a 'tropospheric_HCHO_column_number_density_validity>50;derive(datetime_stop {time});
#bin_spatial(2001, 50.000000, 0.01, 2001, -120.000000, 0.01);
#keep(tropospheric_HCHO_column_number_density,
#     tropospheric_HCHO_column_number_density_amf,
#     HCHO_slant_column_number_density,cloud_fraction,sensor_altitude,
#     sensor_azimuth_angle, sensor_zenith_angle,solar_azimuth_angle,
#     solar_zenith_angle)'
#S5P_NRTI_L2__HCHO___20181017T181013_20181017T181513_05241_01_010102_20181017T185718.nc
#output.h5
#
#
## CH4
#
#
#
#
#
