# hab-pkg-deb

This is in an experimental state, but will allow you to do

`hab pkg exec smith/hab-pkg-deb hab-pkg-deb myorigin/mypackage`

and spit out a .deb that you can install on a debian system.

## Known issues

- If you have a package with the same a name, but a newer version, of an
  existing package, it will happily overwrite that, even though one is a
  hab package and the other is a system-level thing, so if you `dpkg -i`
  the package you built with `hab pkg export deb core/findutils`,
  bye-bye `find` command. It will be removed and replaced with the one
  hidden away in /hab
- If you have a description, license, maintainer, or upstream URL with a
  ":" it might cut it off because of the poor method I'm using to extract
  this data from the manifest
- Invalid package names don't get safely converted correctly because of
  my wrong regexes

## Features not implemented

- Doesn't do `preinst`, `postinst`, `prerm`, or `postrm`
- No support for `conffiles`
- Multi-line descriptions
- Doesn't do depends/conflicts/replaces
- Priority and Section are not customizable

## Open Questions
- Do we install everything into /hab? This is what we do now, but if
  there's packages already there you need to do `--force-overwrite`, which
  is probably fine, since things are immutable-ish, but not sure if that's
  what we should be doing .
- Do we put the origin in the package filename or the package name
  somewere?
- There's a "Vendor" field in debs, but hab doesn't have anything that
  really corresponds (there's already "Maintainer".) I'm just sticking
  the origin in there for now. Should we do something else?

## License

Copyright: Copyright (c) 2016 Chef Software, Inc.
License: Apache License, Version 2.0

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

     http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
