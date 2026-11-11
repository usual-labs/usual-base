PRAGMA foreign_keys=OFF;--> statement-breakpoint
CREATE TABLE `__new_wake_targets` (
	`id` text PRIMARY KEY NOT NULL,
	`user_id` text NOT NULL,
	`name` text NOT NULL,
	`platform` text NOT NULL,
	`url` text NOT NULL,
	`secret` text NOT NULL,
	`created_at` integer NOT NULL,
	`recent_wakes` text DEFAULT '[]' NOT NULL,
	`last_wake_at` integer,
	`last_result` text,
	FOREIGN KEY (`user_id`) REFERENCES `user`(`id`) ON UPDATE no action ON DELETE cascade
);
--> statement-breakpoint
CREATE UNIQUE INDEX `wake_targets_name` ON `__new_wake_targets` (`user_id`,`name`);--> statement-breakpoint
INSERT OR IGNORE INTO `__new_wake_targets`("id", "user_id", "name", "platform", "url", "secret", "created_at", "recent_wakes", "last_wake_at", "last_result") SELECT 'wk_' || lower(hex(randomblob(9))), "user_id", "name", "platform", "url", "secret", "created_at", "recent_wakes", "last_wake_at", "last_result" FROM `wake_targets` ORDER BY "created_at" DESC;--> statement-breakpoint
DROP TABLE `wake_targets`;--> statement-breakpoint
ALTER TABLE `__new_wake_targets` RENAME TO `wake_targets`;--> statement-breakpoint
PRAGMA foreign_keys=ON;