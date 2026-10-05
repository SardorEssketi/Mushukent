# Places V2 production category status

As of 2026-10-05, the production places API accepts `pet_shop`,
`veterinary`, `veterinary_pharmacy`, and `shelter`. The production
database has applied Alembic revision `20261002_0024` and its
`place_category` enum includes `veterinary_pharmacy`.
