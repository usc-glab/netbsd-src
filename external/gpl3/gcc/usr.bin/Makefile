#	$NetBSD: Makefile,v 1.15 2024/02/25 00:28:02 mrg Exp $

NOOBJ=# defined

.include <bsd.init.mk>

GCC_MACHINE_ARCH=${MACHINE_ARCH:S/earmv5/earm/}

.if ${MKGCC} != "no" && exists(${.CURDIR}/gcc/arch/${GCC_MACHINE_ARCH}/defs.mk)

.if ${MKGCCCMDS} != "no" || make(includes)

# We keep libcpp here since it depends upon frontend.
SUBDIR+=	host-libiberty .WAIT \
		host-libcpp .WAIT \
		../../../mit/isl/lib/libisl \
		backend .WAIT \
		frontend .WAIT \
		common common-target .WAIT \
		libcody libcpp libdecnumber .WAIT \
		gcov gcov-dump cc1 cc1obj cc1objplus cc1plus cpp g++ gcc \
		lto1 lto-wrapper lto-dump
.endif

SUBDIR+=	include

.include <bsd.subdir.mk>

.else
# Do nothing. (PROG undefined)
.include <bsd.prog.mk>
.endif
