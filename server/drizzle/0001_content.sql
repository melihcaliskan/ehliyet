CREATE TABLE `answers` (
	`id` text PRIMARY KEY NOT NULL,
	`user_id` text NOT NULL,
	`question_id` text NOT NULL,
	`exam_id` text,
	`choice` integer NOT NULL,
	`correct` integer NOT NULL,
	`answered_at` integer NOT NULL,
	FOREIGN KEY (`user_id`) REFERENCES `users`(`id`) ON UPDATE no action ON DELETE cascade,
	FOREIGN KEY (`question_id`) REFERENCES `questions`(`id`) ON UPDATE no action ON DELETE no action,
	FOREIGN KEY (`exam_id`) REFERENCES `exams`(`id`) ON UPDATE no action ON DELETE cascade
);
--> statement-breakpoint
CREATE INDEX `idx_answers_user_question` ON `answers` (`user_id`,`question_id`,`answered_at`);--> statement-breakpoint
CREATE TABLE `exam_routes` (
	`id` text PRIMARY KEY NOT NULL,
	`city` text NOT NULL,
	`district` text NOT NULL,
	`name` text NOT NULL,
	`distance_km` real NOT NULL,
	`is_premium` integer DEFAULT false NOT NULL,
	`path` text NOT NULL,
	`checkpoints` text NOT NULL,
	`video_lesson_id` text,
	FOREIGN KEY (`video_lesson_id`) REFERENCES `lessons`(`id`) ON UPDATE no action ON DELETE no action
);
--> statement-breakpoint
CREATE INDEX `idx_routes_city` ON `exam_routes` (`city`,`district`);--> statement-breakpoint
CREATE TABLE `exams` (
	`id` text PRIMARY KEY NOT NULL,
	`user_id` text NOT NULL,
	`kind` text NOT NULL,
	`topic_id` text,
	`question_ids` text NOT NULL,
	`started_at` integer NOT NULL,
	`finished_at` integer,
	`correct` integer,
	`wrong` integer,
	`duration_sec` integer,
	FOREIGN KEY (`user_id`) REFERENCES `users`(`id`) ON UPDATE no action ON DELETE cascade,
	FOREIGN KEY (`topic_id`) REFERENCES `topics`(`id`) ON UPDATE no action ON DELETE no action
);
--> statement-breakpoint
CREATE INDEX `idx_exams_user` ON `exams` (`user_id`,`started_at`);--> statement-breakpoint
CREATE TABLE `lesson_progress` (
	`user_id` text NOT NULL,
	`lesson_id` text NOT NULL,
	`position_sec` integer DEFAULT 0 NOT NULL,
	`completed` integer DEFAULT false NOT NULL,
	`updated_at` integer NOT NULL,
	PRIMARY KEY(`user_id`, `lesson_id`),
	FOREIGN KEY (`user_id`) REFERENCES `users`(`id`) ON UPDATE no action ON DELETE cascade,
	FOREIGN KEY (`lesson_id`) REFERENCES `lessons`(`id`) ON UPDATE no action ON DELETE no action
);
--> statement-breakpoint
CREATE TABLE `lessons` (
	`id` text PRIMARY KEY NOT NULL,
	`kind` text NOT NULL,
	`chapter` text NOT NULL,
	`title` text NOT NULL,
	`minutes` integer NOT NULL,
	`is_premium` integer DEFAULT false NOT NULL,
	`video_url` text,
	`sort` integer DEFAULT 0 NOT NULL
);
--> statement-breakpoint
CREATE TABLE `questions` (
	`id` text PRIMARY KEY NOT NULL,
	`topic_id` text NOT NULL,
	`text` text NOT NULL,
	`options` text NOT NULL,
	`answer` integer NOT NULL,
	`explanation` text NOT NULL,
	`source` text,
	FOREIGN KEY (`topic_id`) REFERENCES `topics`(`id`) ON UPDATE no action ON DELETE no action
);
--> statement-breakpoint
CREATE INDEX `idx_questions_topic` ON `questions` (`topic_id`);--> statement-breakpoint
CREATE TABLE `topics` (
	`id` text PRIMARY KEY NOT NULL,
	`name` text NOT NULL,
	`icon` text NOT NULL,
	`color` text NOT NULL,
	`sort` integer DEFAULT 0 NOT NULL
);
