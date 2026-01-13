-- +micrate Up
-- SQL in section 'Up' is executed when this migration is applied

-- Add tsvector columns for full-text search
ALTER TABLE organizations ADD COLUMN search_vector tsvector;
ALTER TABLE domains ADD COLUMN search_vector tsvector;
ALTER TABLE users ADD COLUMN search_vector tsvector;

-- Create GIN indexes for fast full-text search
CREATE INDEX idx_organizations_search ON organizations USING GIN(search_vector);
CREATE INDEX idx_domains_search ON domains USING GIN(search_vector);
CREATE INDEX idx_users_search ON users USING GIN(search_vector);

-- +micrate StatementBegin
CREATE FUNCTION organizations_search_vector_update() RETURNS trigger AS $$
BEGIN
  NEW.search_vector := 
    setweight(to_tsvector('simple', COALESCE(NEW.name, '')), 'A') ||
    setweight(to_tsvector('simple', COALESCE(NEW.description, '')), 'B') ||
    setweight(to_tsvector('simple', COALESCE(NEW.subdomain, '')), 'C');
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;
-- +micrate StatementEnd

-- +micrate StatementBegin
CREATE FUNCTION domains_search_vector_update() RETURNS trigger AS $$
BEGIN
  NEW.search_vector := 
    setweight(to_tsvector('simple', COALESCE(NEW.name, '')), 'A') ||
    setweight(to_tsvector('simple', COALESCE(NEW.domain, '')), 'A') ||
    setweight(to_tsvector('simple', COALESCE(NEW.description, '')), 'B');
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;
-- +micrate StatementEnd

-- +micrate StatementBegin
CREATE FUNCTION users_search_vector_update() RETURNS trigger AS $$
BEGIN
  NEW.search_vector := 
    setweight(to_tsvector('simple', COALESCE(NEW.name, '')), 'A') ||
    setweight(to_tsvector('simple', COALESCE(NEW.email, '')), 'B');
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;
-- +micrate StatementEnd

-- Create triggers to automatically update search vectors
CREATE TRIGGER organizations_search_vector_trigger 
  BEFORE INSERT OR UPDATE ON organizations 
  FOR EACH ROW EXECUTE FUNCTION organizations_search_vector_update();

CREATE TRIGGER domains_search_vector_trigger 
  BEFORE INSERT OR UPDATE ON domains 
  FOR EACH ROW EXECUTE FUNCTION domains_search_vector_update();

CREATE TRIGGER users_search_vector_trigger 
  BEFORE INSERT OR UPDATE ON users 
  FOR EACH ROW EXECUTE FUNCTION users_search_vector_update();

-- Update existing records
UPDATE organizations SET search_vector = 
  setweight(to_tsvector('simple', COALESCE(name, '')), 'A') ||
  setweight(to_tsvector('simple', COALESCE(description, '')), 'B') ||
  setweight(to_tsvector('simple', COALESCE(subdomain, '')), 'C');

UPDATE domains SET search_vector = 
  setweight(to_tsvector('simple', COALESCE(name, '')), 'A') ||
  setweight(to_tsvector('simple', COALESCE(domain, '')), 'A') ||
  setweight(to_tsvector('simple', COALESCE(description, '')), 'B');

UPDATE users SET search_vector = 
  setweight(to_tsvector('simple', COALESCE(name, '')), 'A') ||
  setweight(to_tsvector('simple', COALESCE(email, '')), 'B');

-- +micrate Down
-- SQL section 'Down' is executed when this migration is rolled back

DROP TRIGGER IF EXISTS organizations_search_vector_trigger ON organizations;
DROP TRIGGER IF EXISTS domains_search_vector_trigger ON domains;
DROP TRIGGER IF EXISTS users_search_vector_trigger ON users;

DROP FUNCTION IF EXISTS organizations_search_vector_update();
DROP FUNCTION IF EXISTS domains_search_vector_update();
DROP FUNCTION IF EXISTS users_search_vector_update();

DROP INDEX IF EXISTS idx_organizations_search;
DROP INDEX IF EXISTS idx_domains_search;
DROP INDEX IF EXISTS idx_users_search;

ALTER TABLE organizations DROP COLUMN IF EXISTS search_vector;
ALTER TABLE domains DROP COLUMN IF EXISTS search_vector;
ALTER TABLE users DROP COLUMN IF EXISTS search_vector;
