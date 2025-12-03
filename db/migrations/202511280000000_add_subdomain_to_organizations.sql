-- +micrate Up
-- SQL in section 'Up' is executed when this migration is applied

-- Add subdomain field for tenant resolution
ALTER TABLE organizations ADD COLUMN subdomain TEXT;

-- Ensure subdomains are unique
CREATE UNIQUE INDEX idx_organizations_subdomain ON organizations(subdomain) WHERE subdomain IS NOT NULL;

-- +micrate Down
-- SQL section 'Down' is executed when this migration is rolled back

DROP INDEX IF EXISTS idx_organizations_subdomain;
ALTER TABLE organizations DROP COLUMN IF EXISTS subdomain;
