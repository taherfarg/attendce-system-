# Flutter App Structure

This document outlines the planned directory structure for the "Smart Attendance System" Flutter app.

```
lib/
├── main.dart                  # Entry point
├── app.dart                   # Material App configuration, Routes, Theme
├── core/                      # Core utilities and services
│   ├── constants/             # App-wide constants (colors, text styles)
│   ├── error/                 # Custom error handling (Failures, Exceptions)
│   ├── services/
│   │   ├── auth_service.dart  # Supabase Auth wrapper
│   │   ├── location_service.dart # Geolocator logic checks
│   │   ├── wifi_service.dart  # Network info logic checks
│   │   └── supabase_client.dart # Singleton Supabase client
│   └── utils/                 # Helpers (Date formatters, validators)
├── data/                      # Data layer (Repositories, Models)
│   ├── models/
│   │   ├── user_model.dart
│   │   ├── attendance_model.dart
│   │   └── face_profile_model.dart
│   └── repositories/
│       ├── auth_repository.dart
│       ├── attendance_repository.dart
│       └── face_repository.dart
├── domain/                    # Domain layer (Entities, UseCases - Optional for MVP but good for clean arch)
│   ├── entities/
│   └── usecases/
├── presentation/              # UI Layer
│   ├── common_widgets/        # Reusable widgets (Buttons, Inputs)
│   ├── pages/
│   │   ├── splash_page.dart
│   │   ├── login_page.dart
│   │   ├── home/
│   │   │   ├── home_page.dart # Main dashboard for Employee
│   │   │   └── admin_home_page.dart # Main dashboard for Admin
│   │   ├── attendance/
│   │   │   ├── face_scan_page.dart # Camera view for face detection
│   │   │   └── check_in_result_page.dart
│   │   └── profile/
│   │       └── enrollment_page.dart # Face registration
│   └── state_management/      # Providers/Blocs (e.g., AuthProvider, AttendanceProvider)
```
