// =====================================================================
// HARDWARE SELF-TEST: MFRC522 reader + buzzer  (ESP8266, NO WiFi)
// =====================================================================
// Flash this FIRST to verify the hardware before the full attendance sketch.
// It: beeps twice at boot, prints the reader's firmware version (proves SPI
// wiring), then on each card tap prints the UID + block-1 text and beeps once.
//
// Open Serial Monitor @ 9600.
//
// IMPORTANT pin note: the buzzer is on D2 (GPIO4), NOT D8. D8 = GPIO15 must be
// LOW at boot — a buzzer there can stop the ESP8266 from booting (the classic
// "nothing happens, no serial" symptom).
// =====================================================================

#include <SPI.h>
#include <MFRC522.h>

// SAFE pins: avoid GPIO0(D3), GPIO2(D4), GPIO15(D8) for the reader — they are
// boot-strapping pins and a wired peripheral on them can stop the ESP booting
// (continuous serial garbage / reset loop).
#define RST_PIN D1   // GPIO5  (safe)
#define SS_PIN  D2   // GPIO4  (safe)
#define BUZZER  D8   // GPIO15 (idle-low buzzer is boot-safe)

MFRC522 mfrc522(SS_PIN, RST_PIN);
MFRC522::MIFARE_Key key;

void beep(int times) {
  for (int i = 0; i < times; i++) {
    tone(BUZZER, 2700);
    delay(120);
    noTone(BUZZER);
    delay(100);
  }
  digitalWrite(BUZZER, LOW);
}

void setup() {
  Serial.begin(9600);
  delay(400);
  Serial.println();
  Serial.println("=== RFID + BUZZER SELF TEST ===");

  pinMode(BUZZER, OUTPUT);
  Serial.println("Buzzer test: you should hear 2 beeps now...");
  beep(2);

  SPI.begin();
  mfrc522.PCD_Init();
  delay(50);

  byte v = mfrc522.PCD_ReadRegister(mfrc522.VersionReg);
  Serial.print("MFRC522 firmware version: 0x");
  Serial.println(v, HEX);
  if (v == 0x00 || v == 0xFF) {
    Serial.println("** READER NOT DETECTED **");
    Serial.println("   Check: 3.3V power (NOT 5V), SDA->D4, SCK->D5, MOSI->D7,");
    Serial.println("   MISO->D6, RST->D3, GND->GND. Re-seat jumper wires.");
  } else {
    Serial.println("Reader OK (0x91/0x92 = genuine, 0x12/0x88/other = clone).");
    Serial.println("Tap a card now.");
  }

  for (byte i = 0; i < 6; i++) key.keyByte[i] = 0xFF;  // default MIFARE key
}

void loop() {
  if (!mfrc522.PICC_IsNewCardPresent() || !mfrc522.PICC_ReadCardSerial()) return;

  Serial.print("Card UID:");
  for (byte i = 0; i < mfrc522.uid.size; i++) {
    Serial.print(mfrc522.uid.uidByte[i] < 0x10 ? " 0" : " ");
    Serial.print(mfrc522.uid.uidByte[i], HEX);
  }
  Serial.println();
  beep(1);

  // Try to read block 1 (where the attendance SRN lives).
  byte buf[18];
  byte len = 18;
  MFRC522::StatusCode st = mfrc522.PCD_Authenticate(
      MFRC522::PICC_CMD_MF_AUTH_KEY_A, 1, &key, &(mfrc522.uid));
  if (st == MFRC522::STATUS_OK) {
    st = mfrc522.MIFARE_Read(1, buf, &len);
    if (st == MFRC522::STATUS_OK) {
      buf[16] = '\0';
      Serial.print("Block 1 text: \"");
      Serial.print((char*)buf);
      Serial.println("\"");
    } else {
      Serial.println("Block 1 read failed.");
    }
  } else {
    Serial.println("Auth failed — blank/locked card, or not MIFARE Classic.");
  }

  mfrc522.PICC_HaltA();
  mfrc522.PCD_StopCrypto1();
  delay(1500);
}
