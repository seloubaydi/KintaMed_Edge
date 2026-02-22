# KintaMed Edge 🏥 ⚡️

[![Flutter](https://img.shields.io/badge/Flutter-%2302569B.svg?style=flat&logo=Flutter&logoColor=white)](https://flutter.dev/)
[![AI-Powered](https://img.shields.io/badge/AI--Powered-MedGemma%201.5-blueviolet.svg?style=flat)](https://huggingface.co/eloubaydi/medgemma-1.5-ort-standard)
[![Offline First](https://img.shields.io/badge/Offline--First-Local%20Inference-green.svg?style=flat)](https://github.com/google/gemma.cpp)
[![Security](https://img.shields.io/badge/Security-SQLCipher%20Encrypted-red.svg?style=flat)](https://www.zetetic.net/sqlcipher/)

**KintaMed Edge** is an offline-first, AI-powered diagnostic and triage assistant designed for **Community Health Workers (CHWs)** operating in remote areas, disaster zones, and conflict regions where internet connectivity is non-existent.

---

## 🌍 The Mission

### The Problem
In rural regions or field hospitals, specialist doctors are scarce. Frontline health workers often lack the advanced clinical expertise required to differentiate between routine ailments and critical conditions that require immediate medical evacuation.

### The Solution: Medical Intelligence at the Edge
KintaMed Edge brings the power of **Google's MedGemma 1.5** directly to consumer-grade tablets and laptops. By performing all AI inference locally, the app provides clinical decision support without requiring a single byte of data to leave the device.

---

## ⚖️ Legal & Privacy

Before deployment, please review the following:
- [**Privacy Policy**](docs/PRIVACY_POLICY.md) - Our "Zero-Cloud" and encryption standards.
- [**Terms of Service**](docs/TERMS_OF_SERVICE.md) - Mandatory expert approval and limitation of liability.

---

## ✨ Key Features

- 🧠 **Offline Medical AI**: Uses a quantized version of **MedGemma 1.5** for on-device clinical reasoning.
- 🚦 **Intelligent Triage**: Automatically suggests a triage category (**Red**, **Yellow**, **Green**) based on vital signs and symptoms.
- 📸 **Visual Intelligence**: Multimodal capabilities allow workers to attach photos (wounds, rashes, X-rays) for AI-driven clinical analysis.
- 📄 **PDF Report Generation**: Instant generation of clinical summaries for sharing via Bluetooth or physical hand-off during evacuations.
- 🔒 **Privacy-First Design**: Local, encrypted database (SQLCipher) ensuring patient data never touches the cloud.


---

## 🏗️ Architecture & Technical Tools

KintaMed Edge is built for resilience and performance on high-end consumer hardware.

### Core Stack
- **Frontend Framework**: [Flutter](https://flutter.dev/) (Cross-platform)
- **State Management**: [Riverpod](https://riverpod.dev/) (`flutter_riverpod`, `riverpod_annotation`)
- **On-Device LLM**: **MedGemma 1.5** (ONNX Runtime Standard) running entirely locally via a custom C++ FFI Bridge (`dart:ffi`) using ONNX Runtime GenAI.
- **Local Database**: SQLite with military-grade encryption using **SQLCipher** (`sqflite_sqlcipher`).

### Key Packages & Capabilities
- **Visual AI Processing**: `image_picker` and `image` for capturing and preprocessing wound/rash photos before sending them to the multimodal vision encoder.
- **PDF Report Generation**: `pdf` and `printing` for generating instant clinical summaries.
- **Data Persistence & State**: `shared_preferences` for fast settings access, synchronized with Riverpod state.
- **Offline Reliability**: `wakelock_plus` to keep the device awake during heavy AI inference.
- **Design & UI**: Premium dark-mode UI optimized for visibility in harsh environments using `flutter_animate` for smooth interactions, `google_fonts`, and `flutter_markdown` for correct rendering of AI clinical outputs.

---

## 🚀 Getting Started

### Prerequisites
- Flutter SDK (>= 3.10.1)
- High-end mobile device or tablet (>8GB RAM recommended for Visual AI capabilities)
- ~3.83GB of free space for MedGemma 1.5 ONNX model weights

### Installation
1.  **Clone the repository**:
    ```bash
    git clone https://github.com/seloubaydi/KintaMed_Edge.git
    ```
2.  **Install dependencies**:
    ```bash
    flutter pub get
    ```
3.  **Run the app**:
    ```bash
    flutter run
    ```

### AI Model Setup
Upon first launch, the app will initialize the **MedGemma 1.5** engine in the background. Model files are downloaded directly from Hugging Face ([eloubaydi/medgemma-1.5-ort-standard](https://huggingface.co/eloubaydi/medgemma-1.5-ort-standard)) and require approximately 3.83GB of storage. The model is persistently loaded and managed via our custom C++ native bridge to ensure responsive triage performance across assessments. Once the model weights are fetched and initialized, the app operates completely offline.

---

## 📖 What it really does & How to use it

**KintaMed Edge** transforms a consumer device into an expert-level medical triage assistant that operates completely independently of the internet or cloud infrastructure. It acts as secondary clinical decision support for frontline workers managing complex cases.

### Step-by-Step Usage:
1.  **Patient Intake**: Open the app and begin a new assessment. The healthcare worker enters basic demographic information and current vital signs (BP, SpO2, Temp, Heart Rate).
2.  **Symptom Collection**: Record the patient's chief complaint and symptoms. This can be typed manually.
3.  **Visual Evidence (Multimodal)**: If the patient presents with physical signs (e.g., a wound, skin rash, or visible trauma), the worker can easily snap a photo or attach an image.
4.  **Local Inference**: The application packages the structured vitals, text symptoms, and visual evidence, formatting a prompt that is seamlessly passed to the on-device MedGemma engine.
5.  **Triage Output & Action Plan**: The AI quickly parses the clinical picture (*without any internet connection*) and outputs a structured response including:
    - **Triage Level**: Recommended categorization (e.g., Red/Immediate, Yellow/Urgent, Green/Delayed) based on standard protocols.
    - **Differential Diagnosis**: Potential causes for the clinical presentation.
    - **Urgent Actions & Treatment Plan**: Next steps to stabilize and treat the patient.
    - **Reasoning**: A clear explanation of *why* the AI made these recommendations, ensuring explainability.
6.  **Report Generation**: The worker can instantly export the complete assessment as an encrypted PDF report for physical hand-off to transport teams or higher-level care facilities.

---

## 🛡️ Ethical Considerations & Safety

**Disclaimer**: *KintaMed Edge is a decision-support tool and does not replace the professional judgment of a healthcare provider.*

- The model is restricted to acting as a consultative assistant and is explicitly instructed to be conservative in its triage recommendations.
- All AI responses provide the "Reasoning" driving the judgment to allow clinical workers to verify the AI's logic.
- The app operates purely offline, maintaining strict patient confidentiality in sensitive and volatile zones.

---

## 📄 Open Source License

[![CC BY 4.0](https://img.shields.io/badge/License-CC%20BY%204.0-blue.svg)](https://creativecommons.org/licenses/by/4.0/deed.en)
---

Developed with ❤️ for the global health community.
