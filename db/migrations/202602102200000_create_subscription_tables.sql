-- +micrate Up
-- SQL in this section is executed when the migration is applied.

-- Subscription state enum
CREATE TYPE subscription_state AS ENUM ('Active', 'Suspended', 'Cancelled');

-- Invoice status enum
CREATE TYPE invoice_status AS ENUM ('Open', 'Paid', 'Void', 'Uncollectible');

-- Billing interval enum
CREATE TYPE billing_interval AS ENUM ('monthly', 'yearly');

-- Services (Features/Capabilities)
CREATE TABLE services (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name VARCHAR(255) NOT NULL,
  description TEXT,
  entitlement_keys TEXT[] NOT NULL DEFAULT '{}', -- Array of feature flag strings
  created_at TIMESTAMP WITHOUT TIME ZONE NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMP WITHOUT TIME ZONE NOT NULL DEFAULT NOW()
);

-- Plans (Bundles of Services)
CREATE TABLE plans (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name VARCHAR(255) NOT NULL,
  billing_interval billing_interval NOT NULL,
  price BIGINT NOT NULL, -- in cents
  currency VARCHAR(3) NOT NULL DEFAULT 'USD',
  service_ids UUID[] NOT NULL DEFAULT '{}', -- References services(id)
  created_at TIMESTAMP WITHOUT TIME ZONE NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMP WITHOUT TIME ZONE NOT NULL DEFAULT NOW()
);

-- Subscriptions (Org <-> Plan link)
CREATE TABLE subscriptions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  org_id UUID NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
  plan_id UUID NOT NULL REFERENCES plans(id),
  state subscription_state NOT NULL DEFAULT 'Active',
  
  start_date DATE NOT NULL,
  current_period_start DATE NOT NULL,
  current_period_end DATE NOT NULL,
  next_invoice_at TIMESTAMP WITHOUT TIME ZONE NOT NULL,
  
  payment_terms_days INT NOT NULL DEFAULT 14,
  cutoff_grace_days INT NOT NULL DEFAULT 7,
  
  created_at TIMESTAMP WITHOUT TIME ZONE NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMP WITHOUT TIME ZONE NOT NULL DEFAULT NOW()
);

-- Invoices
CREATE TABLE invoices (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  org_id UUID NOT NULL REFERENCES organizations(id),
  subscription_id UUID NOT NULL REFERENCES subscriptions(id),
  
  period_start DATE NOT NULL,
  period_end DATE NOT NULL,
  issue_date DATE NOT NULL,
  due_date DATE NOT NULL,
  
  amount_total BIGINT NOT NULL,
  status invoice_status NOT NULL DEFAULT 'Open',
  
  created_at TIMESTAMP WITHOUT TIME ZONE NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMP WITHOUT TIME ZONE NOT NULL DEFAULT NOW()
);

-- Payments
CREATE TABLE payments (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  invoice_id UUID NOT NULL REFERENCES invoices(id),
  amount BIGINT NOT NULL,
  paid_at TIMESTAMP WITHOUT TIME ZONE NOT NULL DEFAULT NOW(),
  provider_key VARCHAR(50) NOT NULL, -- 'manual', 'stripe'
  provider_reference VARCHAR(255),
  
  created_at TIMESTAMP WITHOUT TIME ZONE NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMP WITHOUT TIME ZONE NOT NULL DEFAULT NOW()
);

-- Entitlement Snapshots (Runtime Cache)
CREATE TABLE entitlement_snapshots (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  org_id UUID NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
  enabled_service_keys TEXT[] NOT NULL DEFAULT '{}',
  computed_at TIMESTAMP WITHOUT TIME ZONE NOT NULL DEFAULT NOW(),
  reason VARCHAR(255), -- 'subscription_active', 'admin_override'
  
  created_at TIMESTAMP WITHOUT TIME ZONE NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMP WITHOUT TIME ZONE NOT NULL DEFAULT NOW()
);

-- Indexes for performance
CREATE INDEX idx_subscriptions_org_id ON subscriptions(org_id);
CREATE INDEX idx_subscriptions_state ON subscriptions(state);
CREATE INDEX idx_invoices_subscription_id ON invoices(subscription_id);
CREATE INDEX idx_invoices_status_due_date ON invoices(status, due_date);
CREATE INDEX idx_entitlement_snapshots_org_id ON entitlement_snapshots(org_id);

-- Ensure only one non-cancelled subscription per organization
CREATE UNIQUE INDEX idx_subscriptions_one_active_per_org
  ON subscriptions (org_id)
  WHERE state IN ('Active', 'Suspended');


-- +micrate Down
-- SQL in this section is executed when the migration is rolled back.
DROP TABLE entitlement_snapshots;
DROP TABLE payments;
DROP TABLE invoices;
DROP TABLE subscriptions;
DROP TABLE plans;
DROP TABLE services;
DROP TYPE IF EXISTS billing_interval;
DROP TYPE IF EXISTS invoice_status;
DROP TYPE IF EXISTS subscription_state;
