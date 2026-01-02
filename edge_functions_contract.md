# Edge Functions API Contract

## 1. `verify_attendance`

**Purpose**: Validates face, location, and Wi-Fi before creating an attendance record.

**Method**: `POST`

**Authorization**: `Bearer <user_token>`

**Request Body**:

```json
{
  "user_id": "uuid",
  "face_embedding": [0.12, -0.45, ...], // Array of floats from ML Kit
  "location": {
    "lat": 25.2048,
    "lng": 55.2708
  },
  "wifi_info": {
    "ssid": "Office_Wifi_5G",
    "bssid": "xx:xx:xx:xx:xx:xx"
  },
  "type": "check_in" // or "check_out"
}
```

**Response (Success - 200)**:

```json
{
  "success": true,
  "message": "Check-in successful",
  "data": {
    "attendance_id": "uuid",
    "status": "present",
    "time": "2023-10-27T10:00:00Z"
  }
}
```

**Response (Error - 400/403)**:

```json
{
  "success": false,
  "error": "LOCATION_INVALID", // or "FACE_MISMATCH", "WIFI_INVALID"
  "message": "You are 500m away from the office."
}
```

**Logic Flow**:

1. **Fetch User Profile**: Get stored `face_embedding` for `user_id`.
2. **Face Match**: Calculate Euclidean/Cosine distance between request embedding and stored embedding. If distance > threshold, fail.
3. **Fetch System Settings**: Get `office_location`, `allowed_radius`, `allowed_wifi`.
4. **Location Check**: Calculate distance between `location` and `office_location`. If > `allowed_radius`, fail.
5. **Wi-Fi Check**: Check if `wifi_info.ssid` is in `allowed_wifi` list. If not, fail.
6. **DB Insert**: If all pass, insert into `attendance` table using Service Role (bypassing RLS restriction).

---

## 2. `enroll_face`

**Purpose**: Securely saves the user's face embedding during enrollment.

**Method**: `POST`

**Request Body**:

```json
{
  "user_id": "uuid",
  "face_embedding": [ ... ]
}
```

**Logic**:

1. Check if user already has a profile (optional, or overwrite).
2. Store encrypted or raw embedding in `face_profiles`.
