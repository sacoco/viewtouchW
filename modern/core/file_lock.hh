#pragma once

#include <string>

// A file with a secret in it (a pairing key, a backup's password-derived
// key, a station helper's token): locked to the account that wrote it.
// QFile::setPermissions(ReadOwner | WriteOwner) does this correctly on its
// own on Unix (chmod 600); on Windows it leaves the folder's inherited ACL
// in place; this closes that gap. A no-op on Unix.

namespace vt::core {

void restrictToCurrentUser(const std::string &utf8Path);

}
