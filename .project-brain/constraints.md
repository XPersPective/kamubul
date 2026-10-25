# Constraints

- C-001: Product and app/store language is Turkish; distribution focus is Türkiye (source: user, 16.10.2026).
- C-002: Official public-job sources only; do not bypass WAF/login/CAPTCHA. Unknown eligibility stays unknown (source: legacy C-004/C-050).
- C-003: Source ingestion and extraction run on the server; the phone uses API/cache and user-opened official links (source: legacy C-002/C-053).
- C-004: Minimize personal data; profile and saved items stay local unless the user explicitly enables the relevant feature (source: legacy C-003).
- C-005: No paid service, quota upgrade or new recurring automation without explicit authorization (source: legacy C-001/C-062).
- C-006: Preserve accessibility, privacy, secret handling and truthful notification/subscription claims (source: legacy C-006/C-020/C-030/C-051).
- C-007: Store publishing/distribution is outside Project Brain scope; do not migrate store submission work (source: user, 18.10.2026; Project Brain scope).
- C-008: Do not claim a guaranteed ranking or download result; evaluate growth with evidence (source: user goal, interpreted as an objective rather than a guarantee).
- C-009: Do not use external CLI agent pools; use only host-native models (source: user, 25.10.2026).
