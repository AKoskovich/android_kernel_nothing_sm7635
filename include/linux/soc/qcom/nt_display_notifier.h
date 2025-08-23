/* SPDX-License-Identifier: GPL-2.0-only */
/*
 * Copyright (c) 2021, The Linux Foundation. All rights reserved.
 */

#ifndef __NT_DISPLAY_NOTIFIER_H
#define __NT_DISPLAY_NOTIFIER_H

#include <linux/err.h>
#include <linux/errno.h>
#include <linux/types.h>

/*Add for fp*/
#define FP_NOTIFIER_EVENT_UI		0x01

struct fp_notify_event {
	bool lhbm_state;
};

int nt_display_event_register_notifier(struct notifier_block *nb);
int nt_display_event_unregister_notifier(struct notifier_block *nb);
int nt_display_event_call_notifier(unsigned long val, void *data);

void nt_display_update_lhbm_state(bool lhbm_state);

#endif	/* __NT_DISPLAY_NOTIFIER_H */
