// Reklamsız deneme başlangıcı: aynı cihaz (uygulamaya özgü ANDROID_ID karması) yeniden kurulsa da
// ilk görülme tarihi korunur. Ham kimlik alınmaz; IP başına günlük istek sınırlıdır.
export async function handleTrial(body, env, deps) {
  const hash = body?.deviceHash;
  if (typeof hash !== 'string' || !/^[a-f\d]{64}$/.test(hash)) return { status: 400, body: { error: 'device_hash' } };
  const now = deps.now ?? new Date();
  const day = now.toISOString().slice(0, 10);
  const ipKey = 'trial-ip:' + (await deps.sha256('ip:' + deps.ip)).slice(0, 24);
  const used = await env.DB.prepare('INSERT INTO assistant_usage (day,bucket,count) VALUES (?,?,1) ON CONFLICT(day,bucket) DO UPDATE SET count=count+1 RETURNING count').bind(day, ipKey).first();
  if (used.count > (Number(env.TRIAL_DAILY_IP) || 30)) return { status: 429, body: { error: 'rate_limited' } };
  // İlk kayıt kazanır: mevcut tarih asla ileri alınmaz.
  await env.DB.prepare('INSERT OR IGNORE INTO trial_devices (hash, first_seen) VALUES (?, ?)').bind(hash, now.toISOString()).run();
  const row = await env.DB.prepare('SELECT first_seen FROM trial_devices WHERE hash = ?').bind(hash).first();
  return { status: 200, body: { firstSeen: row.first_seen } };
}
