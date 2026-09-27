# WorkManager'ın Room veritabanı R8 tarafından silinmesin
# (ORTAK_UYGULAMA_STANDARDI.md 8).
-keep class androidx.work.impl.WorkDatabase { *; }
-keep class androidx.work.impl.WorkDatabase_Impl { *; }
-keep class androidx.work.impl.model.** { *; }
-keep class * extends androidx.work.ListenableWorker { *; }
-keep class androidx.room.** { *; }
