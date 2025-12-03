-- +micrate Up
-- SQL in section 'Up' is executed when this migration is applied

-- Add password hash field for username/password authentication
ALTER TABLE users ADD COLUMN password_hash TEXT;

-- +micrate Down
-- SQL section 'Down' is executed when this migration is rolled back

ALTER TABLE users DROP COLUMN password_hash;
