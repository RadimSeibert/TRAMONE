#define TINY_GSM_MODEM_SIM800
#include <SoftwareSerial.h>
#include <TinyGsmClient.h>
#include <PubSubClient.h>
#include <avr/wdt.h>
#include <OneWire.h>

#define apn "internet.t-mobile.cz" 
#define user ""
#define password ""
#define mqtt_server "mqtt.eclipseprojects.io"
#define mqtt_port 1883
SoftwareSerial gsmSerial(7, 8); // RX, TX
#define GSM_RST 4
#define SAMPLER_0_CTRL_1 2
#define SAMPLER_0_CTRL_2 3
#define SAMPLER_1_CTRL_1 5
#define SAMPLER_1_CTRL_2 6
#define ONE_WIRE_BUS 11
#define HEATING 12

String message = "";
const char* topic_request="TRAMONE/1A/request";
const char* topic_response="TRAMONE/1A/response";
boolean test_sampler_0;
boolean test_sampler_1;
boolean request_sampler_0=false;
boolean request_sampler_1=false;
boolean messageReceived = false;
const int num_readings=500;
// DS18B20 sensors:
byte addr1[8];
byte addr2[8];
boolean temp_in_error=false;
boolean temp_out_error=false;
float PUMP_SENSOR_0;
float PUMP_SENSOR_1;
long int last_msg_time;
boolean heating=false;
boolean main_loop=false;

TinyGsm modem(gsmSerial);
TinyGsmClient gsmClient(modem);
PubSubClient client(gsmClient);
OneWire ds(ONE_WIRE_BUS);

void reconnect(long int starttime) {
  while (!client.connected()) {
    wdt_reset();   
    Serial.print(F("Connecting to MQTT..."));
    if (client.connect("TRAMONE_CLIENT_1A")) {
      Serial.println(F("OK"));
      client.subscribe(topic_request);
    } else {
      Serial.print(F("failed, rc="));
      Serial.print(client.state());
      Serial.println(F(" try again in 5 seconds"));
      delay(5000);
      wdt_reset(); 
    }
    if (millis()-starttime>60000) {
      Serial.println(F("Connection timeout. Reboting..."));
      while(true);
      //asm volatile ("jmp 0x0000");
    }
  }
}

void callback(char* topic_request, byte* payload, unsigned int length) {
  Serial.print(F("Message arrived ["));
  Serial.print(topic_request);
  Serial.print("] ");
  messageReceived=true;
  payload[length] = '\0'; // Přidání ukončovacího znaku
  message = (char*)payload;
  Serial.println(message);
}


void PUMP_SENSOR_read(byte pin, float &pump_sens, boolean &test_sampler)
{  
  long sum=0;
  for (byte max_i=0;max_i<10; max_i++)
  {  
    long max=0;
    for (int i=0; i<num_readings; i++)
    {
      long value=analogRead(pin);
      if (value>max)
      {
        max=value;      
      }
    }
    sum=sum+max;
    delay(100);
  }
  pump_sens=sum/10;
  wdt_reset(); 

  if (pump_sens>700) 
  {
    test_sampler=true;
  }
  else if (pump_sens<600) 
  {
    test_sampler=false;
  }

}


void sampler_start(byte CTRL_1,byte CTRL_2)
{
      digitalWrite(CTRL_1, LOW);
      delay(1000);
      digitalWrite(CTRL_1, HIGH);
      delay(3000);
      wdt_reset();
      digitalWrite(CTRL_1, LOW);
      delay(250);
      digitalWrite(CTRL_1, HIGH);
      delay(3000);
      wdt_reset();
      digitalWrite(CTRL_2, LOW);
      delay(250);
      digitalWrite(CTRL_2, HIGH);
      delay(3000);
      digitalWrite(CTRL_1, LOW);
      delay(250);
      digitalWrite(CTRL_1, HIGH);
      delay(4000);
      wdt_reset();
      digitalWrite(CTRL_1, LOW);
      delay(250);
      digitalWrite(CTRL_1, HIGH);
      delay(1000); 
      wdt_reset();  
}

void sampler_stop(byte CTRL_1)
{
      digitalWrite(CTRL_1, LOW);
      wdt_reset();
      delay(5000);
      wdt_reset();
      delay(5000);
      wdt_reset();
      digitalWrite(CTRL_1, HIGH);
      delay(1000);
      wdt_reset();
}


float readTemperature(byte addr[8]) {
  byte data[9];
  ds.reset();
  ds.select(addr);
  ds.write(0x44, 1);        // Start conversion, with parasite power on at the end
  delay(1000);              // Wait for conversion to complete
  ds.reset();
  ds.select(addr);
  ds.write(0xBE);           // Read Scratchpad
  for (int i = 0; i < 9; i++) {  // We need 9 bytes
    data[i] = ds.read();
  }
  // Convert the data to actual temperature
  int16_t raw = (data[1] << 8) | data[0];
  return (float)raw / 16.0;
}


void temp_and_heat() {
  float temp_in = readTemperature(addr1);
  float temp_out = readTemperature(addr2);
  Serial.print(F("Temp in: "));
  Serial.print(temp_in);
  Serial.println(F(" °C"));
  Serial.print(F("Temp out: "));
  Serial.print(temp_out);
  Serial.println(F(" °C"));
  if (main_loop=true) {
    client.publish(topic_response, reinterpret_cast<const uint8_t*>(("TEMP|"+String(temp_in, 2)+"|"+String(temp_out, 2)+"     ").c_str()),18,false);
    wdt_reset();
  }

  if (temp_in_error==false && temp_out_error==false) {
    // heating controll with hysteresis
    if ( (temp_in<25 && (temp_in-temp_out)<2)  || temp_in<5 ) {
      //heating start
      digitalWrite(HEATING, HIGH); //aktivní v HIGH
      if (heating==false && main_loop==true) {
        client.publish(topic_response, reinterpret_cast<const uint8_t*>("HEAT|ON|OK"),10,false);
        wdt_reset();
      }
      heating=true;
    }
    if ( (temp_in>7 && (temp_in-temp_out)>2.5) || temp_in>27 ) {
      //heating stop
      digitalWrite(HEATING, LOW);
      if (heating==true && main_loop==true) {
        client.publish(topic_response, reinterpret_cast<const uint8_t*>("HEAT|OFF|OK"),11,false);
        wdt_reset();
      }
      heating=false;
    }
  }
}


void setup() {

  wdt_enable(WDTO_8S);

  //init controll pins of sampler 0
  pinMode(SAMPLER_0_CTRL_1, OUTPUT);
  pinMode(SAMPLER_0_CTRL_2, OUTPUT);
  digitalWrite(SAMPLER_0_CTRL_1, HIGH);
  digitalWrite(SAMPLER_0_CTRL_2, HIGH);

  //init controll pins of sampler 1
  pinMode(SAMPLER_1_CTRL_1, OUTPUT);
  pinMode(SAMPLER_1_CTRL_2, OUTPUT);
  digitalWrite(SAMPLER_1_CTRL_1, HIGH);
  digitalWrite(SAMPLER_1_CTRL_2, HIGH);

  //init input pins of sampler 0 an sampler 1 Pump sensors
  pinMode(A0, INPUT);
  pinMode(A1, INPUT);

  //init heating pin
  pinMode(HEATING, OUTPUT);
  digitalWrite(HEATING, LOW);  

  Serial.begin(9600);

// temp sensors init
   if (!ds.search(addr1)) {
    Serial.println(F("No more addresses or error."));
    temp_in_error=true;
  }
  if (!ds.search(addr2)) {
    Serial.println(F("No more addresses or error."));
    temp_out_error=true;
  }
  // Ověření adres pomocí CRC
  if (OneWire::crc8(addr1, 7) != addr1[7] || addr1[0] != 0x28) {
    Serial.println(F("Invalid address for sensor 1"));
    temp_in_error=true;
  }
  if (OneWire::crc8(addr2, 7) != addr2[7] || addr2[0] != 0x28) {
    Serial.println(F("Invalid address for sensor 2"));
    temp_out_error=true;
  }
  Serial.println(F("Sensors initialized"));
  wdt_reset(); 

  //reset GSM
  pinMode(GSM_RST, OUTPUT);
  digitalWrite(GSM_RST, LOW);
  delay(1500);
  digitalWrite(GSM_RST, HIGH);
  delay(2000);
  gsmSerial.begin(9600);
  delay(1000);
  wdt_reset(); 
  gsmSerial.println("AT");
  String gsm_message="";
  while (gsmSerial.available()) {
    char c = gsmSerial.read();
    gsm_message += c;
  }
  Serial.println(gsm_message);
  delay(500);
  
  // Připojení k síti
  long int starttime=millis();
  Serial.print(F("Connecting to network..."));
  while (!modem.waitForNetwork()) {
    temp_and_heat();
    if (millis()-starttime>30000) {
      while (true);
      }
    else {
      wdt_reset();
    }    
  }
  Serial.println(F("OK"));

  // Připojení k GPRS
  Serial.print(F("Connecting to GPRS..."));
  starttime=millis();
  wdt_reset();
  while (!modem.gprsConnect(apn, user, password)) {
    temp_and_heat();
    if (millis()-starttime>10000) {
      while (true);
    }
    else {
      wdt_reset();
    }
  }
  Serial.println(F("OK"));

  wdt_enable(WDTO_8S);
  
  // Nastavení MQTT serveru a callback funkce
  client.setServer(mqtt_server, mqtt_port);
  wdt_reset(); 
  client.setCallback(callback);
  client.setKeepAlive(60);
  client.loop(); 
  client.publish(topic_response, reinterpret_cast<const uint8_t*>("STATUS|REBOOT|OK"),16,false);
  wdt_reset(); 

  last_msg_time=millis();

}
// konec setup()


  


void loop() {
 main_loop=true;
 wdt_reset();
 if (!modem.isNetworkConnected()) {
    while(true);
    //asm volatile ("jmp 0x0000")
  }
  
  wdt_reset();
  client.loop(); 
  if (!client.connected()) {
    long int starttime=millis();
    reconnect(starttime);
    wdt_reset();
  }  

  if (messageReceived)
  {
    last_msg_time=millis();
  }
  
  if (messageReceived && message!="99")
  {
    // char to boolean for evaluating conditions
    request_sampler_0 = (message.charAt(0) == '1');
    request_sampler_1 = (message.charAt(1) == '1');
    Serial.println(F("A new request detected"));
    Serial.println("ACCEPT|"+message);
    client.publish(topic_response, reinterpret_cast<const uint8_t*>(("ACCEPT|"+message+"|OK").c_str()),12 , false);
    messageReceived=false;
  }

  if (millis()-last_msg_time>180000)
  {
    //connection error, reboot by watchdog
    while(true);
  }

  wdt_reset();

// ***************************
// sampler pump operation read
  PUMP_SENSOR_read(A0,PUMP_SENSOR_0,test_sampler_0);
  PUMP_SENSOR_read(A1,PUMP_SENSOR_1,test_sampler_1);  
  client.publish(topic_response, reinterpret_cast<const uint8_t*>(("PUMP|"+String(PUMP_SENSOR_0, 0)+"|"+String(PUMP_SENSOR_1, 0)+"     ").c_str()),15,false);
  wdt_reset();
// end sampler pump operation test
// *******************************
    
   


      
    //startovací sekvence pro sampler 0:
    if ((request_sampler_0 == true) && (test_sampler_0==false))
    {
      client.publish(topic_response, reinterpret_cast<const uint8_t*>("EXEC|0|ON"),9, false);
      Serial.println(F("Sampler 0 switching on..."));
      sampler_start(SAMPLER_0_CTRL_1,SAMPLER_0_CTRL_2);
      Serial.println(F("Sampler switching on finished"));
    }
    //vypínací sekvence pro sampler 0:
    if ((request_sampler_0 == false) && (test_sampler_0==true))
    {
      client.publish(topic_response,  reinterpret_cast<const uint8_t*>("EXEC|0|OFF"),10, false);
      Serial.println(F("Sampler switching off..."));
      sampler_stop(SAMPLER_0_CTRL_1);
      Serial.println(F("Sampler switching off finished"));
    }

    //startovací sekvence pro sampler 1:
    if ((request_sampler_1==true) && (test_sampler_1==false) )
    {
      client.publish(topic_response, reinterpret_cast<const uint8_t*>("EXEC|1|ON"),9, false);
      Serial.println(F("Sampler 1 switching on..."));
      sampler_start(SAMPLER_1_CTRL_1,SAMPLER_1_CTRL_2);
      Serial.println(F("Sampler switching on finished"));
    }
    //vypínací sekvence pro sampler 1:
    if ((request_sampler_1==false) && (test_sampler_1==true))
    {
      client.publish(topic_response, reinterpret_cast<const uint8_t*>("EXEC|1|OFF"),10, false);
      Serial.println(F("Sampler switching off..."));
      sampler_stop(SAMPLER_1_CTRL_1);
      Serial.println(F("Sampler switching off finished"));
    }

    PUMP_SENSOR_read(A0,PUMP_SENSOR_0,test_sampler_0);
    PUMP_SENSOR_read(A1,PUMP_SENSOR_1,test_sampler_1);  

    String response_sampler0 = test_sampler_0 ? "1" : "0"; 
    String response_sampler1 = test_sampler_1 ? "1" : "0";   
    if ((request_sampler_0 == test_sampler_0) && (request_sampler_1 == test_sampler_1))
    {  
      client.publish(topic_response, reinterpret_cast<const uint8_t*>(("STATE|"+response_sampler0+response_sampler1+"|OK").c_str()), 11, false);
      Serial.println("STATE_"+response_sampler0+response_sampler1);
    }
    else
    {
      client.publish(topic_response, reinterpret_cast<const uint8_t*>(("STATE|"+response_sampler0+response_sampler1+"|ERROR").c_str()), 14, false);
      Serial.println("STATE_"+response_sampler0+response_sampler1);
    }


  temp_and_heat();
  
  wdt_reset();
  delay(4000); 
  wdt_reset();
  delay(4000); 
  
}
