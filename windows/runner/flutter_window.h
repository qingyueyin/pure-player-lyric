#ifndef RUNNER_FLUTTER_WINDOW_H_
#define RUNNER_FLUTTER_WINDOW_H_

#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <flutter/method_channel.h>

#include <cstdint>
#include <memory>
#include <string>

#include "win32_window.h"

// A window that does nothing but host a Flutter view.
class FlutterWindow : public Win32Window {
 public:
  // Creates a new FlutterWindow hosting a Flutter view running |project|.
  explicit FlutterWindow(const flutter::DartProject& project);
  virtual ~FlutterWindow();

 protected:
  // Win32Window:
  bool OnCreate() override;
  void OnDestroy() override;
  LRESULT MessageHandler(HWND window, UINT const message, WPARAM const wparam,
                         LPARAM const lparam) noexcept override;

  void SetClickThrough(bool enabled);
  void UpdateUnlockHover();
  void ShowUnlockButton();
  void HideUnlockButton();
  void UnlockFromButton();
  bool LoadMaterialIconsFont();
  HFONT EnsureUnlockIconFont(int pixel_size);

  static LRESULT CALLBACK UnlockButtonWindowProc(HWND window,
                                                  UINT const message,
                                                  WPARAM const wparam,
                                                  LPARAM const lparam) noexcept;

 private:
  // The project to run.
  flutter::DartProject project_;

  // The Flutter instance hosted by this window.
  std::unique_ptr<flutter::FlutterViewController> flutter_controller_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
      window_channel_;

  HWND flutter_view_ = nullptr;
  HWND unlock_button_ = nullptr;
  HFONT unlock_icon_font_ = nullptr;

  bool click_through_ = false;
  bool material_icons_font_loaded_ = false;
  int unlock_button_alignment_ = 1;
  int unlock_icon_font_size_ = 0;
  COLORREF unlock_button_icon_color_ = RGB(255, 255, 255);
  uint64_t hover_started_at_ = 0;
  std::wstring material_icons_font_path_;
};

#endif  // RUNNER_FLUTTER_WINDOW_H_
