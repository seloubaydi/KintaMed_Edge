# Datenschutzerklärung für KintaMed Edge 🛡️

**Zuletzt aktualisiert: 23. Januar 2026**

KintaMed Edge verpflichtet sich zum Schutz der Privatsphäre und Sicherheit von Patientendaten, die von kommunalen Gesundheitshelfern (Community Health Workers, CHWs) verarbeitet werden. Diese Datenschutzerklärung erläutert unsere „Zero-Cloud“-Datenphilosophie und wie wir absolute Vertraulichkeit im Außeneinsatz gewährleisten.

---

## 1. Zero-Cloud-Datenphilosophie
KintaMed Edge ist eine **Offline-First**-Anwendung. **Wir sammeln, übertragen oder speichern keine Daten auf externen Servern, bei Cloud-Anbietern oder in Datenbanken Dritter.**

Alles, was Sie in die App eingeben, verbleibt auf dem physischen Gerät, auf dem die App installiert ist.

## 2. Daten, die wir lokal verarbeiten
Um klinische Entscheidungsunterstützung zu bieten, verarbeitet die App die folgenden Daten ausschließlich auf Ihrem Gerät:
- **Patientenstammdaten**: Name, Alter, Geschlecht, Geburtsdatum.
- **Klinische Daten**: Vitalparameter (Blutdruck, SpO2, Herzfrequenz usw.), Symptome und Krankengeschichte.
- **Klinische Medien**: Fotos von Wunden, Hautausschlägen oder diagnostische Bilder.
- **Sprachaufzeichnungen**: Temporäre Audioverarbeitung für die Sprache-zu-Text-Konvertierung.

## 3. Datensicherheit & Verschlüsselung
Alle auf dem Gerät gespeicherten Daten sind durch **SQLCipher** geschützt, das eine Verschlüsselung nach Militärstandard (AES-256) bietet. Dies stellt sicher, dass selbst bei Verlust oder Diebstahl des physischen Geräts nicht ohne die autorisierten Anmeldedaten der Anwendung auf Patienteninformationen zugegriffen werden kann.

## 4. Erforderliche Berechtigungen
Die App fordert spezifische Berechtigungen an, um im Außeneinsatz zu funktionieren:
- **Kamera**: Zur Aufnahme klinischer Bilder für die KI-Analyse.
- **Mikrofon**: Zur freihändigen Aufzeichnung von Symptomen.
- **Speicher/Dateisystem**: Zum Speichern der MedGemma KI-Modellgewichte (~3 GB) und der verschlüsselten lokalen Datenbank.

## 5. Zugriff durch Dritte
Es gibt **keinen Zugriff Dritter** auf Ihre Daten. Da die App für ihre Kernfunktionen keine Verbindung zum Internet herstellt, können keine Daten an Werbetreibende, Analyseanbieter oder Regierungsbehörden weitergegeben werden.

## 6. Datenspeicherung
Daten werden auf Ihrem Gerät gespeichert, bis Sie eine Bewertung manuell löschen oder die App-Daten löschen. Benutzer sind dafür verantwortlich, regelmäßige Datenlöschungen gemäß den Protokollen ihrer lokalen Gesundheitsorganisation durchzuführen.

## 7. Kontakt
Bei Fragen zur technischen Umsetzung dieser Datenschutzerklärung wenden Sie sich bitte an das Entwicklungsteam in unserem Repository.

---
**Hinweis**: Durch die Nutzung von KintaMed Edge erkennen Sie an, dass Sie für die physische Sicherheit des Geräts und die Vertraulichkeit aller auf dem Bildschirm angezeigten Patientendaten verantwortlich sind.
