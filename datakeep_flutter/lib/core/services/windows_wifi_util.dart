import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:win32/win32.dart';

/// Windows：用 WlanAPI 读当前 SSID，避免 netsh 闪控制台。
class WindowsWifiUtil {
  WindowsWifiUtil._();

  static String? currentSsid() {
    if (kIsWeb || !Platform.isWindows) return null;

    final negotiated = calloc<Uint32>();
    final client = calloc<IntPtr>();
    try {
      final open = WlanOpenHandle(2, nullptr, negotiated, client);
      if (open != ERROR_SUCCESS) return null;

      final ppList = calloc<Pointer<WLAN_INTERFACE_INFO_LIST>>();
      try {
        final enumRc = WlanEnumInterfaces(client.value, nullptr, ppList);
        if (enumRc != ERROR_SUCCESS || ppList.value == nullptr) return null;

        final list = ppList.value.ref;
        for (var i = 0; i < list.dwNumberOfItems; i++) {
          final info = list.InterfaceInfo[i];
          if (info.isState != wlan_interface_state_connected) continue;

          final guid = calloc<GUID>()..ref = info.InterfaceGuid;
          final dataSize = calloc<Uint32>();
          final ppData = calloc<Pointer<WLAN_CONNECTION_ATTRIBUTES>>();
          try {
            final q = WlanQueryInterface(
              client.value,
              guid,
              wlan_intf_opcode_current_connection,
              nullptr,
              dataSize,
              ppData.cast(),
              nullptr,
            );
            if (q != ERROR_SUCCESS || ppData.value == nullptr) continue;

            try {
              final attrs = ppData.value.ref;
              final ssid = _ssidFromDot11(attrs.wlanAssociationAttributes.dot11Ssid);
              if (ssid != null && ssid.isNotEmpty) return ssid;
            } finally {
              WlanFreeMemory(ppData.value.cast());
            }
          } finally {
            calloc.free(guid);
            calloc.free(dataSize);
            calloc.free(ppData);
          }
        }
      } finally {
        if (ppList.value != nullptr) {
          WlanFreeMemory(ppList.value.cast());
        }
        calloc.free(ppList);
        WlanCloseHandle(client.value, nullptr);
      }
    } catch (e) {
      debugPrint('[wifi] WlanAPI 读取失败: $e');
    } finally {
      calloc.free(negotiated);
      calloc.free(client);
    }
    return null;
  }

  static String? _ssidFromDot11(DOT11_SSID ssid) {
    final len = ssid.uSSIDLength;
    if (len <= 0 || len > 32) return null;
    final bytes = Uint8List(len);
    for (var i = 0; i < len; i++) {
      bytes[i] = ssid.ucSSID[i];
    }
    try {
      return utf8.decode(bytes);
    } catch (_) {
      return String.fromCharCodes(bytes);
    }
  }
}
