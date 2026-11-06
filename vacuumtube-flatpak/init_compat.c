#include <va/va_backend.h>

/*
 * The Flatpak runtime used by VacuumTube 2.0.1 is org.freedesktop.Platform
 * 25.08, whose libva implements VA-API 1.22.  Build the driver with the 1.22
 * init symbol as the primary entry point, and also export wrappers for the
 * next two API minors so a runtime refresh does not immediately break the
 * driver with "could not find __vaDriverInit_1_XX".
 */

extern VAStatus __vaDriverInit_1_22(VADriverContextP context);

VAStatus __attribute__((visibility("default")))
__vaDriverInit_1_23(VADriverContextP context)
{
	return __vaDriverInit_1_22(context);
}

VAStatus __attribute__((visibility("default")))
__vaDriverInit_1_24(VADriverContextP context)
{
	return __vaDriverInit_1_22(context);
}

VAStatus __attribute__((visibility("default")))
__vaDriverInit_1_25(VADriverContextP context)
{
	return __vaDriverInit_1_22(context);
}
