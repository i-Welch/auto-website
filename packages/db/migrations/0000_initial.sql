CREATE TYPE "public"."business_status" AS ENUM('discovered', 'audited', 'demo_built', 'outreach_sent', 'replied', 'converted', 'active', 'churned', 'do_not_contact');--> statement-breakpoint
CREATE TYPE "public"."contact_kind" AS ENUM('email', 'phone', 'facebook', 'instagram', 'twitter', 'linkedin', 'website', 'other');--> statement-breakpoint
CREATE TABLE IF NOT EXISTS "business" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"slug" text NOT NULL,
	"canonical_name" text NOT NULL,
	"canonical_phone" text,
	"canonical_address_street" text,
	"canonical_address_city" text,
	"canonical_address_state" text,
	"canonical_address_zip" text,
	"canonical_website" text,
	"niche" text NOT NULL,
	"metro" text NOT NULL,
	"presence_score" integer,
	"value_score" integer,
	"priority" integer,
	"score_breakdown" jsonb,
	"status" "business_status" DEFAULT 'discovered' NOT NULL,
	"raw" jsonb,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "business_slug_unique" UNIQUE("slug")
);
--> statement-breakpoint
CREATE TABLE IF NOT EXISTS "business_audit" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"business_id" uuid NOT NULL,
	"field" text NOT NULL,
	"old_value" jsonb,
	"new_value" jsonb,
	"actor" text NOT NULL,
	"at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE IF NOT EXISTS "business_source" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"business_id" uuid NOT NULL,
	"source" text NOT NULL,
	"external_id" text,
	"raw" jsonb NOT NULL,
	"confidence" integer,
	"first_seen" timestamp with time zone DEFAULT now() NOT NULL,
	"last_seen" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE IF NOT EXISTS "contact" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"business_id" uuid NOT NULL,
	"kind" "contact_kind" NOT NULL,
	"value" text NOT NULL,
	"verified" boolean DEFAULT false NOT NULL,
	"do_not_contact" boolean DEFAULT false NOT NULL,
	"metadata" jsonb,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE IF NOT EXISTS "dedup_candidate" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"primary_business_id" uuid NOT NULL,
	"candidate_business_id" uuid NOT NULL,
	"match_score" integer NOT NULL,
	"reason" text NOT NULL,
	"status" text DEFAULT 'pending' NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE IF NOT EXISTS "discovery_run" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"source" text NOT NULL,
	"metro" text NOT NULL,
	"niche" text NOT NULL,
	"queries" jsonb NOT NULL,
	"results_count" integer DEFAULT 0 NOT NULL,
	"new_businesses_count" integer DEFAULT 0 NOT NULL,
	"cost_estimate_cents" integer DEFAULT 0 NOT NULL,
	"status" text NOT NULL,
	"error" text,
	"started_at" timestamp with time zone DEFAULT now() NOT NULL,
	"finished_at" timestamp with time zone
);
--> statement-breakpoint
DO $$ BEGIN
 ALTER TABLE "business_audit" ADD CONSTRAINT "business_audit_business_id_business_id_fk" FOREIGN KEY ("business_id") REFERENCES "public"."business"("id") ON DELETE cascade ON UPDATE no action;
EXCEPTION
 WHEN duplicate_object THEN null;
END $$;
--> statement-breakpoint
DO $$ BEGIN
 ALTER TABLE "business_source" ADD CONSTRAINT "business_source_business_id_business_id_fk" FOREIGN KEY ("business_id") REFERENCES "public"."business"("id") ON DELETE cascade ON UPDATE no action;
EXCEPTION
 WHEN duplicate_object THEN null;
END $$;
--> statement-breakpoint
DO $$ BEGIN
 ALTER TABLE "contact" ADD CONSTRAINT "contact_business_id_business_id_fk" FOREIGN KEY ("business_id") REFERENCES "public"."business"("id") ON DELETE cascade ON UPDATE no action;
EXCEPTION
 WHEN duplicate_object THEN null;
END $$;
--> statement-breakpoint
DO $$ BEGIN
 ALTER TABLE "dedup_candidate" ADD CONSTRAINT "dedup_candidate_primary_business_id_business_id_fk" FOREIGN KEY ("primary_business_id") REFERENCES "public"."business"("id") ON DELETE cascade ON UPDATE no action;
EXCEPTION
 WHEN duplicate_object THEN null;
END $$;
--> statement-breakpoint
DO $$ BEGIN
 ALTER TABLE "dedup_candidate" ADD CONSTRAINT "dedup_candidate_candidate_business_id_business_id_fk" FOREIGN KEY ("candidate_business_id") REFERENCES "public"."business"("id") ON DELETE cascade ON UPDATE no action;
EXCEPTION
 WHEN duplicate_object THEN null;
END $$;
--> statement-breakpoint
CREATE INDEX IF NOT EXISTS "business_metro_niche_idx" ON "business" USING btree ("metro","niche");--> statement-breakpoint
CREATE INDEX IF NOT EXISTS "business_priority_idx" ON "business" USING btree ("priority");--> statement-breakpoint
CREATE INDEX IF NOT EXISTS "business_phone_idx" ON "business" USING btree ("canonical_phone");--> statement-breakpoint
CREATE INDEX IF NOT EXISTS "business_audit_business_idx" ON "business_audit" USING btree ("business_id");--> statement-breakpoint
CREATE INDEX IF NOT EXISTS "business_audit_at_idx" ON "business_audit" USING btree ("at");--> statement-breakpoint
CREATE INDEX IF NOT EXISTS "business_source_business_idx" ON "business_source" USING btree ("business_id");--> statement-breakpoint
CREATE INDEX IF NOT EXISTS "business_source_source_idx" ON "business_source" USING btree ("source");--> statement-breakpoint
CREATE UNIQUE INDEX IF NOT EXISTS "business_source_uniq_ext" ON "business_source" USING btree ("source","external_id");--> statement-breakpoint
CREATE INDEX IF NOT EXISTS "contact_business_idx" ON "contact" USING btree ("business_id");--> statement-breakpoint
CREATE UNIQUE INDEX IF NOT EXISTS "contact_uniq" ON "contact" USING btree ("business_id","kind","value");--> statement-breakpoint
CREATE INDEX IF NOT EXISTS "dedup_primary_idx" ON "dedup_candidate" USING btree ("primary_business_id");--> statement-breakpoint
CREATE INDEX IF NOT EXISTS "dedup_status_idx" ON "dedup_candidate" USING btree ("status");--> statement-breakpoint
CREATE INDEX IF NOT EXISTS "discovery_run_started_idx" ON "discovery_run" USING btree ("started_at");--> statement-breakpoint
CREATE INDEX IF NOT EXISTS "discovery_run_source_idx" ON "discovery_run" USING btree ("source");