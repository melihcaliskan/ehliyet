ALTER TABLE `fee_items` ADD `is_estimate` integer DEFAULT false NOT NULL;--> statement-breakpoint
ALTER TABLE `fee_items` ADD `source` text;