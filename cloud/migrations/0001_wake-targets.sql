CREATE TABLE `room_posts` (
	`base_id` text NOT NULL,
	`room` text NOT NULL,
	`file` text NOT NULL,
	`author` text NOT NULL,
	`at` integer NOT NULL,
	PRIMARY KEY(`base_id`, `room`, `file`),
	FOREIGN KEY (`base_id`) REFERENCES `bases`(`id`) ON UPDATE no action ON DELETE cascade
);
--> statement-breakpoint
CREATE INDEX `room_posts_room` ON `room_posts` (`base_id`,`room`,`at`);--> statement-breakpoint
CREATE TABLE `wake_targets` (
	`token_id` text PRIMARY KEY NOT NULL,
	`user_id` text NOT NULL,
	`platform` text NOT NULL,
	`name` text NOT NULL,
	`url` text NOT NULL,
	`secret` text NOT NULL,
	`created_at` integer NOT NULL,
	`recent_wakes` text DEFAULT '[]' NOT NULL,
	`last_wake_at` integer,
	`last_result` text,
	FOREIGN KEY (`token_id`) REFERENCES `tokens`(`id`) ON UPDATE no action ON DELETE cascade,
	FOREIGN KEY (`user_id`) REFERENCES `user`(`id`) ON UPDATE no action ON DELETE cascade
);
--> statement-breakpoint
CREATE INDEX `wake_targets_user` ON `wake_targets` (`user_id`);