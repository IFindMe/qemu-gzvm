/*
 * Minimal migration blocker declarations for the trimmed fork.
 *
 * QEMU's full migration subsystem is not present here, so blockers are
 * no-ops.  This header keeps 9P's "do not migrate while mounted" logic
 * source-compatible with upstream QEMU.
 */
#ifndef MIGRATION_BLOCKER_H
#define MIGRATION_BLOCKER_H

#include "qapi/error.h"

int migrate_add_blocker(Error **reasonp, Error **errp);
void migrate_del_blocker(Error **reasonp);

#endif
