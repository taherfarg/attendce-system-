-- Increase allowed radius to 1000 meters (1 km) to prevent "too far" errors during testing
UPDATE system_settings
SET setting_value = '1000'
WHERE setting_key = 'allowed_radius_meters';

-- Verify the change
SELECT * FROM system_settings WHERE setting_key = 'allowed_radius_meters';
