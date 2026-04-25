import {
  pgTable,
  uuid,
  text,
  integer,
  timestamp,
  jsonb,
  boolean,
  pgEnum,
  index,
  uniqueIndex,
} from 'drizzle-orm/pg-core';

export const businessStatusEnum = pgEnum('business_status', [
  'discovered',
  'audited',
  'demo_built',
  'outreach_sent',
  'replied',
  'converted',
  'active',
  'churned',
  'do_not_contact',
]);

export const contactKindEnum = pgEnum('contact_kind', [
  'email',
  'phone',
  'facebook',
  'instagram',
  'twitter',
  'linkedin',
  'website',
  'other',
]);

export const business = pgTable(
  'business',
  {
    id: uuid('id').primaryKey().defaultRandom(),
    slug: text('slug').notNull().unique(),
    canonicalName: text('canonical_name').notNull(),
    canonicalPhone: text('canonical_phone'),
    canonicalAddressStreet: text('canonical_address_street'),
    canonicalAddressCity: text('canonical_address_city'),
    canonicalAddressState: text('canonical_address_state'),
    canonicalAddressZip: text('canonical_address_zip'),
    canonicalWebsite: text('canonical_website'),
    niche: text('niche').notNull(),
    metro: text('metro').notNull(),
    presenceScore: integer('presence_score'),
    valueScore: integer('value_score'),
    priority: integer('priority'),
    scoreBreakdown: jsonb('score_breakdown'),
    status: businessStatusEnum('status').notNull().default('discovered'),
    raw: jsonb('raw'),
    createdAt: timestamp('created_at', { withTimezone: true }).notNull().defaultNow(),
    updatedAt: timestamp('updated_at', { withTimezone: true }).notNull().defaultNow(),
  },
  (t) => ({
    metroNicheIdx: index('business_metro_niche_idx').on(t.metro, t.niche),
    priorityIdx: index('business_priority_idx').on(t.priority),
    phoneIdx: index('business_phone_idx').on(t.canonicalPhone),
  }),
);

export const businessSource = pgTable(
  'business_source',
  {
    id: uuid('id').primaryKey().defaultRandom(),
    businessId: uuid('business_id')
      .notNull()
      .references(() => business.id, { onDelete: 'cascade' }),
    source: text('source').notNull(),
    externalId: text('external_id'),
    raw: jsonb('raw').notNull(),
    confidence: integer('confidence'),
    firstSeen: timestamp('first_seen', { withTimezone: true }).notNull().defaultNow(),
    lastSeen: timestamp('last_seen', { withTimezone: true }).notNull().defaultNow(),
  },
  (t) => ({
    businessIdx: index('business_source_business_idx').on(t.businessId),
    sourceIdx: index('business_source_source_idx').on(t.source),
    uniqExternalId: uniqueIndex('business_source_uniq_ext').on(t.source, t.externalId),
  }),
);

export const contact = pgTable(
  'contact',
  {
    id: uuid('id').primaryKey().defaultRandom(),
    businessId: uuid('business_id')
      .notNull()
      .references(() => business.id, { onDelete: 'cascade' }),
    kind: contactKindEnum('kind').notNull(),
    value: text('value').notNull(),
    verified: boolean('verified').notNull().default(false),
    doNotContact: boolean('do_not_contact').notNull().default(false),
    metadata: jsonb('metadata'),
    createdAt: timestamp('created_at', { withTimezone: true }).notNull().defaultNow(),
  },
  (t) => ({
    businessIdx: index('contact_business_idx').on(t.businessId),
    uniq: uniqueIndex('contact_uniq').on(t.businessId, t.kind, t.value),
  }),
);

export const businessAudit = pgTable(
  'business_audit',
  {
    id: uuid('id').primaryKey().defaultRandom(),
    businessId: uuid('business_id')
      .notNull()
      .references(() => business.id, { onDelete: 'cascade' }),
    field: text('field').notNull(),
    oldValue: jsonb('old_value'),
    newValue: jsonb('new_value'),
    actor: text('actor').notNull(),
    at: timestamp('at', { withTimezone: true }).notNull().defaultNow(),
  },
  (t) => ({
    businessIdx: index('business_audit_business_idx').on(t.businessId),
    atIdx: index('business_audit_at_idx').on(t.at),
  }),
);

export const discoveryRun = pgTable(
  'discovery_run',
  {
    id: uuid('id').primaryKey().defaultRandom(),
    source: text('source').notNull(),
    metro: text('metro').notNull(),
    niche: text('niche').notNull(),
    queries: jsonb('queries').notNull(),
    resultsCount: integer('results_count').notNull().default(0),
    newBusinessesCount: integer('new_businesses_count').notNull().default(0),
    costEstimateCents: integer('cost_estimate_cents').notNull().default(0),
    status: text('status').notNull(),
    error: text('error'),
    startedAt: timestamp('started_at', { withTimezone: true }).notNull().defaultNow(),
    finishedAt: timestamp('finished_at', { withTimezone: true }),
  },
  (t) => ({
    startedIdx: index('discovery_run_started_idx').on(t.startedAt),
    sourceIdx: index('discovery_run_source_idx').on(t.source),
  }),
);

export const dedupCandidate = pgTable(
  'dedup_candidate',
  {
    id: uuid('id').primaryKey().defaultRandom(),
    primaryBusinessId: uuid('primary_business_id')
      .notNull()
      .references(() => business.id, { onDelete: 'cascade' }),
    candidateBusinessId: uuid('candidate_business_id')
      .notNull()
      .references(() => business.id, { onDelete: 'cascade' }),
    matchScore: integer('match_score').notNull(),
    reason: text('reason').notNull(),
    status: text('status').notNull().default('pending'),
    createdAt: timestamp('created_at', { withTimezone: true }).notNull().defaultNow(),
  },
  (t) => ({
    primaryIdx: index('dedup_primary_idx').on(t.primaryBusinessId),
    statusIdx: index('dedup_status_idx').on(t.status),
  }),
);
