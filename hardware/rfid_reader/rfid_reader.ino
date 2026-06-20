// =====================================================================
// RFID fallback attendance reader (ESP8266 + MFRC522)  -- NO LCD version
// =====================================================================
// SUPERVISED FALLBACK ONLY. A card tap has no liveness/face check, so the
// backend records every tap with reason='manual_rfid' (auditable). The teacher
// should hold the reader and tap each student's card while watching them.
//
// The card stores the student's SRN in block 1 (e.g. "R23EF073"). On tap we
// send {secret, room, srn} to the Supabase `rfid_attendance` edge function,
// which resolves the open session for this room and marks the student present.
//
// Feedback without an LCD:
//   - Serial Monitor @ 9600 prints every step + the server response.
//   - Buzzer: 1 short beep on scan, 2 beeps on success, 3 beeps on error.
// =====================================================================

#include <SPI.h>
#include <MFRC522.h>
#include <Arduino.h>
#include <ESP8266WiFi.h>
#include <ESP8266HTTPClient.h>
#include <WiFiClientSecureBearSSL.h>
#include <time.h>

// SAFE pins: avoid GPIO0(D3), GPIO2(D4), GPIO15(D8) for the reader — they are
// boot-strapping pins; a peripheral on them can stop the ESP booting.
#define RST_PIN D1   // GPIO5
#define SS_PIN  D2   // GPIO4
#define BUZZER  D8   // GPIO15 (idle-low buzzer is boot-safe)

MFRC522 mfrc522(SS_PIN, RST_PIN);
MFRC522::MIFARE_Key key;
MFRC522::StatusCode status;

int  blockNum = 1;
byte bufferLen = 18;
byte readBlockData[18];

// ---------- Backend (already pointed at your Supabase project) ----------
// verify_jwt=false on this function -> no apikey/JWT header required; the
// device authenticates with RFID_DEVICE_SECRET. Rotate the secret if leaked.
const String FN_URL      = "https://hxdqkqratnqiouyenvyz.supabase.co/functions/v1/rfid_attendance";
const String RFID_SECRET = "rfid-LH1-3f9Qa72ZxV8m";  // == RFID_DEVICE_SECRET
const String ROOM_CODE   = "LH-1";                    // this reader's room

// >>> EDIT THESE to your network (straight quotes only!) <<<
#define WIFI_SSID     "RoomZone"
#define WIFI_PASSWORD "13572468"

// ---------- Queue (offline-resilient) ----------
struct AttendanceRecord { String srn; };
#define MAX_QUEUE 60
AttendanceRecord queue[MAX_QUEUE];
int queueStart = 0;
int queueEnd = 0;

// ---------- Timers ----------
unsigned long lastUploadAttempt = 0;
unsigned long uploadInterval = 5000;  // retry every 5s
unsigned long lastScanTime = 0;
unsigned long scanCooldown = 2000;    // ignore re-reads of the same card for 2s

// Works for BOTH active and passive buzzers: tone() drives a ~2.7 kHz square
// wave (passive needs a frequency; active sounds on it too).
void beep(int times) {
  for (int i = 0; i < times; i++) {
    tone(BUZZER, 2700);
    delay(90);
    noTone(BUZZER);
    delay(70);
  }
  digitalWrite(BUZZER, LOW);
}

void setup() {
  Serial.begin(9600);
  pinMode(BUZZER, OUTPUT);
  SPI.begin();
  mfrc522.PCD_Init();

  Serial.print("Connecting WiFi");
  WiFi.begin(WIFI_SSID, WIFI_PASSWORD);
  int attempts = 0;
  while (WiFi.status() != WL_CONNECTED && attempts < 30) {
    delay(500); Serial.print("."); attempts++;
  }
  Serial.println();
  if (WiFi.status() == WL_CONNECTED) {
    Serial.println("WiFi connected: " + WiFi.localIP().toString());
    configTime(19800, 0, "pool.ntp.org", "time.nist.gov");  // server stamps the real time anyway
  } else {
    Serial.println("WiFi FAILED");
  }
  Serial.println("Ready. Scan a card.");
}

void loop() {
  if (millis() - lastUploadAttempt >= uploadInterval) {
    if (WiFi.status() == WL_CONNECTED) sendQueuedData();
    lastUploadAttempt = millis();
  }

  // Debounce: don't re-read the same card held on the reader.
  if (millis() - lastScanTime < scanCooldown) return;

  if (mfrc522.PICC_IsNewCardPresent() && mfrc522.PICC_ReadCardSerial()) {
    ReadDataFromBlock(blockNum, readBlockData);
    readBlockData[16] = '\0';                 // null-terminate the 16 data bytes
    String srn = String((char*)readBlockData);
    srn.trim();

    Serial.println("Scanned SRN: " + srn);
    beep(1);
    lastScanTime = millis();

    if (srn.length() > 0 && (queueEnd + 1) % MAX_QUEUE != queueStart) {
      queue[queueEnd] = { srn };
      queueEnd = (queueEnd + 1) % MAX_QUEUE;
      Serial.println("Queued: " + srn + "  (queue=" +
                     String((queueEnd - queueStart + MAX_QUEUE) % MAX_QUEUE) + ")");
    } else {
      Serial.println("Queue full or empty SRN, skipping.");
    }

    mfrc522.PICC_HaltA();
    mfrc522.PCD_StopCrypto1();
  }
}

void sendQueuedData() {
  while (queueStart != queueEnd) {
    String srn = queue[queueStart].srn;

    std::unique_ptr<BearSSL::WiFiClientSecure> client(new BearSSL::WiFiClientSecure);
    client->setInsecure();  // skips cert validation; fine on a trusted LAN
    HTTPClient https;

    String finalUrl = FN_URL + "?secret=" + urlencode(RFID_SECRET) +
                      "&room=" + urlencode(ROOM_CODE) +
                      "&srn="  + urlencode(srn);
    Serial.println("POST " + finalUrl);

    if (https.begin(*client, finalUrl)) {
      int code = https.POST("");          // params are in the query string
      String body = https.getString();
      Serial.printf("HTTP %d: %s\n", code, body.c_str());

      if (code == 200) {
        String name = jsonValue(body, "name");
        Serial.println(">> PRESENT: " + (name.length() ? name : srn));
        beep(2);
        queueStart = (queueStart + 1) % MAX_QUEUE;   // pop on success
      } else if (code == 404) {
        Serial.println(">> UNKNOWN CARD: " + srn);
        beep(3);
        queueStart = (queueStart + 1) % MAX_QUEUE;   // pop (retry won't help)
      } else if (code == 409) {
        Serial.println(">> NO OPEN SESSION — will retry.");
        beep(3);
        https.end();
        break;                                       // keep queued, retry later
      } else {
        Serial.println(">> Upload failed, will retry.");
        https.end();
        break;
      }
      https.end();
    } else {
      Serial.println("HTTPS begin failed");
      break;
    }
    delay(200);
  }
}

void ReadDataFromBlock(int blockNum, byte readBlockData[]) {
  for (byte i = 0; i < 6; i++) key.keyByte[i] = 0xFF;
  status = mfrc522.PCD_Authenticate(MFRC522::PICC_CMD_MF_AUTH_KEY_A, blockNum, &key, &(mfrc522.uid));
  if (status != MFRC522::STATUS_OK) {
    Serial.println("Auth failed");
    return;
  }
  status = mfrc522.MIFARE_Read(blockNum, readBlockData, &bufferLen);
  if (status != MFRC522::STATUS_OK) {
    Serial.println("Read failed");
    return;
  }
}

// Minimal JSON string-value extractor (avoids an ArduinoJson dependency).
String jsonValue(const String& body, const String& key) {
  String needle = "\"" + key + "\":\"";
  int i = body.indexOf(needle);
  if (i < 0) return "";
  i += needle.length();
  int j = body.indexOf('"', i);
  if (j < 0) return "";
  return body.substring(i, j);
}

String urlencode(String str) {
  String encoded = "";
  char c, code0, code1;
  for (unsigned int i = 0; i < str.length(); i++) {
    c = str.charAt(i);
    if (isalnum(c)) {
      encoded += c;
    } else {
      code1 = (c & 0xf) + '0';
      if ((c & 0xf) > 9) code1 = (c & 0xf) - 10 + 'A';
      code0 = ((c >> 4) & 0xf) + '0';
      if (((c >> 4) & 0xf) > 9) code0 = ((c >> 4) & 0xf) - 10 + 'A';
      encoded += '%'; encoded += code0; encoded += code1;
    }
  }
  return encoded;
}
