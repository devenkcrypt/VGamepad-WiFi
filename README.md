# VGamepad WiFi Controller 🎮📡

VGamepad is a mobile gamepad app that connects to your PC or games via WiFi, giving you **smooth, real-time control** for games and applications. Perfect for testing, gaming, or DIY projects.  

---

## 🚀 Features
- Connects to PC/game through local WiFi  
- Real-time input for multiple buttons & controls  
- Lightweight, fast, and responsive  
- User-friendly mobile interface  
- Works on multiple platforms  

---

## 🛠 Tech Stack
- **Mobile App:** Flutter  
- **Server / Communication:** Node.js + Socket.IO  
- **Real-time Networking:** WebSocket protocol  
- **UI/UX:** Custom buttons and layouts for smooth gameplay  

---

## ⚡ Setup Guide

### 1️⃣ Clone the repository
```bash
git clone https://github.com/username/VGamepad-WiFi.git
cd VGamepad-WiFi


2️⃣ Install server dependencies
cd server
npm install

3️⃣ Run the server
node index.js

4️⃣ Run the mobile app
cd ../mobile-app
flutter pub get
flutter run
