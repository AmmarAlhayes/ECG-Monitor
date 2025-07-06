#include <BluetoothSerial.h>
BluetoothSerial SerialBT;



void setup() {
  Serial.begin(115200);
  SerialBT.begin("ECG_Monitor"); // Name that appears in Bluetooth list
  pinMode(A0, INPUT);
}

void loop() {
  int ecgValue = analogRead(A0); 
  SerialBT.println(ecgValue);        // Send ECG value over Bluetooth
  delay(10);                         // ~100Hz sample rate
}
