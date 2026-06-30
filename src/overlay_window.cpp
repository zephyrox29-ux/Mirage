#include "overlay_window.h"
#include <shellapi.h>

static const wchar_t* WINDOW_CLASS = L"MirageOverlay";
static const UINT     WM_TRAYICON  = WM_APP + 1;
static NOTIFYICONDATAW g_nid = {};

static LRESULT CALLBACK wnd_proc(HWND hwnd, UINT msg, WPARAM wParam, LPARAM lParam) {
    switch (msg) {
    case WM_DISPLAYCHANGE: {
        int w = (int)(lParam & 0xFFFF);
        int h = (int)(lParam >> 16);
        SetWindowPos(hwnd, HWND_TOPMOST, 0, 0, w, h, SWP_NOACTIVATE | SWP_SHOWWINDOW);
        return 0;
    }
    case WM_CLOSE:
        return 0; // ignore, close via tray only
    case WM_ERASEBKGND:
        return 1; // skip background erase
    case WM_TRAYICON:
        if (lParam == WM_RBUTTONUP) {
            POINT pt;
            GetCursorPos(&pt);
            HMENU menu = CreatePopupMenu();
            AppendMenuW(menu, MF_STRING, 1, L"Exit Mirage");
            SetForegroundWindow(hwnd); // so menu closes properly
            TrackPopupMenu(menu, TPM_RIGHTALIGN | TPM_BOTTOMALIGN, pt.x, pt.y, 0, hwnd, nullptr);
            DestroyMenu(menu);
        }
        return 0;
    case WM_COMMAND:
        if (LOWORD(wParam) == 1) {
            PostQuitMessage(0);
        }
        return 0;
    }
    return DefWindowProcW(hwnd, msg, wParam, lParam);
}

void get_screen_size(int& width, int& height) {
    DEVMODEW dm = {};
    dm.dmSize = sizeof(dm);
    if (EnumDisplaySettingsW(nullptr, ENUM_CURRENT_SETTINGS, &dm)) {
        width  = (int)dm.dmPelsWidth;
        height = (int)dm.dmPelsHeight;
    } else {
        width  = GetSystemMetrics(SM_CXSCREEN);
        height = GetSystemMetrics(SM_CYSCREEN);
    }
}

HWND create_overlay_window(HINSTANCE hInstance, int width, int height) {
    WNDCLASSEXW wc = {};
    wc.cbSize        = sizeof(WNDCLASSEXW);
    wc.lpfnWndProc   = wnd_proc;
    wc.hInstance     = hInstance;
    wc.lpszClassName = WINDOW_CLASS;
    wc.hCursor       = nullptr;
    wc.hbrBackground = nullptr; // no background — layered window uses per-pixel alpha

    static bool registered = false;
    if (!registered) {
        RegisterClassExW(&wc);
        registered = true;
    }

    DWORD ex_style = WS_EX_TRANSPARENT | WS_EX_LAYERED | WS_EX_TOPMOST
                   | WS_EX_NOACTIVATE;
    DWORD style = WS_POPUP;

    HWND hwnd = CreateWindowExW(
        ex_style, WINDOW_CLASS, L"Mirage", style,
        0, 0, width, height,
        nullptr, nullptr, hInstance, nullptr
    );

    SetLayeredWindowAttributes(hwnd, 0, 0, LWA_ALPHA); // transparent until effects activate

    // System tray icon
    g_nid.cbSize           = sizeof(NOTIFYICONDATAW);
    g_nid.hWnd             = hwnd;
    g_nid.uID              = 1;
    g_nid.uFlags           = NIF_ICON | NIF_MESSAGE | NIF_TIP;
    g_nid.uCallbackMessage = WM_TRAYICON;
    g_nid.hIcon            = LoadIcon(nullptr, IDI_APPLICATION);
    wcscpy_s(g_nid.szTip, L"Mirage");
    Shell_NotifyIconW(NIM_ADD, &g_nid);

    SetWindowPos(hwnd, HWND_TOPMOST, 0, 0, 0, 0,
                 SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE | SWP_SHOWWINDOW);
    return hwnd;
}

void destroy_overlay_window(HWND hwnd) {
    Shell_NotifyIconW(NIM_DELETE, &g_nid);
    if (hwnd) DestroyWindow(hwnd);
}
