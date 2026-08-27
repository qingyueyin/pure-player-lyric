#include "flutter_window.h"

#include <algorithm>
#include <optional>

#include "flutter/generated_plugin_registrant.h"
#include <flutter/standard_method_codec.h>

namespace {

constexpr UINT kSetClickThroughMessage = WM_APP + 0x3D1;
constexpr UINT kSetUnlockButtonAlignmentMessage = WM_APP + 0x3D3;
constexpr UINT kSetUnlockButtonColorMessage = WM_APP + 0x3D4;
constexpr UINT_PTR kUnlockHoverTimer = 0x3D2;
constexpr UINT kUnlockHoverIntervalMs = 100;
constexpr uint64_t kUnlockHoverDelayMs = 2000;
constexpr int kUnlockButtonLogicalSize = 48;
constexpr int kUnlockButtonLogicalMargin = 8;
constexpr COLORREF kUnlockTransparentColor = RGB(255, 0, 255);
constexpr wchar_t kUnlockGlyph[] = {0xE3B0, L'\0'};
constexpr wchar_t kUnlockButtonClassName[] =
    L"PURE_PLAYER_LYRIC_UNLOCK_BUTTON";

int ScaleForDpi(HWND window, int value) {
  return MulDiv(value, GetDpiForWindow(window), 96);
}

bool ContainsPoint(const RECT& rect, const POINT& point) {
  return point.x >= rect.left && point.x < rect.right &&
         point.y >= rect.top && point.y < rect.bottom;
}

COLORREF ColorRefFromArgb(uint32_t argb) {
  return RGB((argb >> 16) & 0xFF, (argb >> 8) & 0xFF, argb & 0xFF);
}

std::wstring ExecutableDirectory() {
  wchar_t path[MAX_PATH]{};
  const DWORD length = GetModuleFileName(nullptr, path, ARRAYSIZE(path));
  if (length == 0 || length == ARRAYSIZE(path)) return L"";
  std::wstring directory(path, length);
  const auto separator = directory.find_last_of(L"\\/");
  if (separator == std::wstring::npos) return L"";
  directory.resize(separator);
  return directory;
}

}  // namespace

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  window_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(),
          "pure_player_lyric/window",
          &flutter::StandardMethodCodec::GetInstance());
  flutter_view_ = flutter_controller_->view()->GetNativeWindow();
  SetChildContent(flutter_view_);

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    // this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  SetClickThrough(false);
  if (unlock_button_ != nullptr) {
    DestroyWindow(unlock_button_);
    unlock_button_ = nullptr;
  }
  if (unlock_icon_font_ != nullptr) {
    DeleteObject(unlock_icon_font_);
    unlock_icon_font_ = nullptr;
  }
  if (material_icons_font_loaded_) {
    RemoveFontResourceEx(material_icons_font_path_.c_str(), FR_PRIVATE,
                         nullptr);
    material_icons_font_loaded_ = false;
  }
  window_channel_.reset();
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }
  flutter_view_ = nullptr;

  Win32Window::OnDestroy();
}

void FlutterWindow::SetClickThrough(bool enabled) {
  click_through_ = enabled;
  const auto update_style = [enabled](HWND window, bool layered) {
    if (window == nullptr) return;
    auto ex_style = GetWindowLongPtr(window, GWL_EXSTYLE);
    if (enabled) {
      ex_style |= WS_EX_TRANSPARENT;
      if (layered) ex_style |= WS_EX_LAYERED;
    } else {
      ex_style &= ~WS_EX_TRANSPARENT;
      if (layered) ex_style &= ~WS_EX_LAYERED;
    }
    SetWindowLongPtr(window, GWL_EXSTYLE, ex_style);
    SetWindowPos(window, nullptr, 0, 0, 0, 0,
                 SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE |
                     SWP_FRAMECHANGED);
  };

  update_style(GetHandle(), true);
  update_style(flutter_view_, false);

  if (enabled) {
    hover_started_at_ = 0;
    SetTimer(GetHandle(), kUnlockHoverTimer, kUnlockHoverIntervalMs, nullptr);
  } else {
    KillTimer(GetHandle(), kUnlockHoverTimer);
    hover_started_at_ = 0;
    HideUnlockButton();
  }
}

void FlutterWindow::UpdateUnlockHover() {
  const auto main_window = GetHandle();
  if (!click_through_ || main_window == nullptr ||
      !IsWindowVisible(main_window) || IsIconic(main_window)) {
    hover_started_at_ = 0;
    HideUnlockButton();
    return;
  }

  POINT cursor{};
  RECT bounds{};
  if (!GetCursorPos(&cursor) || !GetWindowRect(main_window, &bounds) ||
      !ContainsPoint(bounds, cursor)) {
    hover_started_at_ = 0;
    HideUnlockButton();
    return;
  }

  const auto now = GetTickCount64();
  if (hover_started_at_ == 0) {
    hover_started_at_ = now;
    return;
  }
  if (now - hover_started_at_ >= kUnlockHoverDelayMs) {
    ShowUnlockButton();
  }
}

void FlutterWindow::ShowUnlockButton() {
  const auto main_window = GetHandle();
  if (main_window == nullptr) return;

  if (unlock_button_ == nullptr) {
    WNDCLASS window_class{};
    window_class.hCursor = LoadCursor(nullptr, IDC_HAND);
    window_class.lpszClassName = kUnlockButtonClassName;
    window_class.hInstance = GetModuleHandle(nullptr);
    window_class.lpfnWndProc = FlutterWindow::UnlockButtonWindowProc;
    if (!RegisterClass(&window_class) &&
        GetLastError() != ERROR_CLASS_ALREADY_EXISTS) {
      return;
    }

    unlock_button_ = CreateWindowEx(
        WS_EX_TOPMOST | WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE | WS_EX_LAYERED,
        kUnlockButtonClassName, L"Desktop lyric unlock", WS_POPUP, 0, 0, 0, 0,
        main_window, nullptr, GetModuleHandle(nullptr), this);
    if (unlock_button_ == nullptr) {
      return;
    }
    SetLayeredWindowAttributes(unlock_button_, kUnlockTransparentColor, 0,
                               LWA_COLORKEY);
    LoadMaterialIconsFont();
  }

  RECT bounds{};
  if (!GetWindowRect(main_window, &bounds)) return;
  const int size = ScaleForDpi(main_window, kUnlockButtonLogicalSize);
  const int margin = ScaleForDpi(main_window, kUnlockButtonLogicalMargin);
  int left = bounds.left + (bounds.right - bounds.left - size) / 2;
  if (unlock_button_alignment_ == 0) {
    left = bounds.left + margin;
  } else if (unlock_button_alignment_ == 2) {
    left = bounds.right - size - margin;
  }
  const int iconHitPadding = ScaleForDpi(main_window, 8);
  SetWindowRgn(unlock_button_,
               CreateEllipticRgn(iconHitPadding, iconHitPadding,
                                 size - iconHitPadding + 1,
                                 size - iconHitPadding + 1),
               TRUE);
  SetWindowPos(unlock_button_, HWND_TOPMOST, left, bounds.top + margin, size,
               size, SWP_NOACTIVATE | SWP_SHOWWINDOW);
}

void FlutterWindow::HideUnlockButton() {
  if (unlock_button_ != nullptr) {
    if (GetCapture() == unlock_button_) ReleaseCapture();
    ShowWindow(unlock_button_, SW_HIDE);
  }
}

void FlutterWindow::UnlockFromButton() {
  SetClickThrough(false);
  if (window_channel_) {
    window_channel_->InvokeMethod("unlock", nullptr);
  }
}

bool FlutterWindow::LoadMaterialIconsFont() {
  if (material_icons_font_loaded_) return true;
  const auto executable_directory = ExecutableDirectory();
  if (executable_directory.empty()) return false;
  material_icons_font_path_ = executable_directory +
                              L"\\data\\flutter_assets\\fonts\\"
                              L"MaterialIcons-Regular.otf";
  material_icons_font_loaded_ =
      AddFontResourceEx(material_icons_font_path_.c_str(), FR_PRIVATE,
                        nullptr) > 0;
  return material_icons_font_loaded_;
}

HFONT FlutterWindow::EnsureUnlockIconFont(int pixel_size) {
  if (!material_icons_font_loaded_) return nullptr;
  if (unlock_icon_font_ != nullptr && unlock_icon_font_size_ == pixel_size) {
    return unlock_icon_font_;
  }
  if (unlock_icon_font_ != nullptr) DeleteObject(unlock_icon_font_);
  unlock_icon_font_size_ = pixel_size;
  unlock_icon_font_ = CreateFont(
      -pixel_size, 0, 0, 0, FW_NORMAL, FALSE, FALSE, FALSE, DEFAULT_CHARSET,
      OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS, ANTIALIASED_QUALITY,
      DEFAULT_PITCH, L"Material Icons");
  return unlock_icon_font_;
}

LRESULT CALLBACK FlutterWindow::UnlockButtonWindowProc(
    HWND window, UINT const message, WPARAM const wparam,
    LPARAM const lparam) noexcept {
  if (message == WM_NCCREATE) {
    const auto create = reinterpret_cast<CREATESTRUCT*>(lparam);
    SetWindowLongPtr(window, GWLP_USERDATA,
                     reinterpret_cast<LONG_PTR>(create->lpCreateParams));
  }
  const auto owner = reinterpret_cast<FlutterWindow*>(
      GetWindowLongPtr(window, GWLP_USERDATA));

  switch (message) {
    case WM_MOUSEACTIVATE:
      return MA_NOACTIVATE;
    case WM_ERASEBKGND:
      return 1;
    case WM_LBUTTONDOWN:
      SetCapture(window);
      return 0;
    case WM_LBUTTONUP:
      ReleaseCapture();
      if (owner != nullptr) owner->UnlockFromButton();
      return 0;
    case WM_PAINT: {
      PAINTSTRUCT paint{};
      HDC dc = BeginPaint(window, &paint);
      RECT client{};
      GetClientRect(window, &client);
      const COLORREF icon_color = owner != nullptr
                                      ? owner->unlock_button_icon_color_
                                      : RGB(255, 255, 255);
      HBRUSH transparent = CreateSolidBrush(kUnlockTransparentColor);
      FillRect(dc, &client, transparent);
      DeleteObject(transparent);

      const int size = client.right - client.left;
      const auto px = [size](int logical) {
        return MulDiv(logical, size, kUnlockButtonLogicalSize);
      };
      RECT content = client;

      SetBkMode(dc, TRANSPARENT);
      SetTextColor(dc, icon_color);
      const auto icon_font = owner != nullptr
                                 ? owner->EnsureUnlockIconFont(px(24))
                                 : nullptr;
      if (icon_font != nullptr) {
        const auto old_font = SelectObject(dc, icon_font);
        DrawText(dc, kUnlockGlyph, -1, &content,
                 DT_CENTER | DT_VCENTER | DT_SINGLELINE | DT_NOPREFIX);
        SelectObject(dc, old_font);
      }
      EndPaint(window, &paint);
      return 0;
    }
  }

  return DefWindowProc(window, message, wparam, lparam);
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  if (message == kSetClickThroughMessage) {
    SetClickThrough(wparam != 0);
    return 0;
  }
  if (message == kSetUnlockButtonAlignmentMessage) {
    unlock_button_alignment_ =
        std::clamp(static_cast<int>(wparam), 0, 3);
    if (unlock_button_ != nullptr && IsWindowVisible(unlock_button_)) {
      ShowUnlockButton();
    }
    return 0;
  }
  if (message == kSetUnlockButtonColorMessage) {
    unlock_button_icon_color_ =
        ColorRefFromArgb(static_cast<uint32_t>(wparam));
    if (unlock_button_ != nullptr) {
      InvalidateRect(unlock_button_, nullptr, FALSE);
    }
    return 0;
  }
  if (message == WM_TIMER && wparam == kUnlockHoverTimer) {
    UpdateUnlockHover();
    return 0;
  }
  if (message == WM_NCHITTEST && click_through_) {
    return HTTRANSPARENT;
  }

  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
