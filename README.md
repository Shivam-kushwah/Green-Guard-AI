# 🌱 Green-Guard-AI  
### Plant Disease Detection using Flutter + TensorFlow Lite

Green-Guard-AI is a mobile application designed to detect plant leaf diseases using a trained **TensorFlow Lite (.tflite)** model.  
This project combines **Flutter (frontend)** + **Python ML model training** to deliver fast, offline, on-device plant disease classification.

---

## 🚀 Features

- 🌿 Real-time plant disease detection  
- 📱 Flutter-based modern UI  
- ⚡ Offline TensorFlow Lite model inference (no internet needed)  
- 🧠 Multi-class image classification  
- 🖼 Supports camera + gallery images  
- 📂 Saves history of previous scans  

---

## 📁 Project Structure

Green-Guard-AI/
│
├── CODE/
│ ├── frontend/ # Flutter Mobile App
│ └── Model-Training/ # Python Model Training Code
│
├── DATA-SET/ (ignored) # Dataset (not uploaded to GitHub)
│
├── DOCUMENTATION/ # Reports, notes, diagrams
│
├── SampleTest/ # Sample leaf images for testing
│
└── .gitignore



---

## 🌾 Dataset  
The dataset is **not included** in this GitHub repo because of large size (≈2GB+).

👉 **Dataset Download Link:**  
(Insert your Google Drive / Mega link here)

Structure example:

DATA-SET/
Train/
Healthy_generic/
Rust_generic/
TRAIN_Corn__Gray_Leaf_Spot/
TRAIN_Wheat__Yellow_Rust/
...


---

## 🧠 Model Training (Python)

ML model training files:

CODE/Model-Training/
├── Model_Trainer.py
├── class_mapping.json
└── plant_disease_model.tflite (generated)


### Libraries Used:
- TensorFlow / Keras  
- NumPy  
- Matplotlib  
- Image preprocessing & augmentation  

Model outputs class label + confidence probability.

---

## 📱 Running the Flutter App

### Step 1 — Clone the repository

git clone https://github.com/Shivam-kushwah/Green-Guard-AI.git
cd Green-Guard-AI/CODE/frontend

### Step 2 — Install dependencies

flutter pub get

### Step 3 — Run the app

flutter run

### 🧪 Testing

Use the provided test image:
SampleTest/leaf.JPG
