-- Separate extraction has its own budget. Old per-chunk summary quota waits
-- must not postpone the canonical job after summary inference is disabled.
UPDATE processing_jobs SET state='pending',due_at=strftime('%Y-%m-%dT%H:%M:%fZ','now'),error_code=NULL
WHERE state='quota_wait' AND error_code IN ('ai_daily_budget','ai_account_quota');
