#!/usr/bin/env bash
# Reduced JIT candidate: preserve the verified scratch closure, add the pinned
# compiler/system userspace and required headers, not the vendor build trees.
# This is a conservative intermediate closure, NOT an audited minimal image.
set -euo pipefail
dest=$1
source /environment
test -x /opt/physics/physics-opt
test -d "$dest/opt/physics"
compiler=$(command -v c++)
test "$compiler" = /opt/rh/gcc-toolset-13/root/usr/bin/c++
before=$(du -sb "$dest" | cut -f1)
copy_tree() {
  local p=$1
  test -d "$p"
  mkdir -p "$dest$p"
  cp -a "$p/." "$dest$p/"
}
copy_headers() {
  local p=$1
  test -d "$p"
  mkdir -p "$dest$p"
  cp -aL "$p/." "$dest$p/"
}
# Keep distro userspace as an initial coarse dependency boundary, then refine
# with compiler traces after the actual S6 case passes. No package installation.
copy_tree /usr
# The toolset is a chroot-shaped tree. Only its installed compiler userspace
# is needed; root/root is a private home, not a JIT dependency or image input.
copy_tree /opt/rh/gcc-toolset-13/root/usr
test -x "$dest$compiler"
test ! -e "$dest/opt/rh/gcc-toolset-13/root/root"
for p in /lib /lib64; do
  if test -d "$p"; then copy_tree "$p"; fi
done
for p in /bin /sbin; do
  if test -L "$p"; then cp -a "$p" "$dest$p"; else copy_tree "$p"; fi
done
mkdir -p "$dest/etc" "$dest/tmp" "$dest/work" "$dest/opt/physics"
chmod 1777 "$dest/tmp"
for p in /etc/alternatives /etc/passwd /etc/group /etc/nsswitch.conf; do
  if test -e "$p"; then cp -a "$p" "$dest$p"; fi
done
# ADFPARSER_INCLUDES is compiled into the pinned MOOSE executable. Preserve
# absolute include paths; dereference generated header links in the build tree.
for p in /opt/physics_vendor/moose/framework/include/utils \
         /opt/physics_vendor/moose/framework/include/base \
         /opt/libmesh/include; do
  copy_headers "$p"
done
# Preserve any other libMesh-configured include directories.
config=/opt/libmesh/bin/libmesh-config
test -x "$config"
includes=$("$config" --include)
printf '%s\n' "$includes"
for flag in $includes; do
  case "$flag" in
    -I/opt/*) copy_headers "${flag#-I}" ;;
    -I/usr/*) test -d "$dest${flag#-I}" ;;
    -I*) echo "Unexpected include path: $flag" >&2; exit 1 ;;
  esac
done
for p in /opt/openmpi/include /opt/petsc/include; do
  if test -d "$p"; then copy_headers "$p"; fi
done
test -r "$dest/opt/physics_vendor/moose/framework/include/base/MooseConfig.h"
test -r "$dest/opt/physics_vendor/moose/framework/include/utils/ADReal.h"
# Snapshot only toolchain-related environment from the known-good build base.
{
  echo '#!/bin/bash'
  echo 'set -eo pipefail'
  for key in PATH LD_LIBRARY_PATH LIBRARY_PATH CPATH CPLUS_INCLUDE_PATH C_INCLUDE_PATH GCC_EXEC_PREFIX COMPILER_PATH; do
    if test -v "$key"; then printf 'export %s=%q\n' "$key" "${!key}"; fi
  done
  echo 'export LD_LIBRARY_PATH=/opt/physics/test/lib:/opt/physics/lib:${LD_LIBRARY_PATH:-}'
  echo 'exec /opt/physics/physics-opt "$@"'
} > "$dest/opt/physics/entrypoint-jit.sh"
chmod 755 "$dest/opt/physics/entrypoint-jit.sh"
ldconfig -r "$dest"
test -s "$dest/etc/ld.so.cache"
test ! -e "$dest/opt/physics_vendor/moose/.git"
test ! -e "$dest/opt/physics_vendor/moose/framework/src"
test ! -e "$dest/opt/physics_vendor/moose/framework/build"
after=$(du -sb "$dest" | cut -f1)
printf 'SCRATCH_ROOT_BYTES=%s\nJIT_ROOT_BYTES=%s\nJIT_ADDED_BYTES=%s\nJIT_CLOSURE_MODE=conservative-system-toolchain-and-headers\n' \
  "$before" "$after" "$((after-before))" > "$dest/opt/physics/JIT_CLOSURE.txt"
cat "$dest/opt/physics/JIT_CLOSURE.txt"
