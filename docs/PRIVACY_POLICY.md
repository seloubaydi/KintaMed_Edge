# Privacy Policy for KintaMed Edge 🛡️

**Last Updated: January 23, 2026**

KintaMed Edge is committed to protecting the privacy and security of patient data handled by Community Health Workers (CHWs). This Privacy Policy explains our "Zero-Cloud" data philosophy and how we ensure absolute confidentiality in the field.

---

## 1. Zero-Cloud Data Philosophy
KintaMed Edge is an **offline-first** application. **We do not collect, transmit, or store any data on external servers, cloud providers, or third-party databases.** 

Everything you input into the app stays on the physical device where the app is installed.

## 2. Data We Process Locally
To provide clinical decision support, the app processes the following data exclusively on your device:
- **Patient Demographics**: Name, age, gender, Date of Birth.
- **Clinical Data**: Vital signs (BP, SpO2, Heart Rate, etc.), symptoms, and medical history.
- **Clinical Media**: Photos of wounds, rashes, or diagnostic images.
- **Voice Recordings**: Temporary audio processing for speech-to-text conversion.

## 3. Data Security & Encryption
All data stored on the device is protected by **SQLCipher**, providing military-grade (AES-256) encryption. This ensures that even if the physical device is lost or stolen, patient information cannot be accessed without the authorized application credentials.

## 4. Required Permissions
The app requests specific permissions to function in the field:
- **Camera**: To capture clinical images for AI analysis.
- **Microphone**: To enable hands-free symptom recording.
- **Storage/File System**: To store the MedGemma AI model weights (~3GB) and encrypted local database.

## 5. Third-Party Access
There is **no third-party access** to your data. Because the app does not connect to the internet for its core functions, no data can be shared with advertisers, analytics providers, or government agencies.

## 6. Data Retention
Data is retained on your device until you manually delete an assessment or clear the app data. Users are responsible for performing periodic data purges according to their local healthcare organization's protocols.

## 7. Contact
For questions regarding the technical implementation of this privacy policy, please contact the development team at our repository.

---
**Note**: By using KintaMed Edge, you acknowledge that you are responsible for the physical security of the device and the confidentiality of any patient data displayed on the screen.
