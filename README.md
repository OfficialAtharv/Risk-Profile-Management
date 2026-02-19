# speed_monitor_flutter

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Lab: Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Cookbook: Useful Flutter samples](https://docs.flutter.dev/cookbook)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

🚗 Speed Monitor – Flutter GPS Speed Tracking App

A modern Flutter-based mobile application that tracks live vehicle speed using GPS, detects overspeeding, and sends automated alerts with location details. Built with Firebase Authentication and designed with a premium animated UI.

📱 Overview

Speed Monitor is a real-time vehicle speed tracking application that:

Tracks live speed using GPS

Detects overspeeding (configurable limit – default 60 km/h)

Sends automatic email alerts with:

GPS coordinates

Google Maps link

Stores trip history in Firebase (user-specific)

Uses Firebase Authentication for secure login/signup

Provides a modern animated UI with bottom navigation

🚀 Features
🔐 Authentication

Firebase Email/Password Authentication

Auto login using AuthWrapper

Secure user session handling

📡 Live Speed Monitoring

Real-time speed tracking using Geolocator

Smooth UI updates

Bottom navigation layout

🚨 Overspeed Detection

Configurable speed limit (default: 60 km/h)

Audio alert system

Text-to-Speech alert

Automatic email notification with location

🧾 Trip History

Start/Stop trip functionality

Trip data stored in Firebase Firestore

User-specific trip history display

Timestamped trip records

🎨 UI/UX

Glassmorphism login design

Gradient buttons

Animated logo

Clean bottom navigation structure

Smooth transitions

🏗 Tech Stack

Flutter (Latest Stable)

Firebase Authentication

Firebase Firestore

Geolocator

Geocoding

Mailer

🎯 Current Status

✔ Authentication fully working
✔ Firebase connected
✔ Live speed tracking integrated
✔ Trip history storage implemented
✔ Overspeed detection working
✔ Email alert system integrated
✔ App builds successfully

⚠️ Known Improvements (Planned)

Improve dashboard speedometer UI

Add cooldown logic to prevent email spam

Optimize performance (frame drop improvements)

Upgrade:

Gradle

Android Gradle Plugin

Kotlin version

Add analytics dashboard

📸 Screenshots
<img width="720" height="1600" alt="image" src="https://github.com/user-attachments/assets/4d45ec56-dcf4-4ec4-8588-10eb2fa9db36" />
<img width="720" height="1600" alt="image" src="https://github.com/user-attachments/assets/aec96a7a-5aed-432a-bfcd-d374411f29ca" />
<img width="720" height="1600" alt="image" src="https://github.com/user-attachments/assets/258f7163-0789-420c-b69e-e48d80bd4bfb" />

Audioplayers

Flutter TTS
