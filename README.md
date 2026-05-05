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


[//]: # ([/soham/]: #)

[//]: # (folder struture for telematics_based : cd /speed_monitor_flutter/telematics_backend$)

[//]: # ()
[//]: # (venv : source venv/bin/activate)

[//]: # ()
[//]: # (run : /home/soham/Android/Sdk/platform-tools/adb devices)

[//]: # (/home/soham/Android/Sdk/platform-tools/adb reverse --list)

[//]: # (/home/soham/Android/Sdk/platform-tools/adb reverse tcp:8001 tcp:8001)

[//]: # (/home/soham/Android/Sdk/platform-tools/adb reverse --list)

[//]: # ()
[//]: # ("&#40;UsbFfs tcp:8001 tcp:8001&#41;")

[//]: # ()
[//]: # (PYTHONPATH=.. python -m uvicorn app.main:app --host 0.0.0.0 --port 8001 --reload)

[//]: # ()
[//]: # ([/soham ]: #)

[//]: # (folder struture for vision_ai :  cd /college/speed_monitor_flutter/vision_backend$)

[//]: # ()
[//]: # (venv : source venv/bin/activate)

[//]: # ()
[//]: # (run : python3 -m uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload)