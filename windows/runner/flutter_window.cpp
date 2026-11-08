#include "flutter_window.h"

#include <flutter/standard_method_codec.h>
#include <flutter_windows.h>
#include <xinput.h>

#include <optional>

#include "flutter/generated_plugin_registrant.h"

namespace {

constexpr UINT_PTR kGamepadTimer = 0x4C55;  // "LU"

using XInputGetStateFn = DWORD(WINAPI*)(DWORD, XINPUT_STATE*);

// XInput is loaded on demand so the app starts on systems without it.
XInputGetStateFn LoadXInput() {
  static XInputGetStateFn get_state = nullptr;
  static bool tried = false;
  if (!tried) {
    tried = true;
    for (const wchar_t* dll :
         {L"xinput1_4.dll", L"xinput1_3.dll", L"xinput9_1_0.dll"}) {
      HMODULE module = LoadLibraryW(dll);
      if (module == nullptr) continue;
      get_state = reinterpret_cast<XInputGetStateFn>(
          GetProcAddress(module, "XInputGetState"));
      if (get_state != nullptr) break;
    }
  }
  return get_state;
}

// Presses and releases a key, as if typed on the keyboard.
void SendKey(WORD vk, bool extended) {
  INPUT inputs[2] = {};
  inputs[0].type = INPUT_KEYBOARD;
  inputs[0].ki.wVk = vk;
  inputs[0].ki.wScan = static_cast<WORD>(MapVirtualKey(vk, MAPVK_VK_TO_VSC));
  inputs[0].ki.dwFlags = extended ? KEYEVENTF_EXTENDEDKEY : 0;
  inputs[1] = inputs[0];
  inputs[1].ki.dwFlags |= KEYEVENTF_KEYUP;
  SendInput(2, inputs, static_cast<int>(sizeof(INPUT)));
}

struct GamepadKey {
  WORD button;
  WORD vk;
  bool extended;
};

constexpr GamepadKey kGamepadKeys[] = {
    {XINPUT_GAMEPAD_DPAD_UP, VK_UP, true},
    {XINPUT_GAMEPAD_DPAD_DOWN, VK_DOWN, true},
    {XINPUT_GAMEPAD_DPAD_LEFT, VK_LEFT, true},
    {XINPUT_GAMEPAD_DPAD_RIGHT, VK_RIGHT, true},
    {XINPUT_GAMEPAD_A, VK_RETURN, false},
    {XINPUT_GAMEPAD_START, VK_RETURN, false},
    {XINPUT_GAMEPAD_B, VK_ESCAPE, false},
    {XINPUT_GAMEPAD_BACK, VK_ESCAPE, false},
    {XINPUT_GAMEPAD_X, VK_SPACE, false},
    {XINPUT_GAMEPAD_Y, VK_APPS, true},  // menu key: quick actions, full screen in the player
    {XINPUT_GAMEPAD_LEFT_SHOULDER, VK_PRIOR, true},
    {XINPUT_GAMEPAD_RIGHT_SHOULDER, VK_NEXT, true},
};

constexpr WORD kDirections = XINPUT_GAMEPAD_DPAD_UP | XINPUT_GAMEPAD_DPAD_DOWN |
                             XINPUT_GAMEPAD_DPAD_LEFT |
                             XINPUT_GAMEPAD_DPAD_RIGHT;

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
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  window_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(), "bobine/window",
          &flutter::StandardMethodCodec::GetInstance());
  window_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                 result) {
        if (call.method_name() == "setFloating") {
          const auto* on = std::get_if<bool>(call.arguments());
          SetFloating(on != nullptr && *on);
          result->Success(flutter::EncodableValue(true));
        } else if (call.method_name() == "startDrag") {
          ReleaseCapture();
          SendMessage(GetHandle(), WM_NCLBUTTONDOWN, HTCAPTION, 0);
          result->Success();
        } else {
          result->NotImplemented();
        }
      });

  SetTimer(GetHandle(), kGamepadTimer, 40, nullptr);

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  if (GetHandle() != nullptr) KillTimer(GetHandle(), kGamepadTimer);
  window_channel_ = nullptr;
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  if (message == WM_TIMER && wparam == kGamepadTimer) {
    PollGamepad();
    return 0;
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

void FlutterWindow::SetFloating(bool on) {
  HWND hwnd = GetHandle();
  if (hwnd == nullptr || on == Win32Window::floating_mode) return;
  if (on) {
    saved_placement_.length = sizeof(WINDOWPLACEMENT);
    GetWindowPlacement(hwnd, &saved_placement_);
    saved_style_ = GetWindowLongPtr(hwnd, GWL_STYLE);
    Win32Window::floating_mode = true;  // lifts the minimum window size
    if (IsZoomed(hwnd)) ShowWindow(hwnd, SW_RESTORE);
    HMONITOR monitor = MonitorFromWindow(hwnd, MONITOR_DEFAULTTONEAREST);
    MONITORINFO info{};
    info.cbSize = sizeof(MONITORINFO);
    GetMonitorInfo(monitor, &info);
    const double scale = FlutterDesktopGetDpiForMonitor(monitor) / 96.0;
    const int width = static_cast<int>(480 * scale);
    const int height = static_cast<int>(270 * scale);
    const int margin = static_cast<int>(24 * scale);
    const LONG_PTR style =
        (saved_style_ & ~static_cast<LONG_PTR>(WS_OVERLAPPEDWINDOW)) |
        static_cast<LONG_PTR>(WS_POPUP) | static_cast<LONG_PTR>(WS_VISIBLE);
    SetWindowLongPtr(hwnd, GWL_STYLE, style);
    SetWindowPos(hwnd, HWND_TOPMOST, info.rcWork.right - width - margin,
                 info.rcWork.bottom - height - margin, width, height,
                 SWP_FRAMECHANGED | SWP_SHOWWINDOW);
  } else {
    Win32Window::floating_mode = false;
    SetWindowLongPtr(hwnd, GWL_STYLE, saved_style_);
    SetWindowPos(hwnd, HWND_NOTOPMOST, 0, 0, 0, 0,
                 SWP_NOMOVE | SWP_NOSIZE | SWP_FRAMECHANGED);
    SetWindowPlacement(hwnd, &saved_placement_);
  }
}

void FlutterWindow::PollGamepad() {
  const XInputGetStateFn get_state = LoadXInput();
  if (get_state == nullptr) return;
  if (GetForegroundWindow() != GetHandle()) {
    gamepad_buttons_ = 0;
    return;
  }
  WORD buttons = 0;
  bool connected = false;
  for (DWORD i = 0; i < XUSER_MAX_COUNT; ++i) {
    XINPUT_STATE state{};
    if (get_state(i, &state) != ERROR_SUCCESS) continue;
    connected = true;
    buttons = state.Gamepad.wButtons;
    // The left stick moves like the d-pad.
    constexpr SHORT kDeadZone = 16000;
    // (WORD arithmetic is done in int: casts keep /W4 /WX quiet.)
    WORD stick = 0;
    if (state.Gamepad.sThumbLY > kDeadZone) stick = XINPUT_GAMEPAD_DPAD_UP;
    if (state.Gamepad.sThumbLY < -kDeadZone) stick = XINPUT_GAMEPAD_DPAD_DOWN;
    if (state.Gamepad.sThumbLX < -kDeadZone) {
      stick = static_cast<WORD>(stick | XINPUT_GAMEPAD_DPAD_LEFT);
    }
    if (state.Gamepad.sThumbLX > kDeadZone) {
      stick = static_cast<WORD>(stick | XINPUT_GAMEPAD_DPAD_RIGHT);
    }
    buttons = static_cast<WORD>(buttons | stick);
    break;
  }
  if (!connected) {
    gamepad_buttons_ = 0;
    return;
  }
  const ULONGLONG now = GetTickCount64();
  const WORD pressed = static_cast<WORD>(buttons & ~gamepad_buttons_);
  for (const auto& key : kGamepadKeys) {
    if ((pressed & key.button) != 0) SendKey(key.vk, key.extended);
  }
  // Holding a direction repeats it, like a keyboard key.
  const WORD held = static_cast<WORD>(buttons & kDirections);
  if ((pressed & kDirections) != 0) {
    gamepad_repeat_at_ = now + 400;
  } else if (held != 0 && now >= gamepad_repeat_at_) {
    for (const auto& key : kGamepadKeys) {
      if ((held & key.button) != 0) SendKey(key.vk, key.extended);
    }
    gamepad_repeat_at_ = now + 90;
  }
  gamepad_buttons_ = buttons;
}

