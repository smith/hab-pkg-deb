#!/bin/bash
#
# # Usage
#
# See the `print_help` function.
#
# # Synopsis
#
# Debian package exporter for Habitat artifacts
#
# # License and Copyright
#
# ```
# Copyright: Copyright (c) 2016 Chef Software, Inc.
# License: Apache License, Version 2.0
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
# ```

# Everything in this script was shamelessy and gratefully copied from
# hab-pkg-dockerize, hab-pkg-tarize, and omnibus/packagers/deb.rb.

# Default variables
pkg=
preinst=
postinst=
prerm=
postrm=
conflicts=
provides=
replaces=

# Fail if there are any unset variables and whenever a command returns a
# non-zero exit code.
set -eu

# If the variable `$DEBUG` is set, then print the shell commands as we execute.
if [ -n "${DEBUG:-}" ]; then
  set -x
  export DEBUG
fi

# ## Help

# **Internal** Prints help
print_help() {
  printf -- "$program $version

$author

Habitat Package Debian - Create a Debian package from a set of Habitat packages

USAGE:
  $program [FLAGS] [OPTIONS] <PKG_IDENT_OR_ARTIFACT>

FLAGS:
    -h, --help       Prints help information
    -V, --version    Prints version information

OPTIONS:
    --preinst=FILE   File name of script called before installation
    --postinst=FILE  File name of script called after installation
    --prerm=FILE     File name of script called before removal
    --postrm=FILE    File name of script called after removal
    --conflicts=PKG  Package that this conflicts with
    --provides=PKG   Name of facility this package provides
    --replaces=PKG   Package that this replaces

ARGS:
    <PKG_IDENT_OR_ARTIFACT>  Habitat package identifier (ex: acme/redis)
"
}

# **Internal** Exit the program with an error message and a status code.
#
# ```sh
# exit_with "Something bad went down" 55
# ```
exit_with() {
  case "${TERM:-}" in
    *term | xterm-* | rxvt | screen | screen-*)
      printf -- "\033[1;31mERROR: \033[1;37m$1\033[0m\n"
      ;;
    *)
      printf -- "ERROR: $1\n"
      ;;
  esac
  exit "$2"
}

# **Internal** Print a warning line on stderr. Takes the rest of the line as its
# only argument.
#
# ```sh
# warn "Checksum failed"
# ```
warn() {
  case "${TERM:-}" in
    *term | xterm-* | rxvt | screen | screen-*)
      printf -- "\033[1;33mWARN: \033[1;37m$1\033[0m\n" >&2
      ;;
    *)
      printf -- "WARN: $1\n" >&2
      ;;
  esac
}

# Build the debian package
build_deb() {
  # Install packages into the staging dir
  env FS_ROOT="$staging_dir" hab pkg install "$pkg"
  # Delete files we won't be needing
  rm -rf "${staging_dir:?}/hab/cache"
  # Make a DEBIAN directory
  mkdir -p "$staging_dir/DEBIAN"

  # Set these variables in advance, since they may or may not be in the manifest,
  # since they are optional
  pkg_description=
  pkg_license=
  pkg_maintainer=
  pkg_upstream_url=

  # Read the manifest to extract variables from it
  manifest="$(cat "$staging_dir"/hab/pkgs/"$pkg"/**/**/MANIFEST)"

  # TODO: Handle multi-line descriptions
  # FIXME: This probably fail when there's a ":" in them
  pkg_description="$(grep __Description__: <<< "$manifest" | cut -d ":" -f2 | sed 's/^ *//g')"
  pkg_license="$(grep __License__: <<< "$manifest" | cut -d ":" -f2 | sed 's/^ *//g')"
  pkg_maintainer="$(grep __Maintainer__: <<< "$manifest" | cut -d ":" -f2 | sed 's/^ *//g')"
  pkg_upstream_url="$(grep __Upstream\ URL__: <<< "$manifest" | cut -d ":" -f2 | sed 's/^ *//g')"

	# Get the ident and the origin and release from that
  ident="$(cat "$staging_dir"/hab/pkgs/"$pkg"/**/**/IDENT)"

  pkg_origin="$(echo "$ident" | cut -f1 -d/)"
  pkg_name="$(echo "$ident" | cut -f2 -d/)"
  pkg_version="$(echo "$ident" | cut -f3 -d/)"
  pkg_release="$(echo "$ident" | cut -f4 -d/)"

  # Write the control file
  render_control_file > "$staging_dir/DEBIAN/control"

  # TODO: Write conffiles file

  write_scripts

  render_md5sums > "$staging_dir/DEBIAN/md5sums"

  # Create the package
  dpkg-deb -z9 -Zgzip --debug --build "$staging_dir" \
		"$(safe_base_package_name)_$(safe_version)-${pkg_release}_$(architecture).deb"
}

# Output the contents of the "control" file
render_control_file() {
# TODO: Depends/conflicts/provides, etc. See https://www.debian.org/doc/debian-policy/ch-relationships.html
# TODO: Should vendor be the origin or not?
control=$(cat <<EOF
Package: $(safe_base_package_name)
Version: $(safe_version)-$pkg_release
Vendor: $pkg_origin
Architecture: $(architecture)
Installed-Size: $(installed_size)
Section: $(section)
Priority: $(priority)
EOF
)

# TODO: Format the description correctly
# See https://www.debian.org/doc/debian-policy/ch-controlfields.html#s-f-Description
if [[ ! -z $pkg_description ]]; then
  control="$control
Description: $pkg_description"
# Description is required, so just use the package name if we don't have one
else
  control="$control
Description: $pkg_name"
fi

if [[ ! -z $pkg_upstream_url ]]; then
  control="$control
Homepage: $pkg_upstream_url"
fi

if [[ ! -z $pkg_license ]]; then
  control="$control
License: $pkg_license"
fi

if [[ ! -z $pkg_maintainer ]]; then
  control="$control
Maintainer: $pkg_maintainer"
# Maintainer is required, so use the origin if we don't have one
else
  control="$control
Maintainer: $pkg_origin"
fi

if [[ ! -z $conflicts ]]; then
  control="$control
Conflicts: $conflicts"
fi

if [[ ! -z $provides ]]; then
  control="$control
Provides: $provides"
fi

if [[ ! -z $replaces ]]; then
  control="$control
Replaces: $replaces"
fi

echo "$control"
}

render_md5sums() {
  pushd "$staging_dir" > /dev/null
    find . -type f ! -regex '.*?DEBIAN.*' -exec md5sum {} +
  popd > /dev/null
}

# Return the Debian-ready base package name, converting any invalid characters to
# dashes (-).
safe_base_package_name() {
  name="$pkg_origin-$pkg_name"
  if [[ $name =~ ^[a-z0-9\.\+\\-]+$ ]]; then
    echo "$name"
  else
    converted="${name,,}"
    # FIXME: I'm doing this regex wrong
    converted="${converted//[^a-z0-9\.\+\-]+/-}"
    warn "The 'name' component of Debian package names can only include "
    warn "lower case alphabetical characters (a-z), numbers (0-9), dots (.), "
    warn "plus signs (+), and dashes (-). Converting '$name' to "
    warn "'$converted'."
    echo "$converted"
  fi
}

# Return the Debian-ready version, replacing all dashes (-) with tildes
# (~) and converting any invalid characters to underscores (_).
safe_version() {
  if [[ $pkg_version == *"-"* ]]; then
    converted="${pkg_version//-/\~}"
    warn "Dashes hold special significance in the Debian package versions. "
    warn "Versions that contain a dash and should be considered an earlier "
    warn "version (e.g. pre-releases) may actually be ordered as later "
    warn "(e.g. 12.0.0-rc.6 > 12.0.0). We'll work around this by replacing "
    warn "dashes (-) with tildes (~). Converting '$pkg_version' "
    warn "to '$converted'."
    echo "$converted"
	else
    echo "$pkg_version"
	fi
}

write_scripts() {
  for script_name in preinst postinst prerm postrm; do
    eval "file_name=\$$script_name"
    if [[ -n $file_name ]]; then
      if [[ -f $file_name ]]; then
        install -v -m 0755 "$file_name" "$staging_dir/DEBIAN/$script_name"
      else
        exit_with "$script_name script '$file_name' not found" 1
      fi
    fi
  done
}

# The platform architecture.
architecture() {
  dpkg --print-architecture
}

# The size of the package when installed.
#
# Per http://www.debian.org/doc/debian-policy/ch-controlfields.html, the
# disk space is given as the integer value of the estimated installed
# size in bytes, divided by 1024 and rounded up.
installed_size() {
  du "$staging_dir" --apparent-size --block-size=1024 --summarize | cut -f1
}

# The package priority.
#
# Can be one of required, important, standard, optional, or extra.
# See https://www.debian.org/doc/manuals/debian-faq/ch-pkg_basics.en.html#s-priority
#
# TODO: Allow customizing this
priority() {
  echo extra
}

# The package section.
#
# See https://www.debian.org/doc/debian-policy/ch-archive.html#s-subsections
#
# TODO: Allow customizing this
section() {
  echo misc
}

# Parse the CLI flags and options
parse_options() {
  opts="$(getopt \
    --longoptions help,version:,preinst:,postinst:,prerm:,postrm:,replaces: \
    --name "$program" --options h::,V::,R:: -- "$@" \
  )"
  eval set -- "$opts"

  while :; do
    case "$1" in
      -h | --help)
        print_help
        exit
        ;;
      -v | --version)
        echo "$program $version"
        exit
        ;;
      --preinst)
        preinst=$2
        shift 2
        ;;
      --postinst)
        postinst=$2
        shift 2
        ;;
      --prerm)
        prerm=$2;
        shift 2
        ;;
      --postrm)
        postrm=$2
        shift 2
        ;;
      --conflicts)
        provides=$2
        shift 2
        ;;
      --provides)
        provides=$2
        shift 2
        ;;
      --replaces)
        replaces=$2
        shift 2
        ;;
      --)
        shift
        pkg=$*
        break
        ;;
      *)
        exit_with "Unknown error" 1
        ;;
    esac
  done
  if [ -z "$pkg" ] || [ "$pkg" = "--" ]; then
    print_help
    exit_with "You must specify a Habitat package." 1
  fi
}

# Adjust the $PATH to make sure we're using the right binaries
PATH=$(hab pkg path core/tar)/bin:$(hab pkg path core/findutils)/bin:$(hab pkg path core/coreutils)/bin:$PATH

# The current version of Habitat this program
version='@version@'
# The author of this program
author='@author@'
# The short version of the program name which is used in logging output
program="$(basename "$0")"
# The place where we put the files we're building
staging_dir="${HAB_PKG_DEB_STAGING_DIR:="$(mktemp -t --directory "$program-XXXX")"}"

parse_options "$@"

build_deb
