#include "core/file_lock.hh"

#ifdef _WIN32
#include <vector>

#include <aclapi.h>
#include <windows.h>
#endif

namespace vt::core {

#ifdef _WIN32

namespace {

std::wstring toWide(const std::string &utf8)
{
    if (utf8.empty())
        return {};
    const int len = MultiByteToWideChar(CP_UTF8, 0, utf8.c_str(), -1, nullptr, 0);
    std::wstring wide(len, L'\0');
    MultiByteToWideChar(CP_UTF8, 0, utf8.c_str(), -1, wide.data(), len);
    wide.resize(len - 1);   // drop the terminating NUL MultiByteToWideChar counted
    return wide;
}

}   // namespace

void restrictToCurrentUser(const std::string &utf8Path)
{
    const std::wstring path = toWide(utf8Path);
    if (path.empty())
        return;

    HANDLE token = nullptr;
    if (!OpenProcessToken(GetCurrentProcess(), TOKEN_QUERY, &token))
        return;
    DWORD needed = 0;
    GetTokenInformation(token, TokenUser, nullptr, 0, &needed);
    std::vector<unsigned char> buf(needed);
    const bool gotUser = needed > 0 && GetTokenInformation(token, TokenUser, buf.data(), needed, &needed);
    PSID userSid = gotUser ? reinterpret_cast<TOKEN_USER *>(buf.data())->User.Sid : nullptr;
    if (!userSid) {
        CloseHandle(token);
        return;
    }

    EXPLICIT_ACCESS_W ea = {};
    ea.grfAccessPermissions = GENERIC_ALL;
    ea.grfAccessMode = SET_ACCESS;
    ea.grfInheritance = NO_INHERITANCE;
    ea.Trustee.TrusteeForm = TRUSTEE_IS_SID;
    ea.Trustee.TrusteeType = TRUSTEE_IS_USER;
    ea.Trustee.ptstrName = reinterpret_cast<LPWSTR>(userSid);

    PACL acl = nullptr;
    if (SetEntriesInAclW(1, &ea, nullptr, &acl) == ERROR_SUCCESS) {
        // A protected DACL of just this one ACE: no inherited access from
        // the folder (e.g. the Users group) survives.
        SetNamedSecurityInfoW(const_cast<LPWSTR>(path.c_str()), SE_FILE_OBJECT,
                               OWNER_SECURITY_INFORMATION | DACL_SECURITY_INFORMATION | PROTECTED_DACL_SECURITY_INFORMATION,
                               userSid, nullptr, acl, nullptr);
        LocalFree(acl);
    }
    CloseHandle(token);
}

#else

void restrictToCurrentUser(const std::string &) {}

#endif

}   // namespace vt::core
