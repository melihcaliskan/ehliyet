CREATE TABLE `appointments` (
	`id` text PRIMARY KEY NOT NULL,
	`user_id` text NOT NULL,
	`kind` text NOT NULL,
	`title` text NOT NULL,
	`starts_at` text NOT NULL,
	`location` text,
	`created_at` integer DEFAULT (unixepoch() * 1000) NOT NULL,
	FOREIGN KEY (`user_id`) REFERENCES `users`(`id`) ON UPDATE no action ON DELETE cascade
);
--> statement-breakpoint
CREATE INDEX `idx_appointments_user` ON `appointments` (`user_id`,`starts_at`);--> statement-breakpoint
CREATE TABLE `exam_sessions` (
	`id` text PRIMARY KEY NOT NULL,
	`kind` text NOT NULL,
	`title` text NOT NULL,
	`date` text NOT NULL,
	`city` text,
	`note` text
);
--> statement-breakpoint
CREATE INDEX `idx_sessions_date` ON `exam_sessions` (`date`);--> statement-breakpoint
CREATE TABLE `fee_items` (
	`id` text PRIMARY KEY NOT NULL,
	`category` text NOT NULL,
	`title` text NOT NULL,
	`amount_kurus` integer NOT NULL,
	`license_class` text,
	`is_course_fee` integer DEFAULT false NOT NULL,
	`sort` integer DEFAULT 0 NOT NULL,
	`valid_from` text NOT NULL
);
--> statement-breakpoint
CREATE TABLE `purchases` (
	`id` text PRIMARY KEY NOT NULL,
	`user_id` text,
	`product_id` text NOT NULL,
	`transaction_id` text NOT NULL,
	`original_transaction_id` text NOT NULL,
	`environment` text NOT NULL,
	`purchased_at` integer NOT NULL,
	`expires_at` integer,
	`revoked_at` integer,
	`updated_at` integer NOT NULL,
	FOREIGN KEY (`user_id`) REFERENCES `users`(`id`) ON UPDATE no action ON DELETE set null
);
--> statement-breakpoint
CREATE UNIQUE INDEX `purchases_transaction_id_unique` ON `purchases` (`transaction_id`);--> statement-breakpoint
CREATE INDEX `idx_purchases_user` ON `purchases` (`user_id`);--> statement-breakpoint
CREATE INDEX `idx_purchases_original` ON `purchases` (`original_transaction_id`);--> statement-breakpoint
CREATE TABLE `refresh_tokens` (
	`id` text PRIMARY KEY NOT NULL,
	`user_id` text NOT NULL,
	`token_hash` text NOT NULL,
	`family_id` text NOT NULL,
	`expires_at` integer NOT NULL,
	`revoked_at` integer,
	`created_at` integer DEFAULT (unixepoch() * 1000) NOT NULL,
	FOREIGN KEY (`user_id`) REFERENCES `users`(`id`) ON UPDATE no action ON DELETE cascade
);
--> statement-breakpoint
CREATE UNIQUE INDEX `refresh_tokens_token_hash_unique` ON `refresh_tokens` (`token_hash`);--> statement-breakpoint
CREATE INDEX `idx_refresh_user` ON `refresh_tokens` (`user_id`);--> statement-breakpoint
CREATE TABLE `users` (
	`id` text PRIMARY KEY NOT NULL,
	`email` text,
	`password_hash` text,
	`apple_sub` text,
	`name` text,
	`created_at` integer DEFAULT (unixepoch() * 1000) NOT NULL
);
--> statement-breakpoint
CREATE UNIQUE INDEX `users_email_unique` ON `users` (`email`);--> statement-breakpoint
CREATE UNIQUE INDEX `users_apple_sub_unique` ON `users` (`apple_sub`);