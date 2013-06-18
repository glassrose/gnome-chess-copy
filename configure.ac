AC_INIT(gnome-chess, 3.7.2)
LT_INIT

AC_CONFIG_HEADERS([config.h])

AM_INIT_AUTOMAKE([1.11 no-dist-gzip dist-xz foreign])
AM_SILENT_RULES([yes])
AM_MAINTAINER_MODE
GNOME_MAINTAINER_MODE_DEFINES
 
AM_PROG_VALAC([0.16.0])
AM_PROG_CC_C_O

GLIB_GSETTINGS

dnl ###########################################################################
dnl Dependencies
dnl ###########################################################################

GTK_REQUIRED=3.4.0
RSVG_REQUIRED=2.32.0

PKG_CHECK_MODULES(GNOME_CHESS, [
  glib-2.0
  gio-2.0
  gmodule-2.0
  gtk+-3.0 >= $GTK_REQUIRED
  librsvg-2.0 >= $RSVG_REQUIRED
  sqlite3
  gl
  glu
  x11
])

PKG_CHECK_MODULES(TEST, [
  gio-2.0
])

dnl ###########################################################################
dnl Enable Networking
dnl ###########################################################################

AC_ARG_ENABLE([networking],
    AS_HELP_STRING([--enable-networking=@<:@no/yes@:>@],
        [build with Contacts and Telepathy networking support (default: yes)]),
    [case "${enableval}" in
        yes) networking=yes ;;
         no) networking=no ;;
          *) AC_MSG_ERROR([bad value ${enableval} for --enable-networking]) ;;
     esac],
    [networking=yes])

if test "x$networking" = "xyes"; then
    # Check for folks
    FOLKS_REQUIRED=0.9.0

    PKG_CHECK_MODULES([FOLKS],
        [folks >= $FOLKS_REQUIRED
         folks-telepathy >= $FOLKS_REQUIRED])
    AC_SUBST([FOLKS_CFLAGS])
    AC_SUBST([FOLKS_LIBS])

    PKG_CHECK_MODULES([GEE], [gee-0.8])
    AC_SUBST([GEE_CFLAGS])
    AC_SUBST([GEE_LIBS])

    PKG_CHECK_MODULES([TELEPATHY], [telepathy-glib])
    AC_SUBST([TELEPATHY_CFLAGS])
    AC_SUBST([TELEPATHY_LIBS])

    PKG_CHECK_MODULES([XML], [libxml-2.0])

    AC_DEFINE([ENABLE_NETWORKING],[1],[Defines whether Telepathy networking is enabled])
else
    AC_DEFINE([ENABLE_NETWORKING],[0],
        [Defines whether Telepathy networking is enabled])
fi
AM_CONDITIONAL([ENABLE_NETWORKING], [test "x$networking" = "xyes"])


dnl ###########################################################################
dnl Internationalization
dnl ###########################################################################

IT_PROG_INTLTOOL([0.35.0])
AC_SUBST(GETTEXT_PACKAGE, gnome-chess)

dnl ###########################################################################
dnl Documentation
dnl ###########################################################################

YELP_HELP_INIT

dnl ###########################################################################
dnl Files to generate
dnl ###########################################################################

AC_OUTPUT([
Makefile
data/Makefile
data/icons/Makefile
data/pieces/Makefile
data/pieces/3d/Makefile
data/pieces/fancy/Makefile
data/pieces/simple/Makefile
data/textures/Makefile
data/gnome-chess.desktop.in
help/Makefile
po/Makefile.in
src/Makefile
libgames-contacts/Makefile
tests/Makefile
])

echo "
Configuration:

    Source code location:  ${srcdir}
    Compiler:              ${CC}"

echo "
    Networking enabled:    ${networking}
"

