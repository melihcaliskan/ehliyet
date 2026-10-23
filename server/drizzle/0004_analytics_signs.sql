CREATE TABLE `events` (
	`id` text PRIMARY KEY NOT NULL,
	`user_id` text,
	`device_id` text NOT NULL,
	`session_id` text NOT NULL,
	`name` text NOT NULL,
	`props` text,
	`at` integer NOT NULL,
	`app_version` text,
	FOREIGN KEY (`user_id`) REFERENCES `users`(`id`) ON UPDATE no action ON DELETE cascade
);
--> statement-breakpoint
CREATE INDEX `idx_events_at` ON `events` (`at`);--> statement-breakpoint
CREATE INDEX `idx_events_user` ON `events` (`user_id`,`at`);--> statement-breakpoint
CREATE INDEX `idx_events_session` ON `events` (`session_id`);--> statement-breakpoint
CREATE TABLE `question_reports` (
	`id` text PRIMARY KEY NOT NULL,
	`question_id` text NOT NULL,
	`user_id` text,
	`message` text NOT NULL,
	`resolved` integer DEFAULT false NOT NULL,
	`created_at` integer DEFAULT (unixepoch() * 1000) NOT NULL,
	FOREIGN KEY (`question_id`) REFERENCES `questions`(`id`) ON UPDATE no action ON DELETE cascade,
	FOREIGN KEY (`user_id`) REFERENCES `users`(`id`) ON UPDATE no action ON DELETE set null
);
--> statement-breakpoint
ALTER TABLE `questions` ADD `image` text;--> statement-breakpoint
ALTER TABLE `questions` ADD `active` integer DEFAULT true NOT NULL;--> statement-breakpoint
ALTER TABLE `users` ADD `role` text DEFAULT 'user' NOT NULL;--> statement-breakpoint
ALTER TABLE `users` ADD `last_seen_at` integer;