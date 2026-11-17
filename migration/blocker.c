/*
 * Migration blocker stubs for the trimmed fork.
 *
 * The fork has no live migration support, so registering a blocker cannot
 * fail.  We still own and release the Error object so callers such as 9P
 * can use the normal upstream lifecycle.
 */

#include "qemu/osdep.h"
#include "qapi/error.h"
#include "migration/blocker.h"

int migrate_add_blocker(Error **reasonp, Error **errp)
{
    return 0;
}

void migrate_del_blocker(Error **reasonp)
{
    if (reasonp && *reasonp) {
        error_free(*reasonp);
        *reasonp = NULL;
    }
}
