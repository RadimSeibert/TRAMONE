import serial
import time 
import os
import RPi.GPIO as GPIO
import threading
import subprocess
from datetime import datetime
import pytz
import psutil
#import pandas as pd
#import numpy as npsub

SERIAL_PORT = '/dev/ttyAMA0'  
MQTT_BROKER = 'mqtt.eclipseprojects.io'
#MQTT_BROKER = 'test.mosquitto.org'
MQTT_PORT = 1883
MQTT_TOPICS_DIR = '/home/pi/TRAMONE/MQTT'
pairs=["1","2"]
sites=["A","B"]
last_request_time=[pairs,sites]
last_loop_time_file="/home/pi/TRAMONE/last_networking_loop_time.txt"
last_ftp_download_time="/home/pi/TRAMONE/last_ftp_download_time.txt"
LOG='/home/pi/TRAMONE/log.txt'
lock=threading.Lock()

def main_program_run_test():
	main_program_is_running=False
	for process in psutil.process_iter(['cmdline']):
		if any("tramone_main" in arg for arg in process.info['cmdline']):
			main_program_is_running=True
	if main_program_is_running==False:
		with open(LOG, "a") as file:
			file.write(f"{datetime.now(pytz.utc).strftime('%Y-%m-%d %H:%M:%S')}|ALL|MAIN|BASH_PROGRAM|RUN|ERR\n")
		print("Main program not running. Prepare for reboot in 60 seconds!")
		time.sleep(60)
		with open(LOG, "a") as file:
			file.write(f"{datetime.now(pytz.utc).strftime('%Y-%m-%d %H:%M:%S')}|ALL|ALL|ALL|REBOOT|\n")
		subprocess.Popen(["sudo","reboot"])	
#		subprocess.Popen(["nohup","lxterminal","-e","bash","-c",f"/home/pi/TRAMONE/tramone_main10.sh","&"])
#		for process in psutil.process_iter(['cmdline']):
#			if any("tramone_main" in arg for arg in process.info['cmdline']):
#				with open(LOG, "a") as file:
#					file.write(f"{datetime.now(pytz.utc).strftime('%Y-%m-%d %H:%M:%S')}|ALL|MAIN|BASH_PROGRAM|RUN|OK\n")

def subscribe(command):
	ser.write((command + '\r').encode())	
	time.sleep(0.5)
	response = ser.read(ser.in_waiting).decode()
	print(response)
	print("-------------")
	if "ERR" in response or "+SMSTATE: 0" in response or "+SMSTATE: 2" in response:
		return False

def close_all():		
	global ser
	ser = serial.Serial(SERIAL_PORT, baudrate=115200, timeout=3)
	print("---------------------")
	print("Closing everything...")
	if os.path.exists("/home/pi/TRAMONE/networking_on"):
		os.remove("/home/pi/TRAMONE/networking_on")
#		subprocess.run(["sudo","pkill","-f","gprs"],check=True)
#		print("PPP killed.")
	ser.write(('AT+FTPQUIT' + '\r').encode())
	time.sleep(1)
	response=ser.read(ser.in_waiting).decode()
	print(response)	
	for pair in pairs:
		for site in sites:
			MQTT_TOPIC_REQUEST = f'TRAMONE/{pair}{site}/request'
			MQTT_TOPIC_RESPONSE = f'TRAMONE/{pair}{site}/response'
			ser.write((f'AT+SMUNSUB=TRAMONE/{pair}{site}/request' + '\r').encode())
			time.sleep(0.1)
			response=ser.read(ser.in_waiting).decode()
			print(response)
			ser.write((f'AT+SMUNSUB=TRAMONE/{pair}{site}/response' + '\r').encode())
			time.sleep(0.1)
			response=ser.read(ser.in_waiting).decode()
			print(response)
			ser.write((f'AT+SMUNSUB=TRAMONE/{pair}{site}/filter' + '\r').encode())
			time.sleep(0.1)
			response=ser.read(ser.in_waiting).decode()
			print(response)
	response=ser.read(ser.in_waiting).decode()
	print(response)
	ser.write(('AT+SMDISC' + '\r').encode())
	time.sleep(1)
	response=ser.read(ser.in_waiting).decode()
	print(response)
	ser.write(('AT+CNACT=0,0' + '\r').encode())
	time.sleep(0.2)
	response=ser.read(ser.in_waiting).decode()
	print(response)
	response=ser.read(ser.in_waiting).decode()
	print(response)
	ser.write(('AT+CGACT=0,1' + '\r').encode())
	time.sleep(0.2)
	response=ser.read(ser.in_waiting).decode()
	print(response)
	ser.write(('AT+CGATT=0' + '\r').encode())
	time.sleep(0.2)
	response=ser.read(ser.in_waiting).decode()
	print(response)
	time.sleep(1)
	ser.close()	


def init_GSM():
	err=True
	while err == True:
		err=False
		close_all()
		print("------------")
		print("Init GSM...")
		GPIO.setwarnings(False)
		GPIO.setmode(GPIO.BCM)
		GPIO.setup(4, GPIO.OUT)
		GPIO.output(4, GPIO.HIGH)
		time.sleep(2)
		GPIO.output(4, GPIO.LOW)
		time.sleep(3)
		global ser
		ser = serial.Serial(SERIAL_PORT, baudrate=115200, timeout=3)
		time.sleep(1)
		ser.write(('AT' + '\r').encode())
		time.sleep(0.1)
		response=ser.read(ser.in_waiting).decode()
		print(response)
		if not 'OK' in response:
			print("GSM module off. Starting up...")
			GPIO.output(4, GPIO.HIGH)
			time.sleep(2)
			GPIO.output(4, GPIO.LOW)
			time.sleep(2)
			ser.write(('AT' + '\r').encode())
			time.sleep(0.2)
			response=ser.read(ser.in_waiting).decode()
			print(response)
		else:
			print("GSM module started.")
		ser.write(('AT+IPR=115200' + '\r').encode())
		time.sleep(0.1)
		response=ser.read(ser.in_waiting).decode()
		print(response)
		if not 'OK' in response:
			err=True
		ser.write(('AT+CMNB=1' + '\r').encode())
		time.sleep(0.1)
		response=ser.read(ser.in_waiting).decode()
		print(response)	
		ser.write(('AT+CNMP=38' + '\r').encode())
		time.sleep(0.1)
		response=ser.read(ser.in_waiting).decode()
		print(response)	
		if not 'OK' in response:
			err=True
		ser.write(('AT+CGATT=1' + '\r').encode())
		time.sleep(3)	
		response=ser.read(ser.in_waiting).decode()
		print(response)
		if not 'OK' in response:
			err=True
		ser.write(('AT+CGDCONT=1,"IP","internet.t-mobile.cz"' + '\r').encode())
		time.sleep(0.1)	
		response=ser.read(ser.in_waiting).decode()
		print(response)
		if not 'OK' in response:
			err=True
		ser.write(('AT+CGACT=1,1' + '\r').encode())
		time.sleep(0.1)
		response=ser.read(ser.in_waiting).decode()
		print(response)
		if not 'OK' in response:
			err=True	
		ser.write(('AT+CNACT=0,2' + '\r').encode())
		time.sleep(1)
		response=ser.read(ser.in_waiting).decode()
		print(response)
		if not 'ACTIVE' in response:
			#err=True
			with open(LOG, "a") as file:
				file.write(f"{datetime.now(pytz.utc).strftime('%Y-%m-%d %H:%M:%S')}|ALL|NET|INIT|GSM|ERR\n")
		else:
			print("------------")
			print("Init GSM OK.")
			print("------------")
			with open(LOG, "a") as file:
				file.write(f"{datetime.now(pytz.utc).strftime('%Y-%m-%d %H:%M:%S')}|ALL|NET|INIT|GSM|OK\n")
		#set ntp time
		ser.write(('AT+CNTP' + '\r').encode())
		time.sleep(2)
		response=ser.read(ser.in_waiting).decode()
		print(response)	
		if 'OK' in response:
			lines=response.splitlines()
			for line in lines:
				if "+CNTP:" in line:
					line=line.replace('"','')
					parts=line.split(',')
					parse_datetime=datetime.strptime(f"{parts[1]} {parts[2]}","%Y/%m/%d %H:%M:%S")
					with open(LOG, "a") as file:
						file.write(f"{datetime.now(pytz.utc).strftime('%Y-%m-%d %H:%M:%S')}|ALL|NET|NTP|{parse_datetime}|OK\n")
					formatted_datetime=parse_datetime.strftime("%m%d%H%M%Y.%S")
					subprocess.run(["sudo","date",formatted_datetime])
					break
	return err

def init_MQTT():
	err=False	
	#init MQTT
	ser.write((f'AT+SMCONF="URL",{MQTT_BROKER},{MQTT_PORT}' + '\r').encode())
	time.sleep(0.1)
	response=ser.read(ser.in_waiting).decode()
	print(response)
	if not 'OK' in response:
		err=True
	ser.write(('AT+SMCONF="KEEPTIME",900' + '\r').encode())
	time.sleep(0.1)
	response=ser.read(ser.in_waiting).decode()
	print(response)
	if not 'OK' in response:
		err=True
	ser.write(('AT+SMCONF="CLEANSS",1' + '\r').encode())
	time.sleep(0.1)
	response=ser.read(ser.in_waiting).decode()
	print(response)
	if not 'OK' in response:
		err=True
	ser.write(('AT+SMCONF="CLIENTID","TRAMONE_SERVER"' + '\r').encode())
	time.sleep(0.1)
	response=ser.read(ser.in_waiting).decode()
	print(response)
	if not 'OK' in response:
		err=True
	ser.write(('AT+SMCONN' + '\r').encode())
	time.sleep(5)
	response=ser.read(ser.in_waiting).decode()
	print(response)
	if not 'OK' in response or 'ERR' in response:
		err=True
		print("MQTT reconnection error!!!")
	if err==False:
		#set subscribe responses
		ser.write((f'AT+SMSUB=TRAMONE/#,0' + '\r').encode())
		time.sleep(0.2)
		#test publishing
		for pair in pairs:
			for site in sites:
				#create topic of request
				ser.write((f'AT+SMPUB=TRAMONE/{pair}{site}/request,2,0,0' + '\r').encode())
				time.sleep(0.1)
				ser.write((f'99' + '\r').encode())
				time.sleep(0.1)
				#create topic of filter_replacement
				ser.write((f'AT+SMPUB=TRAMONE/{pair}{site}/filter,2,0,0' + '\r').encode())
				time.sleep(0.1)
				ser.write((f'99' + '\r').encode())
				time.sleep(0.1)
				#check response
		time.sleep(10)
		response = ser.read(ser.in_waiting).decode()
		print(response)
		if '+SMSUB:' in response and "99" in response and not "ERR" in response:
			subscribe_to_log()
			with open(LOG, "a") as file:
				file.write(f"{datetime.now(pytz.utc).strftime('%Y-%m-%d %H:%M:%S')}|{pair}{site}|NET|INIT|MQTT|OK\n")
		else:
			with open(LOG, "a") as file:
				file.write(f"{datetime.now(pytz.utc).strftime('%Y-%m-%d %H:%M:%S')}|{pair}{site}|NET|INIT|MQTT|ERR\n")
			err=True
	print("-------------")
	print("End init MQTT")
	print("-------------")
	return err

def init_FTP():
	err=True
	while err == True:
		err=False	
		#init FTP
		ser.write(('AT+FTPCID?' + '\r').encode())
		time.sleep(1)
		response=ser.read(ser.in_waiting).decode()
		print(response)
		if '+SMSUB:' in response:
			subscribe_to_log()	
		if not 'OK' in response:
			err=True
		else:
			if not '+FTPCID: 0' in response:
				ser.write(('AT+FTPCID=0' + '\r').encode())
				time.sleep(0.1)
				response=ser.read(ser.in_waiting).decode()
				print(response)
				if '+SMSUB:' in response:
					subscribe_to_log()
		ser.write(('AT+FTPSERV="84.42.172.154"' + '\r').encode())
		time.sleep(0.1)
		response=ser.read(ser.in_waiting).decode()
		print(response)
		if '+SMSUB:' in response:
			subscribe_to_log()
		if not 'OK' in response:
			err=True
		ser.write(('AT+FTPUN="aim"' + '\r').encode())
		time.sleep(0.1)
		response=ser.read(ser.in_waiting).decode()
		print(response)
		if '+SMSUB:' in response:
			subscribe_to_log()	
		if not 'OK' in response:
			err=True
		ser.write(('AT+FTPPW="radim64vod"' + '\r').encode())
		time.sleep(0.1)
		response=ser.read(ser.in_waiting).decode()
		print(response)
		if '+SMSUB:' in response:
			subscribe_to_log()
		if not 'OK' in response:
			err=True	
		ser.write(('AT+FTPGETNAME="autovzorsta.txt"' + '\r').encode())
		time.sleep(0.1)
		response=ser.read(ser.in_waiting).decode()
		print(response)
		if '+SMSUB:' in response:
			subscribe_to_log()
		if not 'OK' in response:
			err=True	
		ser.write(('AT+FTPGETPATH="/OCO/vzorsta/"' + '\r').encode())
		time.sleep(0.1)
		response=ser.read(ser.in_waiting).decode()
		print(response)
		if '+SMSUB:' in response:
			subscribe_to_log()	
		if not 'OK' in response:
			err=True
		ser.write(('AT+FTPMODE=1' + '\r').encode())
		time.sleep(0.1)
		response=ser.read(ser.in_waiting).decode()
		print(response)
		if '+SMSUB:' in response:
			subscribe_to_log()	
		if not 'OK' in response:
			err=True
		ser.write(('AT+FTPTYPE="I"' + '\r').encode())
		time.sleep(0.1)
		response=ser.read(ser.in_waiting).decode()
		print(response)
		if '+SMSUB:' in response:
			subscribe_to_log()	
		if not 'OK' in response:
			err=True	
		if err==True:
			print("FTP init error!")
			with open(LOG, "a") as file:
				file.write(f"{datetime.now(pytz.utc).strftime('%Y-%m-%d %H:%M:%S')}|ALL|NET|CONN|FTP|ERR\n")
		else:
			print("FTP connected.")
			with open(LOG, "a") as file:
				file.write(f"{datetime.now(pytz.utc).strftime('%Y-%m-%d %H:%M:%S')}|ALL|NET|CONN|FTP|OK\n")
	return err					
	
def wind_download():
	err=False
	response=ser.read(ser.in_waiting).decode()
	print(response)
	if '+SMSUB:' in response:
			subscribe_to_log()	
	ser.write(('AT+FTPSIZE' + '\r').encode())
	time.sleep(2)
	response=ser.read(ser.in_waiting).decode()
	print(response)
	if '+SMSUB:' in response:
			subscribe_to_log()	
	lines=response.splitlines()
	file_size=None
	for line in lines:
		if "+FTPSIZE:" in line:
			parts=line.split(',')
			file_size=int(parts[-1])
			break
	#download to memory
	ser.write(('AT+FTPEXTGET=1' + '\r').encode())
	time.sleep(2)
	time_start=time.time()
	while True:
		print("Downloading to memory...")
		response=ser.read(ser.in_waiting).decode()
		print(response)
		if '+SMSUB:' in response:
			subscribe_to_log()
		if time.time()-time_start>60:
			print("FTP download timeout!")
			err=True
			break
		if '+FTPEXTGET:' in response:
			lines=response.splitlines()	
			for line in lines:
				if '+FTPEXTGET:' in line:
					FTPEXTGET_state=int(line.split(',')[-1])
					if FTPEXTGET_state==0:
						print("Wind file downloaded successfully.")
					elif FTPEXTGET_state<file_size:
						print("Wind file corrupted or other FTP error.")
						err=True
			break
		time.sleep(3)		
	#print/save from memory
	if err==False:
		with lock:
			ser.write((f'AT+FTPEXTGET=3,0,{file_size}' + '\r').encode())
		response=''
		while True:
			if ser.in_waiting:
				line=ser.readline().decode().strip()
				response += line + '\n'
				if line == 'OK':
					break
		print("---------------------")
		print(response)	
		lines=response.splitlines()
		#extract SMSUB messages
		for line in lines:
			if '+SMSUB:' in line:
				line = line.replace('"', '')
				if line.count("/")<2:
					log_text = f"{datetime.now(pytz.utc).strftime('%Y-%m-%d %H:%M:%S')}|ALL|NET|SUBSCRIBE|{line}|ERR\n"
					with open(LOG, "a") as file:
						file.write(log_text)
					break
				pair_site = line.rsplit('/', 2)[1]
				tmp = line.rsplit('/', 2)[2]
				topic = tmp.split(',', 1)[0]
				message=line.split(',')[1]
				if 'request' in line:
					log_text = f"{datetime.now(pytz.utc).strftime('%Y-%m-%d %H:%M:%S')}|{pair_site}|{topic}|{message}|ON_SERVER|OK\n"
					with open(LOG, "a") as file:
						file.write(log_text)
				if 'response' in line:
					log_text = f"{datetime.now(pytz.utc).strftime('%Y-%m-%d %H:%M:%S')}|{pair_site}|{topic}|{message}\n"
					with open(LOG, "a") as file:
						file.write(log_text)
				if 'filter' in line:
					log_text = f"{datetime.now(pytz.utc).strftime('%Y-%m-%d %H:%M:%S')}|{pair_site}|{topic}|{message}\n"
					with open(LOG, "a") as file:
						file.write(log_text)
		#filter out MQTT and FTP messages 
		filtered_lines=[
			line for line in lines
			if '+FTPEXTGET' not in line and 'OK' not in line and '+SMSUB:' not in line and line.strip()
		]
		with open('/home/pi/TRAMONE/wind.txt','w') as file:
			file.write('\n'.join(filtered_lines)+'\n')
		if err==False:
			with open(LOG, "a") as file:
				file.write(f"{datetime.now(pytz.utc).strftime('%Y-%m-%d %H:%M:%S')}|ALL|MAIN|FTP|WIND_DOWNLOAD|OK\n")
		else:
			with open(LOG, "a") as file:
				file.write(f"{datetime.now(pytz.utc).strftime('%Y-%m-%d %H:%M:%S')}|ALL|MAIN|FTP|WIND_DOWNLOAD|ERR\n")
	return err



def subscribe_to_log():
	lines = response.splitlines()
	for line in lines:
		if '+SMSUB:' in line:
			line = line.replace('"', '')
			if line.count("/")<2:
				log_text = f"{datetime.now(pytz.utc).strftime('%Y-%m-%d %H:%M:%S')}|ALL|SUBSCRIBE|LINE|{line}|ERR\n"
				with open(LOG, "a") as file:
					file.write(log_text)
				break
			#if 'request' in line:
			#	log_text = f"{datetime.now(pytz.utc).strftime('%Y-%m-%d %H:%M:%S')}|{pair_site}|{topic}|{message}|RECEIVED|OK\n"
			#	with open(LOG, "a") as file:
			#		file.write(log_text)
			if 'response' in line:
				pair_site = line.rsplit('/', 2)[1]
				tmp = line.rsplit('/', 2)[2]
				topic = tmp.split(',', 1)[0]
				message=line.split(',')[1]
				log_text = f"{datetime.now(pytz.utc).strftime('%Y-%m-%d %H:%M:%S')}|{pair_site}|{topic}|{message}\n"
				with open(LOG, "a") as file:
					file.write(log_text)
			if 'filter' in line:
				pair_site = line.rsplit('/', 2)[1]
				tmp = line.rsplit('/', 2)[2]
				topic = tmp.split(',', 1)[0]
				message=line.split(',')[1]
				log_text = f"{datetime.now(pytz.utc).strftime('%Y-%m-%d %H:%M:%S')}|{pair_site}|{topic}|{message}||OK\n"
				with open(LOG, "a") as file:
					file.write(log_text)
	return response


def sampling_time():
	for pair in pairs:
		for site in sites:
			for sampler in [0, 1]:
			
				#find the last sampling time reset
				with open(LOG,'r',encoding='utf-8') as file:
					lines=file.readlines()
					reverse_num_line=-1
					for line in reversed(lines):
						reverse_num_line=reverse_num_line+1
						if f"|{pair}{site}|filter|{sampler}|" in line:
							break
				start_line=len(lines)-reverse_num_line
				
				tot_sampling_time=0
				line=start_line
				sampling=False
				
				while line<len(lines):
					if f"|{pair}{site}|response|STATE|" in lines[line]:
						if lines[line].split("|STATE|")[1][sampler]=="1":
							start_time=str(lines[line].split('|')[0])
							start_time=int(datetime.strptime(start_time,"%Y-%m-%d %H:%M:%S").timestamp())
							current_sampling_time=0
							sampling=True
							while line<len(lines):
								if f"|{pair}{site}|response|STATE|" in lines[line]:
									if lines[line].split("|STATE|")[1][sampler]=="0":
										end_time=str(lines[line].split('|')[0])
										end_time=int(datetime.strptime(end_time,"%Y-%m-%d %H:%M:%S").timestamp())		
										current_sampling_time=end_time-start_time
										sampling=False
										break
								line=line+1
							tot_sampling_time=tot_sampling_time+current_sampling_time
					line=line+1
				#calculate total time including last unfinished period 
				if sampling==True:
					tot_sampling_time_log=tot_sampling_time+(int(time.time())-start_time)
				else:
					tot_sampling_time_log=tot_sampling_time
				#sampling time to log
				if round(tot_sampling_time/3600)<48:
					with open(LOG, "a") as file:
						file.write(f"{datetime.now(pytz.utc).strftime('%Y-%m-%d %H:%M:%S')}|{pair}{site}|{sampler}|SAMPLING|{round(tot_sampling_time_log/3600,1)}|OK\n")	
				else:
					with open(LOG, "a") as file:
						file.write(f"{datetime.now(pytz.utc).strftime('%Y-%m-%d %H:%M:%S')}|{pair}{site}|{sampler}|SAMPLING|{round(tot_sampling_time_log/3600,1)}|ERR\n")	

		
if __name__=="__main__":
	###################
	#start main loop
	
	#os.system('x-terminal-emulator')
	
	response=""
	last_request_time = {}
	#set last request time
	for pair in pairs:
		for site in sites:
			if not os.path.exists(f'{MQTT_TOPICS_DIR}/TRAMONE/{pair}{site}/request'):
				os.makedirs(os.path.dirname(f'{MQTT_TOPICS_DIR}/TRAMONE/{pair}{site}/request'),exist_ok=True)
				with open(f'{MQTT_TOPICS_DIR}/TRAMONE/{pair}{site}/request', 'w') as f:
					f.write('')
			last_request_time[(pair,site)] = os.path.getmtime(f'{MQTT_TOPICS_DIR}/TRAMONE/{pair}{site}/request')
	#wind file creation time set to zero
	FTPMDTM_prev=0
	err_count=0
	err=True
	while err==True:
		err=init_GSM()
		if err==False:
			err=init_MQTT()
		if err==True:
			with open(LOG, "a") as file:
				file.write(f"{datetime.now(pytz.utc).strftime('%Y-%m-%d %H:%M:%S')}|ALL|MAIN|INIT|MQTT|ERR\n")
		else:
			with open(LOG, "a") as file:
				file.write(f"{datetime.now(pytz.utc).strftime('%Y-%m-%d %H:%M:%S')}|ALL|MAIN|INIT|MQTT|OK\n")
	#info on succesfull connection for bash
	with open ("/home/pi/TRAMONE/networking_on","w") as file:
		pass	
	hour_prev=0
	minute_prev=0
	#main loop			
	try:
		while True:
			
			main_program_run_test()

			#last loop time to file
			with open(last_loop_time_file, "w") as file:
				file.write(str(round(datetime.now(pytz.utc).timestamp())))
			
			#check MQTT connection
			ser.write(('AT+SMSTATE?' + '\r').encode())
			time.sleep(1)
			response=ser.read(ser.in_waiting).decode()
			print(response)
			if '+SMSUB:' in response:
				subscribe_to_log()
				err_count=0
				err=False
				#info on succesfull connection for bash
				with open ("/home/pi/TRAMONE/networking_on","w") as file:
					pass
			if not 'SMPUB' in response:
				if '+SMSTATE: 0' in response:
					err=True
					with open(LOG, "a") as file:
						file.write(f"{datetime.now(pytz.utc).strftime('%Y-%m-%d %H:%M:%S')}|ALL|MAIN|MQTT|CONN|ERR\n")
					#if MQTT connection error, try to restart only MQTT and if not success, restart GSM and MQTT
					while err == True:
						print("New init...")
						err=init_MQTT()
						while err==True:
							err=init_GSM()
							if err==False:
								err=init_MQTT()
							if err==True:
								with open(LOG, "a") as file:
									file.write(f"{datetime.now(pytz.utc).strftime('%Y-%m-%d %H:%M:%S')}|ALL|MAIN|INIT|MQTT|ERR\n")
							else:
								with open(LOG, "a") as file:
									file.write(f"{datetime.now(pytz.utc).strftime('%Y-%m-%d %H:%M:%S')}|ALL|MAIN|INIT|MQTT|OK\n")			
			
			
			#check if new wind file present on the server every minute
			minute_now=int(datetime.now(pytz.utc).strftime("%Y%m%d%H%M"))
			if minute_now!=minute_prev:
				err=init_FTP()
				ser.write(('AT+FTPMDTM' + '\r').encode())
				time.sleep(5)
				response=ser.read(ser.in_waiting).decode()
				print(response)
				if '+SMSUB:' in response:
					subscribe_to_log()
				if 'OK' in response and ',63' in response:
					print("FTP server error!!!")
					with open(LOG, "a") as file:
						file.write(f"{datetime.now(pytz.utc).strftime('%Y-%m-%d %H:%M:%S')}|ALL|MAIN|FTP|SERVER|ERR\n")	
					err=True
				if 'OK' in response and not ',66' in response:
					err_count=0
					err=False
					lines=response.splitlines()
					for line in lines:
						if "+FTPMDTM:" in line:
							#if not server error code in response
							if "+FTPMDTM: 1,0" in response:
								parts=line.split(',')
								FTPMDTM=int(datetime.strptime(parts[2],"%Y%m%d%H%M%S").timestamp())
								print(f"Wind file is {int(datetime.now(pytz.utc).timestamp())-FTPMDTM}s old.")
								if int(datetime.now(pytz.utc).timestamp())-FTPMDTM > 15*60:
									with open(LOG, "a") as file:
										file.write(f"{datetime.now(pytz.utc).strftime('%Y-%m-%d %H:%M:%S')}|ALL|MAIN|FTP|WIND_ON_SERVER_OLD|ERR\n")	
									err=True
									break
								if FTPMDTM>FTPMDTM_prev:
									err=True
									while err==True:
										err=wind_download()
									FTPMDTM_prev=FTPMDTM
									#break
							else:
								FTPMDTM=FTPMDTM_prev
								with open(LOG, "a") as file:
									file.write(f"{datetime.now(pytz.utc).strftime('%Y-%m-%d %H:%M:%S')}|ALL|MAIN|FTP|SERVER|ERR\n")	
								err=True
								break
				else:
					FTPMDTM=FTPMDTM_prev
					#count failed connections and restart if they are >3 (approx. three minutes)
					err_count=err_count+1
					if err_count>3:
						err=True
						with open(LOG, "a") as file:
							file.write(f"{datetime.now(pytz.utc).strftime('%Y-%m-%d %H:%M:%S')}|ALL|MAIN|FTP|CONN|ERR\n")	
						#if FTP connection error, try to restart only FTP and if not success, restart GSM and FTP
						while err == True:
							print("New FTP init...")
							err=init_FTP()
							while err==True:
								err=init_GSM()
								if err==False:
									err=init_MQTT()
									if err==False:
										err=init_FTP()
								if err==True:
									with open(LOG, "a") as file:
										file.write(f"{datetime.now(pytz.utc).strftime('%Y-%m-%d %H:%M:%S')}|ALL|MAIN|INIT|CONN|ERR\n")
								else:
									with open(LOG, "a") as file:
										file.write(f"{datetime.now(pytz.utc).strftime('%Y-%m-%d %H:%M:%S')}|ALL|MAIN|INIT|CONN|OK\n")		
				minute_prev=minute_now
										
																				
			#check a new request and publish
			for pair in pairs:
				for site in sites:
					current_modification_time_request = os.path.getmtime(f'{MQTT_TOPICS_DIR}/TRAMONE/{pair}{site}/request')
					if current_modification_time_request != last_request_time[(pair,site)]:
						print("New request for "+pair+site)
						if os.path.exists(f'{MQTT_TOPICS_DIR}/TRAMONE/{pair}{site}/request'):
							with open(f'{MQTT_TOPICS_DIR}/TRAMONE/{pair}{site}/request', 'r') as f:
								lines = f.readlines()
								lines = [line.strip() for line in lines]
							if lines:
								for line in lines:
									ser.write((f'AT+SMPUB=TRAMONE/{pair}{site}/request,2,0,0' + '\r').encode())
									time.sleep(0.2)
									#set sampler to idle state if the wind file is old
									if int(datetime.now(pytz.utc).timestamp())-FTPMDTM > 15*60:
										line="00"
										print(f"{datetime.now(pytz.utc).strftime('%Y-%m-%d %H:%M:%S')}|{pair}{site}|request|REPLACED_BY_IDLE|ERR")
										with open(LOG, "a") as file:
											file.write(f"{datetime.now(pytz.utc).strftime('%Y-%m-%d %H:%M:%S')}|{pair}{site}|request|REPLACED_BY_IDLE|ERR\n")	
									ser.write((f'{line}' + '\r').encode())
									time.sleep(5)
									response = ser.read(ser.in_waiting).decode()
									print(response)				
									#response = response.replace('"', '')
									#pair_site = response.rsplit('/', 2)[1]
									#tmp = response.rsplit('/', 2)[2]
									#topic = tmp.split(',', 1)[0]
									#with open(LOG, "a") as file:
									#	file.write(f"{datetime.now(pytz.utc).strftime('%Y-%m-%d %H:%M:%S')}|{pair_site}|{topic}|{line}|IS_ON_SERVER|OK\n")
						last_request_time[(pair,site)] = current_modification_time_request
						
						
			#log messages arrived during main loop
			response=ser.read(ser.in_waiting).decode()
			if '+SMSUB:' in response:
				subscribe_to_log()
			
			#log backup
			with open(LOG, "r") as file:
				lines=file.readlines()
			line_count=len(lines)
			if line_count>1000000:
				with open(LOG, "r") as file_old:
					content=file_old.read()
				timestamp=datetime.now(pytz.utc).strftime("%Y%m%d_%H%M%S")
				base,ext=os.path.splitext(LOG)
				with open(f"{base}_{timestamp}{ext}", "w") as file_new:
					file_new.write(content)
				with open(LOG, "w") as file_old:
					pass
			
			#hourly log sampling time since filter replacement
			hour_now=int(datetime.now(pytz.utc).strftime("%Y%m%d%H"))
			if hour_now!=hour_prev:
				sampling_time()
				hour_prev=hour_now
	
			#longer loop time to limit FTP server load
			time.sleep(3)
			
	except KeyboardInterrupt:
	    pass
	    
	ser.close()
	GPIO.cleanup()


