/*
 * Minimal qtest declarations needed by the 9p backend.
 *
 * The trimmed fork has no qtest server; qtest_allowed is provided by
 * stubs/qtest.c and is always false in production builds.
 */
#ifndef QTEST_H
#define QTEST_H

extern bool qtest_allowed;

static inline bool qtest_enabled(void)
{
    return qtest_allowed;
}

#endif
