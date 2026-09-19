-- PostgreSQL requires the enum value to be committed before it can be used in
-- a constraint. The constraint and retention function live in the next migration.

alter type public.external_backup_status add value if not exists 'deleting';
