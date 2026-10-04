-- 7 günlük reklamsız deneme: yeniden kurulumla sıfırlanmasın diye cihaz karmasının ilk görülme zamanı.
-- Ham cihaz kimliği saklanmaz; istemci uygulamaya özgü tuzla SHA-256 gönderir.
CREATE TABLE IF NOT EXISTS trial_devices (hash TEXT PRIMARY KEY, first_seen TEXT NOT NULL);
